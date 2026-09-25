import Foundation

/// Every data tile the surface can show. Each declares the channels it reads —
/// the page's subscription is simply the union of its tiles' channels.
public enum WidgetKind: String, Codable, Hashable, Sendable, CaseIterable {
    // Trading bot
    case botSummary, botChart, botActions, botPositions, botLog, botHealth, botOvernight
    // Health
    case whoopSummary, recoveryBrief
    // Time
    case focusSchedule, agenda, nextEvent, pomodoro, timerCompact, dailyStats, clock
    // Mac
    case systemSummary, systemDetail, processes, appSwitcher, appContext, git
    // Media & audio
    case nowPlaying, volume, micControl, meeting
    // Morning
    case greeting, weather, priorities, startDay
    // Markets
    case portfolio, movers, turbos

    public struct Size: Hashable, Sendable {
        public let cols: Int
        public let rows: Int
        public init(_ cols: Int, _ rows: Int) {
            self.cols = cols
            self.rows = rows
        }
    }

    public enum Category: String, CaseIterable, Sendable {
        case trading = "Trading"
        case health = "Health"
        case time = "Time & Focus"
        case mac = "Mac"
        case media = "Media & Calls"
        case morning = "Morning"
        case markets = "Markets"
    }

    public var title: String {
        switch self {
        case .botSummary: "Trading Bot"
        case .botChart: "P&L Chart"
        case .botActions: "Bot Controls"
        case .botPositions: "Positions"
        case .botLog: "Trade Log"
        case .botHealth: "Bot Health"
        case .botOvernight: "Overnight"
        case .whoopSummary: "Recovery"
        case .recoveryBrief: "Recovery Brief"
        case .focusSchedule: "Focus & Schedule"
        case .agenda: "Today's Schedule"
        case .nextEvent: "Next Event"
        case .pomodoro: "Pomodoro"
        case .timerCompact: "Timer"
        case .dailyStats: "Today"
        case .clock: "Clock"
        case .systemSummary: "Mac"
        case .systemDetail: "Mac Monitor"
        case .processes: "Top Processes"
        case .appSwitcher: "Running Apps"
        case .appContext: "Current App"
        case .git: "Repository"
        case .nowPlaying: "Now Playing"
        case .volume: "Sound"
        case .micControl: "Microphone"
        case .meeting: "Meeting"
        case .greeting: "Greeting"
        case .weather: "Weather"
        case .priorities: "Top 3"
        case .startDay: "Start the Day"
        case .portfolio: "Portfolio"
        case .movers: "Movers"
        case .turbos: "Turbo Barriers"
        }
    }

    public var symbol: String {
        switch self {
        case .botSummary: "chart.line.uptrend.xyaxis"
        case .botChart: "chart.xyaxis.line"
        case .botActions: "playpause.circle"
        case .botPositions: "list.bullet.rectangle"
        case .botLog: "text.alignleft"
        case .botHealth: "waveform.path.ecg"
        case .botOvernight: "moon.stars"
        case .whoopSummary: "heart.circle"
        case .recoveryBrief: "bolt.heart"
        case .focusSchedule: "moon.circle"
        case .agenda: "calendar"
        case .nextEvent: "calendar.badge.clock"
        case .pomodoro: "timer"
        case .timerCompact: "timer.circle"
        case .dailyStats: "checkmark.seal"
        case .clock: "clock"
        case .systemSummary: "cpu"
        case .systemDetail: "gauge.with.dots.needle.67percent"
        case .processes: "list.number"
        case .appSwitcher: "square.grid.3x2"
        case .appContext: "macwindow"
        case .git: "arrow.triangle.branch"
        case .nowPlaying: "music.note"
        case .volume: "speaker.wave.2"
        case .micControl: "mic"
        case .meeting: "video"
        case .greeting: "sun.horizon"
        case .weather: "cloud.sun"
        case .priorities: "list.number"
        case .startDay: "sunrise"
        case .portfolio: "briefcase"
        case .movers: "arrow.up.arrow.down"
        case .turbos: "exclamationmark.triangle"
        }
    }

    public var category: Category {
        switch self {
        case .botSummary, .botChart, .botActions, .botPositions, .botLog, .botHealth, .botOvernight: .trading
        case .whoopSummary, .recoveryBrief: .health
        case .focusSchedule, .agenda, .nextEvent, .pomodoro, .timerCompact, .dailyStats, .clock: .time
        case .systemSummary, .systemDetail, .processes, .appSwitcher, .appContext, .git: .mac
        case .nowPlaying, .volume, .micControl, .meeting: .media
        case .greeting, .weather, .priorities, .startDay: .morning
        case .portfolio, .movers, .turbos: .markets
        }
    }

    public var channels: Set<Channel> {
        switch self {
        case .botSummary, .botChart: [.bot, .botSeries]
        case .botActions, .botPositions, .botHealth, .botOvernight: [.bot]
        case .botLog: [.botEvents]
        case .whoopSummary, .recoveryBrief: [.whoop]
        case .focusSchedule: [.focus, .calendar, .timers]
        case .agenda, .nextEvent: [.calendar]
        case .pomodoro: [.timers, .daily, .focus]
        case .timerCompact: [.timers]
        case .dailyStats: [.daily, .timers]
        case .clock: []
        case .systemSummary: [.system, .media, .audio]
        case .systemDetail, .processes: [.system]
        case .appSwitcher: [.apps]
        case .appContext: [.context, .apps]
        case .git: [.git, .context]
        case .nowPlaying: [.media]
        case .volume, .micControl: [.audio]
        case .meeting: [.calendar, .audio, .context]
        case .greeting: [.whoop, .calendar, .bot, .weather, .daily]
        case .weather: [.weather]
        case .priorities, .startDay: [.daily]
        case .portfolio, .movers, .turbos: [.portfolio]
        }
    }

    public var defaultSize: Size {
        switch self {
        case .botSummary, .whoopSummary, .focusSchedule, .systemSummary: Size(6, 6)
        case .botChart: Size(8, 6)
        case .botActions: Size(4, 6)
        case .botPositions: Size(7, 5)
        case .botLog: Size(5, 5)
        case .botHealth: Size(12, 1)
        case .botOvernight, .recoveryBrief, .weather: Size(4, 5)
        case .agenda, .priorities: Size(6, 5)
        case .nextEvent: Size(5, 3)
        case .pomodoro: Size(7, 8)
        case .timerCompact, .dailyStats, .clock, .volume: Size(4, 3)
        case .systemDetail: Size(8, 7)
        case .processes: Size(4, 5)
        case .appSwitcher: Size(6, 4)
        case .appContext: Size(6, 4)
        case .git: Size(4, 4)
        case .nowPlaying: Size(6, 3)
        case .micControl: Size(4, 5)
        case .meeting: Size(8, 5)
        case .greeting: Size(12, 2)
        case .startDay: Size(6, 2)
        case .portfolio: Size(6, 6)
        case .movers: Size(4, 6)
        case .turbos: Size(4, 4)
        }
    }

    public var minimumSize: Size {
        switch self {
        case .botHealth: Size(6, 1)
        case .greeting, .startDay: Size(4, 2)
        case .clock, .timerCompact, .dailyStats, .volume, .nextEvent, .nowPlaying: Size(3, 2)
        case .weather, .git, .turbos: Size(3, 3)
        default: Size(4, 3)
        }
    }
}
