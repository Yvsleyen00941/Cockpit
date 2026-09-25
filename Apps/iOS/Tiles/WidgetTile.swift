import CCCore
import SwiftUI

/// Routes a widget kind to its view.
struct WidgetTile: View {
    let kind: WidgetKind
    let pageID: String

    var body: some View {
        switch kind {
        case .botSummary: BotSummaryTile()
        case .botChart: BotChartTile()
        case .botActions: BotActionsTile()
        case .botPositions: BotPositionsTile()
        case .botLog: BotLogTile()
        case .botHealth: BotHealthTile()
        case .botOvernight: BotOvernightTile()
        case .whoopSummary: WhoopSummaryTile()
        case .recoveryBrief: RecoveryBriefTile()
        case .focusSchedule: FocusScheduleTile()
        case .agenda: AgendaTile()
        case .nextEvent: NextEventTile()
        case .pomodoro: PomodoroTile()
        case .timerCompact: TimerCompactTile()
        case .dailyStats: DailyStatsTile()
        case .clock: ClockTile()
        case .systemSummary: SystemSummaryTile()
        case .systemDetail: SystemDetailTile()
        case .processes: ProcessesTile()
        case .appSwitcher: AppSwitcherTile()
        case .appContext: AppContextTile()
        case .git: GitTile()
        case .nowPlaying: NowPlayingTile()
        case .volume: VolumeTile()
        case .micControl: MicControlTile()
        case .meeting: MeetingTile()
        case .greeting: GreetingTile()
        case .weather: WeatherTile()
        case .priorities: PrioritiesTile()
        case .startDay: StartDayTile()
        case .portfolio: PortfolioTile()
        case .movers: MoversTile()
        case .turbos: TurbosTile()
        }
    }
}

/// Everything a bot tile needs to know about "not configured".
struct BotGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: (BotState) -> Content

    var body: some View {
        if let bot = model.store.bot, bot.mode != .off {
            content(bot)
        } else {
            SetupPrompt(symbol: "chart.line.uptrend.xyaxis", title: "Connect your trading bot", message: "Point the helper at your bot's local API — or run the simulated bot to try everything.", actionTitle: "Open Settings") {
                model.showSettings = true
            }
            .card()
        }
    }
}

extension BotRunState {
    var color: Color {
        switch self {
        case .running: CC.green
        case .paused: CC.orange
        case .stopped, .unreachable: CC.red
        case .unknown: CC.text2
        }
    }
}
