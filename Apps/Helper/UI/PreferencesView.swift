import AppKit
import CCCore
import CCNet
import SwiftUI

/// Native macOS settings window for everything that belongs on the Mac:
/// integrations and their secrets, permissions, paired devices, the local API.
struct PreferencesView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, devices, bot, whoop, portfolio, focus, git, brief, permissions, advanced, activity
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .devices: "Devices"
            case .bot: "Trading Bot"
            case .whoop: "WHOOP"
            case .portfolio: "PortTracker"
            case .focus: "Focus"
            case .git: "Git"
            case .brief: "Brief & Timers"
            case .permissions: "Permissions"
            case .advanced: "Advanced"
            case .activity: "Activity"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .devices: "ipad.landscape"
            case .bot: "chart.line.uptrend.xyaxis"
            case .whoop: "heart.circle"
            case .portfolio: "briefcase"
            case .focus: "moon"
            case .git: "arrow.triangle.branch"
            case .brief: "sun.horizon"
            case .permissions: "lock.shield"
            case .advanced: "wrench.and.screwdriver"
            case .activity: "list.bullet.rectangle"
            }
        }
    }

    @State private var pane: Pane = .general
    @State private var hub = Hub.shared

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane {
                case .general: GeneralPane()
                case .devices: DevicesPane()
                case .bot: BotPane()
                case .whoop: WhoopPane()
                case .portfolio: PortfolioPane()
                case .focus: FocusPane()
                case .git: GitPane()
                case .brief: BriefPane()
                case .permissions: PermissionsPane()
                case .advanced: AdvancedPane()
                case .activity: ActivityPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane.title)
        }
        .frame(width: 780, height: 560)
        .onAppear { hub.permissions.refresh() }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @State private var hub = Hub.shared
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent("This Mac", value: hub.identity.macName)
                LabeledContent("Model", value: MacInfo.model)
                LabeledContent("Helper", value: MacInfo.helperVersion)
                LabeledContent("Bonjour") {
                    HStack(spacing: 6) {
                        Circle().fill(hub.server.isListening ? Color.green : Color.red).frame(width: 7, height: 7)
                        Text(hub.server.isListening ? "Advertising \(Bonjour.serviceType) on port \(hub.server.port ?? 0)" : "Not listening")
                    }
                }
                LabeledContent("USB-C", value: hub.usb.attachedCount > 0 ? "\(hub.usb.attachedCount) device attached" : "No device on the cable")
            }
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in LoginItem.set(value) }
            }
            Section("Layout") {
                LabeledContent("Workspace", value: "Revision \(hub.workspace.revision) · \(hub.workspace.pages.count) pages")
                HStack {
                    Button("Reveal workspace.json") {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.workspace])
                    }
                    Button("Open in Editor") { NSWorkspace.shared.open(Paths.workspace) }
                    Spacer()
                    Button("Reset to Defaults", role: .destructive) { hub.resetWorkspace() }
                }
                Text("Edit workspace.json in any editor — every iPad reloads the moment you save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Devices

private struct DevicesPane: View {
    @State private var hub = Hub.shared

    var body: some View {
        Form {
            Section("Paired") {
                if hub.pairedDevices.isEmpty {
                    Text("No devices yet. Open Control Center on your iPad and choose this Mac.")
                        .foregroundStyle(.secondary)
                }
                ForEach(hub.pairedDevices) { device in
                    HStack(spacing: 12) {
                        Image(systemName: device.platform.symbol).frame(width: 24)
                        VStack(alignment: .leading) {
                            Text(device.deviceName)
                            Text(detail(device)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if hub.connectedDevices.contains(where: { $0.id == device.deviceID }) {
                            Text("Connected").font(.caption).foregroundStyle(.green)
                        }
                        Button("Forget", role: .destructive) { hub.forget(deviceID: device.deviceID) }
                    }
                }
            }
            Section {
                Text("Pairing uses a 6-digit code shown on this Mac. Each device gets its own 256-bit key in the Keychain; every session is mutually authenticated and encrypted (ChaCha20-Poly1305).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task { hub.pairedDevicesChanged(await hub.devices.all()) }
    }

    private func detail(_ device: PairedDevice) -> String {
        var parts = ["Paired \(device.pairedAt.formatted(date: .abbreviated, time: .omitted))"]
        if let seen = device.lastSeen { parts.append("last seen \(Fmt.ago(seen))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Trading bot

private struct BotPane: View {
    @State private var hub = Hub.shared
    @State private var settings = Hub.shared.integrations.bot
    @State private var apiKey = ""
    @State private var testResult: ActionResult?
    @State private var fieldMapText = ""

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.mode) {
                    ForEach(BotMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(settings.mode == .simulated ? "A built-in simulated bot drives every screen (marked SIM) until your real one is connected." : settings.mode == .live ? "Polls your bot's local REST API while a device is watching. See docs/BOT-API.md for the contract." : "Bot tiles show a setup prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if settings.mode == .live {
                Section("Endpoint") {
                    TextField("Base URL", text: $settings.baseURL, prompt: Text("http://127.0.0.1:8000"))
                    TextField("Status", text: $settings.statusPath)
                    TextField("Events", text: $settings.eventsPath)
                    TextField("P&L series", text: $settings.seriesPath)
                    TextField("Pause (POST)", text: $settings.pausePath)
                    TextField("Resume (POST)", text: $settings.resumePath)
                    TextField("Close all (POST)", text: $settings.closeAllPath)
                    Stepper("Poll every \(Int(settings.pollSeconds)) s", value: $settings.pollSeconds, in: 1...60)
                    SecureField("API key (sent as Bearer)", text: $apiKey, prompt: Text(settings.hasAPIKey ? "•••••• saved" : "optional"))
                }
                Section("Field mapping") {
                    TextEditor(text: $fieldMapText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 84)
                    Text("One per line: `pnlToday = stats.daily.pnl`. Keys: status, pnlToday, pnlTodayPct, equity, currency, tradesToday, lastHeartbeat, apiConnected, positions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Command center") {
                TextField("App bundle IDs (comma separated)", text: Binding(
                    get: { settings.commandCenterBundleIDs.joined(separator: ", ") },
                    set: { settings.commandCenterBundleIDs = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
                Text("When one of these apps is in front, the iPad shows the Bot page. A bot web UI on localhost:8000 is detected automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                    Button("Test Connection") {
                        save()
                        Task { testResult = await hub.bot.test() }
                    }
                    Spacer()
                    if let testResult {
                        Label(testResult.message ?? (testResult.ok ? "OK" : "Failed"), systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(testResult.ok ? .green : .red)
                    }
                }
            }
        }
        .onAppear {
            fieldMapText = settings.fieldMap.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
        }
    }

    private func save() {
        var map: [String: String] = [:]
        for line in fieldMapText.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty { map[parts[0]] = parts[1] }
        }
        settings.fieldMap = map
        var all = hub.integrations
        all.bot = settings
        if !apiKey.isEmpty { all.secrets = [IntegrationSettings.SecretKey.botAPIKey: apiKey] }
        hub.applyIntegrations(all)
        settings = hub.integrations.bot
        apiKey = ""
    }
}

// MARK: - WHOOP

private struct WhoopPane: View {
    @State private var hub = Hub.shared
    @State private var settings = Hub.shared.integrations.whoop
    @State private var secret = ""
    @State private var result: ActionResult?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle().fill(hub.whoop.isConnected ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(hub.whoop.isConnected ? (hub.state.whoop?.recovery.map { "Connected · recovery \(Int($0))%" } ?? "Connected") : "Not connected")
                    }
                }
            }
            Section("Developer app") {
                TextField("Client ID", text: $settings.clientID)
                SecureField("Client secret", text: $secret, prompt: Text(settings.hasClientSecret ? "•••••• saved" : "from developer.whoop.com"))
                TextField("Redirect URI", text: $settings.redirectURI)
                Text("Use the redirect registered in your WHOOP developer app (yours is http://localhost:8080). Scopes requested: \(WhoopProvider.scopes).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Save") { save() }
                    Button(hub.whoop.isConnected ? "Reconnect" : "Connect WHOOP") {
                        save()
                        working = true
                        Task {
                            result = await hub.whoop.connect()
                            working = false
                        }
                    }
                    .disabled(working)
                    if hub.whoop.isConnected {
                        Button("Disconnect", role: .destructive) { hub.whoop.disconnect() }
                    }
                    Spacer()
                    if working { ProgressView().controlSize(.small) }
                    if let result {
                        Label(result.message ?? "", systemImage: result.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(result.ok ? .green : .red)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func save() {
        var all = hub.integrations
        all.whoop = settings
        if !secret.isEmpty { all.secrets = [IntegrationSettings.SecretKey.whoopClientSecret: secret] }
        hub.applyIntegrations(all)
        settings = hub.integrations.whoop
        secret = ""
    }
}

// MARK: - PortTracker

private struct PortfolioPane: View {
    @State private var hub = Hub.shared
    @State private var settings = Hub.shared.integrations.portfolio
    @State private var authValue = ""

    var body: some View {
        Form {
            Section {
                Toggle("Show PortTracker on the Markets page", isOn: $settings.enabled)
                TextField("Deployment URL", text: $settings.baseURL, prompt: Text("https://your-porttracker.vercel.app"))
                Picker("Auth header", selection: $settings.authHeader) {
                    Text("Cookie").tag("Cookie")
                    Text("Authorization").tag("Authorization")
                }
                SecureField("Header value", text: $authValue, prompt: Text(settings.hasAuthValue ? "•••••• saved" : "sb-…-auth-token=… or Bearer …"))
                Stepper("Refresh every \(Int(settings.pollSeconds)) s", value: $settings.pollSeconds, in: 10...300, step: 10)
            }
            Section {
                Text("Reads /api/market/standby — total in EUR at live FX, the day's move, movers among your holdings, turbos near their barrier. The route checks your Supabase session, so paste your session cookie, or add a token path to the route and use Authorization.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = hub.state.portfolio?.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if let total = hub.state.portfolio?.totalEur {
                    Label("Connected · \(Fmt.money(total))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button("Save") {
                    var all = hub.integrations
                    all.portfolio = settings
                    if !authValue.isEmpty { all.secrets = [IntegrationSettings.SecretKey.portfolioAuth: authValue] }
                    hub.applyIntegrations(all)
                    settings = hub.integrations.portfolio
                    authValue = ""
                }
            }
        }
    }
}

// MARK: - Focus

private struct FocusPane: View {
    @State private var hub = Hub.shared

    var body: some View {
        Form {
            Section("How it works") {
                Text("macOS only lets apps change Focus through Shortcuts. Create one shortcut per Focus, named exactly “Focus: <Name>”, containing a single Set Focus → Turn On action — plus “Focus: Off” (Set Focus → Turn Off). Focus syncs to your iPhone automatically when “Share Across Devices” is on.")
                    .font(.callout)
                Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
            }
            Section("Detected") {
                let focus = hub.state.focus
                if (focus?.available ?? []).isEmpty {
                    Text("No “Focus: …” shortcuts yet.").foregroundStyle(.secondary)
                }
                ForEach(focus?.available ?? [], id: \.self) { name in
                    Label("Focus: \(name)", systemImage: "moon.fill")
                }
                Label("Focus: Off", systemImage: focus?.canTurnOff == true ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(focus?.canTurnOff == true ? .primary : .secondary)
                Button("Rescan") { Task { await hub.focus.refreshShortcuts(); await hub.focus.tick() } }
            }
            Section("Reading the active Focus") {
                let granted = hub.permissions.granted(.fullDiskAccess)
                Label(granted ? "Full Disk Access granted — the iPad shows your real Focus." : "Without Full Disk Access the iPad shows the Focus it last set.", systemImage: granted ? "checkmark.circle.fill" : "info.circle")
                if !granted {
                    Button("Grant Full Disk Access…") { hub.permissions.request(.fullDiskAccess) }
                }
            }
        }
    }
}

// MARK: - Git

private struct GitPane: View {
    @State private var hub = Hub.shared

    var body: some View {
        Form {
            Section("Repositories") {
                ForEach(hub.integrations.gitRepositories, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                        Text(path)
                        Spacer()
                        Button(role: .destructive) {
                            hub.updateIntegrations { $0.gitRepositories.removeAll { $0 == path } }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Repository…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK {
                        let paths = panel.urls.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
                        hub.updateIntegrations { $0.gitRepositories += paths.filter { !$0.isEmpty } }
                    }
                }
            }
            Section {
                Text("The repository Xcode has open is tracked automatically. Keys like Commit…, Push and Pull run in the current repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Brief & timers (workspace preferences)

private struct BriefPane: View {
    @State private var hub = Hub.shared
    @State private var preferences = Hub.shared.workspace.preferences

    var body: some View {
        Form {
            Section("You") {
                TextField("Name in the greeting", text: $preferences.ownerName)
            }
            Section("Morning Brief") {
                Stepper("Starts \(clock(preferences.morningStart))", value: $preferences.morningStart, in: 0...(23 * 60), step: 30)
                Stepper("Ends \(clock(preferences.morningEnd))", value: $preferences.morningEnd, in: 0...(24 * 60), step: 30)
                TextField("Weather location", text: $preferences.weatherLocation)
                HStack {
                    TextField("Latitude", value: $preferences.latitude, format: .number)
                    TextField("Longitude", value: $preferences.longitude, format: .number)
                }
                Toggle("Mirror top 3 to Reminders", isOn: $preferences.mirrorPrioritiesToReminders)
            }
            Section("Pomodoro") {
                Stepper("Focus \(Int(preferences.pomodoroMinutes)) min", value: $preferences.pomodoroMinutes, in: 5...90, step: 5)
                Stepper("Short break \(Int(preferences.shortBreakMinutes)) min", value: $preferences.shortBreakMinutes, in: 1...30)
                Stepper("Long break \(Int(preferences.longBreakMinutes)) min", value: $preferences.longBreakMinutes, in: 5...60, step: 5)
                Stepper("\(preferences.sessionsPerCycle) sessions per cycle", value: $preferences.sessionsPerCycle, in: 2...8)
                Toggle("Start breaks automatically", isOn: $preferences.autoStartBreaks)
                Stepper("Deep work \(Int(preferences.deepWorkMinutes)) min", value: $preferences.deepWorkMinutes, in: 30...240, step: 15)
                TextField("Focus for deep work", text: $preferences.focusName)
                TextField("Focus that means studying", text: $preferences.studyFocusName)
            }
            Section {
                Button("Save") {
                    var workspace = hub.workspace
                    workspace.preferences = preferences
                    hub.applyWorkspace(workspace)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @State private var hub = Hub.shared

    var body: some View {
        Form {
            Section {
                ForEach(hub.permissions.statuses) { status in
                    HStack(spacing: 12) {
                        Image(systemName: status.granted ? "checkmark.circle.fill" : (status.required ? "exclamationmark.circle.fill" : "circle.dashed"))
                            .foregroundStyle(status.granted ? .green : (status.required ? .orange : .secondary))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.kind.title + (status.required ? " (required)" : ""))
                            Text(status.kind.purpose).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !status.granted {
                            Button("Grant…") { hub.permissions.request(status.kind) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section {
                Button("Check Again") { hub.permissions.refresh() }
            }
        }
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @State private var hub = Hub.shared
    @State private var token = LocalAPI.token
    @State private var apns = Hub.shared.apns.config

    var body: some View {
        Form {
            Section("Context tracking") {
                Toggle("Read the current browser tab's URL", isOn: Binding(get: { hub.integrations.browserURLTracking }, set: { value in hub.updateIntegrations { $0.browserURLTracking = value } }))
                Toggle("Read window titles", isOn: Binding(get: { hub.integrations.windowTitleTracking }, set: { value in hub.updateIntegrations { $0.windowTitleTracking = value } }))
                Toggle("Weather", isOn: Binding(get: { hub.integrations.weatherEnabled }, set: { value in hub.updateIntegrations { $0.weatherEnabled = value } }))
            }
            Section("Local API · 127.0.0.1:\(Bonjour.localAPIPort)") {
                LabeledContent("Token") {
                    HStack {
                        Text(token).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(token, forType: .string)
                        }
                        Button("Regenerate") {
                            LocalAPI.regenerateToken()
                            token = LocalAPI.token
                        }
                    }
                }
                Text(verbatim: "curl -H \"Authorization: Bearer \(token)\" -X POST http://127.0.0.1:\(Bonjour.localAPIPort)/v1/toast -d '{\"title\":\"Build done\",\"style\":\"success\"}'")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Text("Routes: /v1/action, /v1/scene, /v1/navigate, /v1/toast, /v1/bot/event, /v1/bot/status, /v1/state. Loopback only — nothing on the network can reach it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Live Activity push (optional)") {
                Toggle("Push iPhone Live Activity updates from this Mac", isOn: $apns.enabled)
                TextField("Team ID", text: $apns.teamID)
                TextField("APNs key ID", text: $apns.keyID)
                HStack {
                    TextField(".p8 key path", text: $apns.keyPath)
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.data]
                        if panel.runModal() == .OK, let url = panel.url { apns.keyPath = url.path }
                    }
                }
                Toggle("Development (sandbox) APNs", isOn: $apns.sandbox)
                Text("Requires a paid Apple Developer membership. Without it the Live Activity refreshes whenever the iPhone app runs, and its timer counts down on its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Save") { hub.apns.update { $0 = apns } }
            }
        }
    }
}

// MARK: - Activity

private struct ActivityPane: View {
    @State private var log = LogStore.shared

    var body: some View {
        VStack(spacing: 0) {
            List(log.entries.reversed()) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Text(Fmt.clock(entry.date, seconds: true))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Image(systemName: icon(entry.level))
                        .foregroundStyle(color(entry.level))
                        .font(.caption)
                    Text(entry.message)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            HStack {
                Spacer()
                Button("Clear") { log.clear() }
            }
            .padding(8)
        }
    }

    private func icon(_ level: LogStore.Entry.Level) -> String {
        switch level {
        case .info: "info.circle"
        case .action: "hand.tap"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(_ level: LogStore.Entry.Level) -> Color {
        switch level {
        case .info: .secondary
        case .action: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}
