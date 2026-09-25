import CCCore
import SwiftUI

// MARK: - Shared bits

/// A capsule switch in the palette's colours.
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
                    .fill(isOn ? color : CC.elevated)
                    .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.6) : CC.divider, lineWidth: 1))
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
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

// MARK: - WHOOP (home quadrant)

struct WhoopSummaryTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let whoop = model.store.whoop, whoop.connected {
            GeometryReader { proxy in
                let ring = min(proxy.size.height - 64, proxy.size.width * 0.38, 190)
                VStack(alignment: .leading, spacing: 14) {
                    CardHeader(title: "Recovery", symbol: "heart.circle.fill") {
                        Text(whoop.recoveryAt.map { "WHOOP · \(Fmt.clock($0))" } ?? "WHOOP")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(CC.text3)
                    }
                    HStack(spacing: 22) {
                        ZStack {
                            RingGauge(value: (whoop.recovery ?? 0) / 100, color: CC.recovery(whoop.recovery ?? 0), lineWidth: ring * 0.09)
                            VStack(spacing: 0) {
                                Text(whoop.recovery.map { "\(Int($0))" } ?? "—")
                                    .font(CCFont.display(ring * 0.3))
                                    .foregroundStyle(CC.text)
                                    .contentTransition(.numericText())
                                Text(whoop.recoveryState == .pending ? "SCORING" : "PERCENT")
                                    .font(.system(size: 10, weight: .semibold))
                                    .tracking(1.2)
                                    .foregroundStyle(CC.text2)
                            }
                        }
                        .frame(width: ring, height: ring)
                        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 18) {
                            GridRow {
                                metric("Strain", whoop.strain.map { String(format: "%.1f", $0) } ?? "—", nil, bar: (whoop.strain ?? 0) / 21, color: CC.accent)
                                metric("HRV", whoop.hrv.map { "\(Int($0.rounded()))" } ?? "—", "ms")
                            }
                            GridRow {
                                metric("Resting HR", whoop.restingHR.map { "\(Int($0))" } ?? "—", "bpm")
                                metric("Sleep", whoop.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—", nil)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    let (headline, tone) = BriefComposer.recoveryHeadline(whoop)
                    Text(headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(toneColor(tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .card()
        } else {
            SetupPrompt(symbol: "heart.circle", title: "Connect WHOOP", message: "Recovery, strain, HRV and sleep — signed in once on your Mac.", actionTitle: model.store.whoop?.configured == true ? "Sign in on Mac" : "Open Settings") {
                if model.store.whoop?.configured == true {
                    model.send(.integration(IntegrationCommand(.whoop, .connect)))
                } else {
                    model.showSettings = true
                }
            }
            .card()
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String?, bar: Double? = nil, color: Color = CC.accent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stat(label: label, value: value, size: 26, unit: unit)
            if let bar {
                BarGauge(value: bar, color: color, height: 5).frame(width: 90)
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
            CardHeader(title: "Recovery", symbol: "bolt.heart.fill")
            if let whoop, whoop.connected, let recovery = whoop.recovery {
                HStack(spacing: 16) {
                    ZStack {
                        RingGauge(value: recovery / 100, color: CC.recovery(recovery), lineWidth: 11)
                        Text("\(Int(recovery))%")
                            .font(CCFont.number(28, weight: .bold))
                            .foregroundStyle(CC.text)
                    }
                    .frame(width: 104, height: 104)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(zoneTitle(recovery))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CC.recovery(recovery))
                        Text(zoneAdvice(recovery))
                            .font(.system(size: 13))
                            .foregroundStyle(CC.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let performance = whoop.sleepPerformance {
                            Text("Sleep performance \(Int(performance))%")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(CC.text3)
                        }
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Stat(label: "Sleep", value: whoop.sleepHours.map { Fmt.hoursMinutes($0) } ?? "—", size: 18)
                    Spacer()
                    Stat(label: "HRV", value: whoop.hrv.map { "\(Int($0.rounded()))" } ?? "—", size: 18, unit: "ms")
                    Spacer()
                    Stat(label: "RHR", value: whoop.restingHR.map { "\(Int($0))" } ?? "—", size: 18, unit: "bpm")
                }
            } else {
                SetupPrompt(symbol: "heart.circle", title: "No recovery yet", message: whoop?.connected == true ? "WHOOP hasn't scored today's recovery." : "Connect WHOOP in Settings.")
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
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Focus & Schedule", symbol: "moon.circle.fill")
            HStack(spacing: 12) {
                Image(systemName: focus?.active == true ? "moon.fill" : "moon")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(focus?.active == true ? CC.indigo : CC.text2)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill((focus?.active == true ? CC.indigo : CC.text2).opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus?.active == true ? (focus?.name ?? "Focus on") : "Focus off")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CC.text)
                    Text(focusDetail(focus))
                        .font(.system(size: 12))
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                }
                Spacer()
                CCToggle(isOn: focus?.active == true, color: CC.indigo, enabled: focus?.isControllable ?? false) {
                    model.send(.focus(FocusCommand(focus?.active == true ? .off : .on, name: preferences.focusName)))
                }
            }
            Divider().overlay(CC.divider)
            NextEventBlock(compact: false)
            LaterToday()
                .frame(maxHeight: .infinity, alignment: .top)
            if let timer = model.store.timers?.primary {
                TimerRow(timer: timer)
            } else {
                HStack(spacing: 10) {
                    LargeActionButton(title: "Block \(Int(preferences.pomodoroMinutes)) min", symbol: "timer", color: CC.accent, height: 56) {
                        model.send(.timer(.start(.pomodoro, focus: true)))
                    }
                    LargeActionButton(title: "Deep \(Int(preferences.deepWorkMinutes))", symbol: "brain.head.profile", color: CC.indigo, style: .tinted, height: 56) {
                        model.send(.timer(.start(.deepWork, focus: true)))
                    }
                    .frame(maxWidth: 190)
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
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(CC.hex(event.colorHex))
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 5) {
                            SectionLabel(ongoing ? "Now · ends \(Fmt.until(event.end, from: context.date))" : "Next · \(Fmt.until(event.start, from: context.date))", color: ongoing ? CC.green : CC.accent)
                            Text(event.title)
                                .font(.system(size: compact ? 17 : 20, weight: .semibold))
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
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x0A0A0F))
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(Capsule().fill(CC.green))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").foregroundStyle(CC.green)
                        Text("Nothing else on the calendar today")
                            .font(.system(size: 15))
                            .foregroundStyle(CC.text2)
                    }
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
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Later")
                    ForEach(Array(later)) { event in
                        HStack(spacing: 10) {
                            Text(Fmt.clock(event.start))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CC.text2)
                            Circle().fill(CC.hex(event.colorHex)).frame(width: 6, height: 6)
                            Text(event.title)
                                .font(.system(size: 14))
                                .foregroundStyle(CC.text)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct NextEventTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Up Next", symbol: "calendar.badge.clock")
            NextEventBlock(compact: true)
            Spacer(minLength: 0)
        }
        .card()
    }
}

// MARK: - Agenda

struct AgendaTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let events = model.store.calendar?.today(context.date) ?? []
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Today", symbol: "calendar") {
                    Text("\(events.filter { !$0.isAllDay }.count) events")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CC.text3)
                }
                if events.isEmpty {
                    SetupPrompt(symbol: "sun.max", title: "A clear day", message: model.store.calendar?.access == .granted ? "Nothing on the calendar." : "Allow calendar access in the helper on your Mac.")
                } else {
                    ScrollViewReader { reader in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 6) {
                                ForEach(events) { event in
                                    agendaRow(event, now: context.date)
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

    private func agendaRow(_ event: CalendarEvent, now: Date) -> some View {
        let past = event.end < now
        let ongoing = event.isOngoing(at: now)
        return HStack(spacing: 12) {
            Text(event.isAllDay ? "ALL DAY" : Fmt.clock(event.start))
                .font(.system(size: event.isAllDay ? 10 : 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(ongoing ? CC.green : CC.text2)
                .frame(width: 52, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(CC.hex(event.colorHex)).frame(width: 3, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text([event.isAllDay ? nil : "\(Fmt.duration(event.end.timeIntervalSince(event.start)))", event.location, event.meetingURL == nil ? nil : "Online"].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if ongoing { Pill(text: "Now", color: CC.green, dot: true) }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ongoing ? CC.green.opacity(0.08) : .clear))
        .opacity(past ? 0.45 : 1)
    }
}

// MARK: - Pomodoro (Study)

/// Large, centred: ring, 64 pt time, session dots, start/pause/reset/skip and
/// "do not disturb until the timer ends" (Focus on Mac and iPhone together).
struct PomodoroTile: View {
    @Environment(AppModel.self) private var model
    @State private var kind: TimerKind = .pomodoro
    @State private var focusWhenStarting = true

    var body: some View {
        let timer = model.store.timers?.primary
        let preferences = model.workspace.preferences
        let session = timer?.session ?? model.store.timers?.nextSession ?? 1
        let cycle = timer?.sessionsPerCycle ?? preferences.sessionsPerCycle
        GeometryReader { proxy in
            let ring = min(proxy.size.height - 70, proxy.size.width * 0.5, 330)
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: timer.map { $0.kind.isBreak ? "Break" : "Focus Session \($0.session) of \($0.sessionsPerCycle)" } ?? "Pomodoro", symbol: "timer") {
                    HStack(spacing: 6) {
                        ForEach(1...max(1, cycle), id: \.self) { index in
                            Circle()
                                .fill(index < session || (index == session && timer?.state == .finished) ? CC.orange : (index == session ? CC.orange.opacity(0.5) : CC.text3.opacity(0.45)))
                                .frame(width: 9, height: 9)
                        }
                    }
                }
                HStack(spacing: 28) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let remaining = timer?.remaining(at: context.date) ?? preferences.minutes(for: kind) * 60
                        let progress = timer?.progress(at: context.date) ?? 0
                        let tint = (timer?.kind ?? kind).isBreak ? CC.green : CC.orange
                        ZStack {
                            RingGauge(value: progress, color: tint, lineWidth: ring * 0.055)
                                .animation(.linear(duration: 1), value: progress)
                            VStack(spacing: 4) {
                                Text(Fmt.countdown(remaining))
                                    .font(CCFont.display(64))
                                    .foregroundStyle(timer?.state == .paused ? CC.text2 : CC.text)
                                    .contentTransition(.numericText(countsDown: true))
                                    .animation(.snappy(duration: 0.3), value: Int(remaining))
                                Text((timer?.label ?? kind.title).uppercased())
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(1.4)
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
                HStack(spacing: 4) {
                    ForEach([TimerKind.pomodoro, .shortBreak, .longBreak, .deepWork], id: \.self) { option in
                        Button {
                            Feedback.tap()
                            withAnimation(.snappy) { kind = option }
                        } label: {
                            VStack(spacing: 1) {
                                Text("\(Int(preferences.minutes(for: option)))")
                                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                Text(option == .pomodoro ? "FOCUS" : option == .shortBreak ? "BREAK" : option == .longBreak ? "LONG" : "DEEP")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .tracking(0.8)
                            }
                            .foregroundStyle(kind == option ? CC.text : CC.text2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(kind == option ? CC.accent.opacity(0.3) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressStyle(scale: 0.95))
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(CC.elevated.opacity(0.7)))
                LargeActionButton(title: "Start", symbol: "play.fill", color: CC.orange) {
                    model.send(.timer(TimerCommand(.start, preset: TimerPreset(kind: kind, focus: !kind.isBreak && focusWhenStarting))))
                }
            } else if let timer {
                LargeActionButton(title: timer.state == .running ? "Pause" : "Resume", symbol: timer.state == .running ? "pause.fill" : "play.fill", color: timer.state == .running ? CC.orange : CC.green) {
                    model.send(.timer(TimerCommand(.toggle)))
                }
                HStack(spacing: 10) {
                    LargeActionButton(title: "Reset", symbol: "arrow.counterclockwise", color: CC.accent, style: .tinted, height: 52) {
                        model.send(.timer(TimerCommand(.reset)))
                    }
                    LargeActionButton(title: "Skip", symbol: "forward.end.fill", color: CC.accent, style: .tinted, height: 52) {
                        model.send(.timer(TimerCommand(.skip)))
                    }
                    LargeActionButton(title: "+5", symbol: "plus", color: CC.accent, style: .tinted, height: 52) {
                        model.send(.timer(TimerCommand(.extend, seconds: 300)))
                    }
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Do not disturb until timer ends")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CC.text)
                    Text("Focus on your Mac and iPhone")
                        .font(.system(size: 12))
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
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.elevated.opacity(0.6)))
            if let daily = model.store.daily {
                Text("Today: \(daily.pomodorosCompleted) session\(daily.pomodorosCompleted == 1 ? "" : "s") · \(Fmt.hoursMinutes(daily.focusMinutes / 60)) focused")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(CC.text2)
            }
        }
        .frame(maxWidth: 340)
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
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        SectionLabel(timer.label, color: tint)
                        Text(Fmt.countdown(timer.remaining(at: context.date)))
                            .font(CCFont.number(26))
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
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
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
        }
        .buttonStyle(PressStyle())
    }
}

struct TimerCompactTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Timer", symbol: "timer")
            if let timer = model.store.timers?.primary {
                TimerRow(timer: timer)
            } else {
                LargeActionButton(title: "Focus \(Int(model.workspace.preferences.pomodoroMinutes))", symbol: "play.fill", color: CC.orange, height: 56) {
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
            CardHeader(title: "Today", symbol: "checkmark.seal.fill")
            HStack {
                Stat(label: "Sessions", value: "\(daily?.pomodorosCompleted ?? 0)", size: 26)
                Spacer()
                Stat(label: "Focused", value: Fmt.hoursMinutes((daily?.focusMinutes ?? 0) / 60), size: 26)
                Spacer()
                Stat(label: "Top 3", value: "\(daily?.priorities.filter(\.done).count ?? 0)/\(daily?.priorities.filter { !$0.text.isEmpty }.count ?? 0)", size: 26)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

struct ClockTile: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.clock(context.date, seconds: true))
                    .font(CCFont.display(52))
                    .foregroundStyle(CC.text)
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 15))
                    .foregroundStyle(CC.text2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .card()
    }
}
