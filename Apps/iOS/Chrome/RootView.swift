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

/// Top bar (50 pt) · page · bottom strip (80 pt), plus every overlay.
struct SurfaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            CC.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar()
                PageHost()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                BottomStrip()
            }
            .blur(radius: dimmed ? 2.5 : 0)
            .allowsHitTesting(!dimmed)

            if dimmed {
                DisconnectedOverlay()
                    .transition(.opacity)
            }

            ToastHost()
                .padding(.top, Metrics.topBar + 10)

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

/// The current page, cross-fading with a slight scale (0.95 → 1) over 250 ms
/// whenever the context changes it.
struct PageHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let page = model.currentPage {
                PageView(page: page)
                    .id(page.id)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.95)), removal: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.currentPage?.id)
    }
}

// MARK: - Disconnected

/// Dims the cached layout and searches — reconnection is automatic.
struct DisconnectedOverlay: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 22) {
                Radar()
                    .frame(width: 180, height: 180)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(CC.text)
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(CC.text2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                HStack(spacing: 12) {
                    Button("Try Now") { model.link.appBecameActive() }
                        .buttonStyle(CapsuleButtonStyle(color: CC.accent))
                    Button("Explore Demo") { model.setDemo(true) }
                        .buttonStyle(CapsuleButtonStyle(color: CC.text2))
                }
            }
            .padding(40)
        }
    }

    private var title: String {
        switch model.link.status {
        case .connecting(let name): "Connecting to \(name)…"
        default: "Searching for your Mac…"
        }
    }

    private var detail: String {
        if let error = model.link.lastError { return error }
        return "Make sure ControlCenter Helper is running and both devices are on the same Wi-Fi — or plug in the USB-C cable. Reconnects on its own."
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
                        .strokeBorder(CC.accent.opacity(0.55 * (1 - phase)), lineWidth: 1.5)
                        .scaleEffect(0.3 + phase * 0.7)
                }
                Circle()
                    .fill(RadialGradient(colors: [CC.accent.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 110, height: 110)
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(CC.text)
            }
        }
    }
}

struct CapsuleButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Capsule().fill(color.opacity(0.16)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
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
            Image(systemName: toast.symbol ?? symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CC.card.opacity(0.75)))
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(tint.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
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
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CC.elevated))
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                Spacer()
            }
            .padding(20)
            .background(CC.bg)
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
            .background(CC.bg)
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
                Color.black.ignoresSafeArea()
                VStack(spacing: 28) {
                    VStack(spacing: 6) {
                        Text(Fmt.clock(context.date))
                            .font(.system(size: 150, weight: .thin).monospacedDigit())
                            .foregroundStyle(CC.text.opacity(0.92))
                        Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(CC.text2)
                    }
                    HStack(spacing: 44) {
                        if let bot = model.store.bot, bot.mode != .off {
                            complication("BOT", Fmt.money(bot.pnlToday, currency: bot.currency, signed: true), CC.pnl(bot.pnlToday))
                        }
                        if let recovery = model.store.whoop?.recovery {
                            complication("RECOVERY", "\(Int(recovery))%", CC.recovery(recovery))
                        }
                        if let event = model.store.calendar?.next(after: context.date) {
                            complication("NEXT · \(Fmt.clock(event.start))", event.title, CC.text)
                        }
                        if let weather = model.store.weather {
                            complication(weather.location.uppercased(), "\(Int(weather.temperature.rounded()))°", CC.text)
                        }
                    }
                    .frame(maxWidth: 1000)
                    if case .macAsleep(let name) = model.link.status {
                        Label("\(name) is asleep", systemImage: "moon.zzz.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(CC.indigo)
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
        VStack(spacing: 6) {
            SectionLabel(label)
            Text(value)
                .font(.system(size: 30, weight: .medium).monospacedDigit())
                .foregroundStyle(color.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 240)
    }
}
