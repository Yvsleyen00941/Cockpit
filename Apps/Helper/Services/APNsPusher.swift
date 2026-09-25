import CCCore
import CryptoKit
import Foundation

/// Optional: keeps the iPhone Live Activity fresh while the iPhone app is
/// asleep, by pushing ActivityKit updates straight from the Mac to APNs
/// (token-based JWT, CryptoKit only). Needs a paid Apple Developer membership
/// and an APNs key (.p8). Without it, the Live Activity still updates
/// whenever the iPhone app runs, and its timer counts down on its own.
@MainActor
final class APNsPusher {
    struct Config: Codable {
        var enabled = false
        var teamID = ""
        var keyID = ""
        var keyPath = ""
        var bundleID = "be.yorben.controlcenter"
        var sandbox = true
        var tokens: [String: Data] = [:]
    }

    private(set) var config = Config()
    private var jwt: (token: String, issued: Date)?
    private var lastPush = Date.distantPast
    private var lastSignature = ""
    private var pending: Task<Void, Never>?

    func load() {
        config = JSONStore.load(Config.self, from: Paths.apns) ?? Config()
    }

    func save() {
        JSONStore.save(config, to: Paths.apns)
    }

    func update(_ change: (inout Config) -> Void) {
        change(&config)
        jwt = nil
        save()
    }

    func register(_ registration: PushTokenRegistration, deviceID: String) {
        guard registration.kind == .liveActivity else { return }
        config.tokens[deviceID] = registration.token
        config.sandbox = registration.sandbox
        config.bundleID = registration.bundleID
        save()
        Log.shared.info("Live Activity push token registered")
    }

    /// Called when bot, timers or recovery change. Coalesced; status changes
    /// push immediately, P&L drift at most once a minute.
    func stateChanged(_ state: LiveState) {
        guard config.enabled, !config.tokens.isEmpty else { return }
        let content = DeskContentState(state: state)
        let signature = "\(content.botStatus)|\(content.timerEnd ?? 0)|\(content.timerPaused)|\(Int(content.recovery ?? -1))"
        let urgent = signature != lastSignature
        guard urgent || Date().timeIntervalSince(lastPush) > 60 else { return }
        lastSignature = signature
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(urgent ? 100 : 1500))
            guard let self, !Task.isCancelled else { return }
            await self.push(content, priority: urgent ? 10 : 5)
        }
    }

    private func push(_ content: DeskContentState, priority: Int) async {
        guard let token = try? bearer() else { return }
        lastPush = .now
        let host = config.sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
        let body: [String: Any] = [
            "aps": [
                "timestamp": Int(Date().timeIntervalSince1970),
                "event": "update",
                "content-state": content.dictionary,
                "stale-date": Int(Date().addingTimeInterval(900).timeIntervalSince1970),
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
        for (device, pushToken) in config.tokens {
            let hex = pushToken.map { String(format: "%02x", $0) }.joined()
            var request = URLRequest(url: URL(string: "https://\(host)/3/device/\(hex)")!)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("bearer \(token)", forHTTPHeaderField: "authorization")
            request.setValue("\(config.bundleID).push-type.liveactivity", forHTTPHeaderField: "apns-topic")
            request.setValue("liveactivity", forHTTPHeaderField: "apns-push-type")
            request.setValue("\(priority)", forHTTPHeaderField: "apns-priority")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 410 || status == 400 {
                    config.tokens[device] = nil
                    save()
                }
                if status != 200 {
                    Log.shared.warning("APNs \(status): \(String(decoding: data, as: UTF8.self))")
                }
            } catch {
                Log.shared.warning("APNs push failed: \(error.localizedDescription)")
            }
        }
    }

    private func bearer() throws -> String {
        if let jwt, Date().timeIntervalSince(jwt.issued) < 45 * 60 { return jwt.token }
        let pem = try String(contentsOfFile: Paths.expand(config.keyPath), encoding: .utf8)
        let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
        func base64url(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = base64url(try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": config.keyID]))
        let claims = base64url(try JSONSerialization.data(withJSONObject: ["iss": config.teamID, "iat": Int(Date().timeIntervalSince1970)]))
        let signingInput = "\(header).\(claims)"
        let signature = try key.signature(for: Data(signingInput.utf8))
        let token = "\(signingInput).\(base64url(signature.rawRepresentation))"
        jwt = (token, .now)
        return token
    }
}

/// Mirrors the iOS `DeskActivityAttributes.ContentState` (keys and number
/// types must match exactly — ActivityKit decodes this JSON).
struct DeskContentState {
    var botStatus: String
    var pnl: Double
    var pnlPct: Double
    var currency: String
    var positions: Int
    var recovery: Double?
    var timerLabel: String?
    var timerEnd: Double?
    var timerPaused: Bool
    var timerRemaining: Double?
    var simulated: Bool
    var updatedAt: Double

    init(state: LiveState) {
        let bot = state.bot
        botStatus = bot?.status.rawValue ?? "unknown"
        pnl = bot?.pnlToday ?? 0
        pnlPct = bot?.pnlTodayPct ?? 0
        currency = bot?.currency ?? "EUR"
        positions = bot?.positions.count ?? 0
        recovery = state.whoop?.recovery
        let timer = state.timers?.primary
        timerLabel = timer?.label
        timerEnd = timer?.endsAt?.timeIntervalSince1970
        timerPaused = timer?.state == .paused
        timerRemaining = timer?.remainingWhenPaused
        simulated = bot?.mode == .simulated
        updatedAt = Date().timeIntervalSince1970
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "botStatus": botStatus, "pnl": pnl, "pnlPct": pnlPct, "currency": currency,
            "positions": positions, "timerPaused": timerPaused, "simulated": simulated, "updatedAt": updatedAt,
        ]
        if let recovery { result["recovery"] = recovery }
        if let timerLabel { result["timerLabel"] = timerLabel }
        if let timerEnd { result["timerEnd"] = timerEnd }
        if let timerRemaining { result["timerRemaining"] = timerRemaining }
        return result
    }
}
