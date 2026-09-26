import CCCore
import SwiftUI

/// iPad: the control surface. iPhone: the pocket companion.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad && sizeClass != .compact {
                SurfaceView()
            } else {
                PhoneRootView()
            }
        }
        .preferredColorScheme(scheme)
        .tint(CC.accent)
    }

    private var scheme: ColorScheme? {
        switch model.theme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// The scene, and on it: the top bar · the page · the dock, plus every overlay.
struct SurfaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            SceneLayer(mood: SceneMood.page(model.currentPage?.id))
            VStack(spacing: 0) {
                TopBar()
                PageHost()
                    .padding(.horizontal, 20)
                    .padding(.top, 2)
                    .padding(.bottom, 12)
                BottomStrip()
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .blur(radius: dimmed ? 6 : 0)
            .allowsHitTesting(!dimmed)

            if dimmed {
                DisconnectedOverlay()
                    .transition(.opacity)
            }

            ToastHost()
                .padding(.top, Metrics.topBar + 8)

            if showAmbient {
                AmbientView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if showPairing {
                PairingFlow()
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: dimmed)
        .animation(.easeInOut(duration: 0.6), value: showAmbient)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .simultaneousGesture(TapGesture().onEnded { model.lastTouch = .now })
        .sheet(item: $model.prompt) { prompt in
            PromptSheet(prompt: prompt)
        }
        .sheet(item: $model.output) { item in
            OutputSheet(item: item)
        }
        .confirmationDialog(model.confirmation?.key.label ?? "", isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }), titleVisibility: .visible, presenting: model.confirmation) { pending in
            Button(pending.key.label, role: pending.key.action.isDestructive ? .destructive : nil) {
                model.tap(pending.key, pageID: pending.pageID, confirmed: true)
            }
        } message: { pending in
            Text(confirmationMessage(pending.key))
        }
        .fullScreenCover(isPresented: $model.showSettings) {
            SettingsView()
        }
    }

    private var dimmed: Bool {
        let status = model.link.status
        switch status {
        case .connected, .needsPairing, .macAsleep: return false
        default: return true
        }
    }

    private var showPairing: Bool {
        !model.isDemo && model.link.status == .needsPairing
    }

    private var showAmbient: Bool {
        if case .macAsleep = model.link.status { return true }
        guard let presence = model.store.context?.presence, model.link.status.isConnected else { return false }
        return presence == .locked || presence == .asleep
    }

    private func confirmationMessage(_ key: ButtonDef) -> String {
        if case .bot(.closeAll) = key.action, let bot = model.store.bot {
            return "Closes \(bot.positions.count) open position\(bot.positions.count == 1 ? "" : "s") at market (unrealised \(Fmt.money(bot.unrealizedTotal, currency: bot.currency, signed: true)))."
        }
        return key.action.summary
    }
}

/// The current page. When the context changes it, the old page fades and the
/// new page's tiles rise into place one after another.
struct PageHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let page = model.currentPage {
                PageView(page: page)
                    .id(page.id)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.currentPage?.id)
    }
}

/// The scene behind the surface; a new page's mood crossfades in.
struct SceneLayer: View {
    var mood: SceneMood

    var body: some View {
        ZStack {
            SceneBackdrop(mood: mood)
                .id(mood.name)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 1.1), value: mood.name)
        .ignoresSafeArea()
    }
}

// MARK: - Disconnected

/// Dims the cached layout and searches — reconnection is automatic.
struct DisconnectedOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            CC.ink.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 24) {
                Radar()
                    .frame(width: 180, height: 180)
                VStack(spacing: 8) {
                    Text(title)
                        .font(CCFont.title(28, weight: .light))
                        .foregroundStyle(CC.text)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(CC.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                HStack(spacing: 12) {
                    Button("Try now") { model.link.appBecameActive() }
                        .buttonStyle(GlowCapsuleStyle())
                    Button("Explore the demo") { model.setDemo(true) }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text))
                }
            }
            .padding(44)
            .background(CardBackground(radius: 34))
        }
    }

    private var title: String {
        switch model.link.status {
        case .connecting(let name): "Connecting to \(name)…"
        default: "Searching for your Mac…"
        }
    }

    private var detail: String {
        let hint = "Make sure ControlCenter Helper is running and both devices are on the same Wi-Fi — or plug in the USB-C cable. Reconnects on its own."
        guard let error = model.link.lastError else { return hint }
        // Plain language for the usual suspects; the raw error stays in the connection details.
        if error.contains("refused") { return "Your Mac is on the network, but ControlCenter Helper isn't running. Open it from Applications — this reconnects on its own." }
        if error.localizedCaseInsensitiveContains("timed out") || error.contains("timeout") { return "Your Mac didn't answer. " + hint }
        if error.localizedCaseInsensitiveContains("authentication") { return "Your Mac didn't recognise this iPad. Pair it again from Settings → Connection." }
        return hint
    }
}

struct Radar: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { ring in
                    let phase = (t / 2.4 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .strokeBorder(CC.accent.opacity(0.6 * (1 - phase)), lineWidth: 1.2)
                        .scaleEffect(0.3 + phase * 0.7)
                }
                Circle()
                    .fill(RadialGradient(colors: [CC.accent.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 64))
                    .frame(width: 120, height: 120)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 38, weight: .ultraLight))
                    .foregroundStyle(CC.text)
            }
        }
    }
}

/// A glass capsule button — the quiet sibling of `GlowCapsuleStyle`.
struct CapsuleButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 22)
            .frame(height: 46)
            .background(GlassShape(shape: Capsule(), shadow: false))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Toasts

struct ToastHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            ForEach(model.toasts) { item in
                ToastView(toast: item.toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        withAnimation { model.toasts.removeAll { $0.id == item.id } }
                    }
            }
        }
        .frame(maxWidth: 460)
        .allowsHitTesting(!model.toasts.isEmpty)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            IconOrb(symbol: toast.symbol ?? symbol, tint: tint, size: 38)
                .glow(tint, spread: 10, opacity: 0.4, y: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 14, weight: .semibold, design: toast.style == .trade ? .monospaced : .default))
                    .foregroundStyle(CC.text)
                if let message = toast.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12, design: toast.style == .trade ? .monospaced : .default))
                        .foregroundStyle(CC.text2)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 18)
        .padding(.vertical, 11)
        .background(CardBackground(highlight: tint, radius: 24))
    }

    private var tint: Color {
        switch toast.style {
        case .info: CC.accent
        case .success: CC.green
        case .warning: CC.orange
        case .error: CC.red
        case .trade: toast.title.hasPrefix("BUY") ? CC.green : CC.red
        }
    }

    private var symbol: String {
        switch toast.style {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .trade: "arrow.left.arrow.right.circle.fill"
        }
    }
}

// MARK: - Sheets

/// For keys containing `{{input}}` — a commit message, a search.
struct PromptSheet: View {
    let prompt: InputPrompt
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(prompt.action.summary.replacingOccurrences(of: "{{input}}", with: "…"))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(CC.text2)
                TextField("Type here — or dictate", text: $text, axis: .vertical)
                    .font(.system(size: 20))
                    .lineLimit(1...4)
                    .padding(14)
                    .background(Well(radius: 16))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                Spacer()
            }
            .padding(20)
            .background(SceneBackdrop(mood: .cobalt))
            .navigationTitle(prompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send", action: submit).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty).bold()
                }
            }
        }
        .presentationDetents([.height(280)])
        .onAppear { focused = true }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.submitPrompt(prompt, input: value)
        dismiss()
    }
}

/// Shell and git output, terminal-style.
struct OutputSheet: View {
    let item: OutputItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(item.text)
                    .font(CCFont.mono)
                    .foregroundStyle(CC.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            .background(SceneBackdrop(mood: .terminal, dim: 0.25))
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: item.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Ambient

/// When the Mac locks or sleeps the surface becomes a dim bedside clock with
/// the essentials, and lowers the screen brightness. Any touch wakes it.
struct AmbientView: View {
    @Environment(AppModel.self) private var model
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness

    var body: some View {
        TimelineView(.everyMinute) { context in
            ZStack {
                SceneBackdrop(mood: .night, dim: 0.35)
                VStack(spacing: 34) {
                    VStack(spacing: 4) {
                        Text(Fmt.clock(context.date))
                            .font(.system(size: 190, weight: .ultraLight).monospacedDigit())
                            .tracking(-6)
                            .foregroundStyle(CC.text.opacity(0.94))
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(CC.text2)
                    }
                    HStack(spacing: 14) {
                        if let bot = model.store.bot, bot.mode != .off {
                            complication("Bot", Fmt.money(bot.pnlToday, currency: bot.currency, signed: true), CC.pnl(bot.pnlToday))
                        }
                        if let recovery = model.store.whoop?.recovery {
                            complication("Recovery", "\(Int(recovery))%", CC.recovery(recovery))
                        }
                        if let event = model.store.calendar?.next(after: context.date) {
                            complication("Next · \(Fmt.clock(event.start))", event.title, CC.text)
                        }
                        if let weather = model.store.weather {
                            complication(weather.location, "\(Int(weather.temperature.rounded()))°", CC.text)
                        }
                    }
                    .frame(maxWidth: 1040)
                    if case .macAsleep(let name) = model.link.status {
                        HStack(spacing: 10) {
                            GlossyOrb(color: CC.indigo, size: 10)
                            Text("\(name) is asleep")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CC.text2)
                    }
                }
            }
        }
        .onAppear {
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = CGFloat(model.workspace.preferences.ambientBrightness)
        }
        .onDisappear {
            UIScreen.main.brightness = savedBrightness
        }
        .onTapGesture {
            UIScreen.main.brightness = savedBrightness
            model.link.appBecameActive()
        }
    }

    private func complication(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            Text(value)
                .font(.system(size: 28, weight: .light).monospacedDigit())
                .foregroundStyle(color.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .frame(maxWidth: 250, alignment: .leading)
        .background(CardBackground(radius: 22))
    }
}
