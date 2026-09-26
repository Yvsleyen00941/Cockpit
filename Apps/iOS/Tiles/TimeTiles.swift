import CCCore
import SwiftUI

// MARK: - Shared bits

/// A glass switch: the track glows in its colour when on.
struct CCToggle: View {
    var isOn: Bool
    var color: Color = CC.accent
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(CC.track))
                    .overlay(Capsule().strokeBorder(isOn ? .white.opacity(0.28) : CC.divider, lineWidth: 1))
                    .glow(isOn ? color : .clear, spread: 8, opacity: 0.4, y: 2)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(CC.ink.opacity(0.12), lineWidth: 0.5))
                    .padding(3)
            }
            .frame(width: 54, height: 32)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOn)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// A soft disc of light behind a gauge — the halo from the fleet dashboard.
struct Halo: View {
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            let radius = min(proxy.size.width, proxy.size.height) / 2
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.3), color.opacity(0.08), color.opacity(0)], center: .center, startRadius: radius * 0.55, endRadius: radius * 1.12))
                .frame(width: radius * 2.24, height: radius * 2.24)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - WHOOP (home quadrant)

struct WhoopSummaryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let whoop = model.store.whoop, whoop.connected {
            GeometryReader { proxy in
                let ring = min(proxy.size.height - 70, proxy.size.width * 0.38, 200)
                let metricSize: CGFloat = proxy.size.width < 440 ? 22 : 30
                let tint = CC.recovery(whoop.recovery ?? 0)
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Recovery", symbol: "heart.fill", tint: tint) {
                        Text(whoop.recoveryAt.map { "WHOOP · \(Fmt.clock($0))" } ?? "WHOOP")
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(CC.text3)
                    }
                    HStack(spacing: 26) {
                        ZStack {
                            Halo(color: tint)
                            RingGauge(value: (whoop.recovery ?? 0) / 100, color: tint, lineWidth: ring * 0.075)
                            VStack(spacing: 0) {
                                Text(whoop.recovery.map { "\(Int($0))" } ?? "—")
                                    .font(CCFont.display(ring * 0.34))
                                    .tracking(-ring * 0.01)
                                    .foregroundStyle(CC.text)
                                    .contentTransition(.numericText())
                                Text(whoop.recoveryState == .pending ? "Scoring" : "Recovery")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(CC.text2)
                            }
                        }
                        .frame(width: ring, height: ring)
                        Grid(alignment: .leading, horizontalSpacing: metricSize < 30 ? 16 : 26, verticalSpacing: 18) {
                            GridRow {
                                metric("Strain", whoop.strain.map { String(format: "%.1f", $0) } ?? "—", nil, size: metricSize, bar: (whoop.strain ?? 0) / 21, color: CC.accent)
                                metric("HRV", whoop.hrv.map { "\(Int($0.rounded()))" } ?? "—", "ms", size: metricSize)
                            }
                            GridRow {
                                metric("Resting HR", whoop.restingHR.map { "\(Int($0))" } ?? "—", "bpm", size: metricSize)
                                metric("Sleep", whoop.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—", nil, size: metricSize)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    let (headline, tone) = BriefComposer.recoveryHeadline(whoop)
                    Text(headline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(toneColor(tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .card()
        } else {
            SetupPrompt(symbol: "heart.fill", title: "Connect WHOOP", message: "Recovery, strain, HRV and sleep — signed in once on your Mac.", actionTitle: model.store.whoop?.configured == true ? "Sign in on Mac" : "Open Settings") {
                if model.store.whoop?.configured == true {
                    model.send(.integration(IntegrationCommand(.whoop, .connect)))
                } else {
                    model.showSettings = true
                }
            }
            .card()
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String?, size: CGFloat = 30, bar: Double? = nil, color: Color = CC.accent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Stat(label: label, value: value, size: size, unit: unit)
            if let bar {
                BarGauge(value: bar, color: color, height: 5).frame(width: 96)
            }
        }
    }

    private func toneColor(_ tone: BriefTone) -> Color {
        switch tone {
        case .great: CC.green
        case .steady: CC.yellow
        case .careful: CC.red
        case .neutral: CC.text2
        }
    }
}

/// Morning Brief variant: the ring, the plain-language line, sleep detail.
struct RecoveryBriefTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let whoop = model.store.whoop
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Recovery", symbol: "bolt.heart.fill", tint: whoop?.recovery.map(CC.recovery) ?? CC.accent)
            if let whoop, whoop.connected, let recovery = whoop.recovery {
                HStack(spacing: 18) {
                    ZStack {
                        Halo(color: CC.recovery(recovery))
                        RingGauge(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 9)
                        Text("\(Int(recovery))%")
                            .font(CCFont.display(30))
                            .foregroundStyle(CC.text)
                    }
                    .frame(width: 108, height: 108)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(zoneTitle(recovery))
                            .font(CCFont.title(24, weight: .regular))
                            .foregroundStyle(CC.recovery(recovery))
                        Text(zoneAdvice(recovery))
                            .font(.system(size: 14))
                            .foregroundStyle(CC.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let performance = whoop.sleepPerformance {
                            Text("Sleep performance \(Int(performance))%")
                                .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(CC.text3)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Stat(label: "Sleep", value: whoop.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—", size: 20)
                    Spacer()
                    Stat(label: "HRV", value: whoop.hrv.map { "\(Int($0.rounded()))" } ?? "—", size: 20, unit: "ms")
                    Spacer()
                    Stat(label: "RHR", value: whoop.restingHR.map { "\(Int($0))" } ?? "—", size: 20, unit: "bpm")
                }
            } else {
                SetupPrompt(symbol: "heart", title: "No recovery yet", message: whoop?.connected == true ? "WHOOP hasn't scored today's recovery." : "Connect WHOOP in Settings.")
            }
        }
        .card()
    }
}

private func zoneTitle(_ recovery: Double) -> String {
    switch RecoveryZone(score: recovery) {
    case .green: "Primed"
    case .yellow: "Steady"
    case .red: "Recover"
    }
}

private func zoneAdvice(_ recovery: Double) -> String {
    switch RecoveryZone(score: recovery) {
    case .green: "Put the hardest problem first — your body can take the load."
    case .yellow: "Front-load focus, keep training moderate."
    case .red: "Light work, short sessions, early night."
    }
}

// MARK: - Focus & schedule (home quadrant)

struct FocusScheduleTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let focus = model.store.focus
        let preferences = model.workspace.preferences
        let active = focus?.active == true
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Focus & schedule", symbol: "moon.fill", tint: CC.indigo)
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(active ? CC.indigo.opacity(0.22) : CC.elevated)
                        Image(systemName: active ? "moon.fill" : "moon")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(active ? CC.indigo : CC.text2)
                    }
                    .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active ? (focus?.name ?? "Focus on") : "Focus off")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(CC.text)
                        Text(focusDetail(focus))
                            .font(.system(size: 13))
                            .foregroundStyle(CC.text2)
                            .lineLimit(1)
                    }
                    Spacer()
                    CCToggle(isOn: active, color: CC.indigo, enabled: focus?.isControllable ?? false) {
                        model.send(.focus(FocusCommand(active ? .off : .on, name: preferences.focusName)))
                    }
                }
                NextEventBlock(compact: proxy.size.height < 330)
                    .padding(12)
                    .background(Well(radius: 16))
                if proxy.size.height > 300 {
                    LaterToday()
                }
                Spacer(minLength: 0)
                if let timer = model.store.timers?.primary {
                    TimerRow(timer: timer)
                } else {
                    HStack(spacing: 10) {
                        LargeActionButton(title: "Block \(Int(preferences.pomodoroMinutes)) min", symbol: "timer", color: CC.accent, height: 50) {
                            model.send(.timer(.start(.pomodoro, focus: true)))
                        }
                        LargeActionButton(title: "Deep \(Int(preferences.deepWorkMinutes))", symbol: "brain.head.profile", color: CC.indigo, style: .tinted, height: 50) {
                            model.send(.timer(.start(.deepWork, focus: true)))
                        }
                        .frame(maxWidth: 180)
                    }
                }
            }
        }
        .card()
    }

    private func focusDetail(_ focus: FocusInfo?) -> String {
        guard let focus else { return "Waiting for your Mac" }
        if !focus.isControllable { return "Add “Focus: …” shortcuts on your Mac" }
        if !focus.known { return "Last set from Control Center" }
        return focus.active ? "Syncs to your iPhone" : "\(focus.available.count) modes ready"
    }
}

/// The next (or ongoing) calendar event with a live countdown and Join.
struct NextEventBlock: View {
    var compact: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let calendar = model.store.calendar, calendar.access == .granted {
                if let event = calendar.featured(at: context.date) {
                    let ongoing = event.isOngoing(at: context.date)
                    let color = CC.hex(event.colorHex)
                    HStack(alignment: .center, spacing: 12) {
                        Capsule()
                            .fill(color)
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ongoing ? "Now · ends \(Fmt.until(event.end, from: context.date))" : "Next · \(Fmt.until(event.start, from: context.date))")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(ongoing ? CC.green : CC.accent)
                            Text(event.title)
                                .font(.system(size: compact ? 17 : 20, weight: .medium))
                                .foregroundStyle(CC.text)
                                .lineLimit(compact ? 1 : 2)
                            Text([ "\(Fmt.clock(event.start))–\(Fmt.clock(event.end))", event.location ].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(CC.text2)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let link = event.meetingURL {
                            Button {
                                model.send(.openURL(URLRef(url: link)))
                            } label: {
                                Label("Join", systemImage: "video.fill")
                            }
                            .buttonStyle(GlowCapsuleStyle(color: CC.green, height: 36))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(CC.green)
                        Text("Nothing else on the calendar today")
                            .font(.system(size: 15))
                            .foregroundStyle(CC.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button {
                    model.send(.integration(IntegrationCommand(.calendar, .connect)))
                } label: {
                    Label("Allow calendar access on your Mac", systemImage: "calendar.badge.exclamationmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CC.accent)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The next couple of events after the featured one, compact.
struct LaterToday: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let events = model.store.calendar?.today(context.date) ?? []
            let featured = model.store.calendar?.featured(at: context.date)
            let later = events.filter { !$0.isAllDay && $0.start > context.date && $0.id != featured?.id }.prefix(2)
            if !later.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    SectionLabel("Later")
                    ForEach(Array(later)) { event in
                        HStack(spacing: 10) {
                            Text(Fmt.clock(event.start))
                                .font(.system(size: 13.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(CC.text2)
                            Circle()
                                .fill(CC.hex(event.colorHex))
                                .frame(width: 7, height: 7)
                            Text(event.title)
                                .font(.system(size: 14.5))
                                .foregroundStyle(CC.text)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

struct NextEventTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Up next", symbol: "calendar.badge.clock")
            NextEventBlock(compact: true)
            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - Agenda

/// Today as a timeline: a line with a dot per event; the one in progress glows.
struct AgendaTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let events = model.store.calendar?.today(context.date) ?? []
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Today", symbol: "calendar") {
                    Text("\(events.filter { !$0.isAllDay }.count) events")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CC.text3)
                }
                if events.isEmpty {
                    SetupPrompt(symbol: "sun.max", title: "A clear day", message: model.store.calendar?.access == .granted ? "Nothing on the calendar." : "Allow calendar access in the helper on your Mac.")
                } else {
                    ScrollViewReader { reader in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 2) {
                                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                                    agendaRow(event, now: context.date, first: index == 0, last: index == events.count - 1)
                                        .id(event.id)
                                }
                            }
                        }
                        .onAppear {
                            // Start at what's happening now, not at 08:00.
                            if let current = events.first(where: { $0.end > context.date && !$0.isAllDay }) {
                                reader.scrollTo(current.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    private func agendaRow(_ event: CalendarEvent, now: Date, first: Bool, last: Bool) -> some View {
        let past = event.end < now
        let ongoing = event.isOngoing(at: now)
        let color = CC.hex(event.colorHex)
        return HStack(spacing: 12) {
            Text(event.isAllDay ? "All day" : Fmt.clock(event.start))
                .font(.system(size: event.isAllDay ? 12 : 14, weight: .medium).monospacedDigit())
                .foregroundStyle(ongoing ? CC.green : CC.text2)
                .frame(width: 50, alignment: .leading)
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(first ? .clear : CC.divider).frame(width: 1.5)
                    Rectangle().fill(last ? .clear : CC.divider).frame(width: 1.5)
                }
                Circle()
                    .fill(ongoing ? CC.green : color)
                    .frame(width: ongoing ? 11 : 8, height: ongoing ? 11 : 8)
                    .background(Circle().fill(CC.green.opacity(ongoing ? 0.3 : 0)).frame(width: 22, height: 22))
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text([event.isAllDay ? nil : "\(Fmt.duration(event.end.timeIntervalSince(event.start)))", event.location, event.meetingURL == nil ? nil : "Online"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12.5))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if ongoing { Pill(text: "Now", color: CC.green, dot: true) }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background {
            if ongoing { Well(radius: 14, tint: CC.green) }
        }
        .opacity(past ? 0.42 : 1)
    }
}

// MARK: - Pomodoro (Study)

/// Large, centred: ring, 72 pt time, session dots, start/pause/reset/skip and
/// "do not disturb until the timer ends" (Focus on Mac and iPhone together).
struct PomodoroTile: View {
    @Environment(AppModel.self) private var model
    @State private var kind: TimerKind = .pomodoro
    @State private var focusWhenStarting = true
    @Namespace private var presetSelection

    var body: some View {
        let timer = model.store.timers?.primary
        let preferences = model.workspace.preferences
        let session = timer?.session ?? model.store.timers?.nextSession ?? 1
        let cycle = timer?.sessionsPerCycle ?? preferences.sessionsPerCycle
        GeometryReader { proxy in
            let ring = min(proxy.size.height - 58, proxy.size.width * 0.5, 330)
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: timer.map { $0.kind.isBreak ? "Break" : "Focus session \($0.session) of \($0.sessionsPerCycle)" } ?? "Pomodoro", symbol: "timer", tint: CC.orange) {
                    HStack(spacing: 7) {
                        ForEach(1...max(1, cycle), id: \.self) { index in
                            let done = index < session || (index == session && timer?.state == .finished)
                            let current = index == session
                            Capsule()
                                .fill(done ? CC.orange : (current ? CC.orange.opacity(0.55) : CC.track))
                                .frame(width: current ? 22 : 9, height: 9)
                        }
                    }
                }
                HStack(spacing: 30) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = timer?.remaining(at: context.date) ?? preferences.minutes(for: kind) * 60
                        let progress = timer?.progress(at: context.date) ?? 0
                        let tint = (timer?.kind ?? kind).isBreak ? CC.green : CC.orange
                        ZStack {
                            Halo(color: tint).opacity(timer == nil ? 0.5 : 1)
                            RingGauge(value: progress, color: tint, lineWidth: ring * 0.04)
                                .animation(.linear(duration: 1), value: progress)
                            VStack(spacing: 2) {
                                Text(Fmt.countdown(remaining))
                                    .font(.system(size: min(78, ring * 0.25), weight: .ultraLight).monospacedDigit())
                                    .tracking(-2)
                                    .foregroundStyle(timer?.state == .paused ? CC.text2 : CC.text)
                                    .contentTransition(.numericText(countsDown: true))
                                    .animation(.snappy(duration: 0.3), value: Int(remaining))
                                Text(timer?.label ?? kind.title)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(tint)
                            }
                        }
                        .frame(width: ring, height: ring)
                    }
                    controls(timer)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .card()
    }

    @ViewBuilder
    private func controls(_ timer: TimerState?) -> some View {
        let preferences = model.workspace.preferences
        VStack(alignment: .leading, spacing: 14) {
            if timer == nil {
                HStack(spacing: 2) {
                    ForEach([TimerKind.pomodoro, .shortBreak, .longBreak, .deepWork], id: \.self) { option in
                        Button {
                            Feedback.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { kind = option }
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(Int(preferences.minutes(for: option)))")
                                    .font(.system(size: 19, weight: kind == option ? .medium : .light).monospacedDigit())
                                Text(option == .pomodoro ? "Focus" : option == .shortBreak ? "Break" : option == .longBreak ? "Long" : "Deep")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(kind == option ? .white : CC.text2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background {
                                if kind == option {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(LinearGradient(colors: [Color(hex: 0x6A92FF), Color(hex: 0x3A62F5)], startPoint: .top, endPoint: .bottom))
                                        .glow(Color(hex: 0x3A62F5), spread: 10, opacity: 0.45, y: 3)
                                        .matchedGeometryEffect(id: "preset", in: presetSelection)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.95))
                    }
                }
                .padding(4)
                .background(Well(radius: 18))
                LargeActionButton(title: "Start", symbol: "play.fill", color: CC.orange, height: 60) {
                    model.send(.timer(TimerCommand(.start, preset: TimerPreset(kind: kind, focus: !kind.isBreak && focusWhenStarting))))
                }
            } else if let timer {
                LargeActionButton(title: timer.state == .running ? "Pause" : "Resume", symbol: timer.state == .running ? "pause.fill" : "play.fill", color: timer.state == .running ? CC.orange : CC.green, height: 60) {
                    model.send(.timer(TimerCommand(.toggle)))
                }
                HStack(spacing: 10) {
                    LargeActionButton(title: "Reset", symbol: "arrow.counterclockwise", color: CC.accent, style: .tinted, height: 48) {
                        model.send(.timer(TimerCommand(.reset)))
                    }
                    LargeActionButton(title: "Skip", symbol: "forward.end.fill", color: CC.accent, style: .tinted, height: 48) {
                        model.send(.timer(TimerCommand(.skip)))
                    }
                    LargeActionButton(title: "+5", symbol: "plus", color: CC.accent, style: .tinted, height: 48) {
                        model.send(.timer(TimerCommand(.extend, seconds: 300)))
                    }
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Do not disturb")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(CC.text)
                    Text("Mac and iPhone, until it ends")
                        .font(.system(size: 12.5))
                        .foregroundStyle(CC.text2)
                }
                Spacer()
                CCToggle(isOn: timer?.focusDuring ?? focusWhenStarting, color: CC.indigo) {
                    if let timer {
                        model.send(.timer(TimerCommand(.setFocus, enabled: !timer.focusDuring)))
                    } else {
                        focusWhenStarting.toggle()
                    }
                }
            }
            .padding(14)
            .background(Well(radius: 18))
            if let daily = model.store.daily {
                Text("Today: \(daily.pomodorosCompleted) session\(daily.pomodorosCompleted == 1 ? "" : "s") · \(Fmt.hoursMinutes(daily.focusMinutes / 60)) focused")
                    .font(.system(size: 13.5).monospacedDigit())
                    .foregroundStyle(CC.text2)
            }
        }
        .frame(maxWidth: 350)
    }
}

/// Compact timer used inside the Focus & Schedule quadrant.
struct TimerRow: View {
    let timer: TimerState
    @Environment(AppModel.self) private var model

    var body: some View {
        let tint = timer.kind.isBreak ? CC.green : CC.orange
        HStack(spacing: 14) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 14) {
                    RingGauge(value: timer.progress(at: context.date), color: tint, lineWidth: 5)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(timer.label, color: tint)
                        Text(Fmt.countdown(timer.remaining(at: context.date)))
                            .font(.system(size: 26, weight: .light).monospacedDigit())
                            .foregroundStyle(CC.text)
                            .contentTransition(.numericText(countsDown: true))
                    }
                }
            }
            Spacer()
            circleButton(timer.state == .running ? "pause.fill" : "play.fill", tint) { model.send(.timer(TimerCommand(.toggle))) }
            circleButton("stop.fill", CC.text2) { model.send(.timer(TimerCommand(.stop))) }
        }
        .padding(10)
        .background(Well(radius: 18, tint: tint))
    }

    private func circleButton(_ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 42, height: 42)
                .background(Circle().fill(CC.elevated))
                .overlay(Circle().strokeBorder(CC.divider, lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

struct TimerCompactTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Timer", symbol: "timer", tint: CC.orange)
            if let timer = model.store.timers?.primary {
                TimerRow(timer: timer)
            } else {
                LargeActionButton(title: "Focus \(Int(model.workspace.preferences.pomodoroMinutes))", symbol: "play.fill", color: CC.orange, height: 52) {
                    model.send(.timer(.start(.pomodoro, focus: true)))
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

struct DailyStatsTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let daily = model.store.daily
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Today", symbol: "checkmark.seal.fill", tint: CC.green)
            HStack {
                Stat(label: "Sessions", value: "\(daily?.pomodorosCompleted ?? 0)", size: 32)
                Spacer()
                Stat(label: "Focused", value: Fmt.hoursMinutes((daily?.focusMinutes ?? 0) / 60), size: 32)
                Spacer()
                Stat(label: "Top 3", value: "\(daily?.priorities.filter(\.done).count ?? 0)/\(daily?.priorities.filter { !$0.text.isEmpty }.count ?? 0)", size: 32)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

struct ClockTile: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.clock(context.date, seconds: true))
                    .font(.system(size: 60, weight: .ultraLight).monospacedDigit())
                    .tracking(-1.5)
                    .foregroundStyle(CC.text)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(CC.text2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .card()
    }
}
