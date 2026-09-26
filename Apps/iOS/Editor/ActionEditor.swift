import CCCore
import SwiftUI

/// The action types, grouped the way people think about them.
enum ActionKind: String, CaseIterable, Identifiable {
    case keyCombo, text
    case openApp, openURL, openPath
    case shortcut, appleScript, shell, macro, scene
    case media, system, window, audio, call
    case bot, focus, timer, git
    case navigate, daily, clipboard, integration
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keyCombo: "Keyboard Shortcut"
        case .text: "Type Text"
        case .openApp: "Open App"
        case .openURL: "Open URL"
        case .openPath: "Open File or Folder"
        case .shortcut: "Run Shortcut"
        case .appleScript: "AppleScript"
        case .shell: "Shell Command"
        case .macro: "Macro"
        case .scene: "Scene"
        case .media: "Media Key"
        case .system: "System"
        case .window: "Window"
        case .audio: "Sound & Mic"
        case .call: "Call Control"
        case .bot: "Trading Bot"
        case .focus: "Focus"
        case .timer: "Timer"
        case .git: "Git"
        case .navigate: "Show Page"
        case .daily: "Today"
        case .clipboard: "Clipboard"
        case .integration: "Integration"
        case .none: "Nothing"
        }
    }

    var symbol: String {
        switch self {
        case .keyCombo: "command"
        case .text: "character.cursor.ibeam"
        case .openApp: "app.badge"
        case .openURL: "link"
        case .openPath: "folder"
        case .shortcut: "square.stack.3d.up"
        case .appleScript: "applescript"
        case .shell: "terminal"
        case .macro: "list.number"
        case .scene: "sparkles"
        case .media: "playpause"
        case .system: "gearshape.2"
        case .window: "rectangle.split.2x1"
        case .audio: "speaker.wave.2"
        case .call: "phone"
        case .bot: "chart.line.uptrend.xyaxis"
        case .focus: "moon"
        case .timer: "timer"
        case .git: "arrow.triangle.branch"
        case .navigate: "rectangle.stack"
        case .daily: "checklist"
        case .clipboard: "doc.on.clipboard"
        case .integration: "puzzlepiece"
        case .none: "circle.slash"
        }
    }

    static let groups: [(String, [ActionKind])] = [
        ("Keyboard", [.keyCombo, .text]),
        ("Open", [.openApp, .openURL, .openPath]),
        ("Automation", [.shortcut, .macro, .scene, .appleScript, .shell]),
        ("Mac", [.media, .system, .window, .audio, .call]),
        ("Integrations", [.bot, .focus, .timer, .git]),
        ("Control Center", [.navigate, .daily, .clipboard, .integration, .none]),
    ]

    init(_ action: ButtonAction) {
        self = ActionKind(rawValue: action.typeName) ?? .none
    }

    var defaultAction: ButtonAction {
        switch self {
        case .keyCombo: .keyCombo(KeyCombo(keys: ["cmd"]))
        case .text: .text(TextInput(text: "", submit: false))
        case .openApp: .openApp(AppRef(bundleID: "com.apple.Safari", name: "Safari"))
        case .openURL: .openURL(URLRef(url: "https://"))
        case .openPath: .openPath("~/Downloads")
        case .shortcut: .shortcut(ShortcutRun(name: ""))
        case .appleScript: .appleScript("tell application \"Finder\" to activate")
        case .shell: .shell(ShellCommand(command: "echo hello"))
        case .macro: .macro([])
        case .scene: .scene("startDay")
        case .media: .media(.playPause)
        case .system: .system(.missionControl)
        case .window: .window(.leftHalf)
        case .audio: .audio(AudioCommand(.micToggle))
        case .call: .call(.toggleMute)
        case .bot: .bot(.pause)
        case .focus: .focus(FocusCommand(.toggle))
        case .timer: .timer(.start(.pomodoro))
        case .git: .git(GitCommand(.status))
        case .navigate: .navigate("home")
        case .daily: .daily(DailyCommand(.setStudyMode, enabled: true))
        case .clipboard: .clipboard(ClipboardCommand(.copyURL))
        case .integration: .integration(IntegrationCommand(.whoop, .refresh))
        case .none: .none
        }
    }
}

/// Edits any `ButtonAction` — used by keys, strip keys, macro steps and scenes.
struct ActionEditor: View {
    @Binding var action: ButtonAction
    @Environment(AppModel.self) private var model

    var body: some View {
        Section("Action") {
            Picker(selection: Binding(get: { ActionKind(action) }, set: { action = $0.defaultAction })) {
                ForEach(ActionKind.groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                }
            } label: {
                Text("Type")
            }
            .pickerStyle(.menu)
            fields
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch action {
        case .keyCombo(let combo):
            KeyComboEditor(combo: Binding(get: { combo }, set: { action = .keyCombo($0) }))
        case .text(let input):
            TextField("Text to type — {{date}}, {{url}}, {{input}}…", text: Binding(get: { input.text }, set: { action = .text(TextInput(text: $0, submit: input.pressesReturn)) }), axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...6)
            Toggle("Press Return after", isOn: Binding(get: { input.pressesReturn }, set: { action = .text(TextInput(text: input.text, submit: $0)) }))
        case .openApp(let app):
            MacItemPicker(title: "App", kind: .installedApps, selection: app.bundleID, display: app.name ?? app.bundleID) { item in
                action = .openApp(AppRef(bundleID: item.id, name: item.title))
            }
        case .openURL(let ref):
            TextField("https://…  ({{input}} asks when tapped)", text: Binding(get: { ref.url }, set: { action = .openURL(URLRef(url: $0, bundleID: ref.bundleID)) }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Picker("Open with", selection: Binding(get: { ref.bundleID ?? "" }, set: { action = .openURL(URLRef(url: ref.url, bundleID: $0.isEmpty ? nil : $0)) })) {
                Text("Default browser").tag("")
                Text("Safari").tag(Bundles.safari)
                Text("Chrome").tag(Bundles.chrome)
                Text("Arc").tag(Bundles.arc)
                Text("Notion").tag(Bundles.notion)
            }
        case .openPath(let path):
            TextField("~/Folder or /path/to/file", text: Binding(get: { path }, set: { action = .openPath($0) }))
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .shortcut(let run):
            MacItemPicker(title: "Shortcut", kind: .shortcuts, selection: run.name, display: run.name.isEmpty ? "Choose…" : run.name) { item in
                action = .shortcut(ShortcutRun(name: item.id, input: run.input))
            }
            TextField("Input (optional)", text: Binding(get: { run.input ?? "" }, set: { action = .shortcut(ShortcutRun(name: run.name, input: $0.isEmpty ? nil : $0)) }))
        case .appleScript(let source):
            TextEditor(text: Binding(get: { source }, set: { action = .appleScript($0) }))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 140)
        case .shell(let command):
            TextField("Command", text: Binding(get: { command.command }, set: { value in var c = command; c.command = value; action = .shell(c) }), axis: .vertical)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Working directory (optional)", text: Binding(get: { command.cwd ?? "" }, set: { value in var c = command; c.cwd = value.isEmpty ? nil : value; action = .shell(c) }))
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
            Toggle("Show output on the iPad", isOn: Binding(get: { command.showOutput ?? false }, set: { value in var c = command; c.showOutput = value; action = .shell(c) }))
            Stepper("Timeout \(Int(command.timeout ?? 60)) s", value: Binding(get: { command.timeout ?? 60 }, set: { value in var c = command; c.timeout = value; action = .shell(c) }), in: 5...600, step: 5)
        case .macro(let steps):
            NavigationLink {
                MacroEditor(steps: Binding(get: { steps }, set: { action = .macro($0) }))
            } label: {
                LabeledContent("Steps", value: "\(steps.count)")
            }
        case .scene(let id):
            Picker("Scene", selection: Binding(get: { id }, set: { action = .scene($0) })) {
                ForEach(model.workspace.scenes) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
            }
        case .media(let command):
            Picker("Key", selection: Binding(get: { command }, set: { action = .media($0) })) {
                ForEach(MediaCommand.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        case .system(let command):
            Picker("Command", selection: Binding(get: { command }, set: { action = .system($0) })) {
                ForEach(SystemCommand.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        case .window(let command):
            Picker("Tile", selection: Binding(get: { command }, set: { action = .window($0) })) {
                ForEach(WindowCommand.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
        case .audio(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .audio(AudioCommand($0, value: command.value)) })) {
                Text("Toggle Microphone").tag(AudioCommand.Kind.micToggle)
                Text("Mute Microphone").tag(AudioCommand.Kind.micMute)
                Text("Unmute Microphone").tag(AudioCommand.Kind.micUnmute)
                Text("Toggle Sound").tag(AudioCommand.Kind.outputMuteToggle)
                Text("Set Volume").tag(AudioCommand.Kind.setOutputVolume)
                Text("Set Mic Level").tag(AudioCommand.Kind.setInputVolume)
            }
            if command.command == .setOutputVolume || command.command == .setInputVolume {
                Slider(value: Binding(get: { command.value ?? 0.5 }, set: { action = .audio(AudioCommand(command.command, value: $0)) }), in: 0...1)
            }
        case .call(let command):
            Picker("Control", selection: Binding(get: { command }, set: { action = .call($0) })) {
                ForEach(CallCommand.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }
            Text("Works with Zoom, Teams, Google Meet, Webex and Discord.").font(.caption).foregroundStyle(CC.text2)
        case .bot(let command):
            Picker("Command", selection: Binding(get: { command }, set: { action = .bot($0) })) {
                ForEach(BotCommand.allCases, id: \.self) { Text($0.title).tag($0) }
            }
        case .focus(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .focus(FocusCommand($0, name: command.name)) })) {
                Text("Turn On").tag(FocusCommand.Kind.on)
                Text("Turn Off").tag(FocusCommand.Kind.off)
                Text("Toggle").tag(FocusCommand.Kind.toggle)
            }
            .pickerStyle(.segmented)
            if command.command != .off {
                MacItemPicker(title: "Focus", kind: .focusModes, selection: command.name ?? "", display: command.name ?? "Default (\(model.workspace.preferences.focusName))") { item in
                    action = .focus(FocusCommand(command.command, name: item.id))
                }
            }
        case .timer(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .timer(TimerCommand($0, preset: command.preset ?? TimerPreset(kind: .pomodoro))) })) {
                ForEach(TimerCommand.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            if command.command == .start {
                let preset = command.preset ?? TimerPreset(kind: .pomodoro)
                Picker("Kind", selection: Binding(get: { preset.kind }, set: { value in var p = preset; p.kind = value; action = .timer(TimerCommand(.start, preset: p)) })) {
                    ForEach(TimerKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Stepper("\(Int(preset.minutes ?? model.workspace.preferences.minutes(for: preset.kind))) minutes", value: Binding(get: { preset.minutes ?? model.workspace.preferences.minutes(for: preset.kind) }, set: { value in var p = preset; p.minutes = value; action = .timer(TimerCommand(.start, preset: p)) }), in: 1...240)
                Toggle("Focus while it runs", isOn: Binding(get: { preset.focus ?? false }, set: { value in var p = preset; p.focus = value; action = .timer(TimerCommand(.start, preset: p)) }))
            }
        case .git(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .git(GitCommand($0, message: $0 == .commitAll ? "{{input}}" : nil, repo: command.repo)) })) {
                ForEach(GitCommand.Kind.allCases, id: \.self) { Text($0 == .commitAll ? "Commit all" : $0.rawValue.capitalized).tag($0) }
            }
            TextField("Repository (blank = current)", text: Binding(get: { command.repo ?? "" }, set: { action = .git(GitCommand(command.command, message: command.message, repo: $0.isEmpty ? nil : $0)) }))
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never)
        case .navigate(let page):
            Picker("Page", selection: Binding(get: { page }, set: { action = .navigate($0) })) {
                ForEach(model.workspace.pages) { Label($0.title, systemImage: $0.symbol).tag($0.id) }
            }
        case .daily(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .daily(DailyCommand($0, enabled: true)) })) {
                Text("Study Mode").tag(DailyCommand.Kind.setStudyMode)
                Text("Start the Day").tag(DailyCommand.Kind.startDay)
                Text("Dismiss Brief").tag(DailyCommand.Kind.dismissBrief)
                Text("Carry Over Priorities").tag(DailyCommand.Kind.carryOver)
                Text("Clear Priorities").tag(DailyCommand.Kind.clearPriorities)
            }
            if command.command == .setStudyMode {
                Toggle("Study mode on", isOn: Binding(get: { command.enabled ?? true }, set: { action = .daily(DailyCommand(.setStudyMode, enabled: $0)) }))
            }
        case .clipboard(let command):
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .clipboard(ClipboardCommand($0, text: command.text)) })) {
                Text("Copy current URL").tag(ClipboardCommand.Kind.copyURL)
                Text("Set text").tag(ClipboardCommand.Kind.setText)
            }
            if command.command == .setText {
                TextField("Text", text: Binding(get: { command.text ?? "" }, set: { action = .clipboard(ClipboardCommand(.setText, text: $0)) }))
            }
        case .app(let control):
            MacItemPicker(title: "App", kind: .installedApps, selection: control.bundleID, display: control.bundleID) { item in
                action = .app(AppControl(control.command, bundleID: item.id))
            }
            Picker("Command", selection: Binding(get: { control.command }, set: { action = .app(AppControl($0, bundleID: control.bundleID)) })) {
                Text("Bring to front").tag(AppControl.Kind.activate)
                Text("Hide").tag(AppControl.Kind.hide)
                Text("Quit").tag(AppControl.Kind.quit)
            }
        case .integration(let command):
            Picker("Integration", selection: Binding(get: { command.integration }, set: { action = .integration(IntegrationCommand($0, command.command)) })) {
                ForEach(IntegrationID.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Command", selection: Binding(get: { command.command }, set: { action = .integration(IntegrationCommand(command.integration, $0)) })) {
                ForEach(IntegrationCommand.Kind.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
        case .none, .unsupported:
            Text(action.summary.isEmpty ? "This key does nothing yet." : action.summary).foregroundStyle(CC.text2)
        }
    }
}

// MARK: - Key combo

struct KeyComboEditor: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @FocusState private var recorderFocused: Bool

    private static let namedKeys: [NamedKey] = [.return, .tab, .space, .delete, .forwardDelete, .escape, .left, .right, .up, .down, .home, .end, .pageUp, .pageDown, .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(KeyModifier.displayOrder, id: \.self) { modifier in
                let on = combo.modifiers.contains(modifier)
                Button {
                    toggle(modifier)
                } label: {
                    Text(modifier.symbol)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .frame(width: 44, height: 38)
                        .foregroundStyle(on ? Color(hex: 0x0A0A0F) : CC.text)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? CC.accent : CC.elevated))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(modifier.title)
            }
            Spacer()
            Text(combo.display.isEmpty ? "—" : combo.display)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(CC.text)
        }
        HStack {
            TextField("Key (a, 4, /, …)", text: Binding(get: {
                guard let key = combo.key, combo.namedKey == nil else { return "" }
                return key
            }, set: { value in
                setKey(value.last.map { String($0).lowercased() })
            }))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            Menu("Special Key") {
                ForEach(Self.namedKeys, id: \.self) { key in
                    Button("\(key.symbol)  \(key.rawValue)") { setKey(key.rawValue) }
                }
            }
        }
        Button(recording ? "Press a shortcut on your keyboard…" : "Record from a hardware keyboard", systemImage: "keyboard") {
            recording = true
            recorderFocused = true
        }
        .focusable()
        .focused($recorderFocused)
        .onKeyPress(phases: .down) { press in
            guard recording else { return .ignored }
            var keys: [String] = []
            if press.modifiers.contains(.control) { keys.append("ctrl") }
            if press.modifiers.contains(.option) { keys.append("opt") }
            if press.modifiers.contains(.shift) { keys.append("shift") }
            if press.modifiers.contains(.command) { keys.append("cmd") }
            let key: String? = switch press.key {
            case .return: "return"
            case .tab: "tab"
            case .space: "space"
            case .delete: "delete"
            case .deleteForward: "forwardDelete"
            case .escape: "escape"
            case .leftArrow: "left"
            case .rightArrow: "right"
            case .upArrow: "up"
            case .downArrow: "down"
            case .home: "home"
            case .end: "end"
            case .pageUp: "pageUp"
            case .pageDown: "pageDown"
            default: press.characters.lowercased().first.map(String.init)
            }
            guard let key else { return .ignored }
            combo = KeyCombo(keys: keys + [key])
            recording = false
            return .handled
        }
    }

    private func toggle(_ modifier: KeyModifier) {
        var modifiers = combo.modifiers
        if modifiers.contains(modifier) { modifiers.remove(modifier) } else { modifiers.insert(modifier) }
        let ordered = KeyModifier.displayOrder.filter(modifiers.contains).map(\.rawValue)
        combo = KeyCombo(keys: ordered + (combo.key.map { [$0] } ?? []))
    }

    private func setKey(_ key: String?) {
        let modifiers = KeyModifier.displayOrder.filter(combo.modifiers.contains).map(\.rawValue)
        combo = KeyCombo(keys: modifiers + (key.map { [$0] } ?? []))
    }
}

// MARK: - Picking things that live on the Mac

/// Lists shortcuts, apps or Focus modes straight from the Mac.
struct MacItemPicker: View {
    let title: String
    let kind: Query.Kind
    let selection: String
    let display: String
    let onPick: (QueryItem) -> Void

    @Environment(AppModel.self) private var model
    @State private var items: [QueryItem] = []
    @State private var loading = false
    @State private var showing = false
    @State private var search = ""

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack {
                Text(title).foregroundStyle(CC.text)
                Spacer()
                if kind == .installedApps { AppIconView(bundleID: selection, size: 22) }
                Text(display).foregroundStyle(CC.text2).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(CC.text3)
            }
        }
        .sheet(isPresented: $showing) {
            NavigationStack {
                List(filtered) { item in
                    Button {
                        onPick(item)
                        showing = false
                    } label: {
                        HStack(spacing: 12) {
                            if kind == .installedApps { AppIconView(bundleID: item.id, size: 30) }
                            VStack(alignment: .leading) {
                                Text(item.title).foregroundStyle(CC.text)
                                if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(CC.text2) }
                            }
                            Spacer()
                            if item.id == selection { Image(systemName: "checkmark").foregroundStyle(CC.accent) }
                        }
                    }
                }
                .overlay {
                    if loading { ProgressView() } else if items.isEmpty { ContentUnavailableView("Nothing found", systemImage: "questionmark.folder", description: Text("Connect to your Mac to list its \(title.lowercased())s.")) }
                }
                .searchable(text: $search)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showing = false } } }
            }
            .task {
                loading = true
                items = await model.query(kind)?.items ?? []
                loading = false
                if kind == .installedApps { model.images.request(items.map(\.id), via: model.link) }
            }
        }
    }

    private var filtered: [QueryItem] {
        search.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(search) || ($0.subtitle ?? "").localizedCaseInsensitiveContains(search) }
    }
}

// MARK: - Macros

struct MacroEditor: View {
    @Binding var steps: [MacroStep]
    @Environment(AppModel.self) private var model
    @State private var recording = false

    var body: some View {
        List {
            Section {
                ForEach($steps) { $step in
                    NavigationLink {
                        CCForm {
                            ActionEditor(action: $step.action)
                            Section("Then wait") {
                                Stepper(String(format: "%.2f s", step.delay ?? 0), value: Binding(get: { step.delay ?? 0 }, set: { step.delay = $0 == 0 ? nil : $0 }), in: 0...10, step: 0.05)
                            }
                        }
                        .navigationTitle("Step")
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ActionKind(step.action).symbol).foregroundStyle(CC.accent).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(step.action.summary.isEmpty ? ActionKind(step.action).title : step.action.summary)
                                if let delay = step.delay, delay > 0 {
                                    Text(String(format: "then wait %.2f s", delay)).font(.caption).foregroundStyle(CC.text2)
                                }
                            }
                        }
                    }
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { steps.remove(atOffsets: $0) }
                Button("Add Step", systemImage: "plus") {
                    steps.append(MacroStep(.keyCombo(KeyCombo(keys: ["cmd"]))))
                }
            } footer: {
                Text("Steps run on the Mac in order. Mix keystrokes, apps, shortcuts, Focus, timers — anything.")
            }
            Section("Record on your Mac") {
                if recording {
                    HStack {
                        StatusDot(color: CC.red, size: 8, pulsing: true)
                        Text("Recording — type on your Mac's keyboard")
                        Spacer()
                        Text("\(model.recording?.steps.count ?? 0) keys").monospacedDigit().foregroundStyle(CC.text2)
                    }
                    Button("Stop and Add", systemImage: "stop.fill") {
                        model.link.send(.recordMacro(RecordMacro(.stop)))
                    }
                } else {
                    Button("Record Keystrokes", systemImage: "record.circle") {
                        model.recording = nil
                        recording = true
                        model.link.send(.recordMacro(RecordMacro(.start)))
                    }
                }
                if let error = model.recording?.error {
                    Text(error).font(.caption).foregroundStyle(CC.orange)
                }
            }
        }
        .navigationTitle("Macro")
        .toolbar { EditButton() }
        .onChange(of: model.recording) { _, recording in
            guard let recording, !recording.recording, self.recording else { return }
            self.recording = false
            steps += recording.steps
        }
    }
}

// MARK: - SF Symbols

struct SymbolPicker: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selection = name
                            dismiss()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 22))
                                .foregroundStyle(selection == name ? Color(hex: 0x0A0A0F) : CC.text)
                                .frame(width: 64, height: 56)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selection == name ? CC.accent : CC.elevated))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(name)
                    }
                }
                .padding(16)
            }
            .background(CC.bg)
            .searchable(text: $search, prompt: "Search symbols")
            .navigationTitle("Symbol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var filtered: [String] {
        search.isEmpty ? SymbolCatalog.all : SymbolCatalog.all.filter { $0.localizedCaseInsensitiveContains(search.replacingOccurrences(of: " ", with: ".")) }
    }
}

enum SymbolCatalog {
    static let all: [String] = [
        // Keyboard & editing
        "command", "option", "shift", "control", "escape", "delete.left", "return", "keyboard", "character.cursor.ibeam", "textformat", "bold", "italic", "underline", "strikethrough", "textformat.size", "textformat.size.larger", "textformat.size.smaller", "list.bullet", "list.number", "checklist", "checkmark.square", "quote.opening", "curlybraces", "chevron.left.forwardslash.chevron.right", "highlighter", "pencil", "square.and.pencil", "scissors", "doc.on.doc", "doc.on.clipboard", "arrow.uturn.backward", "arrow.uturn.forward", "magnifyingglass", "text.magnifyingglass",
        // Navigation
        "chevron.left", "chevron.right", "chevron.up", "chevron.down", "arrow.left", "arrow.right", "arrow.up", "arrow.down", "arrow.clockwise", "arrow.counterclockwise", "arrow.triangle.2.circlepath", "arrow.up.left.and.arrow.down.right", "house", "house.fill", "link", "safari", "globe",
        // Windows & apps
        "macwindow", "macwindow.badge.plus", "sidebar.left", "sidebar.right", "rectangle.split.2x1", "rectangle.split.3x1", "rectangle.lefthalf.filled", "rectangle.righthalf.filled", "rectangle.tophalf.filled", "rectangle.bottomhalf.filled", "rectangle.3.group", "square.grid.2x2", "square.grid.3x3", "square.on.square", "plus.square.on.square", "xmark.square", "display", "display.2", "laptopcomputer", "ipad.landscape", "iphone", "menubar.dock.rectangle", "app.badge",
        // Files
        "folder", "folder.fill", "folder.badge.plus", "doc", "doc.text", "doc.richtext", "doc.plaintext", "tray.and.arrow.down", "archivebox", "trash", "externaldrive", "icloud", "arrow.down.circle", "square.and.arrow.up", "paperclip",
        // Media
        "play.fill", "pause.fill", "playpause.fill", "stop.fill", "forward.fill", "backward.fill", "forward.end.fill", "backward.end.fill", "speaker.wave.2.fill", "speaker.slash.fill", "music.note", "headphones", "mic.fill", "mic.slash.fill", "video.fill", "video.slash.fill", "camera.viewfinder", "camera", "photo", "record.circle",
        // Development
        "hammer", "hammer.fill", "wrench.and.screwdriver", "terminal", "terminal.fill", "ladybug", "ant", "cpu", "memorychip", "server.rack", "network", "antenna.radiowaves.left.and.right", "arrow.triangle.branch", "arrow.triangle.merge", "checkmark.circle", "xmark.circle", "exclamationmark.triangle", "gear", "gearshape.2", "puzzlepiece", "shippingbox", "cube",
        // Communication
        "envelope", "envelope.fill", "paperplane.fill", "message", "bubble.left", "text.bubble", "phone.fill", "phone.down.fill", "hand.raised.fill", "person", "person.2", "at",
        // Time & focus
        "timer", "stopwatch", "clock", "alarm", "calendar", "calendar.badge.clock", "hourglass", "moon", "moon.fill", "moon.stars.fill", "sun.max", "sun.max.fill", "sunrise.fill", "sunset.fill", "bed.double.fill", "brain.head.profile", "graduationcap", "graduationcap.fill", "book", "book.fill", "books.vertical",
        // Finance
        "chart.line.uptrend.xyaxis", "chart.xyaxis.line", "chart.bar.fill", "chart.pie.fill", "dollarsign.circle", "eurosign.circle", "banknote", "creditcard", "briefcase", "briefcase.fill", "bitcoinsign.circle", "arrow.up.right", "arrow.down.right",
        // Health
        "heart", "heart.fill", "heart.circle", "bolt.heart", "figure.run", "figure.walk", "dumbbell", "drop.fill", "flame.fill", "leaf",
        // Home & misc
        "lightbulb", "lightbulb.fill", "lamp.desk", "fan", "powerplug", "bolt.fill", "sparkles", "star", "star.fill", "flag", "bookmark", "tag", "bell", "bell.slash", "lock.fill", "lock.open", "key", "eye", "eye.slash", "wand.and.stars", "paintbrush", "cup.and.saucer.fill", "fork.knife", "car.fill", "airplane", "location.fill", "map", "cloud.sun", "cloud.rain", "snowflake", "circle.lefthalf.filled", "square.dashed", "circle.dashed",
    ]
}
