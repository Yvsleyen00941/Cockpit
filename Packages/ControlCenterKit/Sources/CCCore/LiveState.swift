import Foundation

// MARK: - Channels

/// One live data stream. Clients subscribe to the channels their visible tiles
/// need; the Mac only runs the providers somebody is looking at.
public enum Channel: String, Codable, Sendable, CaseIterable, Hashable {
    case context, apps, system, media, audio, calendar, focus
    case bot, botSeries, botEvents
    case whoop, weather, timers, daily, portfolio, git, helper

    /// Cheap channels every client always receives: they drive the chrome
    /// (top bar, bottom strip, context switching).
    public static let always: Set<Channel> = [.context, .audio, .timers, .daily, .focus, .helper, .media]
}

// MARK: - Context

public enum MacPresence: String, Codable, Sendable, Hashable {
    case active, idle, locked, asleep
}

/// What is in front of you on the Mac right now.
public struct ActiveContext: Codable, Hashable, Sendable {
    public var bundleID: String
    public var appName: String
    public var windowTitle: String?
    /// Current tab URL when a browser is frontmost.
    public var url: String?
    public var pid: Int32?
    public var since: Date
    public var presence: MacPresence

    public init(bundleID: String, appName: String, windowTitle: String? = nil, url: String? = nil, pid: Int32? = nil, since: Date = .now, presence: MacPresence = .active) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.pid = pid
        self.since = since
        self.presence = presence
    }

    public var urlHost: String? {
        guard let url, let host = URL(string: url)?.host(percentEncoded: false) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct RunningApp: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var isActive: Bool
    public var isHidden: Bool
    public var pid: Int32

    public var id: String { bundleID }

    public init(bundleID: String, name: String, isActive: Bool, isHidden: Bool, pid: Int32) {
        self.bundleID = bundleID
        self.name = name
        self.isActive = isActive
        self.isHidden = isHidden
        self.pid = pid
    }
}

public struct RunningApps: Codable, Hashable, Sendable {
    public var apps: [RunningApp]
    public init(apps: [RunningApp]) { self.apps = apps }
}

// MARK: - System

public enum MemoryPressure: String, Codable, Sendable, Hashable { case normal, warning, critical }
public enum ThermalLevel: String, Codable, Sendable, Hashable { case nominal, fair, serious, critical }

public struct BatteryInfo: Codable, Hashable, Sendable {
    public var level: Double
    public var isCharging: Bool
    public var onAC: Bool
    public var minutesRemaining: Int?

    public init(level: Double, isCharging: Bool, onAC: Bool, minutesRemaining: Int? = nil) {
        self.level = level
        self.isCharging = isCharging
        self.onAC = onAC
        self.minutesRemaining = minutesRemaining
    }
}

public struct ProcessUsage: Codable, Hashable, Sendable, Identifiable {
    public var pid: Int32
    public var name: String
    public var cpu: Double
    public var memory: UInt64
    public var bundleID: String?

    public var id: Int32 { pid }

    public init(pid: Int32, name: String, cpu: Double, memory: UInt64, bundleID: String? = nil) {
        self.pid = pid
        self.name = name
        self.cpu = cpu
        self.memory = memory
        self.bundleID = bundleID
    }
}

public struct SystemStats: Codable, Hashable, Sendable {
    public var model: String
    /// 0…1 across all cores.
    public var cpu: Double
    /// 0…1 per logical core; efficiency cores first.
    public var cpuCores: [Double]
    public var efficiencyCores: Int
    public var memUsed: UInt64
    public var memTotal: UInt64
    public var memPressure: MemoryPressure
    public var swapUsed: UInt64
    public var gpu: Double?
    public var thermal: ThermalLevel
    public var battery: BatteryInfo?
    /// Bytes per second.
    public var netIn: Double
    public var netOut: Double
    public var diskFree: UInt64
    public var diskTotal: UInt64
    public var uptime: Double
    public var topProcesses: [ProcessUsage]
    public var sampledAt: Date

    public init(model: String, cpu: Double, cpuCores: [Double], efficiencyCores: Int, memUsed: UInt64, memTotal: UInt64, memPressure: MemoryPressure, swapUsed: UInt64, gpu: Double?, thermal: ThermalLevel, battery: BatteryInfo?, netIn: Double, netOut: Double, diskFree: UInt64, diskTotal: UInt64, uptime: Double, topProcesses: [ProcessUsage], sampledAt: Date) {
        self.model = model
        self.cpu = cpu
        self.cpuCores = cpuCores
        self.efficiencyCores = efficiencyCores
        self.memUsed = memUsed
        self.memTotal = memTotal
        self.memPressure = memPressure
        self.swapUsed = swapUsed
        self.gpu = gpu
        self.thermal = thermal
        self.battery = battery
        self.netIn = netIn
        self.netOut = netOut
        self.diskFree = diskFree
        self.diskTotal = diskTotal
        self.uptime = uptime
        self.topProcesses = topProcesses
        self.sampledAt = sampledAt
    }

    public var memFraction: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
}

// MARK: - Media & audio

public enum MediaSource: String, Codable, Sendable, Hashable {
    case spotify, music

    public var title: String { self == .spotify ? "Spotify" : "Music" }
    public var bundleID: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
}

public struct NowPlaying: Codable, Hashable, Sendable {
    public var source: MediaSource
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    /// Seconds into the track at `positionAt`. Clients extrapolate while playing,
    /// so the Mac never has to stream a ticking position.
    public var position: Double
    public var duration: Double
    public var positionAt: Date
    public var artworkID: String?
    public var artworkURL: String?

    public init(source: MediaSource, title: String, artist: String, album: String, isPlaying: Bool, position: Double, duration: Double, positionAt: Date = .now, artworkID: String? = nil, artworkURL: String? = nil) {
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.position = position
        self.duration = duration
        self.positionAt = positionAt
        self.artworkID = artworkID
        self.artworkURL = artworkURL
    }

    public func position(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionAt))
    }
}

/// `nil` track = nothing playing.
public struct MediaState: Codable, Hashable, Sendable {
    public var nowPlaying: NowPlaying?
    public init(nowPlaying: NowPlaying?) { self.nowPlaying = nowPlaying }
}

public struct AudioState: Codable, Hashable, Sendable {
    public var outputVolume: Double
    public var outputMuted: Bool
    public var outputDevice: String
    public var inputMuted: Bool
    public var inputVolume: Double
    public var inputDevice: String
    /// An app is capturing from the microphone right now (a call, a recording).
    public var micInUse: Bool

    public init(outputVolume: Double, outputMuted: Bool, outputDevice: String, inputMuted: Bool, inputVolume: Double, inputDevice: String, micInUse: Bool) {
        self.outputVolume = outputVolume
        self.outputMuted = outputMuted
        self.outputDevice = outputDevice
        self.inputMuted = inputMuted
        self.inputVolume = inputVolume
        self.inputDevice = inputDevice
        self.micInUse = micInUse
    }
}

// MARK: - Calendar & focus

public enum AccessState: String, Codable, Sendable, Hashable {
    case granted, denied, notDetermined, unavailable
}

public struct CalendarEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarName: String
    public var colorHex: String
    public var location: String?
    public var meetingURL: String?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendarName: String, colorHex: String, location: String? = nil, meetingURL: String? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.colorHex = colorHex
        self.location = location
        self.meetingURL = meetingURL
    }

    public func isOngoing(at date: Date) -> Bool { !isAllDay && start <= date && date < end }
}

public struct CalendarState: Codable, Hashable, Sendable {
    public var access: AccessState
    /// Today's events plus the next 24 hours, sorted by start.
    public var events: [CalendarEvent]

    public init(access: AccessState, events: [CalendarEvent]) {
        self.access = access
        self.events = events
    }

    public func next(after date: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.start > date }
    }

    public func ongoing(at date: Date) -> CalendarEvent? {
        events.first { $0.isOngoing(at: date) }
    }

    /// The event to feature: an ongoing one, else the next one.
    public func featured(at date: Date) -> CalendarEvent? {
        ongoing(at: date) ?? next(after: date)
    }

    public func today(_ date: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        events.filter { calendar.isDate($0.start, inSameDayAs: date) || ($0.isAllDay && calendar.isDate(date, inSameDayAs: $0.start)) }
    }
}

public struct FocusInfo: Codable, Hashable, Sendable {
    /// The Mac could read the Focus state (needs Full Disk Access).
    public var known: Bool
    public var active: Bool
    public var name: String?
    /// Focus names that have a matching "Focus: <Name>" shortcut on the Mac.
    public var available: [String]
    /// Whether the "Focus: Off" shortcut exists.
    public var canTurnOff: Bool

    public init(known: Bool, active: Bool, name: String?, available: [String], canTurnOff: Bool) {
        self.known = known
        self.active = active
        self.name = name
        self.available = available
        self.canTurnOff = canTurnOff
    }

    public var isControllable: Bool { !available.isEmpty }
}

// MARK: - Trading bot

public enum BotMode: String, Codable, Sendable, Hashable, CaseIterable {
    case off, simulated, live

    public var title: String {
        switch self {
        case .off: "Off"
        case .simulated: "Simulated"
        case .live: "Live"
        }
    }
}

public enum BotRunState: String, Codable, Sendable, Hashable {
    case running, paused, stopped, unreachable, unknown

    public var title: String {
        switch self {
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .unreachable: "Offline"
        case .unknown: "Unknown"
        }
    }
}

public enum PositionSide: String, Codable, Sendable, Hashable { case long, short }

public struct BotPosition: Codable, Hashable, Sendable, Identifiable {
    public var symbol: String
    public var side: PositionSide
    public var quantity: Double
    public var entryPrice: Double
    public var currentPrice: Double
    public var unrealizedPnL: Double
    public var openedAt: Date?

    public var id: String { "\(symbol)-\(side.rawValue)" }

    public init(symbol: String, side: PositionSide, quantity: Double, entryPrice: Double, currentPrice: Double, unrealizedPnL: Double, openedAt: Date? = nil) {
        self.symbol = symbol
        self.side = side
        self.quantity = quantity
        self.entryPrice = entryPrice
        self.currentPrice = currentPrice
        self.unrealizedPnL = unrealizedPnL
        self.openedAt = openedAt
    }

    public var unrealizedPct: Double {
        guard entryPrice != 0 else { return 0 }
        let move = (currentPrice - entryPrice) / entryPrice
        return side == .long ? move : -move
    }
}

public enum BotEventKind: String, Codable, Sendable, Hashable {
    case buy, sell, info, warning, error, paused, resumed
}

public struct BotEvent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var time: Date
    public var kind: BotEventKind
    public var symbol: String?
    public var quantity: Double?
    public var price: Double?
    public var pnl: Double?
    /// "filled", "stop", "take profit", "rejected"…
    public var outcome: String?
    public var message: String?

    public init(id: String = UUID().uuidString, time: Date, kind: BotEventKind, symbol: String? = nil, quantity: Double? = nil, price: Double? = nil, pnl: Double? = nil, outcome: String? = nil, message: String? = nil) {
        self.id = id
        self.time = time
        self.kind = kind
        self.symbol = symbol
        self.quantity = quantity
        self.price = price
        self.pnl = pnl
        self.outcome = outcome
        self.message = message
    }

    public var isTrade: Bool { kind == .buy || kind == .sell }
}

public struct BotOvernight: Codable, Hashable, Sendable {
    public var pnl: Double
    public var trades: Int
    public var from: Date
    public var to: Date

    public init(pnl: Double, trades: Int, from: Date, to: Date) {
        self.pnl = pnl
        self.trades = trades
        self.from = from
        self.to = to
    }
}

public struct BotState: Codable, Hashable, Sendable {
    public var mode: BotMode
    public var status: BotRunState
    public var pnlToday: Double
    public var pnlTodayPct: Double?
    public var equity: Double?
    public var currency: String
    public var positions: [BotPosition]
    public var tradesToday: Int
    public var lastHeartbeat: Date?
    public var apiConnected: Bool
    public var lastEvent: BotEvent?
    public var overnight: BotOvernight?
    public var error: String?
    public var updatedAt: Date

    public init(mode: BotMode, status: BotRunState, pnlToday: Double, pnlTodayPct: Double? = nil, equity: Double? = nil, currency: String = "EUR", positions: [BotPosition] = [], tradesToday: Int = 0, lastHeartbeat: Date? = nil, apiConnected: Bool = false, lastEvent: BotEvent? = nil, overnight: BotOvernight? = nil, error: String? = nil, updatedAt: Date = .now) {
        self.mode = mode
        self.status = status
        self.pnlToday = pnlToday
        self.pnlTodayPct = pnlTodayPct
        self.equity = equity
        self.currency = currency
        self.positions = positions
        self.tradesToday = tradesToday
        self.lastHeartbeat = lastHeartbeat
        self.apiConnected = apiConnected
        self.lastEvent = lastEvent
        self.overnight = overnight
        self.error = error
        self.updatedAt = updatedAt
    }

    public static let off = BotState(mode: .off, status: .unknown, pnlToday: 0)

    public var unrealizedTotal: Double { positions.reduce(0) { $0 + $1.unrealizedPnL } }
}

public struct PnLPoint: Codable, Hashable, Sendable {
    public var t: Date
    public var v: Double

    public init(t: Date, v: Double) {
        self.t = t
        self.v = v
    }
}

public struct PnLSeries: Codable, Hashable, Sendable {
    public var dayStart: Date
    public var points: [PnLPoint]

    public init(dayStart: Date, points: [PnLPoint]) {
        self.dayStart = dayStart
        self.points = points
    }
}

public struct BotEventLog: Codable, Hashable, Sendable {
    /// Newest first, capped.
    public var events: [BotEvent]
    public init(events: [BotEvent]) { self.events = events }
}

// MARK: - Health

public struct WhoopState: Codable, Hashable, Sendable {
    public enum ScoreState: String, Codable, Sendable, Hashable { case scored, pending, unscorable }

    public var configured: Bool
    public var connected: Bool
    public var recovery: Double?
    public var recoveryState: ScoreState?
    public var hrv: Double?
    public var restingHR: Double?
    public var spo2: Double?
    public var skinTemp: Double?
    public var strain: Double?
    public var sleepHours: Double?
    public var sleepPerformance: Double?
    public var sleepEfficiency: Double?
    public var recoveryAt: Date?
    public var updatedAt: Date?
    public var error: String?

    public init(configured: Bool, connected: Bool, recovery: Double? = nil, recoveryState: ScoreState? = nil, hrv: Double? = nil, restingHR: Double? = nil, spo2: Double? = nil, skinTemp: Double? = nil, strain: Double? = nil, sleepHours: Double? = nil, sleepPerformance: Double? = nil, sleepEfficiency: Double? = nil, recoveryAt: Date? = nil, updatedAt: Date? = nil, error: String? = nil) {
        self.configured = configured
        self.connected = connected
        self.recovery = recovery
        self.recoveryState = recoveryState
        self.hrv = hrv
        self.restingHR = restingHR
        self.spo2 = spo2
        self.skinTemp = skinTemp
        self.strain = strain
        self.sleepHours = sleepHours
        self.sleepPerformance = sleepPerformance
        self.sleepEfficiency = sleepEfficiency
        self.recoveryAt = recoveryAt
        self.updatedAt = updatedAt
        self.error = error
    }

    public static let notConfigured = WhoopState(configured: false, connected: false)
}

public enum RecoveryZone: String, Sendable, Hashable {
    case green, yellow, red

    /// WHOOP's own bands: 67–100 green, 34–66 yellow, 0–33 red.
    public init(score: Double) {
        switch score {
        case 67...: self = .green
        case 34..<67: self = .yellow
        default: self = .red
        }
    }
}

// MARK: - Weather

public struct HourForecast: Codable, Hashable, Sendable, Identifiable {
    public var time: Date
    public var temperature: Double
    public var code: Int
    public var precipitationChance: Int
    public var isDay: Bool

    public var id: Date { time }

    public init(time: Date, temperature: Double, code: Int, precipitationChance: Int, isDay: Bool) {
        self.time = time
        self.temperature = temperature
        self.code = code
        self.precipitationChance = precipitationChance
        self.isDay = isDay
    }
}

public struct WeatherState: Codable, Hashable, Sendable {
    public var location: String
    public var temperature: Double
    public var apparent: Double
    public var code: Int
    public var isDay: Bool
    public var high: Double
    public var low: Double
    public var precipitationChance: Int
    public var wind: Double
    public var hourly: [HourForecast]
    public var sunrise: Date?
    public var sunset: Date?
    public var updatedAt: Date

    public init(location: String, temperature: Double, apparent: Double, code: Int, isDay: Bool, high: Double, low: Double, precipitationChance: Int, wind: Double, hourly: [HourForecast], sunrise: Date?, sunset: Date?, updatedAt: Date) {
        self.location = location
        self.temperature = temperature
        self.apparent = apparent
        self.code = code
        self.isDay = isDay
        self.high = high
        self.low = low
        self.precipitationChance = precipitationChance
        self.wind = wind
        self.hourly = hourly
        self.sunrise = sunrise
        self.sunset = sunset
        self.updatedAt = updatedAt
    }

    public var condition: WeatherCondition { WeatherCondition(code: code, isDay: isDay) }
}

// MARK: - Timers

public enum TimerRunState: String, Codable, Sendable, Hashable { case running, paused, finished }

/// Timers live on the Mac. Clients receive `endsAt` and count down themselves,
/// so the iPad, the iPhone Live Activity and the menu bar all agree to the
/// second without a single tick crossing the network.
public struct TimerState: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: TimerKind
    public var label: String
    public var duration: Double
    public var state: TimerRunState
    public var startedAt: Date
    /// Valid while running.
    public var endsAt: Date?
    /// Valid while paused.
    public var remainingWhenPaused: Double?
    /// 1-based Pomodoro session within the cycle.
    public var session: Int
    public var sessionsPerCycle: Int
    public var focusDuring: Bool

    public init(id: String = UUID().uuidString, kind: TimerKind, label: String, duration: Double, state: TimerRunState, startedAt: Date, endsAt: Date?, remainingWhenPaused: Double? = nil, session: Int = 1, sessionsPerCycle: Int = 4, focusDuring: Bool = false) {
        self.id = id
        self.kind = kind
        self.label = label
        self.duration = duration
        self.state = state
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.remainingWhenPaused = remainingWhenPaused
        self.session = session
        self.sessionsPerCycle = sessionsPerCycle
        self.focusDuring = focusDuring
    }

    public func remaining(at date: Date) -> Double {
        switch state {
        case .running: max(0, (endsAt ?? date).timeIntervalSince(date))
        case .paused: max(0, remainingWhenPaused ?? duration)
        case .finished: 0
        }
    }

    public func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, 1 - remaining(at: date) / duration))
    }
}

public struct TimersState: Codable, Hashable, Sendable {
    public var timers: [TimerState]
    /// Where the next Pomodoro will start (1-based).
    public var nextSession: Int

    public init(timers: [TimerState], nextSession: Int = 1) {
        self.timers = timers
        self.nextSession = nextSession
    }

    public var primary: TimerState? {
        timers.first { $0.state != .finished }
    }
}

// MARK: - Daily

public struct Priority: Codable, Hashable, Sendable {
    public var text: String
    public var done: Bool

    public init(text: String, done: Bool = false) {
        self.text = text
        self.done = done
    }
}

public struct DailyState: Codable, Hashable, Sendable {
    /// yyyy-MM-dd, local to the Mac.
    public var date: String
    public var priorities: [Priority]
    /// Yesterday's unfinished priorities, offered for carry-over.
    public var carryOver: [Priority]
    public var pomodorosCompleted: Int
    public var focusMinutes: Double
    public var studyMode: Bool
    /// First connection of the day inside the morning window: show the Brief.
    public var briefPending: Bool
    public var dayStarted: Bool

    public init(date: String, priorities: [Priority] = [Priority(text: ""), Priority(text: ""), Priority(text: "")], carryOver: [Priority] = [], pomodorosCompleted: Int = 0, focusMinutes: Double = 0, studyMode: Bool = false, briefPending: Bool = false, dayStarted: Bool = false) {
        self.date = date
        self.priorities = priorities
        self.carryOver = carryOver
        self.pomodorosCompleted = pomodorosCompleted
        self.focusMinutes = focusMinutes
        self.studyMode = studyMode
        self.briefPending = briefPending
        self.dayStarted = dayStarted
    }
}

// MARK: - Portfolio (PortTracker)

public struct PortfolioMover: Codable, Hashable, Sendable, Identifiable {
    public var symbol: String
    public var name: String
    public var changePct: Double
    public var valueEur: Double?

    public var id: String { symbol }

    public init(symbol: String, name: String, changePct: Double, valueEur: Double?) {
        self.symbol = symbol
        self.name = name
        self.changePct = changePct
        self.valueEur = valueEur
    }
}

public struct TurboProximity: Codable, Hashable, Sendable, Identifiable {
    public var symbol: String
    public var underlying: String
    public var isLong: Bool
    public var distancePct: Double?
    public var knockedOut: Bool

    public var id: String { symbol }

    public init(symbol: String, underlying: String, isLong: Bool, distancePct: Double?, knockedOut: Bool) {
        self.symbol = symbol
        self.underlying = underlying
        self.isLong = isLong
        self.distancePct = distancePct
        self.knockedOut = knockedOut
    }

    /// PortTracker pulses a turbo within five percent of its barrier.
    public var inDanger: Bool { !knockedOut && (distancePct ?? 100) < 5 }
}

public struct PortfolioState: Codable, Hashable, Sendable {
    public var configured: Bool
    public var totalEur: Double?
    public var dayChangeEur: Double?
    public var dayChangePct: Double?
    public var gainers: [PortfolioMover]
    public var losers: [PortfolioMover]
    public var turbos: [TurboProximity]
    public var series: [Double]
    public var unpriced: [String]
    public var asOf: Date?
    public var error: String?

    public init(configured: Bool, totalEur: Double? = nil, dayChangeEur: Double? = nil, dayChangePct: Double? = nil, gainers: [PortfolioMover] = [], losers: [PortfolioMover] = [], turbos: [TurboProximity] = [], series: [Double] = [], unpriced: [String] = [], asOf: Date? = nil, error: String? = nil) {
        self.configured = configured
        self.totalEur = totalEur
        self.dayChangeEur = dayChangeEur
        self.dayChangePct = dayChangePct
        self.gainers = gainers
        self.losers = losers
        self.turbos = turbos
        self.series = series
        self.unpriced = unpriced
        self.asOf = asOf
        self.error = error
    }

    public static let notConfigured = PortfolioState(configured: false)
}

// MARK: - Git

public struct RepoStatus: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var name: String
    public var branch: String
    public var ahead: Int
    public var behind: Int
    public var staged: Int
    public var modified: Int
    public var untracked: Int
    public var conflicts: Int
    public var lastCommit: String?
    public var lastCommitDate: Date?

    public var id: String { path }

    public init(path: String, name: String, branch: String, ahead: Int = 0, behind: Int = 0, staged: Int = 0, modified: Int = 0, untracked: Int = 0, conflicts: Int = 0, lastCommit: String? = nil, lastCommitDate: Date? = nil) {
        self.path = path
        self.name = name
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.staged = staged
        self.modified = modified
        self.untracked = untracked
        self.conflicts = conflicts
        self.lastCommit = lastCommit
        self.lastCommitDate = lastCommitDate
    }

    public var isClean: Bool { staged + modified + untracked + conflicts == 0 }
}

public struct GitState: Codable, Hashable, Sendable {
    /// The repository the Mac considers current (Xcode's workspace, else the first configured).
    public var current: RepoStatus?
    public var repos: [RepoStatus]

    public init(current: RepoStatus?, repos: [RepoStatus]) {
        self.current = current
        self.repos = repos
    }
}

// MARK: - Helper status

public enum PermissionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case accessibility, automation, calendar, reminders, fullDiskAccess, inputMonitoring

    public var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .automation: "Automation"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .fullDiskAccess: "Full Disk Access"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    public var purpose: String {
        switch self {
        case .accessibility: "Send keystrokes, tile windows, read window titles"
        case .automation: "Control Spotify, Music, Safari and Terminal"
        case .calendar: "Today's schedule and the next event"
        case .reminders: "Mirror your top 3 priorities to Reminders"
        case .fullDiskAccess: "Read which Focus mode is active"
        case .inputMonitoring: "Record keystroke macros"
        }
    }
}

public struct PermissionStatus: Codable, Hashable, Sendable, Identifiable {
    public var kind: PermissionKind
    public var granted: Bool
    public var required: Bool

    public var id: PermissionKind { kind }

    public init(kind: PermissionKind, granted: Bool, required: Bool) {
        self.kind = kind
        self.granted = granted
        self.required = required
    }
}

public enum IntegrationHealth: String, Codable, Sendable, Hashable {
    case off, ok, warning, error, needsSetup
}

public struct IntegrationStatus: Codable, Hashable, Sendable, Identifiable {
    public var id: IntegrationID
    public var health: IntegrationHealth
    public var detail: String

    public init(id: IntegrationID, health: IntegrationHealth, detail: String) {
        self.id = id
        self.health = health
        self.detail = detail
    }
}

public enum DevicePlatform: String, Codable, Sendable, Hashable {
    case iPad, iPhone, mac, widget, unknown

    public var symbol: String {
        switch self {
        case .iPad: "ipad.landscape"
        case .iPhone: "iphone"
        case .mac: "laptopcomputer"
        case .widget: "square.grid.2x2"
        case .unknown: "questionmark.square"
        }
    }
}

public enum LinkTransport: String, Codable, Sendable, Hashable {
    case wifi, usb, demo

    public var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .usb: "USB-C"
        case .demo: "Demo"
        }
    }
}

public struct ConnectedDevice: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var platform: DevicePlatform
    public var transport: LinkTransport
    public var latencyMs: Double?
    public var connectedAt: Date

    public init(id: String, name: String, platform: DevicePlatform, transport: LinkTransport, latencyMs: Double?, connectedAt: Date) {
        self.id = id
        self.name = name
        self.platform = platform
        self.transport = transport
        self.latencyMs = latencyMs
        self.connectedAt = connectedAt
    }
}

public struct HelperStatus: Codable, Hashable, Sendable {
    public var version: String
    public var macName: String
    public var model: String
    public var osVersion: String
    public var permissions: [PermissionStatus]
    public var integrations: [IntegrationStatus]
    public var devices: [ConnectedDevice]

    public init(version: String, macName: String, model: String, osVersion: String, permissions: [PermissionStatus], integrations: [IntegrationStatus], devices: [ConnectedDevice]) {
        self.version = version
        self.macName = macName
        self.model = model
        self.osVersion = osVersion
        self.permissions = permissions
        self.integrations = integrations
        self.devices = devices
    }

    public func permission(_ kind: PermissionKind) -> Bool {
        permissions.first { $0.kind == kind }?.granted ?? false
    }

    public func integration(_ id: IntegrationID) -> IntegrationStatus? {
        integrations.first { $0.id == id }
    }
}

// MARK: - Channel values

/// One channel's full value. Channels are small, so a change replaces the whole
/// value; unchanged values are never resent (the hub diffs with `==`).
public enum ChannelValue: Hashable, Sendable {
    case context(ActiveContext)
    case apps(RunningApps)
    case system(SystemStats)
    case media(MediaState)
    case audio(AudioState)
    case calendar(CalendarState)
    case focus(FocusInfo)
    case bot(BotState)
    case botSeries(PnLSeries)
    case botEvents(BotEventLog)
    case whoop(WhoopState)
    case weather(WeatherState)
    case timers(TimersState)
    case daily(DailyState)
    case portfolio(PortfolioState)
    case git(GitState)
    case helper(HelperStatus)

    public var channel: Channel {
        switch self {
        case .context: .context
        case .apps: .apps
        case .system: .system
        case .media: .media
        case .audio: .audio
        case .calendar: .calendar
        case .focus: .focus
        case .bot: .bot
        case .botSeries: .botSeries
        case .botEvents: .botEvents
        case .whoop: .whoop
        case .weather: .weather
        case .timers: .timers
        case .daily: .daily
        case .portfolio: .portfolio
        case .git: .git
        case .helper: .helper
        }
    }
}

extension ChannelValue: Codable {
    private enum Keys: String, CodingKey { case ch, v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let channel = try c.decode(Channel.self, forKey: .ch)
        switch channel {
        case .context: self = .context(try c.decode(ActiveContext.self, forKey: .v))
        case .apps: self = .apps(try c.decode(RunningApps.self, forKey: .v))
        case .system: self = .system(try c.decode(SystemStats.self, forKey: .v))
        case .media: self = .media(try c.decode(MediaState.self, forKey: .v))
        case .audio: self = .audio(try c.decode(AudioState.self, forKey: .v))
        case .calendar: self = .calendar(try c.decode(CalendarState.self, forKey: .v))
        case .focus: self = .focus(try c.decode(FocusInfo.self, forKey: .v))
        case .bot: self = .bot(try c.decode(BotState.self, forKey: .v))
        case .botSeries: self = .botSeries(try c.decode(PnLSeries.self, forKey: .v))
        case .botEvents: self = .botEvents(try c.decode(BotEventLog.self, forKey: .v))
        case .whoop: self = .whoop(try c.decode(WhoopState.self, forKey: .v))
        case .weather: self = .weather(try c.decode(WeatherState.self, forKey: .v))
        case .timers: self = .timers(try c.decode(TimersState.self, forKey: .v))
        case .daily: self = .daily(try c.decode(DailyState.self, forKey: .v))
        case .portfolio: self = .portfolio(try c.decode(PortfolioState.self, forKey: .v))
        case .git: self = .git(try c.decode(GitState.self, forKey: .v))
        case .helper: self = .helper(try c.decode(HelperStatus.self, forKey: .v))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(channel, forKey: .ch)
        switch self {
        case .context(let v): try c.encode(v, forKey: .v)
        case .apps(let v): try c.encode(v, forKey: .v)
        case .system(let v): try c.encode(v, forKey: .v)
        case .media(let v): try c.encode(v, forKey: .v)
        case .audio(let v): try c.encode(v, forKey: .v)
        case .calendar(let v): try c.encode(v, forKey: .v)
        case .focus(let v): try c.encode(v, forKey: .v)
        case .bot(let v): try c.encode(v, forKey: .v)
        case .botSeries(let v): try c.encode(v, forKey: .v)
        case .botEvents(let v): try c.encode(v, forKey: .v)
        case .whoop(let v): try c.encode(v, forKey: .v)
        case .weather(let v): try c.encode(v, forKey: .v)
        case .timers(let v): try c.encode(v, forKey: .v)
        case .daily(let v): try c.encode(v, forKey: .v)
        case .portfolio(let v): try c.encode(v, forKey: .v)
        case .git(let v): try c.encode(v, forKey: .v)
        case .helper(let v): try c.encode(v, forKey: .v)
        }
    }
}

// MARK: - LiveState

/// Everything the hub knows, as one value. Both sides hold one.
public struct LiveState: Codable, Hashable, Sendable {
    public var context: ActiveContext?
    public var apps: RunningApps?
    public var system: SystemStats?
    public var media: MediaState?
    public var audio: AudioState?
    public var calendar: CalendarState?
    public var focus: FocusInfo?
    public var bot: BotState?
    public var botSeries: PnLSeries?
    public var botEvents: BotEventLog?
    public var whoop: WhoopState?
    public var weather: WeatherState?
    public var timers: TimersState?
    public var daily: DailyState?
    public var portfolio: PortfolioState?
    public var git: GitState?
    public var helper: HelperStatus?

    public init() {}

    /// Applies a value; returns `false` when nothing changed.
    @discardableResult
    public mutating func apply(_ value: ChannelValue) -> Bool {
        switch value {
        case .context(let v): return Self.assign(&context, v)
        case .apps(let v): return Self.assign(&apps, v)
        case .system(let v): return Self.assign(&system, v)
        case .media(let v): return Self.assign(&media, v)
        case .audio(let v): return Self.assign(&audio, v)
        case .calendar(let v): return Self.assign(&calendar, v)
        case .focus(let v): return Self.assign(&focus, v)
        case .bot(let v): return Self.assign(&bot, v)
        case .botSeries(let v): return Self.assign(&botSeries, v)
        case .botEvents(let v): return Self.assign(&botEvents, v)
        case .whoop(let v): return Self.assign(&whoop, v)
        case .weather(let v): return Self.assign(&weather, v)
        case .timers(let v): return Self.assign(&timers, v)
        case .daily(let v): return Self.assign(&daily, v)
        case .portfolio(let v): return Self.assign(&portfolio, v)
        case .git(let v): return Self.assign(&git, v)
        case .helper(let v): return Self.assign(&helper, v)
        }
    }

    public func value(for channel: Channel) -> ChannelValue? {
        switch channel {
        case .context: context.map(ChannelValue.context)
        case .apps: apps.map(ChannelValue.apps)
        case .system: system.map(ChannelValue.system)
        case .media: media.map(ChannelValue.media)
        case .audio: audio.map(ChannelValue.audio)
        case .calendar: calendar.map(ChannelValue.calendar)
        case .focus: focus.map(ChannelValue.focus)
        case .bot: bot.map(ChannelValue.bot)
        case .botSeries: botSeries.map(ChannelValue.botSeries)
        case .botEvents: botEvents.map(ChannelValue.botEvents)
        case .whoop: whoop.map(ChannelValue.whoop)
        case .weather: weather.map(ChannelValue.weather)
        case .timers: timers.map(ChannelValue.timers)
        case .daily: daily.map(ChannelValue.daily)
        case .portfolio: portfolio.map(ChannelValue.portfolio)
        case .git: git.map(ChannelValue.git)
        case .helper: helper.map(ChannelValue.helper)
        }
    }

    public func values(for channels: some Sequence<Channel>) -> [ChannelValue] {
        channels.compactMap(value(for:))
    }

    private static func assign<T: Equatable>(_ slot: inout T?, _ value: T) -> Bool {
        guard slot != value else { return false }
        slot = value
        return true
    }
}
