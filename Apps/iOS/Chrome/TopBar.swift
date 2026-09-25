import CCCore
import SwiftUI

/// 50 pt: connection · what's in front on the Mac · page tabs · pin · clock · settings.
struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            ConnectionBadge()
            Rectangle().fill(CC.divider).frame(width: 1, height: 24)
            ContextChip()
                .frame(maxWidth: 280, alignment: .leading)
            Spacer(minLength: 8)
            PageTabs()
            Spacer(minLength: 8)
            if model.editing {
                EditingBadge()
            } else {
                HStack(spacing: 6) {
                    BarIconButton(symbol: "square.and.pencil", active: false, help: "Edit layout") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.editing = true }
                    }
                    BarIconButton(symbol: model.navigator.pinned == nil ? "pin" : "pin.fill", active: model.navigator.pinned != nil, help: "Pin this page") {
                        withAnimation(.snappy) { model.navigator.togglePin() }
                    }
                }
            }
            ClockView()
            BarIconButton(symbol: "gearshape.fill", active: false, help: "Settings") {
                model.showSettings = true
            }
        }
        .padding(.horizontal, 20)
        .frame(height: Metrics.topBar)
        .background(CC.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(CC.divider).frame(height: 1)
        }
    }
}

struct BarIconButton: View {
    let symbol: String
    var active: Bool
    var help: String
    let action: () -> Void

    var body: some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(active ? CC.accent : CC.text2)
                .frame(width: 36, height: 36)
                .background(Circle().fill(active ? CC.accent.opacity(0.16) : CC.elevated.opacity(0.7)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(help)
    }
}

// MARK: - Connection

struct ConnectionBadge: View {
    @Environment(AppModel.self) private var model
    @State private var showDetails = false

    var body: some View {
        let link = model.link
        Button { showDetails = true } label: {
            HStack(spacing: 9) {
                StatusDot(color: color(link), size: 8, pulsing: !link.status.isConnected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(link.macName ?? "No Mac")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CC.text)
                        .lineLimit(1)
                    Text(subtitle(link))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(CC.text2)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 118, alignment: .leading)
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

struct ConnectionDetails: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let link = model.link
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 22))
                    .foregroundStyle(CC.accent)
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
        HStack(spacing: 10) {
            AppIconView(bundleID: context?.bundleID, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(context?.appName ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CC.text)
                    .lineLimit(1)
                Text(subtitle(context))
                    .font(.system(size: 11))
                    .foregroundStyle(CC.text2)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .animation(.easeOut(duration: 0.2), value: context?.bundleID)
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
/// selected tab expands to show its name; the highlight slides between tabs.
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
                Rectangle().fill(CC.divider).frame(width: 1, height: 20).padding(.horizontal, 4)
                tab(current)
            }
        }
        .padding(3)
        .background(Capsule().fill(CC.elevated.opacity(0.55)))
        .overlay(Capsule().strokeBorder(CC.divider, lineWidth: 1))
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.navigator.pageID)
    }

    private func tab(_ page: Page) -> some View {
        let selected = page.id == model.navigator.pageID
        return Button {
            Feedback.tap()
            model.show(page: page.id)
        } label: {
            HStack(spacing: 7) {
                if let bundleID = page.appBundleID {
                    AppIconView(bundleID: bundleID, size: 18, fallback: page.symbol)
                } else {
                    Image(systemName: page.symbol)
                        .font(.system(size: 14, weight: .semibold))
                }
                if selected {
                    Text(page.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(selected ? CC.text : CC.text2)
            .padding(.horizontal, selected ? 12 : 10)
            .frame(height: 32)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [CC.accent.opacity(0.32), CC.accent.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(CC.accent.opacity(0.45), lineWidth: 1))
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
            Button {
                Feedback.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { model.editing = false }
            } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0A0A0F))
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(CC.accent))
            }
            .buttonStyle(PressStyle())
        }
    }
}

struct ClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .trailing, spacing: 0) {
                Text(Fmt.clock(context.date))
                    .font(.system(size: 19, weight: .semibold).monospacedDigit())
                    .foregroundStyle(CC.text)
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CC.text2)
            }
        }
        .frame(minWidth: 64, alignment: .trailing)
    }
}
