import Foundation

// MARK: - Random

/// Small, fast, seedable PRNG so simulated days are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Standard normal via Box–Muller.
    public mutating func gaussian() -> Double {
        let u1 = max(Double.leastNonzeroMagnitude, Double.random(in: 0..<1, using: &self))
        let u2 = Double.random(in: 0..<1, using: &self)
        return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
    }
}

// MARK: - Bot simulation

/// A plausible trading day: a random walk with a slight edge, a handful of
/// positions, trades every minute or two, overnight crypto activity. Seeded by
/// the date, so a relaunch reproduces the same morning.
public struct BotSimulation: Sendable {
    public struct Instrument: Sendable {
        public let symbol: String
        public let basePrice: Double
        /// Volatility per sqrt(hour), as a fraction.
        public let vol: Double
        public let lot: Double
    }

    public static let instruments: [Instrument] = [
        Instrument(symbol: "BTC-EUR", basePrice: 58_240, vol: 0.006, lot: 0.05),
        Instrument(symbol: "ETH-EUR", basePrice: 2_310, vol: 0.008, lot: 1.2),
        Instrument(symbol: "SOL-EUR", basePrice: 131.4, vol: 0.011, lot: 20),
        Instrument(symbol: "ASML.AS", basePrice: 688.2, vol: 0.004, lot: 4),
        Instrument(symbol: "ADYEN.AS", basePrice: 1_384, vol: 0.005, lot: 2),
        Instrument(symbol: "INGA.AS", basePrice: 16.42, vol: 0.004, lot: 150),
    ]

    public private(set) var status: BotRunState = .running
    public private(set) var positions: [BotPosition] = []
    public private(set) var series: [PnLPoint] = []
    public private(set) var events: [BotEvent] = []
    public private(set) var realized: Double = 0
    public private(set) var tradesToday = 0
    public private(set) var dayStart: Date
    public let startEquity: Double = 25_000

    private var prices: [String: Double] = [:]
    private var rng: SplitMix64
    private var lastStep: Date
    private var nextTradeAt: Date
    private var calendar: Calendar

    public init(now: Date = .now, calendar: Calendar = .current, seed: UInt64? = nil) {
        self.calendar = calendar
        dayStart = calendar.startOfDay(for: now)
        let day = UInt64(max(0, dayStart.timeIntervalSince1970 / 86_400))
        rng = SplitMix64(seed: seed ?? (day &* 2_654_435_761 &+ 97))
        lastStep = dayStart
        nextTradeAt = dayStart
        for instrument in Self.instruments {
            prices[instrument.symbol] = instrument.basePrice * (1 + rng.gaussian() * 0.01)
        }
        replayDay(until: now)
    }

    // MARK: Public API

    public mutating func step(to now: Date) -> [BotEvent] {
        if !calendar.isDate(now, inSameDayAs: dayStart) {
            rollDay(to: now)
        }
        var newEvents: [BotEvent] = []
        var t = lastStep
        // Advance in small increments so long gaps (sleep) stay realistic.
        while t < now {
            let dt = min(30, now.timeIntervalSince(t))
            t = t.addingTimeInterval(dt)
            movePrices(dt: dt)
            if status == .running, t >= nextTradeAt {
                if let event = trade(at: t) { newEvents.append(event) }
                let hour = calendar.component(.hour, from: t)
                let daytime = (7..<22).contains(hour)
                nextTradeAt = t.addingTimeInterval(daytime ? Double.random(in: 480...1_440, using: &rng) : Double.random(in: 2_100...4_800, using: &rng))
            }
            recordPoint(at: t)
        }
        lastStep = now
        return newEvents
    }

    public mutating func pause(at now: Date) -> BotEvent {
        status = .paused
        return log(BotEvent(id: nextID(), time: now, kind: .paused, message: "Paused from Control Center"))
    }

    public mutating func resume(at now: Date) -> BotEvent {
        status = .running
        nextTradeAt = now.addingTimeInterval(20)
        return log(BotEvent(id: nextID(), time: now, kind: .resumed, message: "Resumed from Control Center"))
    }

    public mutating func closeAll(at now: Date) -> [BotEvent] {
        var closed: [BotEvent] = []
        for position in positions {
            closed.append(close(position, at: now, outcome: "close all"))
        }
        positions.removeAll()
        recordPoint(at: now, force: true)
        return closed
    }

    public func state(now: Date, mode: BotMode = .simulated) -> BotState {
        let unrealized = positions.reduce(0) { $0 + $1.unrealizedPnL }
        let pnl = realized + unrealized
        return BotState(
            mode: mode,
            status: status,
            pnlToday: pnl.rounded(toPlaces: 2),
            pnlTodayPct: pnl / startEquity,
            equity: (startEquity + pnl).rounded(toPlaces: 2),
            currency: "EUR",
            positions: positions,
            tradesToday: tradesToday,
            lastHeartbeat: now,
            apiConnected: true,
            lastEvent: events.first { $0.isTrade },
            overnight: overnight(now: now),
            updatedAt: now
        )
    }

    public var pnlSeries: PnLSeries { PnLSeries(dayStart: dayStart, points: series) }

    public var eventLog: BotEventLog { BotEventLog(events: Array(events.prefix(50))) }

    // MARK: Internals

    private mutating func replayDay(until now: Date) {
        // Pre-open a couple of positions around midnight (crypto never sleeps).
        _ = step(to: min(now, dayStart.addingTimeInterval(60)))
        _ = step(to: now)
    }

    private mutating func rollDay(to now: Date) {
        dayStart = calendar.startOfDay(for: now)
        realized = 0
        tradesToday = 0
        series = []
        lastStep = max(lastStep, dayStart)
    }

    private mutating func movePrices(dt: Double) {
        let hours = dt / 3600
        for instrument in Self.instruments {
            guard var price = prices[instrument.symbol] else { continue }
            let drift = 0.00004 * hours
            price *= 1 + drift + instrument.vol * sqrt(hours) * rng.gaussian()
            prices[instrument.symbol] = price
        }
        for index in positions.indices {
            let p = positions[index]
            let current = prices[p.symbol] ?? p.currentPrice
            positions[index].currentPrice = current
            let move = (current - p.entryPrice) * p.quantity
            positions[index].unrealizedPnL = (p.side == .long ? move : -move).rounded(toPlaces: 2)
        }
    }

    private mutating func trade(at time: Date) -> BotEvent? {
        let shouldClose = !positions.isEmpty && (positions.count >= 4 || Double.random(in: 0...1, using: &rng) < 0.45)
        if shouldClose {
            // Close the position with the most extreme P&L (take profit / stop out).
            guard let index = positions.indices.max(by: { abs(positions[$0].unrealizedPnL) < abs(positions[$1].unrealizedPnL) }) else { return nil }
            let position = positions.remove(at: index)
            let outcome = position.unrealizedPnL >= 0 ? "take profit" : "stop"
            return close(position, at: time, outcome: outcome)
        }
        let open = Set(positions.map(\.symbol))
        let candidates = Self.instruments.filter { !open.contains($0.symbol) }
        guard let instrument = candidates.randomElement(using: &rng), let price = prices[instrument.symbol] else { return nil }
        let side: PositionSide = Double.random(in: 0...1, using: &rng) < 0.72 ? .long : .short
        let quantity = instrument.lot * Double(Int.random(in: 1...3, using: &rng))
        positions.append(BotPosition(symbol: instrument.symbol, side: side, quantity: quantity, entryPrice: price, currentPrice: price, unrealizedPnL: 0, openedAt: time))
        tradesToday += 1
        return log(BotEvent(id: nextID(), time: time, kind: side == .long ? .buy : .sell, symbol: instrument.symbol, quantity: quantity, price: price, outcome: "filled"))
    }

    private mutating func close(_ position: BotPosition, at time: Date, outcome: String) -> BotEvent {
        realized += position.unrealizedPnL
        tradesToday += 1
        return log(BotEvent(id: nextID(), time: time, kind: position.side == .long ? .sell : .buy, symbol: position.symbol, quantity: position.quantity, price: position.currentPrice, pnl: position.unrealizedPnL, outcome: outcome))
    }

    private mutating func nextID() -> String {
        String(format: "%016llx", rng.next())
    }

    @discardableResult
    private mutating func log(_ event: BotEvent) -> BotEvent {
        events.insert(event, at: 0)
        if events.count > 200 { events.removeLast(events.count - 200) }
        return event
    }

    private mutating func recordPoint(at time: Date, force: Bool = false) {
        let value = (realized + positions.reduce(0) { $0 + $1.unrealizedPnL }).rounded(toPlaces: 2)
        if let last = series.last, !force, time.timeIntervalSince(last.t) < 120 { return }
        series.append(PnLPoint(t: time, v: value))
        if series.count > 800 { series.removeFirst(series.count - 800) }
    }

    private func overnight(now: Date) -> BotOvernight? {
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dayStart) ?? dayStart
        let night = events.filter { $0.isTrade && $0.time >= dayStart && $0.time < morning }
        guard !night.isEmpty else { return nil }
        return BotOvernight(pnl: night.compactMap(\.pnl).reduce(0, +).rounded(toPlaces: 2), trades: night.count, from: dayStart, to: min(now, morning))
    }
}

extension Double {
    public func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

// MARK: - Demo data

/// Believable sample data for demo mode, previews and screenshots.
public enum DemoData {
    public static func whoop(now: Date) -> WhoopState {
        WhoopState(configured: true, connected: true, recovery: 78, recoveryState: .scored, hrv: 68.4, restingHR: 51, spo2: 96.8, skinTemp: 33.6, strain: 9.8, sleepHours: 7.7, sleepPerformance: 91, sleepEfficiency: 93, recoveryAt: Calendar.current.startOfDay(for: now).addingTimeInterval(6.9 * 3600), updatedAt: now)
    }

    public static func calendar(now: Date, cal: Calendar = .current) -> CalendarState {
        let day = cal.startOfDay(for: now)
        func at(_ h: Double) -> Date { day.addingTimeInterval(h * 3600) }
        return CalendarState(access: .granted, events: [
            CalendarEvent(id: "e0", title: "Deep work — Control Center", start: at(8.5), end: at(10), calendarName: "Personal", colorHex: "#2E86AB"),
            CalendarEvent(id: "e1", title: "Statistics — Hoorcollege", start: at(10.25), end: at(12), calendarName: "UAntwerpen", colorHex: "#F18F01", location: "Stadscampus R.013"),
            CalendarEvent(id: "e2", title: "Lunch", start: at(12.5), end: at(13.25), calendarName: "Personal", colorHex: "#2ECC71"),
            CalendarEvent(id: "e3", title: "Project sync", start: at(14), end: at(14.75), calendarName: "Work", colorHex: "#9B59B6", meetingURL: "https://meet.google.com/abc-defg-hij"),
            CalendarEvent(id: "e4", title: "Econometrics — Werkcollege", start: at(15.5), end: at(17.5), calendarName: "UAntwerpen", colorHex: "#F18F01", location: "Stadscampus B.201"),
            CalendarEvent(id: "e5", title: "Gym", start: at(18.5), end: at(19.75), calendarName: "Personal", colorHex: "#2ECC71"),
        ])
    }

    public static func weather(now: Date, location: String = "Wortegem") -> WeatherState {
        let hour = Calendar.current.dateInterval(of: .hour, for: now)?.start ?? now
        let codes = [2, 2, 3, 3, 61, 61, 80, 3, 2, 1, 1, 0]
        let temps = [13.8, 14.6, 15.2, 15.9, 15.1, 14.4, 14.0, 14.3, 13.6, 12.4, 11.3, 10.6]
        let rain = [5, 10, 20, 35, 65, 70, 55, 25, 10, 5, 5, 0]
        let hourly = (0..<12).map { i in
            HourForecast(time: hour.addingTimeInterval(Double(i + 1) * 3600), temperature: temps[i], code: codes[i], precipitationChance: rain[i], isDay: i < 9)
        }
        return WeatherState(location: location, temperature: 14.2, apparent: 12.9, code: 2, isDay: true, high: 16.4, low: 9.1, precipitationChance: 70, wind: 18, hourly: hourly, sunrise: Calendar.current.startOfDay(for: now).addingTimeInterval(7.6 * 3600), sunset: Calendar.current.startOfDay(for: now).addingTimeInterval(19.4 * 3600), updatedAt: now)
    }

    public static func system(now: Date) -> SystemStats {
        let t = now.timeIntervalSinceReferenceDate
        let wave = (sin(t / 7) + 1) / 2
        let cores = (0..<12).map { i -> Double in
            let base = i < 6 ? 0.08 : 0.18
            return min(1, base + 0.25 * ((sin(t / Double(3 + i)) + 1) / 2))
        }
        return SystemStats(
            model: "MacBook Pro · M3 Pro",
            cpu: cores.reduce(0, +) / Double(cores.count),
            cpuCores: cores,
            efficiencyCores: 6,
            memUsed: UInt64((12.1 + wave * 0.8) * 1_073_741_824),
            memTotal: 18 * 1_073_741_824,
            memPressure: .normal,
            swapUsed: 412 * 1_048_576,
            gpu: 0.06 + wave * 0.1,
            thermal: .nominal,
            battery: BatteryInfo(level: 0.84, isCharging: true, onAC: true, minutesRemaining: nil),
            netIn: 180_000 + wave * 900_000,
            netOut: 42_000 + wave * 120_000,
            diskFree: 212 * 1_000_000_000,
            diskTotal: 994 * 1_000_000_000,
            uptime: 3 * 86_400 + 4 * 3600,
            topProcesses: [
                ProcessUsage(pid: 812, name: "Xcode", cpu: 0.214 + wave * 0.05, memory: 2_900_000_000, bundleID: Bundles.xcode),
                ProcessUsage(pid: 455, name: "Safari", cpu: 0.086, memory: 1_400_000_000, bundleID: Bundles.safari),
                ProcessUsage(pid: 1201, name: "Notion", cpu: 0.041, memory: 820_000_000, bundleID: Bundles.notion),
                ProcessUsage(pid: 301, name: "WindowServer", cpu: 0.052, memory: 610_000_000),
                ProcessUsage(pid: 977, name: "Spotify", cpu: 0.018, memory: 380_000_000, bundleID: "com.spotify.client"),
            ],
            sampledAt: now
        )
    }

    public static func media(now: Date) -> MediaState {
        MediaState(nowPlaying: NowPlaying(source: .spotify, title: "Glass Horizons", artist: "Aurora Park", album: "Northbound", isPlaying: true, position: 94, duration: 241, positionAt: now))
    }

    public static let audio = AudioState(outputVolume: 0.42, outputMuted: false, outputDevice: "MacBook Pro Speakers", inputMuted: false, inputVolume: 0.8, inputDevice: "MacBook Pro Microphone", micInUse: false)

    public static let focusOff = FocusState(known: true, active: false, name: nil, available: ["Deep Work", "Study", "Do Not Disturb"], canTurnOff: true)

    public static func daily(now: Date) -> DailyState {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return DailyState(date: f.string(from: now), priorities: [
            Priority(text: "Ship Control Center milestone 2", done: true),
            Priority(text: "Statistics — exercise set 3"),
            Priority(text: "Review bot risk limits"),
        ], pomodorosCompleted: 3, focusMinutes: 75)
    }

    public static func portfolio(now: Date) -> PortfolioState {
        let series = (0..<30).map { i in 46_200 + Double(i) * 62 + sin(Double(i) / 3) * 540 }
        return PortfolioState(
            configured: true,
            totalEur: 48_210.55,
            dayChangeEur: 312.40,
            dayChangePct: 0.65,
            gainers: [
                PortfolioMover(symbol: "ASML", name: "ASML Holding", changePct: 2.41, valueEur: 8_260),
                PortfolioMover(symbol: "VWCE", name: "Vanguard FTSE All-World", changePct: 0.92, valueEur: 21_400),
                PortfolioMover(symbol: "BTC", name: "Bitcoin", changePct: 0.61, valueEur: 5_820),
            ],
            losers: [
                PortfolioMover(symbol: "ADYEN", name: "Adyen", changePct: -1.84, valueEur: 2_770),
                PortfolioMover(symbol: "KBC", name: "KBC Group", changePct: -0.47, valueEur: 3_150),
            ],
            turbos: [
                TurboProximity(symbol: "TL NVDA 95", underlying: "NVDA", isLong: true, distancePct: 3.8, knockedOut: false),
                TurboProximity(symbol: "TS DAX 24500", underlying: "DAX", isLong: false, distancePct: 11.2, knockedOut: false),
            ],
            series: series,
            asOf: now
        )
    }

    public static func git(now: Date) -> GitState {
        let repo = RepoStatus(path: "~/ControlCenter", name: "ControlCenter", branch: "main", ahead: 1, behind: 0, staged: 2, modified: 3, untracked: 1, lastCommit: "Home dashboard quadrants", lastCommitDate: now.addingTimeInterval(-1_860))
        return GitState(current: repo, repos: [repo])
    }

    public static func context(now: Date) -> ActiveContext {
        ActiveContext(bundleID: Bundles.safari, appName: "Safari", windowTitle: "GitHub — yorben/control-center", url: "https://github.com/yorben/control-center", since: now)
    }

    public static let apps = RunningApps(apps: [
        RunningApp(bundleID: Bundles.safari, name: "Safari", isActive: true, isHidden: false, pid: 455),
        RunningApp(bundleID: Bundles.xcode, name: "Xcode", isActive: false, isHidden: false, pid: 812),
        RunningApp(bundleID: Bundles.notion, name: "Notion", isActive: false, isHidden: false, pid: 1201),
        RunningApp(bundleID: Bundles.terminal, name: "Terminal", isActive: false, isHidden: false, pid: 640),
        RunningApp(bundleID: "com.spotify.client", name: "Spotify", isActive: false, isHidden: true, pid: 977),
        RunningApp(bundleID: Bundles.finder, name: "Finder", isActive: false, isHidden: false, pid: 390),
        RunningApp(bundleID: Bundles.mail, name: "Mail", isActive: false, isHidden: false, pid: 702),
    ])

    public static func helper(now: Date) -> HelperStatus {
        HelperStatus(
            version: "1.0 (demo)",
            macName: "MacBook Pro",
            model: "MacBook Pro · M3 Pro",
            osVersion: "macOS 27.0",
            permissions: PermissionKind.allCases.map { PermissionStatus(kind: $0, granted: $0 != .inputMonitoring, required: $0 == .accessibility) },
            integrations: [
                IntegrationStatus(id: .bot, health: .ok, detail: "Simulated"),
                IntegrationStatus(id: .whoop, health: .ok, detail: "Recovery 78%"),
                IntegrationStatus(id: .weather, health: .ok, detail: "Wortegem"),
                IntegrationStatus(id: .portfolio, health: .ok, detail: "€48.2K"),
                IntegrationStatus(id: .calendar, health: .ok, detail: "6 events today"),
                IntegrationStatus(id: .focus, health: .ok, detail: "3 Focus shortcuts"),
                IntegrationStatus(id: .media, health: .ok, detail: "Spotify"),
                IntegrationStatus(id: .git, health: .ok, detail: "ControlCenter"),
            ],
            devices: [ConnectedDevice(id: "demo", name: "iPad Pro", platform: .iPad, transport: .demo, latencyMs: 3.4, connectedAt: now)]
        )
    }
}
