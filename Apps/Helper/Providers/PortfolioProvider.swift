import CCCore
import Foundation

/// PortTracker ("Vectra") — the desk-terminal snapshot from
/// `GET /api/market/standby`: net worth in EUR, the day's move, movers among
/// what you actually hold, and turbos close to their knockout barrier.
///
/// The light snapshot is polled every 30 s; the full one (with the 30-day
/// series) once an hour, exactly as PortTracker's own terminal does, so Yahoo
/// never gets hammered. PortTracker authenticates with your Supabase session,
/// so the helper sends a header you provide (a `Cookie`, or `Authorization`
/// if you add a token path to the route).
@MainActor
final class PortfolioProvider: PollingProvider {
    override var channels: Set<Channel> { [.portfolio] }
    override var interval: TimeInterval { max(10, settings.pollSeconds) }

    private(set) var settings = PortfolioSettings()
    private var series: [Double] = []
    private var lastFull = Date.distantPast

    func configure(_ settings: PortfolioSettings) {
        self.settings = settings
        if !settings.enabled { Hub.shared.publish(.portfolio(.notConfigured)) }
        kick()
    }

    override func tick() async {
        guard settings.enabled, !settings.baseURL.isEmpty else {
            Hub.shared.publish(.portfolio(.notConfigured))
            return
        }
        let full = Date().timeIntervalSince(lastFull) > 3600
        var components = URLComponents(string: settings.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/api/market/standby")
        if full { components?.queryItems = [URLQueryItem(name: "depth", value: "full")] }
        guard let url = components?.url else {
            publishError("The PortTracker URL is not valid")
            return
        }
        var request = URLRequest(url: url, timeoutInterval: full ? 60 : 15)
        if let value = Secrets.get(IntegrationSettings.SecretKey.portfolioAuth) {
            request.setValue(value, forHTTPHeaderField: settings.authHeader)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status != 401 else { return publishError("PortTracker wants you signed in — update the auth header") }
            guard (200..<300).contains(status) else { return publishError("PortTracker replied \(status)") }
            let json = try JSONSerialization.jsonObject(with: data)
            guard JSONPath.bool(at: "ok", in: json) != false, let snapshot = JSONPath.value(at: "snapshot", in: json) else {
                return publishError(JSONPath.string(at: "error", in: json) ?? "Unexpected response")
            }
            if full { lastFull = .now }
            Hub.shared.publish(.portfolio(parse(snapshot)))
        } catch {
            publishError(error.localizedDescription)
        }
    }

    private func publishError(_ message: String) {
        var state = Hub.shared.state.portfolio ?? PortfolioState(configured: true)
        state.configured = true
        state.error = message
        Hub.shared.publish(.portfolio(state))
    }

    func parse(_ snapshot: Any) -> PortfolioState {
        let holdings = (JSONPath.value(at: "holdings", in: snapshot) as? [Any]) ?? []
        let movers: [PortfolioMover] = holdings.compactMap { holding in
            guard let symbol = JSONPath.string(at: "symbol", in: holding),
                  let change = JSONPath.double(at: "changePercent", in: holding),
                  abs(change) >= 0.05 else { return nil }
            return PortfolioMover(symbol: symbol, name: JSONPath.string(at: "name", in: holding) ?? symbol, changePct: change, valueEur: JSONPath.double(at: "valueEur", in: holding))
        }
        let turbos: [TurboProximity] = ((JSONPath.value(at: "turbos", in: snapshot) as? [Any]) ?? []).compactMap { turbo in
            guard let symbol = JSONPath.string(at: "symbol", in: turbo) else { return nil }
            return TurboProximity(
                symbol: symbol,
                underlying: JSONPath.string(at: "underlyingSymbol", in: turbo) ?? "",
                isLong: (JSONPath.string(at: "direction", in: turbo) ?? "LONG").uppercased() == "LONG",
                distancePct: JSONPath.double(at: "distancePercent", in: turbo),
                knockedOut: JSONPath.bool(at: "isKnockedOut", in: turbo) ?? false
            )
        }
        let fullSeries = (JSONPath.value(at: "series", in: snapshot) as? [Any])?.compactMap { JSONPath.double(at: "$", in: $0) } ?? []
        if !fullSeries.isEmpty { series = fullSeries }
        let asOf = JSONPath.date(at: "asOf", in: snapshot)
        return PortfolioState(
            configured: true,
            totalEur: JSONPath.double(at: "totalEur", in: snapshot),
            dayChangeEur: JSONPath.double(at: "dayChangeEur", in: snapshot),
            dayChangePct: JSONPath.double(at: "dayChangePercent", in: snapshot),
            gainers: Array(movers.filter { $0.changePct > 0 }.sorted { $0.changePct > $1.changePct }.prefix(3)),
            losers: Array(movers.filter { $0.changePct < 0 }.sorted { $0.changePct < $1.changePct }.prefix(3)),
            turbos: turbos.sorted { ($0.distancePct ?? 999) < ($1.distancePct ?? 999) },
            series: series,
            unpriced: (JSONPath.value(at: "unpriced", in: snapshot) as? [String]) ?? [],
            asOf: asOf ?? .now,
            error: nil
        )
    }
}
