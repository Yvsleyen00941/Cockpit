import CCCore
import SwiftUI

/// The iPhone companion: the same hub, the same keys, a pocket layout —
/// plus the Live Activity on the Lock Screen and Dynamic Island.
struct PhoneRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            NavigationStack { DeskTab() }
                .tabItem { Label("Desk", systemImage: "rectangle.3.group.fill") }
            NavigationStack { RemoteTab() }
                .tabItem { Label("Remote", systemImage: "command") }
            NavigationStack { PagesTab() }
                .tabItem { Label("Pages", systemImage: "square.grid.2x2.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .overlay(alignment: .top) { ToastHost().padding(.horizontal, 12).padding(.top, 4) }
        .sheet(item: $model.prompt) { PromptSheet(prompt: $0) }
        .sheet(item: $model.output) { OutputSheet(item: $0) }
        .confirmationDialog(model.confirmation?.key.label ?? "", isPresented: Binding(get: { model.confirmation != nil }, set: { if !$0 { model.confirmation = nil } }), titleVisibility: .visible, presenting: model.confirmation) { pending in
            Button(pending.key.label, role: pending.key.action.isDestructive ? .destructive : nil) {
                model.tap(pending.key, pageID: pending.pageID, confirmed: true)
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !model.isDemo && model.link.status == .needsPairing }, set: { _ in })) {
            PhonePairing()
        }
    }
}

private struct DeskTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                BotSummaryTile().frame(height: 290)
                WhoopSummaryTile().frame(height: 250)
                FocusScheduleTile().frame(height: 320)
                if model.store.media?.nowPlaying != nil {
                    NowPlayingTile().frame(height: 132)
                }
                LiveActivityCard()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .background(CC.bg)
        .navigationTitle(BriefComposer.greeting(name: model.workspace.preferences.ownerName, at: .now))
    }

    private var header: some View {
        HStack(spacing: 10) {
            StatusDot(color: model.link.status.isConnected ? CC.green : CC.red, size: 8, pulsing: !model.link.status.isConnected)
            Text(model.link.macName ?? "No Mac")
                .font(.system(size: 14, weight: .semibold))
            Text(model.link.latencyMs.map { "\(Int($0)) ms" } ?? "")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(CC.text2)
            Spacer()
            if let context = model.store.context {
                AppIconView(bundleID: context.bundleID, size: 20)
                Text(context.appName).font(.system(size: 13)).foregroundStyle(CC.text2)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct LiveActivityCard: View {
    @Environment(AppModel.self) private var model
    @State private var running = LiveActivityController.shared.isRunning

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "platter.filled.bottom.iphone")
                .font(.system(size: 26))
                .foregroundStyle(CC.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Lock Screen & Dynamic Island")
                    .font(.system(size: 15, weight: .semibold))
                Text("Bot P&L, recovery and your timer, live.")
                    .font(.system(size: 12))
                    .foregroundStyle(CC.text2)
            }
            Spacer()
            CCToggle(isOn: running, enabled: LiveActivityController.shared.isSupported) {
                if running {
                    LiveActivityController.shared.stop()
                } else {
                    LiveActivityController.shared.start(state: model.store.snapshot, macName: model.link.macName ?? "Mac")
                }
                running.toggle()
            }
        }
        .card()
    }
}

/// A pocket remote for whatever is in front on the Mac.
private struct RemoteTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let context = model.store.context
        let appKeys = context.map { model.workspace.keys(forApp: $0.bundleID) } ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Scenes") {
                    ForEach(model.workspace.scenes) { scene in
                        RowKey(key: ButtonDef(id: "scene.\(scene.id)", label: scene.name, symbol: scene.symbol, color: scene.color, action: .scene(scene.id), caption: ""))
                    }
                }
                section("Quick") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(model.workspace.strip.keys) { key in
                            KeyButton(key: key, size: CGSize(width: 80, height: 76))
                        }
                    }
                }
                section("\(context?.appName ?? "Mac") keys") {
                    if appKeys.isEmpty {
                        Text("No keys mapped for this app.").foregroundStyle(CC.text2)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                            ForEach(appKeys) { key in
                                KeyButton(key: key, size: CGSize(width: 108, height: 80))
                            }
                        }
                    }
                }
            }
            .padding(14)
        }
        .background(CC.bg)
        .navigationTitle("Remote")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
    }
}

private struct PagesTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.workspace.pages) { page in
            NavigationLink {
                PhonePageView(page: page)
            } label: {
                HStack(spacing: 12) {
                    if let bundleID = page.appBundleID {
                        AppIconView(bundleID: bundleID, size: 28, fallback: page.symbol)
                    } else {
                        Image(systemName: page.symbol).foregroundStyle(CC.accent).frame(width: 28)
                    }
                    Text(page.title)
                    Spacer()
                    Button {
                        Task { _ = try? await HubBridge.run(.navigate(page.id)) }
                    } label: {
                        Image(systemName: "ipad.landscape").foregroundStyle(CC.text2)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Show on iPad")
                }
            }
        }
        .navigationTitle("Pages")
    }
}

/// A page's tiles stacked for a narrow screen.
struct PhonePageView: View {
    let page: Page
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(page.tiles) { tile in
                    TileView(tile: tile, pageID: page.id)
                        .frame(height: height(for: tile))
                }
            }
            .padding(12)
        }
        .background(CC.bg)
        .navigationTitle(page.title)
        .onAppear { model.show(page: page.id) }
    }

    private func height(for tile: Tile) -> CGFloat {
        switch tile.content {
        case .keys(let group):
            let rows = Int(ceil(Double(max(1, group.keys.count)) / (group.style == .row ? 1 : 3)))
            let row: CGFloat = group.style == .row ? 58 : (group.style == .large ? 90 : 88)
            return 48 + CGFloat(rows) * row
        case .appKeys:
            return 240
        case .widget(let kind):
            switch kind {
            case .botHealth: return 60
            case .greeting, .startDay: return 110
            case .nowPlaying, .nextEvent, .timerCompact, .dailyStats, .clock: return 150
            case .pomodoro: return 520
            default: return max(220, CGFloat(tile.rows) * 48)
            }
        case .spacer:
            return 0
        }
    }
}

private struct PhonePairing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let connection = model.connection
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        BrandMark().frame(width: 64, height: 64)
                        Text("Pair with your Mac").font(.title2.bold())
                        Text("Open ControlCenter Helper on your Mac, then choose it below.").foregroundStyle(CC.text2)
                    }
                    .padding(.vertical, 8)
                }
                if case .enterCode(let name, let attempt) = connection.pairing {
                    PhoneCodeEntry(macName: name, attempt: attempt)
                } else {
                    Section("Nearby Macs") {
                        if connection.browser.results.isEmpty {
                            HStack { ProgressView(); Text("Searching…").foregroundStyle(CC.text2) }
                        }
                        ForEach(connection.browser.results) { mac in
                            Button {
                                connection.pair(with: mac)
                            } label: {
                                Label(mac.name, systemImage: "laptopcomputer")
                            }
                        }
                    }
                    if case .failed(let message) = connection.pairing {
                        Text(message).foregroundStyle(CC.orange)
                    }
                    Section {
                        Button("Explore the Demo") { model.setDemo(true) }
                    }
                }
            }
        }
    }
}

private struct PhoneCodeEntry: View {
    let macName: String
    let attempt: Int
    @Environment(AppModel.self) private var model
    @State private var code = ""

    var body: some View {
        Section {
            TextField("6-digit code", text: $code)
                .keyboardType(.numberPad)
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .onChange(of: code) { _, value in
                    let digits = value.filter(\.isNumber)
                    if digits.count >= 6 {
                        model.connection.submitCode(String(digits.prefix(6)))
                        code = ""
                    }
                }
            Button("Cancel", role: .cancel) { model.connection.cancelPairing() }
        } header: {
            Text("Enter the code shown on \(macName)")
        } footer: {
            if attempt > 1 { Text("That didn't match — try again.").foregroundStyle(CC.orange) }
        }
    }
}
