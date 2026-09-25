import ActivityKit
import AppIntents
import CCCore
import SwiftUI
import WidgetKit

@main
struct ControlCenterWidgetBundle: WidgetBundle {
    var body: some Widget {
        BotWidget()
        RecoveryWidget()
        DeskWidget()
        DeskLiveActivity()
        if #available(iOS 18.0, *) {
            BotControl()
            MicControl()
            FocusSessionControl()
            StartDayControl()
        }
    }
}

// MARK: - Timeline

struct DeskEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let fresh: Bool
}

struct DeskWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Control Center"
    static let description = IntentDescription("Live numbers from your Mac.")
}

/// Reads what the app last saved to the App Group, then tries a fresh
/// encrypted one-shot fetch from the Mac (a few ms on the LAN).
struct DeskProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DeskEntry {
        DeskEntry(date: .now, snapshot: .preview, fresh: true)
    }

    func snapshot(for configuration: DeskWidgetIntent, in context: Context) async -> DeskEntry {
        if context.isPreview { return placeholder(in: context) }
        return DeskEntry(date: .now, snapshot: SharedStore.loadSnapshot() ?? .preview, fresh: false)
    }

    func timeline(for configuration: DeskWidgetIntent, in context: Context) async -> Timeline<DeskEntry> {
        var snapshot = SharedStore.loadSnapshot() ?? .empty
        var fresh = false
        if let state = await HubBridge.snapshot([.bot, .botSeries, .whoop, .timers, .calendar, .weather, .portfolio, .focus, .audio]) {
            let pages = snapshot.pages
            let scenes = snapshot.scenes
            snapshot = WidgetSnapshot(state: state, workspace: nil, macName: SharedStore.preferredMac?.macName, connected: true)
            snapshot.pages = pages
            snapshot.scenes = scenes
            SharedStore.saveSnapshot(snapshot)
            fresh = true
        }
        let entry = DeskEntry(date: .now, snapshot: snapshot, fresh: fresh)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(fresh ? 15 * 60 : 5 * 60)))
    }
}

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        let now = Date()
        var state = LiveState()
        var simulation = BotSimulation(now: now, seed: 11)
        _ = simulation.step(to: now)
        state.bot = simulation.state(now: now)
        state.botSeries = simulation.pnlSeries
        state.whoop = DemoData.whoop(now: now)
        state.calendar = DemoData.calendar(now: now)
        state.weather = DemoData.weather(now: now)
        state.portfolio = DemoData.portfolio(now: now)
        state.timers = TimersState(timers: [TimerState(kind: .pomodoro, label: "Focus", duration: 1500, state: .running, startedAt: now.addingTimeInterval(-420), endsAt: now.addingTimeInterval(1080), session: 2)])
        return WidgetSnapshot(state: state, workspace: nil, macName: "MacBook Pro", connected: true, now: now)
    }
}

// MARK: - Building blocks

struct WidgetSpark: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let low = min(values.min() ?? 0, 0)
            let high = max(values.max() ?? 1, 0)
            let span = max(high - low, 0.0001)
            let points = values.enumerated().map { index, value in
                CGPoint(x: proxy.size.width * CGFloat(index) / CGFloat(max(1, values.count - 1)), y: proxy.size.height * (1 - CGFloat((value - low) / span)))
            }
            if points.count > 1 {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: proxy.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct WidgetRing: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct Stale: View {
    let entry: DeskEntry

    var body: some View {
        if !entry.fresh, entry.snapshot.updatedAt > .distantPast {
            Text(entry.snapshot.updatedAt, style: .relative)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(CC.text3)
        }
    }
}

extension BotRunState {
    var widgetColor: Color {
        switch self {
        case .running: CC.green
        case .paused: CC.orange
        case .stopped, .unreachable: CC.red
        case .unknown: CC.text2
        }
    }
}

// MARK: - Bot widget

struct BotWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BotWidget", intent: DeskWidgetIntent.self, provider: DeskProvider()) { entry in
            BotWidgetView(entry: entry)
                .containerBackground(for: .widget) { CC.bg }
                .widgetURL(URL(string: "controlcenter://page/bot"))
        }
        .configurationDisplayName("Trading Bot")
        .description("Today's P&L, status and a pause button.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
    }
}

struct BotWidgetView: View {
    let entry: DeskEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let bot = entry.snapshot.bot, bot.mode != .off {
            switch family {
            case .accessoryInline:
                Text("Bot \(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("BOT · \(bot.status.title.uppercased())").font(.system(size: 11, weight: .semibold))
                    Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true)).font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text("\(bot.positions.count) positions · \(Fmt.percent(bot.pnlTodayPct ?? 0))").font(.system(size: 11))
                }
            case .systemSmall:
                small(bot)
            case .systemLarge:
                large(bot)
            default:
                medium(bot)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(CC.accent)
                Text("Trading bot").font(.system(size: 15, weight: .semibold)).foregroundStyle(CC.text)
                Text(SharedStore.preferredMac == nil ? "Pair with your Mac in Control Center." : "Not connected.").font(.system(size: 12)).foregroundStyle(CC.text2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Interactive (iOS 17): pauses or resumes the bot without opening anything.
    @ViewBuilder
    private func botButton(_ bot: BotState, long: Bool) -> some View {
        if bot.status == .paused {
            Button(intent: ResumeBotIntent()) {
                Label(long ? "Resume Bot" : "Resume", systemImage: "play.fill")
                    .font(.system(size: long ? 14 : 13, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(CC.green)
        } else {
            Button(intent: PauseBotIntent()) {
                Label(long ? "Pause Bot" : "Pause", systemImage: "pause.fill")
                    .font(.system(size: long ? 14 : 13, weight: .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(CC.orange)
        }
    }

    private func header(_ bot: BotState) -> some View {
        HStack(spacing: 5) {
            Circle().fill(bot.status.widgetColor).frame(width: 6, height: 6)
            Text(bot.mode == .simulated ? "BOT · SIM" : "BOT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(CC.text2)
            Spacer(minLength: 0)
            Stale(entry: entry)
        }
    }

    private func small(_ bot: BotState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(bot)
            Spacer(minLength: 0)
            Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(CC.pnl(bot.pnlToday))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(Fmt.percent(bot.pnlTodayPct ?? 0))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(CC.pnl(bot.pnlToday))
            WidgetSpark(values: entry.snapshot.botSeries.map(\.v), color: CC.pnl(bot.pnlToday))
                .frame(height: 34)
        }
    }

    private func medium(_ bot: BotState) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                header(bot)
                Spacer(minLength: 0)
                Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(CC.pnl(bot.pnlToday))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("\(Fmt.percent(bot.pnlTodayPct ?? 0)) · \(bot.positions.count) open · \(bot.tradesToday) trades")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(CC.text2)
                botButton(bot, long: false)
            }
            WidgetSpark(values: entry.snapshot.botSeries.map(\.v), color: CC.pnl(bot.pnlToday))
        }
    }

    private func large(_ bot: BotState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(bot)
            Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                .font(.system(size: 38, weight: .bold).monospacedDigit())
                .foregroundStyle(CC.pnl(bot.pnlToday))
            WidgetSpark(values: entry.snapshot.botSeries.map(\.v), color: CC.pnl(bot.pnlToday))
                .frame(height: 90)
            ForEach(bot.positions.prefix(4)) { position in
                HStack {
                    Text(position.symbol).font(.system(size: 13, weight: .semibold))
                    Text(position.side == .long ? "L" : "S").font(.system(size: 10, weight: .bold)).foregroundStyle(position.side == .long ? CC.green : CC.red)
                    Spacer()
                    Text(Fmt.money(position.unrealizedPnL, currency: bot.currency, signed: true))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.pnl(position.unrealizedPnL))
                }
                .foregroundStyle(CC.text)
            }
            Spacer(minLength: 0)
            botButton(bot, long: true)
        }
    }
}

// MARK: - Recovery widget

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "RecoveryWidget", intent: DeskWidgetIntent.self, provider: DeskProvider()) { entry in
            RecoveryWidgetView(entry: entry)
                .containerBackground(for: .widget) { CC.bg }
                .widgetURL(URL(string: "controlcenter://page/brief"))
        }
        .configurationDisplayName("Recovery")
        .description("WHOOP recovery, strain and sleep.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct RecoveryWidgetView: View {
    let entry: DeskEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let whoop = entry.snapshot.whoop
        let recovery = whoop?.recovery ?? 0
        switch family {
        case .accessoryCircular:
            Gauge(value: recovery, in: 0...100) {
                Image(systemName: "heart.fill")
            } currentValueLabel: {
                Text("\(Int(recovery))")
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("RECOVERY").font(.system(size: 11, weight: .semibold))
                Text("\(Int(recovery))%").font(.system(size: 22, weight: .bold))
                Text("Strain \(String(format: "%.1f", whoop?.strain ?? 0)) · \(whoop?.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—")").font(.system(size: 11))
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RECOVERY").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(CC.text2)
                    Spacer()
                    Stale(entry: entry)
                }
                ZStack {
                    WidgetRing(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 9)
                    Text(whoop?.recovery.map { "\(Int($0))%" } ?? "—")
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(CC.text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack {
                    Label(String(format: "%.1f", whoop?.strain ?? 0), systemImage: "flame.fill")
                    Spacer()
                    Label(whoop?.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—", systemImage: "bed.double.fill")
                }
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(CC.text2)
            }
        }
    }
}

// MARK: - Desk widget

struct DeskWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "DeskWidget", intent: DeskWidgetIntent.self, provider: DeskProvider()) { entry in
            DeskWidgetView(entry: entry)
                .containerBackground(for: .widget) { CC.bg }
                .widgetURL(URL(string: "controlcenter://page/home"))
        }
        .configurationDisplayName("Desk")
        .description("Bot, recovery, your next event and the running timer.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

struct DeskWidgetView: View {
    let entry: DeskEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snapshot = entry.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                if let bot = snapshot.bot, bot.mode != .off {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BOT").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(CC.text2)
                        Text(Fmt.money(bot.pnlToday, currency: bot.currency, signed: true))
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundStyle(CC.pnl(bot.pnlToday))
                            .minimumScaleFactor(0.6)
                    }
                }
                Spacer(minLength: 0)
                if let recovery = snapshot.whoop?.recovery {
                    ZStack {
                        WidgetRing(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 5)
                        Text("\(Int(recovery))").font(.system(size: 13, weight: .bold).monospacedDigit()).foregroundStyle(CC.text)
                    }
                    .frame(width: 42, height: 42)
                }
                if let weather = snapshot.weather {
                    VStack(spacing: 2) {
                        Image(systemName: weather.condition.symbol).symbolRenderingMode(.multicolor)
                        Text("\(Int(weather.temperature.rounded()))°").font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text)
                    }
                }
            }
            if let timer = snapshot.timer {
                HStack(spacing: 10) {
                    Image(systemName: timer.kind.isBreak ? "cup.and.saucer.fill" : "timer").foregroundStyle(timer.kind.isBreak ? CC.green : CC.orange)
                    Text(timer.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text)
                    Spacer()
                    if timer.state == .running, let end = timer.endsAt, end > entry.date {
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .font(.system(size: 17, weight: .semibold).monospacedDigit())
                            .foregroundStyle(CC.text)
                            .multilineTextAlignment(.trailing)
                    } else {
                        Text(Fmt.countdown(timer.remaining(at: entry.date))).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(CC.text2)
                    }
                    Button(intent: ToggleTimerIntent()) {
                        Image(systemName: timer.state == .running ? "pause.fill" : "play.fill")
                    }
                    .tint(CC.orange)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.elevated))
            } else {
                Button(intent: StartFocusSessionIntent()) {
                    Label("Start a focus session", systemImage: "timer").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity)
                }
                .tint(CC.accent)
            }
            if let event = snapshot.nextEvent {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(CC.hex(event.colorHex)).frame(width: 3, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text).lineLimit(1)
                        Text("\(Fmt.clock(event.start))–\(Fmt.clock(event.end))\(event.location.map { " · \($0)" } ?? "")").font(.system(size: 11).monospacedDigit()).foregroundStyle(CC.text2).lineLimit(1)
                    }
                    Spacer()
                    Text(event.start, style: .relative).font(.system(size: 11, weight: .semibold)).foregroundStyle(CC.accent)
                }
            }
            if family != .systemMedium, let bot = snapshot.bot, bot.mode != .off {
                WidgetSpark(values: snapshot.botSeries.map(\.v), color: CC.pnl(bot.pnlToday)).frame(maxHeight: 110)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Live Activity

struct DeskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeskActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, macName: context.attributes.macName)
                .activityBackgroundTint(Color(hex: 0x0A0A0F).opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.simulated ? "BOT · SIM" : "BOT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Text(Fmt.money(state.pnl, currency: state.currency, signed: true))
                            .font(.system(size: 20, weight: .bold).monospacedDigit())
                            .foregroundStyle(CC.pnl(state.pnl))
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let recovery = state.recovery {
                        ZStack {
                            WidgetRing(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 4)
                            Text("\(Int(recovery))").font(.system(size: 12, weight: .bold))
                        }
                        .frame(width: 38, height: 38)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Circle().fill(state.status.widgetColor).frame(width: 7, height: 7)
                        Text("\(state.status.title) · \(state.positions) open")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if let end = state.timerEndDate, !state.timerPaused, end > .now {
                            Image(systemName: "timer").foregroundStyle(CC.orange)
                            Text(timerInterval: Date.now...end, countsDown: true)
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .frame(maxWidth: 60)
                        }
                    }
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(state.status.widgetColor).frame(width: 6, height: 6)
                    Text(Fmt.compactMoney(state.pnl, currency: state.currency))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.pnl(state.pnl))
                }
            } compactTrailing: {
                if let end = state.timerEndDate, !state.timerPaused, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.orange)
                        .frame(maxWidth: 44)
                } else if let recovery = state.recovery {
                    Text("\(Int(recovery))%")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.recovery(recovery))
                }
            } minimal: {
                Circle().fill(CC.pnl(state.pnl)).frame(width: 9, height: 9)
            }
            .widgetURL(URL(string: "controlcenter://page/bot"))
        }
    }
}

struct LockScreenActivityView: View {
    let state: DeskActivityAttributes.ContentState
    let macName: String

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(state.status.widgetColor).frame(width: 7, height: 7)
                    Text(state.simulated ? "TRADING BOT · SIM" : "TRADING BOT")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(Fmt.money(state.pnl, currency: state.currency, signed: true))
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundStyle(CC.pnl(state.pnl))
                Text("\(Fmt.percent(state.pnlPct)) · \(state.positions) open · \(macName)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(spacing: 8) {
                if let recovery = state.recovery {
                    ZStack {
                        WidgetRing(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 5)
                        Text("\(Int(recovery))").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 48, height: 48)
                }
                if let end = state.timerEndDate, !state.timerPaused, end > .now {
                    Text(timerInterval: Date.now...end, countsDown: true)
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.orange)
                        .multilineTextAlignment(.center)
                        .frame(width: 64)
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Control Center (iOS 18)

@available(iOS 18.0, *)
struct BotControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "be.yorben.controlcenter.bot", provider: BotControlValue()) { running in
            ControlWidgetToggle("Trading Bot", isOn: running, action: SetBotRunningIntent()) { isOn in
                Label(isOn ? "Running" : "Paused", systemImage: isOn ? "play.circle.fill" : "pause.circle.fill")
            }
            .tint(.green)
        }
        .displayName("Trading Bot")
        .description("Pause or resume the bot on your Mac.")
    }
}

@available(iOS 18.0, *)
struct BotControlValue: ControlValueProvider {
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        if let bot = await HubBridge.snapshot([.bot])?.bot { return bot.status == .running }
        return SharedStore.loadSnapshot()?.bot?.status == .running
    }
}

@available(iOS 18.0, *)
struct MicControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "be.yorben.controlcenter.mic", provider: MicControlValue()) { muted in
            ControlWidgetToggle("Mac Microphone", isOn: muted, action: SetMicMutedIntent()) { isMuted in
                Label(isMuted ? "Muted" : "On", systemImage: isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .tint(.red)
        }
        .displayName("Mac Microphone")
        .description("Mute your Mac's microphone system-wide.")
    }
}

@available(iOS 18.0, *)
struct MicControlValue: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        if let audio = await HubBridge.snapshot([.audio])?.audio { return audio.inputMuted }
        return SharedStore.loadSnapshot()?.micMuted ?? false
    }
}

@available(iOS 18.0, *)
struct FocusSessionControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "be.yorben.controlcenter.focus") {
            ControlWidgetButton(action: StartFocusSessionIntent()) {
                Label("Focus Session", systemImage: "timer")
            }
        }
        .displayName("Focus Session")
        .description("Start a Pomodoro with Focus on your Mac.")
    }
}

@available(iOS 18.0, *)
struct StartDayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "be.yorben.controlcenter.startday") {
            ControlWidgetButton(action: StartTheDayIntent()) {
                Label("Start the Day", systemImage: "sunrise.fill")
            }
        }
        .displayName("Start the Day")
        .description("Focus, morning apps and a deep work timer.")
    }
}
