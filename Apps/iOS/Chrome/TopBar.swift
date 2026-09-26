import CCCore
import SwiftUI

/// Floats on the scene: the status capsule (connection · what's in front on
/// the Mac) · the page switcher · edit, pin, the time and settings.
struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            StatusCapsule()
                .frame(maxWidth: 400, alignment: .leading)
            Spacer(minLength: 8)
            PageTabs()
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                if model.editing {
                    EditingBadge()
                } else {
                    GlassIconButton(symbol: "square.and.pencil", help: "Edit layout") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.editing = true }
                    }
                    GlassIconButton(symbol: model.navigator.pinned == nil ? "pin" : "pin.fill", active: model.navigator.pinned != nil, help: "Pin this page") {
                        withAnimation(.snappy) { model.navigator.togglePin() }
                    }
                }
                ClockView()
                    .padding(.horizontal, 6)
                GlassIconButton(symbol: "gearshape.fill", help: "Settings") {
                    model.showSettings = true
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Metrics.topBar)
    }
}

/// Kept for callers outside the top bar (editor sheets).
struct BarIconButton: View {
    let symbol: String
    var active: Bool
    var help: String
    let action: () -> Void

    var body: some View {
        GlassIconButton(symbol: symbol, active: active, size: 38, help: help, action: action)
    }
}

// MARK: - Status capsule

/// One glass capsule: the connection light and Mac, then the app in front.
struct StatusCapsule: View {
    var body: some View {
        HStack(spacing: 14) {
            ConnectionBadge()
            Rectangle().fill(CC.divider).frame(width: 1, height: 26)
            ContextChip()
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .frame(height: 50)
        .background(GlassShape(shape: Capsule(), shadow: false))
    }
}

struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model
    @State private var showDetails = false

    var body: some View {
        let link = model.link
        Button { showDetails = true } label: {
            HStack(spacing: 10) {
                GlossyOrb(color: color(link), size: 11)
                    .modifier(Breathing(active: !link.status.isConnected))
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.macName ?? "No Mac")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(CC.text)
                        .lineLimit(1)
                    Text(subtitle(link))
                        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                }
            }
            .fixedSize()
        }
        .buttonStyle(PressStyle(scale: 0.98))
        .popover(isPresented: $showDetails, arrowEdge: .bottom) {
            ConnectionDetails()
                .frame(width: 320)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func color(_ link: any HubLink) -> Color {
        switch link.status {
        case .connected: link.isDegraded ? CC.yellow : (link.transport == .demo ? CC.accent : CC.green)
        case .macAsleep: CC.indigo
        default: CC.red
        }
    }

    private func subtitle(_ link: any HubLink) -> String {
        switch link.status {
        case .connected:
            let latency = link.latencyMs.map { "\(max(1, Int($0.rounded()))) ms" } ?? "—"
            return "\(latency) · \(link.transport.title)"
        case .connecting: return "Connecting…"
        case .searching: return "Searching…"
        case .macAsleep: return "Asleep"
        case .needsPairing: return "Not paired"
        case .idle: return "Offline"
        }
    }
}

/// A slow glow in and out — something is waiting.
struct Breathing: ViewModifier {
    var active: Bool
    @State private var low = false

    func body(content: Content) -> some View {
        content
            .opacity(active && low ? 0.45 : 1)
            .onAppear {
                guard active else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever()) { low = true }
            }
    }
}

struct ConnectionDetails: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let link = model.link
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconOrb(symbol: "laptopcomputer", tint: CC.accent, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(link.macName ?? "No Mac").font(.system(size: 16, weight: .semibold))
                    Text(model.store.helper?.model ?? "ControlCenter Helper").font(.system(size: 12)).foregroundStyle(CC.text2)
                }
            }
            Divider()
            detail("Status", link.status.isConnected ? (link.isDegraded ? "Connected · slow" : "Connected") : "Not connected")
            detail("Link", link.transport.title)
            detail("Latency", link.latencyMs.map { String(format: "%.1f ms", $0) } ?? "—")
            detail("Encryption", link.transport == .demo ? "—" : "ChaCha20-Poly1305")
            if let version = model.store.helper?.version { detail("Helper", version) }
            if let error = link.lastError, !link.status.isConnected {
                Text(error).font(.system(size: 12)).foregroundStyle(CC.orange)
            }
            Button("Connection settings") { model.showSettings = true }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CC.accent)
        }
        .padding(18)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(CC.text2)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 13))
    }
}

// MARK: - Context

/// The Mac's frontmost app, its window title or site — the reason the page is what it is.
struct ContextChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let context = model.store.context
        HStack(spacing: 11) {
            AppIconView(bundleID: context?.bundleID, size: 30)
                .id(context?.bundleID)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            VStack(alignment: .leading, spacing: 1) {
                Text(context?.appName ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text(subtitle(context))
                    .font(.system(size: 11.5))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: context?.bundleID)
    }

    private func subtitle(_ context: ActiveContext?) -> String {
        guard let context else { return "Waiting for your Mac" }
        if context.presence == .locked { return "Mac locked" }
        if let host = context.urlHost { return host }
        if let title = context.windowTitle, title != context.appName { return title }
        return model.navigator.resolution?.reason ?? ""
    }
}

// MARK: - Page tabs

/// Icon tabs for the pinned pages, plus a tab for the current app page. The
/// selected tab becomes a lit cobalt pill with its name; it slides between tabs.
struct PageTabs: View {
    @Environment(AppModel.self) private var model
    @Namespace private var selection

    var body: some View {
        let pinned = model.workspace.pages.filter(\.pinnedToBar)
        let current = model.currentPage
        HStack(spacing: 2) {
            ForEach(pinned) { page in
                tab(page)
            }
            if let current, !current.pinnedToBar {
                Rectangle().fill(CC.divider).frame(width: 1, height: 22).padding(.horizontal, 5)
                tab(current)
            }
        }
        .padding(4)
        .background(GlassShape(shape: Capsule(), shadow: false))
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.navigator.pageID)
    }

    private func tab(_ page: Page) -> some View {
        let selected = page.id == model.navigator.pageID
        return Button {
            Feedback.tap()
            model.show(page: page.id)
        } label: {
            HStack(spacing: 7) {
                if let bundleID = page.appBundleID {
                    AppIconView(bundleID: bundleID, size: 20, fallback: page.symbol)
                } else {
                    Image(systemName: page.symbol)
                        .font(.system(size: 15, weight: .semibold))
                }
                if selected {
                    Text(page.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(selected ? .white : CC.text2)
            .padding(.horizontal, selected ? 15 : 12)
            .frame(height: 40)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [Color(hex: 0x6A92FF), Color(hex: 0x3A62F5)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                        .glow(Color(hex: 0x3A62F5), spread: 10, opacity: 0.5, y: 4)
                        .matchedGeometryEffect(id: "tab", in: selection)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95))
        .accessibilityLabel(page.title)
    }
}

struct EditingBadge: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            Pill(text: "Editing", color: CC.orange, symbol: "square.and.pencil")
            Button("Done") {
                Feedback.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.editing = false }
            }
            .buttonStyle(GlowCapsuleStyle(height: 40))
        }
    }
}

struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.clock(context.date))
                    .font(.system(size: 26, weight: .light).monospacedDigit())
                    .tracking(-0.5)
                    .foregroundStyle(CC.text)
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(CC.text2)
            }
        }
        .frame(minWidth: 70, alignment: .trailing)
    }
}
