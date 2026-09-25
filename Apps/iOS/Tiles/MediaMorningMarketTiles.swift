import CCCore
import SwiftUI

// MARK: - Media

struct NowPlayingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Now Playing", symbol: "music.note") {
                if let source = model.store.media?.nowPlaying?.source {
                    Text(source.title).font(.system(size: 11, weight: .medium)).foregroundStyle(CC.text3)
                }
            }
            if let track = model.store.media?.nowPlaying {
                NowPlayingRow(track: track, artwork: 64)
            } else {
                Text("Nothing playing on your Mac")
                    .font(.system(size: 14))
                    .foregroundStyle(CC.text2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        .card()
    }
}

struct VolumeTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Sound", symbol: "speaker.wave.2.fill") {
                Text(model.store.audio?.outputDevice ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(CC.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VolumeControl()
            HStack(spacing: 10) {
                smallKey("speaker.minus.fill", .volumeDown)
                smallKey("speaker.plus.fill", .volumeUp)
                smallKey("playpause.fill", .playPause)
            }
        }
        .card()
    }

    private func smallKey(_ symbol: String, _ command: MediaCommand) -> some View {
        Button {
            Feedback.tap()
            model.send(.media(command))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CC.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(KeyFace(radius: 12))
        }
        .buttonStyle(PressStyle())
    }
}

/// The meeting page's big microphone: system-wide mute, live indicator.
struct MicControlTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let audio = model.store.audio
        let muted = audio?.inputMuted ?? false
        let live = (audio?.micInUse ?? false) && !muted
        let tint = muted ? CC.red : (live ? CC.green : CC.accent)
        GeometryReader { proxy in
        let circle = min(150, max(70, proxy.size.height - 120))
        VStack(spacing: 12) {
            CardHeader(title: "Microphone", symbol: "mic.fill") {
                if live { Pill(text: "Live", color: CC.green, dot: true) }
            }
            Spacer(minLength: 0)
            Button {
                Feedback.heavy()
                model.send(.audio(AudioCommand(.micToggle)))
            } label: {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(0.35), tint.opacity(0.08)], center: .center, startRadius: 4, endRadius: 90))
                    Circle().strokeBorder(tint.opacity(0.6), lineWidth: 2)
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: circle * 0.34, weight: .semibold))
                        .foregroundStyle(tint)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: circle, height: circle)
            }
            .buttonStyle(PressStyle(scale: 0.94))
            Text(muted ? "MUTED" : (live ? "YOU'RE LIVE" : "ON"))
                .font(.system(size: 15, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(tint)
            Text(audio?.inputDevice ?? "")
                .font(.system(size: 12))
                .foregroundStyle(CC.text2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        }
        .card()
    }
}

struct MeetingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let calendar = model.store.calendar
            let event = calendar?.ongoing(at: context.date) ?? calendar?.next(after: context.date)
            let app = model.store.context
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Meeting", symbol: "video.fill") {
                    HStack(spacing: 8) {
                        AppIconView(bundleID: app?.bundleID, size: 18)
                        Text(app?.appName ?? "").font(.system(size: 12, weight: .medium)).foregroundStyle(CC.text2)
                    }
                }
                if let event {
                    let ongoing = event.isOngoing(at: context.date)
                    Text(event.title)
                        .font(CCFont.heading(28))
                        .foregroundStyle(CC.text)
                        .lineLimit(2)
                    HStack(spacing: 24) {
                        Stat(label: ongoing ? "Elapsed" : "Starts", value: ongoing ? Fmt.countdown(context.date.timeIntervalSince(event.start)) : Fmt.clock(event.start), size: 30)
                        Stat(label: ongoing ? "Remaining" : "In", value: ongoing ? Fmt.countdown(event.end.timeIntervalSince(context.date)) : Fmt.until(event.start, from: context.date), color: ongoing && event.end.timeIntervalSince(context.date) < 300 ? CC.orange : CC.text, size: 30)
                        if ongoing {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel("Progress")
                                BarGauge(value: context.date.timeIntervalSince(event.start) / max(1, event.end.timeIntervalSince(event.start)), color: CC.accent, height: 8)
                                    .frame(width: 160)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if let link = event.meetingURL {
                        LargeActionButton(title: ongoing ? "Rejoin" : "Join", symbol: "video.fill", color: CC.green, height: 54) {
                            model.send(.openURL(URLRef(url: link)))
                        }
                        .frame(maxWidth: 260)
                    }
                } else {
                    Text("No meeting on the calendar")
                        .font(CCFont.heading(24))
                        .foregroundStyle(CC.text)
                    Text("Call keys work with Zoom, Teams, Google Meet, Webex and Discord — whichever is running.")
                        .font(.system(size: 13))
                        .foregroundStyle(CC.text2)
                    Spacer(minLength: 0)
                }
            }
            .card()
        }
    }
}

// MARK: - Morning

struct GreetingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            let brief = BriefComposer.compose(whoop: model.store.whoop, calendar: model.store.calendar, bot: model.store.bot, weather: model.store.weather, preferences: model.workspace.preferences, now: context.date)
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(brief.greeting)
                        .font(CCFont.heading(30))
                        .foregroundStyle(CC.text)
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(CC.text2)
                }
                Rectangle().fill(CC.divider).frame(width: 1).padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 5) {
                    Text(brief.headline)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tone(brief.tone))
                    Text(brief.lines.prefix(2).joined(separator: " "))
                        .font(.system(size: 13))
                        .foregroundStyle(CC.text2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if model.store.daily?.briefPending == true {
                    Button("Dismiss") { model.send(.daily(DailyCommand(.dismissBrief))) }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text2))
                }
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                ZStack {
                    CardBackground()
                    LinearGradient(colors: [tone(brief.tone).opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
                }
            )
        }
    }

    private func tone(_ tone: BriefTone) -> Color {
        switch tone {
        case .great: CC.green
        case .steady: CC.yellow
        case .careful: CC.red
        case .neutral: CC.accent
        }
    }
}

struct WeatherTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let weather = model.store.weather {
                CardHeader(title: weather.location, symbol: "location.fill") {
                    Text("H \(Int(weather.high.rounded()))° · L \(Int(weather.low.rounded()))°")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(CC.text2)
                }
                HStack(spacing: 14) {
                    Image(systemName: weather.condition.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 50))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(weather.temperature.rounded()))°")
                            .font(CCFont.display(48))
                            .foregroundStyle(CC.text)
                        Text("\(weather.condition.description) · feels \(Int(weather.apparent.rounded()))°")
                            .font(.system(size: 13))
                            .foregroundStyle(CC.text2)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(weather.hourly.prefix(6)) { hour in
                        VStack(spacing: 6) {
                            Text(Fmt.clock(hour.time).prefix(2) + "h")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(CC.text2)
                            Image(systemName: WeatherCondition(code: hour.code, isDay: hour.isDay).symbol)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 17))
                                .frame(height: 20)
                            Text("\(Int(hour.temperature.rounded()))°")
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CC.text)
                            Text(hour.precipitationChance >= 20 ? "\(hour.precipitationChance)%" : " ")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CC.accent)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                CardHeader(title: "Weather", symbol: "cloud.sun")
                SetupPrompt(symbol: "cloud.sun", title: "Weather is on its way", message: "Open-Meteo refreshes every 30 minutes.")
            }
        }
        .card()
    }
}

/// The three priority slots. Editable in place; they sync to every device
/// (and to Reminders, if you turn that on).
struct PrioritiesTile: View {
    @Environment(AppModel.self) private var model
    @State private var drafts: [String] = ["", "", ""]
    @FocusState private var focused: Int?

    var body: some View {
        let priorities = model.store.daily?.priorities ?? []
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Top 3 Today", symbol: "list.number") {
                if let carry = model.store.daily?.carryOver, !carry.isEmpty, priorities.contains(where: { $0.text.isEmpty }) {
                    Button("Carry over \(carry.count)") { model.send(.daily(DailyCommand(.carryOver))) }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CC.accent)
                }
            }
            ForEach(0..<3, id: \.self) { index in
                let priority = priorities.indices.contains(index) ? priorities[index] : Priority(text: "")
                HStack(spacing: 12) {
                    Button {
                        Feedback.tap()
                        model.send(.daily(DailyCommand(.togglePriority, index: index)))
                    } label: {
                        Image(systemName: priority.done ? "checkmark.circle.fill" : "\(index + 1).circle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(priority.done ? CC.green : CC.accent)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    .disabled(priority.text.isEmpty)
                    TextField("Priority \(index + 1)", text: binding(index, current: priority.text))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(priority.done ? CC.text2 : CC.text)
                        .strikethrough(priority.done, color: CC.text2)
                        .focused($focused, equals: index)
                        .submitLabel(.done)
                        .onSubmit { commit(index) }
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CC.elevated.opacity(0.6)))
            }
        }
        .card()
        .onChange(of: focused) { old, _ in
            if let old { commit(old) }
        }
        .onAppear { drafts = priorities.map(\.text) + Array(repeating: "", count: max(0, 3 - priorities.count)) }
        .onChange(of: priorities) { _, value in
            for index in 0..<3 where focused != index {
                drafts[index] = value.indices.contains(index) ? value[index].text : ""
            }
        }
    }

    private func binding(_ index: Int, current: String) -> Binding<String> {
        Binding(get: { drafts.indices.contains(index) ? drafts[index] : current }, set: { drafts[index] = $0 })
    }

    private func commit(_ index: Int) {
        let text = drafts[index].trimmingCharacters(in: .whitespaces)
        let current = model.store.daily?.priorities
        guard current?.indices.contains(index) != true || current?[index].text != text else { return }
        model.send(.daily(DailyCommand(.setPriority, index: index, text: text)))
    }
}

/// "Start the day": Focus on, morning apps open, a 90-minute deep work timer.
struct StartDayTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let started = model.store.daily?.dayStarted ?? false
        let preferences = model.workspace.preferences
        GeometryReader { proxy in
            if started {
                HStack(spacing: 14) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 26)).foregroundStyle(CC.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Day started").font(.system(size: 17, weight: .semibold)).foregroundStyle(CC.text)
                        Text("\(preferences.focusName) is on · deep work running").font(.system(size: 13)).foregroundStyle(CC.text2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(CardBackground(highlight: CC.green))
            } else {
                LargeActionButton(title: "Start the Day", symbol: "sunrise.fill", color: CC.orange, height: proxy.size.height, subtitle: "\(preferences.focusName) · morning apps · \(Int(preferences.deepWorkMinutes)) min deep work") {
                    model.send(.scene("startDay"))
                }
            }
        }
    }
}

// MARK: - Markets (PortTracker)

struct PortfolioGate<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder var content: (PortfolioState) -> Content

    var body: some View {
        if let portfolio = model.store.portfolio, portfolio.configured {
            content(portfolio)
        } else {
            SetupPrompt(symbol: "briefcase", title: "Connect PortTracker", message: "Net worth, today's move, your movers and turbo barriers — from your PortTracker deployment.", actionTitle: "Open Settings") {
                model.showSettings = true
            }
            .card()
        }
    }
}

struct PortfolioTile: View {
    var body: some View {
        PortfolioGate { portfolio in
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Portfolio · PortTracker", symbol: "briefcase.fill") {
                    if let asOf = portfolio.asOf {
                        Text(Fmt.clock(asOf)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(CC.text3)
                    }
                }
                if let error = portfolio.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CC.orange)
                }
                Text(portfolio.totalEur.map { Fmt.money($0) } ?? "—")
                    .font(CCFont.display(54))
                    .foregroundStyle(CC.text)
                    .contentTransition(.numericText(value: portfolio.totalEur ?? 0))
                    .animation(.snappy, value: portfolio.totalEur)
                HStack(spacing: 10) {
                    Text(Fmt.money(portfolio.dayChangeEur ?? 0, signed: true))
                    Text(Fmt.percent(portfolio.dayChangePct ?? 0, fraction: false))
                    Text("today").foregroundStyle(CC.text2).font(.system(size: 14))
                }
                .font(.system(size: 18, weight: .semibold).monospacedDigit())
                .foregroundStyle(CC.pnl(portfolio.dayChangeEur ?? 0))
                Sparkline(values: portfolio.series, color: CC.pnl((portfolio.series.last ?? 0) - (portfolio.series.first ?? 0)))
                    .frame(maxHeight: .infinity)
                if !portfolio.unpriced.isEmpty {
                    Text("Unpriced: \(portfolio.unpriced.joined(separator: ", "))")
                        .font(.system(size: 11))
                        .foregroundStyle(CC.text3)
                }
            }
            .card()
        }
    }
}

struct MoversTile: View {
    var body: some View {
        PortfolioGate { portfolio in
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Movers", symbol: "arrow.up.arrow.down")
                SectionLabel("Gainers", color: CC.green)
                ForEach(portfolio.gainers) { row($0) }
                if portfolio.gainers.isEmpty { empty }
                Divider().overlay(CC.divider)
                SectionLabel("Losers", color: CC.red)
                ForEach(portfolio.losers) { row($0) }
                if portfolio.losers.isEmpty { empty }
                Spacer(minLength: 0)
            }
            .card()
        }
    }

    private var empty: some View {
        Text("—").font(.system(size: 13)).foregroundStyle(CC.text3)
    }

    private func row(_ mover: PortfolioMover) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(mover.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(CC.text)
                Text(mover.name).font(.system(size: 11)).foregroundStyle(CC.text2).lineLimit(1)
            }
            Spacer()
            Text(Fmt.percent(mover.changePct, fraction: false))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(CC.pnl(mover.changePct))
        }
    }
}

struct TurbosTile: View {
    var body: some View {
        PortfolioGate { portfolio in
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Turbo Barriers", symbol: "exclamationmark.triangle.fill")
                if portfolio.turbos.isEmpty {
                    Text("No turbos held.").font(.system(size: 13)).foregroundStyle(CC.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(portfolio.turbos) { turbo in
                    HStack(spacing: 10) {
                        Text(turbo.isLong ? "L" : "S")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(turbo.isLong ? CC.green : CC.red)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill((turbo.isLong ? CC.green : CC.red).opacity(0.15)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(turbo.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(CC.text).lineLimit(1)
                            Text(turbo.underlying).font(.system(size: 11)).foregroundStyle(CC.text2)
                        }
                        Spacer()
                        if turbo.knockedOut {
                            Pill(text: "KO", color: CC.red)
                        } else {
                            Text(turbo.distancePct.map { String(format: "%.1f%%", $0) } ?? "—")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(turbo.inDanger ? CC.red : CC.text)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(turbo.inDanger ? CC.red.opacity(0.16) : .clear))
                                .modifier(DangerPulse(active: turbo.inDanger))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .card()
        }
    }
}

/// PortTracker's "pulsing red glow" for turbos within 5 % of the barrier.
struct DangerPulse: ViewModifier {
    var active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? CC.red.opacity(on ? 0.8 : 0.1) : .clear, radius: on ? 8 : 2)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever()) { on = true }
            }
    }
}
