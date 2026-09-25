import CCCore
import CCNet
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case connection, pages, mappings, rules, strip, scenes, sources, morning, appearance, permissions, transfer, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .connection: "Connection"
            case .pages: "Pages & Layout"
            case .mappings: "App Mappings"
            case .rules: "Context Rules"
            case .strip: "Bottom Strip"
            case .scenes: "Scenes"
            case .sources: "Data Sources"
            case .morning: "Morning & Timers"
            case .appearance: "Appearance"
            case .permissions: "Mac Permissions"
            case .transfer: "Export & Import"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .connection: "antenna.radiowaves.left.and.right"
            case .pages: "square.grid.2x2"
            case .mappings: "app.badge"
            case .rules: "point.3.filled.connected.trianglepath.dotted"
            case .strip: "dock.rectangle"
            case .scenes: "sparkles"
            case .sources: "puzzlepiece.extension"
            case .morning: "sunrise"
            case .appearance: "paintbrush"
            case .permissions: "lock.shield"
            case .transfer: "square.and.arrow.up.on.square"
            case .about: "info.circle"
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var section: Section? = .connection

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        } detail: {
            NavigationStack {
                Group {
                    switch section ?? .connection {
                    case .connection: ConnectionSettings()
                    case .pages: PagesSettings { dismiss() }
                    case .mappings: MappingsSettings()
                    case .rules: RulesSettings()
                    case .strip: StripSettings()
                    case .scenes: ScenesSettings()
                    case .sources: SourcesSettings()
                    case .morning: MorningSettings()
                    case .appearance: AppearanceSettings()
                    case .permissions: PermissionsSettings()
                    case .transfer: TransferSettings()
                    case .about: AboutSettings()
                    }
                }
                .navigationTitle((section ?? .connection).title)
            }
        }
        .preferredColorScheme(model.theme == .light ? .light : (model.theme == .dark ? .dark : nil))
    }
}

// MARK: - Connection

private struct ConnectionSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let link = model.link
        Form {
            Section {
                LabeledContent("Status", value: link.status.isConnected ? "Connected" : "Not connected")
                LabeledContent("Mac", value: link.macName ?? "—")
                LabeledContent("Link", value: link.transport.title)
                LabeledContent("Latency", value: link.latencyMs.map { String(format: "%.1f ms", $0) } ?? "—")
                if let helper = model.store.helper {
                    LabeledContent("Helper", value: "\(helper.version) · \(helper.osVersion)")
                }
            }
            Section("Paired Macs") {
                ForEach(model.connection.pairedMacs) { mac in
                    HStack {
                        Image(systemName: "laptopcomputer").foregroundStyle(CC.accent)
                        VStack(alignment: .leading) {
                            Text(mac.macName)
                            Text("Paired \(mac.pairedAt.formatted(date: .abbreviated, time: .omitted))\(mac.lastHost.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(CC.text2)
                        }
                        Spacer()
                        if mac.macID == model.connection.currentMac?.macID, link.status.isConnected {
                            Text("In use").font(.caption).foregroundStyle(CC.green)
                        } else {
                            Button("Use") { model.connection.switchTo(mac.macID) }
                        }
                    }
                    .swipeActions {
                        Button("Forget", role: .destructive) { model.connection.forget(mac.macID) }
                    }
                }
                Button("Pair Another Mac", systemImage: "plus") {
                    model.setDemo(false)
                    model.showSettings = false
                    model.connection.forceShowPairing()
                }
            }
            Section {
                Toggle("Demo mode", isOn: Binding(get: { model.isDemo }, set: { model.setDemo($0) }))
                if model.isDemo {
                    Button("Simulate switching app on the Mac", systemImage: "arrow.left.arrow.right") { model.demo.cycleContext() }
                }
            } footer: {
                Text("Demo mode runs everything against a simulated Mac — handy before the helper is installed.")
            }
            Section {
                TextField("This device's name", text: Binding(get: { SharedStore.deviceName }, set: { UserDefaults(suiteName: SharedStore.appGroup)?.set($0, forKey: "deviceName") }))
            } footer: {
                Text("Shown on the Mac while pairing and in its device list. USB-C: plug the iPad into the Mac (with Control Center open) and the link switches to the cable automatically.")
            }
        }
    }
}

// MARK: - Pages

private struct PagesSettings: View {
    let close: () -> Void
    @Environment(AppModel.self) private var model
    @State private var editing: Page?

    var body: some View {
        Form {
            Section {
                Button("Edit the Current Page on Screen", systemImage: "square.and.pencil") {
                    model.editing = true
                    close()
                }
            } footer: {
                Text("Drag tiles to reorder, resize from the corner menu, tap a tile or key to configure it.")
            }
            Section("Pages") {
                ForEach(model.workspace.pages) { page in
                    Button {
                        editing = page
                    } label: {
                        HStack(spacing: 12) {
                            if let bundleID = page.appBundleID {
                                AppIconView(bundleID: bundleID, size: 26, fallback: page.symbol)
                            } else {
                                Image(systemName: page.symbol).foregroundStyle(CC.accent).frame(width: 26)
                            }
                            VStack(alignment: .leading) {
                                Text(page.title).foregroundStyle(CC.text)
                                Text("\(page.tiles.count) tiles\(page.pinnedToBar ? " · in top bar" : "")").font(.caption).foregroundStyle(CC.text2)
                            }
                            Spacer()
                            Button("Show") {
                                model.show(page: page.id)
                                close()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .onMove { from, to in
                    var workspace = model.workspace
                    workspace.pages.move(fromOffsets: from, toOffset: to)
                    model.commit(workspace)
                }
                Button("New Page", systemImage: "plus") {
                    var workspace = model.workspace
                    let page = Page(id: "page.\(UUID().uuidString.prefix(8))", title: "New Page", symbol: "square.grid.2x2", tiles: [
                        Tile(cols: 12, rows: 4, content: .keys(KeyGroup(title: "Keys", keys: []))),
                    ])
                    workspace.pages.append(page)
                    model.commit(workspace)
                    editing = page
                }
            }
        }
        .toolbar { EditButton() }
        .sheet(item: $editing) { page in PageDetails(page: page) }
    }
}

private struct PageDetails: View {
    @State var page: Page
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pickingSymbol = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $page.title)
                Button {
                    pickingSymbol = true
                } label: {
                    LabeledContent("Symbol") { Image(systemName: page.symbol) }
                }
                Toggle("Show in the top bar", isOn: $page.pinnedToBar)
                TextField("App bundle ID (for app pages)", text: Binding(get: { page.appBundleID ?? "" }, set: { page.appBundleID = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Section {
                    Button("Duplicate Page", systemImage: "plus.square.on.square") {
                        var workspace = model.workspace
                        var copy = page
                        copy.id = "page.\(UUID().uuidString.prefix(8))"
                        copy.title += " Copy"
                        copy.tiles = copy.tiles.map { tile in
                            var tile = tile
                            tile.id = UUID().uuidString
                            return tile
                        }
                        workspace.pages.append(copy)
                        model.commit(workspace)
                        dismiss()
                    }
                    Button("Delete Page", systemImage: "trash", role: .destructive) {
                        var workspace = model.workspace
                        workspace.pages.removeAll { $0.id == page.id }
                        model.commit(workspace)
                        dismiss()
                    }
                    .disabled(page.id == "home")
                }
            }
            .navigationTitle(page.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.updatePage(page)
                        dismiss()
                    }
                    .bold()
                }
            }
            .sheet(isPresented: $pickingSymbol) {
                SymbolPicker(selection: Binding(get: { page.symbol }, set: { page.symbol = $0 ?? page.symbol }))
            }
        }
    }
}

// MARK: - App mappings

private struct MappingsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        let mappings = model.workspace.rules.filter { $0.match.isSimpleAppMapping }
        Form {
            Section {
                ForEach(mappings) { rule in
                    HStack(spacing: 12) {
                        HStack(spacing: -6) {
                            ForEach(rule.match.bundleIDs.prefix(4), id: \.self) { AppIconView(bundleID: $0, size: 28) }
                        }
                        VStack(alignment: .leading) {
                            Text(rule.name)
                            Text(rule.match.bundleIDs.joined(separator: ", ")).font(.caption).foregroundStyle(CC.text2).lineLimit(1)
                        }
                        Spacer()
                        Picker("", selection: pageBinding(rule)) {
                            ForEach(model.workspace.pages) { Text($0.title).tag($0.id) }
                        }
                        .labelsHidden()
                    }
                }
                .onDelete { offsets in
                    var workspace = model.workspace
                    let ids = offsets.map { mappings[$0].id }
                    workspace.rules.removeAll { ids.contains($0.id) }
                    model.commit(workspace)
                }
            } footer: {
                Text("When the app is in front on your Mac, the iPad shows the page. Context rules (Study mode, meetings, the Morning Brief) take priority.")
            }
            Section {
                MacItemPicker(title: "Map an App…", kind: .installedApps, selection: "", display: "") { item in
                    var workspace = model.workspace
                    let pageID = workspace.pages.first { $0.appBundleID == item.id }?.id ?? "home"
                    workspace.rules.append(ContextRule(id: "map.\(item.id)", name: item.title, priority: 50, match: RuleMatch(bundleIDs: [item.id]), page: pageID))
                    model.commit(workspace)
                }
            }
        }
    }

    private func pageBinding(_ rule: ContextRule) -> Binding<String> {
        Binding(get: { rule.page }, set: { value in
            var workspace = model.workspace
            if let index = workspace.rules.firstIndex(where: { $0.id == rule.id }) {
                workspace.rules[index].page = value
                model.commit(workspace)
            }
        })
    }
}

// MARK: - Context rules

private struct RulesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if let resolution = model.navigator.resolution {
                    LabeledContent("Showing", value: model.workspace.page(resolution.pageID)?.title ?? resolution.pageID)
                    LabeledContent("Because", value: resolution.reason)
                    LabeledContent("Active modes", value: resolution.modes.isEmpty ? "none" : resolution.modes.sorted().joined(separator: ", "))
                }
                Toggle("Switch pages automatically", isOn: Binding(get: { model.workspace.preferences.autoSwitch }, set: { value in
                    var workspace = model.workspace
                    workspace.preferences.autoSwitch = value
                    model.commit(workspace)
                }))
            }
            Section("Rules — highest priority wins") {
                ForEach(model.workspace.rules.sorted { $0.priority > $1.priority }) { rule in
                    NavigationLink {
                        RuleEditor(rule: rule)
                    } label: {
                        HStack {
                            Text("\(rule.priority)").font(.caption.monospacedDigit()).foregroundStyle(CC.text2).frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(rule.name).foregroundStyle(rule.enabled ? CC.text : CC.text3)
                                Text("→ \(model.workspace.page(rule.page)?.title ?? rule.page)").font(.caption).foregroundStyle(CC.text2)
                            }
                            Spacer()
                            if model.navigator.resolution?.ruleID == rule.id { Pill(text: "Active", color: CC.green) }
                        }
                    }
                }
                Button("New Rule", systemImage: "plus") {
                    var workspace = model.workspace
                    workspace.rules.append(ContextRule(id: "rule.\(UUID().uuidString.prefix(6))", name: "New rule", priority: 70, match: RuleMatch(bundleIDs: ["com.example.app"]), page: "home"))
                    model.commit(workspace)
                }
            }
        }
    }
}

private struct RuleEditor: View {
    @State var rule: ContextRule
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            TextField("Name", text: $rule.name)
            Toggle("Enabled", isOn: $rule.enabled)
            Stepper("Priority \(rule.priority)", value: $rule.priority, in: 0...100)
            Picker("Show page", selection: $rule.page) {
                ForEach(model.workspace.pages) { Text($0.title).tag($0.id) }
            }
            Section("When — all of these hold") {
                list("Frontmost app bundle IDs", $rule.match.bundleIDs)
                list("URL contains", $rule.match.urlContains)
                list("Window title contains", $rule.match.titleContains)
                list("Focus is one of", $rule.match.focusNames)
                list("Modes (morning, study, meeting, focusSession, away)", $rule.match.modes)
                TextField("From (HH:mm)", text: Binding(get: { rule.match.timeStart ?? "" }, set: { rule.match.timeStart = $0.isEmpty ? nil : $0 }))
                TextField("Until (HH:mm)", text: Binding(get: { rule.match.timeEnd ?? "" }, set: { rule.match.timeEnd = $0.isEmpty ? nil : $0 }))
            }
            Section {
                Button("Save Rule") {
                    var workspace = model.workspace
                    if let index = workspace.rules.firstIndex(where: { $0.id == rule.id }) { workspace.rules[index] = rule }
                    model.commit(workspace)
                }
                Button("Delete Rule", role: .destructive) {
                    var workspace = model.workspace
                    workspace.rules.removeAll { $0.id == rule.id }
                    model.commit(workspace)
                }
            }
        }
        .navigationTitle(rule.name)
    }

    private func list(_ title: String, _ binding: Binding<[String]>) -> some View {
        TextField(title, text: Binding(get: { binding.wrappedValue.joined(separator: ", ") }, set: { binding.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

// MARK: - Strip

private struct StripSettings: View {
    @Environment(AppModel.self) private var model
    @State private var editing: ButtonDef?

    var body: some View {
        let strip = model.workspace.strip
        Form {
            Section("Quick keys (always visible)") {
                ForEach(strip.keys) { key in
                    Button {
                        editing = key
                    } label: {
                        HStack {
                            Image(systemName: key.symbol ?? "circle").foregroundStyle(CC.keyTint(key.color)).frame(width: 26)
                            Text(key.label).foregroundStyle(CC.text)
                            Spacer()
                            Text(key.action.summary).font(.caption).foregroundStyle(CC.text2)
                        }
                    }
                }
            }
            Section("Show") {
                toggle("Microphone", \.showsMic)
                toggle("Now playing", \.showsNowPlaying)
                toggle("Running timer", \.showsTimer)
                toggle("Volume", \.showsVolume)
            }
        }
        .sheet(item: $editing) { key in
            KeyEditor(pageID: nil, tileID: nil, key: key) { updated in
                var workspace = model.workspace
                if let index = workspace.strip.keys.firstIndex(where: { $0.id == updated.id }) { workspace.strip.keys[index] = updated }
                model.commit(workspace)
            }
        }
    }

    private func toggle(_ title: String, _ path: WritableKeyPath<StripConfig, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { model.workspace.strip[keyPath: path] }, set: { value in
            var workspace = model.workspace
            workspace.strip[keyPath: path] = value
            model.commit(workspace)
        }))
    }
}

// MARK: - Scenes

private struct ScenesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(model.workspace.scenes) { scene in
                    NavigationLink {
                        SceneEditor(scene: scene)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: scene.symbol).foregroundStyle(CC.key(scene.color)).frame(width: 26)
                            VStack(alignment: .leading) {
                                Text(scene.name)
                                Text("\(scene.steps.count) steps\(scene.page.map { " → \($0)" } ?? "")").font(.caption).foregroundStyle(CC.text2)
                            }
                            Spacer()
                            Button("Run") { model.send(.scene(scene.id)) }.buttonStyle(.borderless)
                        }
                    }
                }
                Button("New Scene", systemImage: "plus") {
                    var workspace = model.workspace
                    workspace.scenes.append(SceneDef(id: "scene.\(UUID().uuidString.prefix(6))", name: "New Scene", symbol: "sparkles", steps: []))
                    model.commit(workspace)
                }
            } footer: {
                Text("Scenes run from keys, Siri (“Run Lecture Mode in Control Center”), widgets, Control Center and the Mac's local API.")
            }
        }
    }
}

private struct SceneEditor: View {
    @State var scene: SceneDef
    @Environment(AppModel.self) private var model
    @State private var pickingSymbol = false

    var body: some View {
        Form {
            TextField("Name", text: $scene.name)
            Button {
                pickingSymbol = true
            } label: {
                LabeledContent("Symbol") { Image(systemName: scene.symbol) }
            }
            ColorSwatches(selection: $scene.color)
            Picker("Then show", selection: Binding(get: { scene.page ?? "" }, set: { scene.page = $0.isEmpty ? nil : $0 })) {
                Text("Stay").tag("")
                ForEach(model.workspace.pages) { Text($0.title).tag($0.id) }
            }
            NavigationLink {
                MacroEditor(steps: $scene.steps)
            } label: {
                LabeledContent("Steps", value: "\(scene.steps.count)")
            }
            Section {
                Button("Save Scene") {
                    var workspace = model.workspace
                    if let index = workspace.scenes.firstIndex(where: { $0.id == scene.id }) { workspace.scenes[index] = scene }
                    model.commit(workspace)
                }
                Button("Run Now") { model.send(.scene(scene.id)) }
                Button("Delete Scene", role: .destructive) {
                    var workspace = model.workspace
                    workspace.scenes.removeAll { $0.id == scene.id }
                    model.commit(workspace)
                }
            }
        }
        .navigationTitle(scene.name)
        .sheet(isPresented: $pickingSymbol) {
            SymbolPicker(selection: Binding(get: { scene.symbol }, set: { scene.symbol = $0 ?? scene.symbol }))
        }
    }
}

// MARK: - Data sources

private struct SourcesSettings: View {
    @Environment(AppModel.self) private var model
    @State private var settings: IntegrationSettings?
    @State private var botKey = ""
    @State private var whoopSecret = ""
    @State private var portfolioAuth = ""
    @State private var saved: ActionResult?

    var body: some View {
        Form {
            Section("Status on the Mac") {
                ForEach(model.store.helper?.integrations ?? []) { status in
                    HStack(spacing: 10) {
                        Circle().fill(color(status.health)).frame(width: 8, height: 8)
                        Image(systemName: status.id.symbol).foregroundStyle(CC.text2).frame(width: 22)
                        Text(status.id.title)
                        Spacer()
                        Text(status.detail).font(.caption).foregroundStyle(CC.text2).lineLimit(1)
                    }
                }
            }
            if let binding = Binding($settings) {
                Section("Trading bot") {
                    Picker("Mode", selection: binding.bot.mode) {
                        ForEach(BotMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if binding.wrappedValue.bot.mode == .live {
                        TextField("Bot URL", text: binding.bot.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField(binding.wrappedValue.bot.hasAPIKey ? "API key (saved)" : "API key (optional)", text: $botKey)
                    }
                    Button("Test Connection") {
                        Task { saved = await model.perform(.integration(IntegrationCommand(.bot, .test))) }
                    }
                }
                Section {
                    TextField("Client ID", text: binding.whoop.clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(binding.wrappedValue.whoop.hasClientSecret ? "Client secret (saved)" : "Client secret", text: $whoopSecret)
                    TextField("Redirect URI", text: binding.whoop.redirectURI).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(model.store.whoop?.connected == true ? "Reconnect WHOOP" : "Sign In on Mac") {
                        Task {
                            await save()
                            saved = await model.perform(.integration(IntegrationCommand(.whoop, .connect)))
                        }
                    }
                } header: {
                    Text("WHOOP")
                } footer: {
                    Text("Sign-in opens in the browser on your Mac; tokens stay in its Keychain.")
                }
                Section("PortTracker") {
                    Toggle("Enabled", isOn: binding.portfolio.enabled)
                    TextField("https://your-porttracker.vercel.app", text: binding.portfolio.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Picker("Auth header", selection: binding.portfolio.authHeader) {
                        Text("Cookie").tag("Cookie")
                        Text("Authorization").tag("Authorization")
                    }
                    SecureField(binding.wrappedValue.portfolio.hasAuthValue ? "Header value (saved)" : "Header value", text: $portfolioAuth)
                }
                Section("Mac context") {
                    Toggle("Weather", isOn: binding.weatherEnabled)
                    Toggle("Read browser tab URLs", isOn: binding.browserURLTracking)
                    Toggle("Read window titles", isOn: binding.windowTitleTracking)
                }
                Section {
                    Button("Save to Mac") { Task { await save() } }.bold()
                    if let saved {
                        Label(saved.message ?? (saved.ok ? "Saved" : "Failed"), systemImage: saved.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(saved.ok ? CC.green : CC.red)
                    }
                } footer: {
                    Text("Secrets are sent once over the encrypted link and stored in the Mac's Keychain — never shown again, never in exported layouts.")
                }
            } else {
                Section { ProgressView("Asking your Mac…") }
            }
        }
        .task {
            settings = await model.query(.integrations)?.integrations
        }
    }

    private func save() async {
        guard var settings else { return }
        var secrets: [String: String] = [:]
        if !botKey.isEmpty { secrets[IntegrationSettings.SecretKey.botAPIKey] = botKey }
        if !whoopSecret.isEmpty { secrets[IntegrationSettings.SecretKey.whoopClientSecret] = whoopSecret }
        if !portfolioAuth.isEmpty { secrets[IntegrationSettings.SecretKey.portfolioAuth] = portfolioAuth }
        settings.secrets = secrets.isEmpty ? nil : secrets
        let reply = try? await model.link.request(.updateIntegrations(settings), timeout: 10)
        if case .actionResult(let result) = reply?.body { saved = result } else { saved = .failure("The Mac didn't answer") }
        botKey = ""
        whoopSecret = ""
        portfolioAuth = ""
        self.settings = await model.query(.integrations)?.integrations ?? self.settings
    }

    private func color(_ health: IntegrationHealth) -> Color {
        switch health {
        case .ok: CC.green
        case .warning: CC.yellow
        case .error: CC.red
        case .needsSetup: CC.orange
        case .off: CC.text3
        }
    }
}

// MARK: - Morning & timers

private struct MorningSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Morning Brief") {
                TextField("Your name", text: pref(\.ownerName))
                Stepper("Shows from \(clock(model.workspace.preferences.morningStart))", value: pref(\.morningStart), in: 0...(23 * 60), step: 30)
                Stepper("Until \(clock(model.workspace.preferences.morningEnd))", value: pref(\.morningEnd), in: 0...(24 * 60), step: 30)
                TextField("Weather location", text: pref(\.weatherLocation))
                Toggle("Mirror top 3 to Reminders", isOn: pref(\.mirrorPrioritiesToReminders))
            }
            Section("Pomodoro") {
                Stepper("Focus \(Int(model.workspace.preferences.pomodoroMinutes)) min", value: pref(\.pomodoroMinutes), in: 5...90, step: 5)
                Stepper("Short break \(Int(model.workspace.preferences.shortBreakMinutes)) min", value: pref(\.shortBreakMinutes), in: 1...30)
                Stepper("Long break \(Int(model.workspace.preferences.longBreakMinutes)) min", value: pref(\.longBreakMinutes), in: 5...60, step: 5)
                Stepper("\(model.workspace.preferences.sessionsPerCycle) sessions per cycle", value: pref(\.sessionsPerCycle), in: 2...8)
                Toggle("Start breaks automatically", isOn: pref(\.autoStartBreaks))
                Stepper("Deep work \(Int(model.workspace.preferences.deepWorkMinutes)) min", value: pref(\.deepWorkMinutes), in: 30...240, step: 15)
            }
            Section("Focus & study") {
                TextField("Focus for deep work", text: pref(\.focusName))
                TextField("Focus that means studying", text: pref(\.studyFocusName))
                TextField("Lecture keywords", text: Binding(get: { model.workspace.preferences.studyKeywords.joined(separator: ", ") }, set: { value in
                    update { $0.studyKeywords = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                }))
                TextField("Course folder", text: pref(\.courseFolder)).textInputAutocapitalization(.never)
                TextField("Projects folder", text: pref(\.projectsFolder)).textInputAutocapitalization(.never)
            }
        }
    }

    private func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }

    private func update(_ change: (inout WorkspacePreferences) -> Void) {
        var workspace = model.workspace
        change(&workspace.preferences)
        model.commit(workspace)
    }

    private func pref<T>(_ path: WritableKeyPath<WorkspacePreferences, T>) -> Binding<T> {
        Binding(get: { model.workspace.preferences[keyPath: path] }, set: { value in update { $0[keyPath: path] = value } })
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Theme", selection: $model.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Dark is the default — it looks best on the desk and saves the mini-LED backlight.")
            }
            Section {
                Toggle("Key click sound", isOn: $model.keyClicks)
            } footer: {
                Text("iPads have no Taptic Engine, so the click and the key's acknowledgement glow are the tap feedback. iPhones also get haptics.")
            }
            Section("Ambient mode") {
                Stepper("Dim after \(Int(model.workspace.preferences.ambientAfterMinutes)) min idle", value: Binding(get: { model.workspace.preferences.ambientAfterMinutes }, set: { value in
                    var workspace = model.workspace
                    workspace.preferences.ambientAfterMinutes = value
                    model.commit(workspace)
                }), in: 1...60)
                Slider(value: Binding(get: { model.workspace.preferences.ambientBrightness }, set: { value in
                    var workspace = model.workspace
                    workspace.preferences.ambientBrightness = value
                    model.commit(workspace)
                }), in: 0.02...0.6) { Text("Brightness") }
            }
        }
    }
}

// MARK: - Permissions

private struct PermissionsSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(model.store.helper?.permissions ?? []) { permission in
                    HStack(spacing: 12) {
                        Image(systemName: permission.granted ? "checkmark.circle.fill" : (permission.required ? "exclamationmark.circle.fill" : "circle.dashed"))
                            .foregroundStyle(permission.granted ? CC.green : (permission.required ? CC.orange : CC.text3))
                            .font(.title3)
                        VStack(alignment: .leading) {
                            Text(permission.kind.title + (permission.required ? " · required" : ""))
                            Text(permission.kind.purpose).font(.caption).foregroundStyle(CC.text2)
                        }
                    }
                }
            } footer: {
                Text("Grant these on the Mac: menu bar icon → the orange “Grant” button, or the helper's Preferences → Permissions.")
            }
        }
    }
}

// MARK: - Export & import

private struct TransferSettings: View {
    @Environment(AppModel.self) private var model
    @State private var importing = false
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                ShareLink(item: WorkspaceFile(workspace: model.workspace), preview: SharePreview("ControlCenter layout", image: Image(systemName: "square.grid.2x2"))) {
                    Label("Export Layout as JSON", systemImage: "square.and.arrow.up")
                }
                Button("Import Layout…", systemImage: "square.and.arrow.down") { importing = true }
            } footer: {
                Text("Pages, keys, strip, rules, scenes and preferences — no secrets. Import replaces your layout on every device. You can also edit workspace.json on the Mac; iPads reload when you save.")
            }
            if let message { Section { Text(message) } }
            Section {
                Button("Reset to Default Layout", role: .destructive) { confirmReset = true }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                var workspace = try JSONDecoder().decode(Workspace.self, from: data)
                workspace.revision = model.workspace.revision
                model.commit(workspace)
                message = "Imported \(workspace.pages.count) pages."
            } catch {
                message = "Couldn't import: \(error.localizedDescription)"
            }
        }
        .confirmationDialog("Reset the layout?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                var fresh = DefaultWorkspace.make(preferences: model.workspace.preferences)
                fresh.revision = model.workspace.revision
                model.commit(fresh)
            }
        }
    }
}

struct WorkspaceFile: Transferable {
    let workspace: Workspace

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(file.workspace)
        }
        .suggestedFileName("ControlCenter-layout.json")
    }
}

// MARK: - About

private struct AboutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    BrandMark().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Control Center").font(.title2.bold())
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") · protocol v\(ccProtocolVersion)")
                            .font(.caption).foregroundStyle(CC.text2)
                    }
                }
            }
            Section("How it fits together") {
                Text("One hub on the Mac owns all live state and runs only the providers a screen is watching. Every key, scene, widget, Siri phrase and Control Center toggle is the same action language. Pages are tiles on a 12 × 12 grid, chosen by rules over what's in front of you, your Focus, your calendar and the time.")
                    .font(.callout)
            }
        }
    }
}
