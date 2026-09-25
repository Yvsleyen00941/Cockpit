import AppKit
import CCCore
import Foundation

/// WHOOP developer API v2 (v1 was retired in 2025).
///
/// OAuth runs on the Mac: the helper opens WHOOP's sign-in page in your
/// browser and catches the redirect on `http://localhost:8080` — the redirect
/// your WHOOP developer app is already registered with. Tokens live in the
/// Keychain and refresh themselves (`offline` scope).
///
/// Recovery and sleep are fetched until today's are scored, then left alone
/// until tomorrow; strain refreshes every five minutes while someone looks.
@MainActor
final class WhoopProvider: PollingProvider {
    override var channels: Set<Channel> { [.whoop] }
    override var interval: TimeInterval { 60 }

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    static let apiBase = "https://api.prod.whoop.com/developer/v2"
    static let authorizeURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    static let scopes = "read:recovery read:cycles read:sleep read:profile read:body_measurement offline"

    private(set) var settings = WhoopSettings()
    private var tokens: Tokens? { didSet { Secrets.set(tokens.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) }, for: "whoop.tokens") } }
    private var state = WhoopState.notConfigured
    private var lastRecoveryFetch = Date.distantPast
    private var lastCycleFetch = Date.distantPast
    private var recoveryScoredDay: Date?

    override init() {
        super.init()
        if let stored = Secrets.get("whoop.tokens"), let decoded = try? JSONDecoder().decode(Tokens.self, from: Data(stored.utf8)) {
            tokens = decoded
        }
    }

    var isConfigured: Bool { !settings.clientID.isEmpty && Secrets.get(IntegrationSettings.SecretKey.whoopClientSecret) != nil }
    var isConnected: Bool { tokens != nil }

    func configure(_ settings: WhoopSettings) {
        self.settings = settings
        publishBaseline()
        kick()
    }

    private func publishBaseline() {
        state.configured = isConfigured
        state.connected = isConnected
        Hub.shared.publish(.whoop(state))
    }

    override func tick() async {
        guard isConnected else {
            publishBaseline()
            return
        }
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        do {
            if recoveryScoredDay != today, now.timeIntervalSince(lastRecoveryFetch) > 600 {
                lastRecoveryFetch = now
                try await fetchRecoveryAndSleep(today: today)
            }
            if now.timeIntervalSince(lastCycleFetch) > 300 {
                lastCycleFetch = now
                try await fetchCycle()
            }
            state.error = nil
        } catch {
            state.error = error.localizedDescription
        }
        state.configured = isConfigured
        state.connected = isConnected
        state.updatedAt = .now
        Hub.shared.publish(.whoop(state))
    }

    // MARK: API

    private func fetchRecoveryAndSleep(today: Date) async throws {
        let recovery = try await get("/recovery", query: ["limit": "1"])
        if let record = (recovery["records"] as? [[String: Any]])?.first {
            let scoreState = (record["score_state"] as? String) ?? ""
            state.recoveryState = scoreState == "SCORED" ? .scored : (scoreState == "UNSCORABLE" ? .unscorable : .pending)
            if let score = record["score"] as? [String: Any] {
                state.recovery = JSONPath.double(at: "recovery_score", in: score)
                state.restingHR = JSONPath.double(at: "resting_heart_rate", in: score)
                state.hrv = JSONPath.double(at: "hrv_rmssd_milli", in: score)
                state.spo2 = JSONPath.double(at: "spo2_percentage", in: score)
                state.skinTemp = JSONPath.double(at: "skin_temp_celsius", in: score)
            }
            let created = JSONPath.date(at: "created_at", in: record) ?? JSONPath.date(at: "updated_at", in: record)
            state.recoveryAt = created
            if state.recoveryState == .scored, let created, created >= today.addingTimeInterval(-6 * 3600) {
                recoveryScoredDay = today
            }
        }
        let sleep = try await get("/activity/sleep", query: ["limit": "5"])
        let records = (sleep["records"] as? [[String: Any]]) ?? []
        if let main = records.first(where: { ($0["nap"] as? Bool) != true && ($0["score_state"] as? String) == "SCORED" }),
           let score = main["score"] as? [String: Any] {
            let stages = score["stage_summary"] as? [String: Any] ?? [:]
            let asleep = ["total_light_sleep_time_milli", "total_slow_wave_sleep_time_milli", "total_rem_sleep_time_milli"]
                .compactMap { JSONPath.double(at: $0, in: stages) }
                .reduce(0, +)
            state.sleepHours = asleep > 0 ? asleep / 3_600_000 : nil
            state.sleepPerformance = JSONPath.double(at: "sleep_performance_percentage", in: score)
            state.sleepEfficiency = JSONPath.double(at: "sleep_efficiency_percentage", in: score)
        }
    }

    private func fetchCycle() async throws {
        let cycles = try await get("/cycle", query: ["limit": "1"])
        if let record = (cycles["records"] as? [[String: Any]])?.first, let score = record["score"] as? [String: Any] {
            state.strain = JSONPath.double(at: "strain", in: score)
        }
    }

    private func get(_ path: String, query: [String: String], retried: Bool = false) async throws -> [String: Any] {
        try await ensureFreshToken()
        guard let tokens else { throw WhoopError("Not signed in to WHOOP") }
        var components = URLComponents(string: Self.apiBase + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !retried {
            self.tokens?.expiresAt = .distantPast
            return try await get(path, query: query, retried: true)
        }
        guard (200..<300).contains(status) else { throw WhoopError("WHOOP replied \(status)") }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func ensureFreshToken() async throws {
        guard let current = tokens, current.expiresAt.timeIntervalSinceNow < 300 else { return }
        guard let refresh = current.refreshToken else {
            tokens = nil
            throw WhoopError("WHOOP session expired — connect again")
        }
        try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "scope": "offline",
        ])
    }

    private func tokenRequest(_ fields: [String: String]) async throws {
        guard let secret = Secrets.get(IntegrationSettings.SecretKey.whoopClientSecret) else { throw WhoopError("WHOOP client secret missing") }
        var all = fields
        all["client_id"] = settings.clientID
        all["client_secret"] = secret
        var request = URLRequest(url: URL(string: Self.tokenURL)!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(all.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else {
            let body = String(decoding: data.prefix(160), as: UTF8.self)
            throw WhoopError("Token request failed (\(status)): \(body)")
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        tokens = Tokens(accessToken: access, refreshToken: (json["refresh_token"] as? String) ?? tokens?.refreshToken, expiresAt: Date().addingTimeInterval(expiresIn))
    }

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: OAuth

    func connect() async -> ActionResult {
        guard isConfigured else {
            return .failure("Add your WHOOP client ID and secret in the helper (Integrations → WHOOP) first.")
        }
        guard let redirect = URLComponents(string: settings.redirectURI), let host = redirect.host,
              ["localhost", "127.0.0.1"].contains(host), let port = redirect.port else {
            return .failure("The redirect URI must look like http://localhost:8080")
        }
        let state = String((0..<24).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! })
        var components = URLComponents(string: Self.authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: settings.clientID),
            URLQueryItem(name: "redirect_uri", value: settings.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        let wait = Task { try await OAuthCallbackServer.waitForCode(port: UInt16(port), expectedState: state, timeout: 300) }
        try? await Task.sleep(for: .milliseconds(150))
        NSWorkspace.shared.open(components.url!)
        Log.shared.info("Opened WHOOP sign-in in your browser")
        do {
            let code = try await wait.value
            try await tokenRequest([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": settings.redirectURI,
            ])
            recoveryScoredDay = nil
            lastRecoveryFetch = .distantPast
            lastCycleFetch = .distantPast
            Hub.shared.updateIntegrations { $0.whoop.connected = true }
            await tick()
            return ActionResult(ok: true, message: "WHOOP connected")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    func disconnect() {
        tokens = nil
        state = WhoopState(configured: isConfigured, connected: false)
        Hub.shared.publish(.whoop(state))
        Hub.shared.updateIntegrations { $0.whoop.connected = false }
    }
}

struct WhoopError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
