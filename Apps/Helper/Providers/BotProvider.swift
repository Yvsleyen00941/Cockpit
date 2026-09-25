import CCCore
import Foundation

/// The trading bot.
///
/// * **Simulated** — a realistic built-in bot, so everything works before the
///   real one is wired in (every screen shows a SIM badge).
/// * **Live** — polls your bot's local REST API every 2 s while someone is
///   watching. Field names are mappable (`fieldMap`), so the bot does not need
///   to change. Trades pushed to `POST /v1/bot/event` on the helper's local API
///   reach the iPad instantly. The contract is documented in docs/BOT-API.md.
@MainActor
final class BotProvider: PollingProvider {
    override var channels: Set<Channel> { [.bot, .botSeries, .botEvents] }
    override var interval: TimeInterval { settings.mode == .live ? max(1, settings.pollSeconds) : 2 }

    private(set) var settings = BotSettings()
    private var simulation: BotSimulation?
    private var ledger = JSONStore.load(BotLedger.self, from: Paths.botLedger) ?? BotLedger()
    private var lastState: BotState?
    private var lastSeriesFetch = Date.distantPast
    private var lastLedgerSave = Date.distantPast

    static let defaultFields: [String: String] = [
        "status": "status",
        "pnlToday": "pnl_today",
        "pnlTodayPct": "pnl_today_pct",
        "equity": "equity",
        "currency": "currency",
        "tradesToday": "trades_today",
        "lastHeartbeat": "last_heartbeat",
        "apiConnected": "api_connected",
        "positions": "positions",
    ]

    func configure(_ settings: BotSettings) {
        let modeChanged = settings.mode != self.settings.mode || settings.baseURL != self.settings.baseURL
        self.settings = settings
        if modeChanged {
            simulation = nil
            lastState = nil
            if settings.mode == .off { Hub.shared.publish(.bot(.off)) }
        }
        kick()
    }

    override func tick() async {
        switch settings.mode {
        case .off:
            Hub.shared.publish(.bot(.off))
        case .simulated:
            stepSimulation()
        case .live:
            await pollLive()
        }
    }

    // MARK: Simulated

    private func stepSimulation() {
        let now = Date()
        if simulation == nil { simulation = BotSimulation(now: now) }
        let fresh = simulation!.step(to: now)
        publishSimulation(announcing: fresh)
    }

    private func publishSimulation(announcing events: [BotEvent]) {
        guard let simulation else { return }
        let now = Date()
        let state = simulation.state(now: now, mode: .simulated)
        lastState = state
        Hub.shared.publish(.bot(state))
        Hub.shared.publish(.botSeries(simulation.pnlSeries))
        Hub.shared.publish(.botEvents(simulation.eventLog))
        events.filter(\.isTrade).forEach(announce)
    }

    // MARK: Live

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(string: settings.baseURL.trimmingCharacters(in: .whitespaces)) else { return nil }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + (path.hasPrefix("/") ? path : "/" + path)
        if !query.isEmpty { components.queryItems = query }
        return components.url
    }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = Secrets.get(IntegrationSettings.SecretKey.botAPIKey) {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func getJSON(_ url: URL) async throws -> Any {
        let (data, response) = try await URLSession.shared.data(for: request(url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private func pollLive() async {
        guard let statusURL = url(settings.statusPath) else {
            publishFailure("Set your bot's URL in the helper's Trading Bot settings.")
            return
        }
        do {
            let json = try await getJSON(statusURL)
            var state = parseStatus(json)
            if !settings.eventsPath.isEmpty, let eventsURL = url(settings.eventsPath, query: ledger.lastEventID.map { [URLQueryItem(name: "since", value: $0)] } ?? []) {
                if let eventsJSON = try? await getJSON(eventsURL) {
                    ingestEvents(eventsJSON, announce: true)
                }
            }
            await updateSeries(current: state.pnlToday)
            state.overnight = ledger.overnight(now: .now)
            if state.lastEvent == nil { state.lastEvent = ledger.events.first { $0.isTrade } }
            lastState = state
            Hub.shared.publish(.bot(state))
            Hub.shared.publish(.botEvents(BotEventLog(events: Array(ledger.events.prefix(50)))))
            saveLedgerIfNeeded()
        } catch {
            publishFailure(error.localizedDescription)
        }
    }

    private func publishFailure(_ message: String) {
        var state = lastState ?? BotState(mode: .live, status: .unreachable, pnlToday: 0)
        state.mode = .live
        state.status = .unreachable
        state.apiConnected = false
        state.error = message
        state.updatedAt = .now
        Hub.shared.publish(.bot(state))
    }

    private func updateSeries(current pnl: Double) async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: .now)
        if ledger.seriesDay != dayStart {
            ledger.seriesDay = dayStart
            ledger.series = []
        }
        if !settings.seriesPath.isEmpty, Date().timeIntervalSince(lastSeriesFetch) > 60, let seriesURL = url(settings.seriesPath) {
            lastSeriesFetch = .now
            if let json = try? await getJSON(seriesURL), let points = parseSeries(json), !points.isEmpty {
                ledger.series = points.filter { $0.t >= dayStart }
                Hub.shared.publish(.botSeries(PnLSeries(dayStart: dayStart, points: ledger.series)))
                return
            }
        }
        // No series endpoint: build it from the polls themselves.
        if let last = ledger.series.last, Date().timeIntervalSince(last.t) < 120 { return }
        ledger.series.append(PnLPoint(t: .now, v: pnl))
        if ledger.series.count > 800 { ledger.series.removeFirst(ledger.series.count - 800) }
        Hub.shared.publish(.botSeries(PnLSeries(dayStart: dayStart, points: ledger.series)))
    }

    private func saveLedgerIfNeeded() {
        guard Date().timeIntervalSince(lastLedgerSave) > 60 else { return }
        lastLedgerSave = .now
        JSONStore.save(ledger, to: Paths.botLedger)
    }

    // MARK: Parsing

    private func field(_ key: String) -> String {
        settings.fieldMap[key] ?? Self.defaultFields[key] ?? key
    }

    func parseStatus(_ json: Any) -> BotState {
        let statusText = (JSONPath.string(at: field("status"), in: json) ?? "unknown").lowercased()
        let status: BotRunState = switch statusText {
        case "running", "active", "trading", "live", "on": .running
        case "paused", "pause", "halted": .paused
        case "stopped", "idle", "off", "disabled": .stopped
        default: .unknown
        }
        let pnl = JSONPath.double(at: field("pnlToday"), in: json) ?? 0
        let pct = JSONPath.double(at: field("pnlTodayPct"), in: json).map { $0 / 100 }
        let equity = JSONPath.double(at: field("equity"), in: json)
        let positions = (JSONPath.value(at: field("positions"), in: json) as? [[String: Any]] ?? []).compactMap(parsePosition)
        return BotState(
            mode: .live,
            status: status,
            pnlToday: pnl,
            pnlTodayPct: pct ?? equity.map { pnl / max(1, $0 - pnl) },
            equity: equity,
            currency: JSONPath.string(at: field("currency"), in: json) ?? "EUR",
            positions: positions,
            tradesToday: Int(JSONPath.double(at: field("tradesToday"), in: json) ?? Double(ledger.tradesToday())),
            lastHeartbeat: JSONPath.date(at: field("lastHeartbeat"), in: json) ?? .now,
            apiConnected: JSONPath.bool(at: field("apiConnected"), in: json) ?? true,
            lastEvent: nil,
            overnight: nil,
            error: nil,
            updatedAt: .now
        )
    }

    private func parsePosition(_ item: [String: Any]) -> BotPosition? {
        func number(_ keys: String...) -> Double? {
            for key in keys { if let v = JSONPath.double(at: key, in: item) { return v } }
            return nil
        }
        guard let symbol = JSONPath.string(at: "symbol", in: item) ?? JSONPath.string(at: "instrument", in: item) else { return nil }
        let side: PositionSide = (JSONPath.string(at: "side", in: item) ?? "long").lowercased().hasPrefix("s") ? .short : .long
        let quantity = number("qty", "quantity", "size", "amount") ?? 0
        let entry = number("entry_price", "entry", "avg_price", "average_price", "open_price") ?? 0
        let current = number("current_price", "price", "mark", "mark_price", "last") ?? entry
        let move = (current - entry) * quantity
        let pnl = number("unrealized_pnl", "unrealised_pnl", "upnl", "pnl") ?? (side == .long ? move : -move)
        return BotPosition(symbol: symbol, side: side, quantity: quantity, entryPrice: entry, currentPrice: current, unrealizedPnL: pnl, openedAt: JSONPath.date(at: "opened_at", in: item))
    }

    private func parseSeries(_ json: Any) -> [PnLPoint]? {
        let items = (json as? [Any]) ?? (JSONPath.value(at: "points", in: json) as? [Any]) ?? []
        let points: [PnLPoint] = items.compactMap { item in
            if let pair = item as? [Any], pair.count >= 2,
               let t = JSONPath.date(at: "$", in: pair[0]), let v = JSONPath.double(at: "$", in: pair[1]) {
                return PnLPoint(t: t, v: v)
            }
            if let t = JSONPath.date(at: "t", in: item) ?? JSONPath.date(at: "time", in: item) ?? JSONPath.date(at: "ts", in: item),
               let v = JSONPath.double(at: "v", in: item) ?? JSONPath.double(at: "pnl", in: item) ?? JSONPath.double(at: "value", in: item) {
                return PnLPoint(t: t, v: v)
            }
            return nil
        }
        return points.sorted { $0.t < $1.t }
    }

    func parseEvent(_ item: Any) -> BotEvent? {
        let kindText = (JSONPath.string(at: "side", in: item) ?? JSONPath.string(at: "kind", in: item) ?? JSONPath.string(at: "type", in: item) ?? "info").lowercased()
        let kind: BotEventKind = switch kindText {
        case "buy", "long", "open_long": .buy
        case "sell", "short", "close", "open_short": .sell
        case "paused", "pause": .paused
        case "resumed", "resume": .resumed
        case "error": .error
        case "warning", "warn": .warning
        default: .info
        }
        let time = JSONPath.date(at: "ts", in: item) ?? JSONPath.date(at: "time", in: item) ?? JSONPath.date(at: "timestamp", in: item) ?? .now
        let id = JSONPath.string(at: "id", in: item) ?? "\(Int(time.timeIntervalSince1970 * 1000))-\(kindText)"
        return BotEvent(
            id: id,
            time: time,
            kind: kind,
            symbol: JSONPath.string(at: "symbol", in: item),
            quantity: JSONPath.double(at: "qty", in: item) ?? JSONPath.double(at: "quantity", in: item),
            price: JSONPath.double(at: "price", in: item),
            pnl: JSONPath.double(at: "pnl", in: item),
            outcome: JSONPath.string(at: "outcome", in: item) ?? JSONPath.string(at: "status", in: item),
            message: JSONPath.string(at: "message", in: item)
        )
    }

    /// Events from polling or from the webhook.
    func ingestEvents(_ json: Any, announce: Bool) {
        let items = (json as? [Any]) ?? (JSONPath.value(at: "events", in: json) as? [Any]) ?? [json]
        let known = Set(ledger.events.map(\.id))
        let fresh = items.compactMap(parseEvent).filter { !known.contains($0.id) }.sorted { $0.time > $1.time }
        guard !fresh.isEmpty else { return }
        ledger.events = (fresh + ledger.events).sorted { $0.time > $1.time }
        if ledger.events.count > 300 { ledger.events.removeLast(ledger.events.count - 300) }
        ledger.lastEventID = ledger.events.first?.id
        Hub.shared.publish(.botEvents(BotEventLog(events: Array(ledger.events.prefix(50)))))
        if announce { fresh.filter(\.isTrade).forEach(self.announce) }
        saveLedgerIfNeeded()
    }

    /// Status pushed by the bot to `POST /v1/bot/status`.
    func ingestStatus(_ json: Any) {
        var state = parseStatus(json)
        state.overnight = ledger.overnight(now: .now)
        state.lastEvent = ledger.events.first { $0.isTrade }
        lastState = state
        Hub.shared.publish(.bot(state))
    }

    private func announce(_ event: BotEvent) {
        let side = event.kind == .buy ? "BUY" : "SELL"
        var detail: [String] = []
        if let quantity = event.quantity, let price = event.price { detail.append("\(Fmt.quantity(quantity)) @ \(Fmt.price(price))") }
        if let pnl = event.pnl { detail.append(Fmt.money(pnl, currency: lastState?.currency ?? "EUR", signed: true)) }
        if let outcome = event.outcome { detail.append(outcome) }
        Hub.shared.toast(Toast(title: "\(side) \(event.symbol ?? "")", message: detail.joined(separator: " · "), style: .trade, symbol: event.kind == .buy ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill"))
        Log.shared.action("Bot \(side) \(event.symbol ?? "") \(detail.joined(separator: " "))")
    }

    // MARK: Commands

    func command(_ command: BotCommand) async -> ActionResult {
        switch settings.mode {
        case .off:
            return .failure("The trading bot integration is off. Turn it on in the helper.")
        case .simulated:
            if simulation == nil { simulation = BotSimulation(now: .now) }
            var events: [BotEvent] = []
            switch command {
            case .pause: events.append(simulation!.pause(at: .now))
            case .resume: events.append(simulation!.resume(at: .now))
            case .closeAll: events += simulation!.closeAll(at: .now)
            case .refresh: break
            }
            publishSimulation(announcing: command == .closeAll ? events : [])
            return ActionResult(ok: true, message: "\(command.title) (simulated)")
        case .live:
            let path: String? = switch command {
            case .pause: settings.pausePath
            case .resume: settings.resumePath
            case .closeAll: settings.closeAllPath
            case .refresh: nil
            }
            if let path {
                guard let target = url(path) else { return .failure("Bot URL is not set") }
                do {
                    let (data, response) = try await URLSession.shared.data(for: request(target, method: "POST"))
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        let body = String(decoding: data.prefix(200), as: UTF8.self)
                        return .failure("Bot replied \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body)")
                    }
                } catch {
                    return .failure(error.localizedDescription)
                }
            }
            Log.shared.action("Bot: \(command.title)")
            await tick()
            return ActionResult(ok: true, message: command.title)
        }
    }

    func test() async -> ActionResult {
        guard settings.mode == .live else { return ActionResult(ok: true, message: "Simulated bot is running") }
        await pollLive()
        if let error = lastState?.error { return .failure(error) }
        return ActionResult(ok: true, message: "Connected — \(lastState?.status.title ?? "OK")")
    }
}

/// Persisted trade history for the overnight summary and the chart.
struct BotLedger: Codable {
    var events: [BotEvent] = []
    var lastEventID: String?
    var seriesDay: Date?
    var series: [PnLPoint] = []

    func tradesToday(now: Date = .now) -> Int {
        let start = Calendar.current.startOfDay(for: now)
        return events.filter { $0.isTrade && $0.time >= start }.count
    }

    /// Trades between 22:00 yesterday and 07:00 today.
    func overnight(now: Date) -> BotOvernight? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let from = today.addingTimeInterval(-2 * 3600)
        let to = min(now, today.addingTimeInterval(7 * 3600))
        let night = events.filter { $0.isTrade && $0.time >= from && $0.time < to }
        guard !night.isEmpty else { return nil }
        return BotOvernight(pnl: night.compactMap(\.pnl).reduce(0, +), trades: night.count, from: from, to: to)
    }
}
