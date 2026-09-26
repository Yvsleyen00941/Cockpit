import CCCore
import SwiftUI

// MARK: - Media

struct NowPlayingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Now playing", symbol: "music.note", tint: CC.pink) {
                if let source = model.store.media?.nowPlaying?.source {
                    Text(source.title).font(.system(size: 13, weight: .medium)).foregroundStyle(CC.text3)
                }
            }
            if let track = model.store.media?.nowPlaying {
                NowPlayingRow(track: track, artwork: 68)
            } else {
                Text("Nothing playing on your Mac")
                    .font(.system(size: 15))
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
                    .font(.system(size: 12.5, weight: .medium))
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
                .foregroundStyle(CC.icon)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(KeyFace(radius: 16))
        }
        .buttonStyle(PressStyle())
    }
}

/// The meeting page's big microphone: a lit orb — green when you're live,
/// red when muted — that mutes system-wide.
struct MicControlTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let audio = model.store.audio
        let muted = audio?.inputMuted ?? false
        let live = (audio?.micInUse ?? false) && !muted
        let tint = muted ? CC.red : (live ? CC.green : CC.accent)
        GeometryReader { proxy in
            let circle = min(156, max(72, proxy.size.height - 128))
            VStack(spacing: 12) {
                CardHeader(title: "Microphone", symbol: "mic.fill", tint: tint) {
                    if live { Pill(text: "Live", color: CC.green, dot: true) }
                }
                Spacer(minLength: 0)
                Button {
                    Feedback.heavy()
                    model.send(.audio(AudioCommand(.micToggle)))
                } label: {
                    ZStack {
                        Halo(color: tint)
                        Circle()
                            .fill(RadialGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: circle * 0.75))
                        Circle()
                            .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)], center: UnitPoint(x: 0.32, y: 0.24), startRadius: 0, endRadius: circle * 0.36))
                        Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
                        Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: circle * 0.32, weight: .semibold))
                            .foregroundStyle(tint.legibleText(in: .dark))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .frame(width: circle, height: circle)
                }
                .buttonStyle(PressStyle(scale: 0.94))
                Text(muted ? "Muted" : (live ? "You're live" : "On"))
                    .font(CCFont.title(22, weight: .light))
                    .foregroundStyle(tint)
                Text(audio?.inputDevice ?? "")
                    .font(.system(size: 13))
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
                CardHeader(title: "Meeting", symbol: "video.fill", tint: CC.teal) {
                    HStack(spacing: 8) {
                        AppIconView(bundleID: app?.bundleID, size: 22)
                        Text(app?.appName ?? "").font(.system(size: 13, weight: .medium)).foregroundStyle(CC.text2)
                    }
                }
                if let event {
                    let ongoing = event.isOngoing(at: context.date)
                    Text(event.title)
                        .font(CCFont.title(32, weight: .light))
                        .foregroundStyle(CC.text)
                        .lineLimit(2)
                    HStack(alignment: .bottom, spacing: 28) {
                        Stat(label: ongoing ? "Elapsed" : "At", value: ongoing ? Fmt.countdown(context.date.timeIntervalSince(event.start)) : Fmt.clock(event.start), size: 34)
                        Stat(label: ongoing ? "Remaining" : "Starts in", value: ongoing ? Fmt.countdown(event.end.timeIntervalSince(context.date)) : Fmt.duration(max(0, event.start.timeIntervalSince(context.date))), color: ongoing && event.end.timeIntervalSince(context.date) < 300 ? CC.orange : CC.text, size: 34)
                        if ongoing {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Progress")
                                BarGauge(value: context.date.timeIntervalSince(event.start) / max(1, event.end.timeIntervalSince(event.start)), color: CC.teal, height: 7)
                                    .frame(width: 170)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    Spacer(minLength: 0)
                    if let link = event.meetingURL {
                        LargeActionButton(title: ongoing ? "Rejoin" : "Join", symbol: "video.fill", color: CC.green, height: 52) {
                            model.send(.openURL(URLRef(url: link)))
                        }
                        .frame(maxWidth: 260)
                    }
                } else {
                    Text("No meeting on the calendar")
                        .font(CCFont.title(28, weight: .light))
                        .foregroundStyle(CC.text)
                    Text("Call keys work with Zoom, Teams, Google Meet, Webex and Discord — whichever is running.")
                        .font(.system(size: 14))
                        .foregroundStyle(CC.text2)
                    Spacer(minLength: 0)
                }
            }
            .card()
        }
    }
}

// MARK: - Morning

/// The Brief's greeting isn't a tile — it's written straight onto the
/// sunrise, big and light.
struct GreetingTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            let brief = BriefComposer.compose(whoop: model.store.whoop, calendar: model.store.calendar, bot: model.store.bot, weather: model.store.weather, preferences: model.workspace.preferences, now: context.date)
            HStack(alignment: .center, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(brief.greeting)
                        .font(CCFont.title(42, weight: .light))
                        .tracking(-0.6)
                        .foregroundStyle(CC.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(CC.text2)
                }
                Capsule().fill(CC.divider).frame(width: 1.5).padding(.vertical, 10)
                VStack(alignment: .leading, spacing: 5) {
                    Text(brief.headline)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(tone(brief.tone))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(brief.lines.prefix(2).joined(separator: " "))
                        .font(.system(size: 14.5))
                        .foregroundStyle(CC.text2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if model.store.daily?.briefPending == true {
                    Button("Dismiss") { model.send(.daily(DailyCommand(.dismissBrief))) }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text))
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 10) {
            if let weather = model.store.weather {
                CardHeader(title: weather.location, symbol: "location.fill", tint: CC.teal) {
                    Text("H \(Int(weather.high.rounded()))° · L \(Int(weather.low.rounded()))°")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .foregroundStyle(CC.text2)
                }
                HStack(spacing: 16) {
                    Image(systemName: weather.condition.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 58))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(Int(weather.temperature.rounded()))°")
                            .font(.system(size: 62, weight: .ultraLight).monospacedDigit())
                            .tracking(-1.5)
                            .foregroundStyle(CC.text)
                        Text("\(weather.condition.description) · feels \(Int(weather.apparent.rounded()))°")
                            .font(.system(size: 14))
                            .foregroundStyle(CC.text2)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    ForEach(Array(weather.hourly.prefix(6).enumerated()), id: \.element.id) { index, hour in
                        VStack(spacing: 6) {
                            Text(index == 0 ? "Now" : Fmt.clock(hour.time).prefix(2) + "h")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(index == 0 ? CC.text : CC.text2)
                            Image(systemName: WeatherCondition(code: hour.code, isDay: hour.isDay).symbol)
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 18))
                                .frame(height: 22)
                            Text("\(Int(hour.temperature.rounded()))°")
                                .font(.system(size: 14, weight: .medium).monospacedDigit())
                                .foregroundStyle(CC.text)
                            Text(hour.precipitationChance >= 20 ? "\(hour.precipitationChance)%" : " ")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(CC.accent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if index == 0 { Well(radius: 14, tint: CC.accent) }
                        }
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
        VStack(alignment: .leading, spacing: 7) {
            CardHeader(title: "Top 3 today", symbol: "list.number") {
                if let carry = model.store.daily?.carryOver, !carry.isEmpty, priorities.contains(where: { $0.text.isEmpty }) {
                    Button("Carry over \(carry.count)") { model.send(.daily(DailyCommand(.carryOver))) }
                        .font(.system(size: 13, weight: .semibold))
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
                        ZStack {
                            Circle()
                                .fill(priority.done ? AnyShapeStyle(LinearGradient(colors: [CC.green.opacity(0.85), CC.green], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(CC.accent.opacity(0.14)))

                            Circle().strokeBorder(priority.done ? .white.opacity(0.3) : CC.accent.opacity(0.4), lineWidth: 1)
                            if priority.done {
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(CC.ink)
                            } else {
                                Text("\(index + 1)").font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(CC.accent)
                            }
                        }
                        .frame(width: 26, height: 26)
                    }
                    .buttonStyle(PressStyle(scale: 0.9))
                    .disabled(priority.text.isEmpty)
                    TextField("Priority \(index + 1)", text: binding(index, current: priority.text))
                        .font(.system(size: 16.5, weight: .medium))
                        .foregroundStyle(priority.done ? CC.text2 : CC.text)
                        .strikethrough(priority.done, color: CC.text2)
                        .focused($focused, equals: index)
                        .submitLabel(.done)
                        .onSubmit { commit(index) }
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 30, maxHeight: .infinity)
                .background(Well(radius: 15))
            }
        }
        .card(padding: 14)
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
/// A slab of sunrise — the warmest thing on the surface.
struct StartDayTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let started = model.store.daily?.dayStarted ?? false
        let preferences = model.workspace.preferences
        if started {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [CC.green.opacity(0.85), CC.green], startPoint: .top, endPoint: .bottom))
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(CC.ink)
                }
                .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day started").font(.system(size: 19, weight: .medium)).foregroundStyle(CC.text)
                    Text("\(preferences.focusName) is on · deep work running").font(.system(size: 14)).foregroundStyle(CC.text2)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CardBackground(highlight: CC.green))
        } else {
            Button {
                Feedback.tap()
                model.send(.scene("startDay"))
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Circle().fill(.white.opacity(0.18)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Start the day")
                            .font(.system(size: 23, weight: .semibold))
                        Text("\(preferences.focusName) · morning apps · \(Int(preferences.deepWorkMinutes)) min deep work")
                            .font(.system(size: 14, weight: .medium))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    let shape = RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    shape
                        .fill(LinearGradient(colors: [Color(hex: 0xFFB257), Color(hex: 0xFF7A45), Color(hex: 0xF0507E)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(shape.fill(RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.15, y: 0), startRadius: 0, endRadius: 320)))
                        .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 1))
                        .background(ShadowPlate(outline: .rounded(Metrics.radius), color: Color(hex: 0xFF7A45, alpha: 0.4), radius: 22, y: 10))
                }
            }
            .buttonStyle(PressStyle(scale: 0.98))
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
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: "Portfolio · PortTracker", symbol: "briefcase.fill", tint: CC.teal) {
                    if let asOf = portfolio.asOf {
                        Text(Fmt.clock(asOf)).font(.system(size: 13, weight: .medium).monospacedDigit()).foregroundStyle(CC.text3)
                    }
                }
                if let error = portfolio.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(CC.orange)
                }
                Text(portfolio.totalEur.map { Fmt.money($0) } ?? "—")
                    .font(CCFont.display(60))
                    .tracking(-1.2)
                    .foregroundStyle(CC.text)
                    .contentTransition(.numericText(value: portfolio.totalEur ?? 0))
                    .animation(.snappy, value: portfolio.totalEur)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 10) {
                    Text(Fmt.money(portfolio.dayChangeEur ?? 0, signed: true))
                    Pill(text: Fmt.percent(portfolio.dayChangePct ?? 0, fraction: false), color: CC.pnl(portfolio.dayChangeEur ?? 0))
                    Text("today").foregroundStyle(CC.text2).font(.system(size: 15))
                }
                .font(.system(size: 19, weight: .regular).monospacedDigit())
                .foregroundStyle(CC.pnl(portfolio.dayChangeEur ?? 0))
                Sparkline(values: portfolio.series, color: CC.pnl((portfolio.series.last ?? 0) - (portfolio.series.first ?? 0)))
                    .frame(maxHeight: .infinity)
                if !portfolio.unpriced.isEmpty {
                    Text("Unpriced: \(portfolio.unpriced.joined(separator: ", "))")
                        .font(.system(size: 12))
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
                CardHeader(title: "Movers", symbol: "arrow.up.arrow.down", tint: CC.teal)
                SectionLabel("Gainers", color: CC.green)
                ForEach(portfolio.gainers) { row($0) }
                if portfolio.gainers.isEmpty { empty }
                Rectangle().fill(CC.divider).frame(height: 1).padding(.vertical, 2)
                SectionLabel("Losers", color: CC.red)
                ForEach(portfolio.losers) { row($0) }
                if portfolio.losers.isEmpty { empty }
                Spacer(minLength: 0)
            }
            .card()
        }
    }

    private var empty: some View {
        Text("—").font(.system(size: 14)).foregroundStyle(CC.text3)
    }

    private func row(_ mover: PortfolioMover) -> some View {
        HStack(spacing: 12) {
            Text(String(mover.symbol.prefix(1)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CC.pnl(mover.changePct))
                .frame(width: 30, height: 30)
                .background(Circle().fill(CC.pnl(mover.changePct).opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(mover.symbol).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(CC.text)
                Text(mover.name).font(.system(size: 12)).foregroundStyle(CC.text2).lineLimit(1)
            }
            Spacer()
            Text(Fmt.percent(mover.changePct, fraction: false))
                .font(.system(size: 15, weight: .regular).monospacedDigit())
                .foregroundStyle(CC.pnl(mover.changePct))
        }
    }
}

struct TurbosTile: View {
    var body: some View {
        PortfolioGate { portfolio in
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(title: "Turbo barriers", symbol: "exclamationmark.triangle.fill", tint: CC.orange)
                if portfolio.turbos.isEmpty {
                    Text("No turbos held.").font(.system(size: 14)).foregroundStyle(CC.text2).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(portfolio.turbos) { turbo in
                    HStack(spacing: 11) {
                        Tag(text: turbo.isLong ? "L" : "S", color: turbo.isLong ? CC.green : CC.red)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(turbo.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(CC.text).lineLimit(1)
                            Text(turbo.underlying).font(.system(size: 12)).foregroundStyle(CC.text2)
                        }
                        Spacer()
                        if turbo.knockedOut {
                            Pill(text: "KO", color: CC.red)
                        } else {
                            Text(turbo.distancePct.map { String(format: "%.1f%%", $0) } ?? "—")
                                .font(.system(size: 14.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(turbo.inDanger ? CC.red : CC.text)
                                .padding(.horizontal, 9)
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
            .background(Capsule().fill(CC.red.opacity(active ? (on ? 0.3 : 0.06) : 0)).padding(-3))
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever()) { on = true }
            }
    }
}
