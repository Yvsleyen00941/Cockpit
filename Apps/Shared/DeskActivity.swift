import ActivityKit
import CCCore
import Foundation

/// The iPhone Live Activity: bot status and P&L, recovery, and the running
/// timer — on the Lock Screen and in the Dynamic Island.
///
/// `ContentState` must stay byte-compatible with the Mac helper's
/// `DeskContentState` (it can push this JSON through APNs).
struct DeskActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var botStatus: String
        var pnl: Double
        var pnlPct: Double
        var currency: String
        var positions: Int
        var recovery: Double?
        var timerLabel: String?
        /// Epoch seconds (Double, not Date, so the Mac's JSON decodes exactly).
        var timerEnd: Double?
        var timerPaused: Bool
        var timerRemaining: Double?
        var simulated: Bool
        var updatedAt: Double

        init(state: LiveState, now: Date = .now) {
            let bot = state.bot
            botStatus = bot?.status.rawValue ?? BotRunState.unknown.rawValue
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
            updatedAt = now.timeIntervalSince1970
        }

        init(snapshot: WidgetSnapshot) {
            var state = LiveState()
            state.bot = snapshot.bot
            state.whoop = snapshot.whoop
            state.timers = snapshot.timer.map { TimersState(timers: [$0]) }
            self.init(state: state, now: snapshot.updatedAt)
        }

        var status: BotRunState { BotRunState(rawValue: botStatus) ?? .unknown }
        var timerEndDate: Date? { timerEnd.map { Date(timeIntervalSince1970: $0) } }
        var updated: Date { Date(timeIntervalSince1970: updatedAt) }
    }

    var macName: String
}
