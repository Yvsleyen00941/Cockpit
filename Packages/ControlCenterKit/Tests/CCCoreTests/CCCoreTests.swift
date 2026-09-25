import Foundation
import Testing
@testable import CCCore

private func json(_ value: some Encodable) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .secondsSince1970
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return try decoder.decode(T.self, from: Data(text.utf8))
}

@Suite("Wire format")
struct WireFormatTests {
    @Test("keyCombo matches the blueprint's JSON exactly")
    func blueprintKeyCombo() throws {
        let action = ButtonAction.keyCombo(KeyCombo(keys: ["cmd", "shift", "4"]))
        #expect(try json(action) == #"{"keys":["cmd","shift","4"],"type":"keyCombo"}"#)
        let decoded = try decode(ButtonAction.self, #"{ "type": "keyCombo", "keys": ["cmd", "shift", "4"] }"#)
        #expect(decoded == action)
    }

    @Test("Every action type round-trips")
    func actionsRoundTrip() throws {
        let actions: [ButtonAction] = [
            .keyCombo(KeyCombo("cmd+t")),
            .text(TextInput(text: "git status", submit: true)),
            .appleScript("tell application \"Safari\" to activate"),
            .shell(ShellCommand(command: "ls", cwd: "~/Developer", timeout: 10, showOutput: true)),
            .shortcut(ShortcutRun(name: "Focus: Deep Work")),
            .openApp(AppRef(bundleID: "com.apple.Safari", name: "Safari")),
            .openURL(URLRef(url: "https://github.com", bundleID: "com.apple.Safari")),
            .openPath("~/Downloads"),
            .media(.playPause),
            .system(.missionControl),
            .window(.leftHalf),
            .audio(AudioCommand(.setOutputVolume, value: 0.5)),
            .call(.toggleMute),
            .bot(.closeAll),
            .focus(FocusCommand(.on, name: "Deep Work")),
            .timer(.start(.pomodoro, minutes: 25, focus: true)),
            .git(GitCommand(.commitAll, message: "wip")),
            .navigate("bot"),
            .scene("startDay"),
            .macro([MacroStep(.keyCombo(.cmd("p")), delay: 0.3, id: "a"), MacroStep(.text(TextInput(text: "x")), id: "b")]),
            .clipboard(ClipboardCommand(.setText, text: "hi")),
            .daily(DailyCommand(.setPriority, index: 0, text: "Ship it")),
            .app(AppControl(.quit, bundleID: "com.spotify.client")),
            .integration(IntegrationCommand(.whoop, .connect)),
            .none,
        ]
        for action in actions {
            let data = try JSONEncoder().encode(action)
            let back = try JSONDecoder().decode(ButtonAction.self, from: data)
            #expect(back == action, "round trip failed for \(action.typeName)")
        }
    }

    @Test("Unknown action types survive instead of breaking the workspace")
    func unknownAction() throws {
        let decoded = try decode(ButtonAction.self, #"{"type":"teleport","to":"mars"}"#)
        #expect(decoded == .unsupported("teleport"))
    }

    @Test("MCCMessage envelope")
    func envelope() throws {
        let message = MCCMessage(.buttonTap(ButtonTap(action: .media(.next), buttonID: "k1")), id: 7)
        let text = try json(message)
        #expect(text.contains(#""type":"buttonTap""#))
        #expect(text.contains(#""id":7"#))
        let back = try decode(MCCMessage.self, text)
        guard case .buttonTap(let tap) = back.body else { Issue.record("wrong body"); return }
        #expect(tap.action == .media(.next))
        #expect(back.id == 7)
    }

    @Test("Live data update round-trips every channel")
    func liveData() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var sim = BotSimulation(now: now, seed: 1)
        _ = sim.step(to: now.addingTimeInterval(600))
        let values: [ChannelValue] = [
            .context(DemoData.context(now: now)), .apps(DemoData.apps), .system(DemoData.system(now: now)),
            .media(DemoData.media(now: now)), .audio(DemoData.audio), .calendar(DemoData.calendar(now: now)),
            .focus(DemoData.focusOff), .bot(sim.state(now: now)), .botSeries(sim.pnlSeries), .botEvents(sim.eventLog),
            .whoop(DemoData.whoop(now: now)), .weather(DemoData.weather(now: now)), .timers(TimersState(timers: [])),
            .daily(DemoData.daily(now: now)), .portfolio(DemoData.portfolio(now: now)), .git(DemoData.git(now: now)),
            .helper(DemoData.helper(now: now)),
        ]
        #expect(Set(values.map(\.channel)) == Set(Channel.allCases))
        let message = MCCMessage(.liveDataUpdate(LiveDataUpdate(values: values, full: true)))
        let back = try decode(MCCMessage.self, try json(message))
        guard case .liveDataUpdate(let update) = back.body else { Issue.record("wrong body"); return }
        var a = LiveState()
        var b = LiveState()
        values.forEach { a.apply($0) }
        update.values.forEach { b.apply($0) }
        #expect(a == b)
    }

    @Test("Applying an identical value reports no change")
    func diffing() {
        var state = LiveState()
        let first = state.apply(.audio(DemoData.audio))
        let second = state.apply(.audio(DemoData.audio))
        #expect(first)
        #expect(!second)
    }
}

@Suite("Keys")
struct KeyTests {
    @Test func parsing() {
        #expect(KeyCombo("cmd+shift+4").keys == ["cmd", "shift", "4"])
        #expect(KeyCombo("⇧⌘4").display == "⇧⌘4")
        #expect(KeyCombo("ctrl+cmd+q").display == "⌃⌘Q")
        #expect(KeyCombo("cmd+opt+return").display == "⌥⌘↩")
        #expect(KeyCombo("cmd++").key == "+")
        #expect(KeyCombo("cmd+\\").key == "\\")
        #expect(KeyCombo("f6").namedKey == .f6)
        #expect(KeyCombo("Command Shift T").keys == ["cmd", "shift", "t"])
    }

    @Test func namedKeyCodes() {
        #expect(NamedKey.return.virtualKeyCode == 36)
        #expect(NamedKey.escape.virtualKeyCode == 53)
        #expect(NamedKey(token: "esc") == .escape)
        #expect(NamedKey(token: "backspace") == .delete)
    }

    @Test func inputPrompt() {
        let search = ButtonAction.openURL(URLRef(url: "https://www.google.com/search?q={{input}}"))
        #expect(search.promptsForInput)
        #expect(search.fillingInput("swift charts") == .openURL(URLRef(url: "https://www.google.com/search?q=swift%20charts")))
        let commit = ButtonAction.text(TextInput(text: "git commit -m \"{{input}}\"", submit: true))
        #expect(commit.fillingInput("fix") == .text(TextInput(text: "git commit -m \"fix\"", submit: true)))
        #expect(!ButtonAction.media(.next).promptsForInput)
    }
}

@Suite("Workspace")
struct WorkspaceTests {
    @Test("Default workspace round-trips")
    func roundTrip() throws {
        let workspace = DefaultWorkspace.make()
        let back = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(workspace))
        #expect(back == workspace)
    }

    @Test("Hand-edited JSON with missing keys still decodes")
    func tolerant() throws {
        let text = #"{"pages":[{"id":"p","tiles":[{"id":"t","cols":4,"rows":3,"content":{"kind":"keys","group":{"keys":[{"label":"Hi","action":{"type":"media","command":"next"}}]}}}]}]}"#
        let workspace = try decode(Workspace.self, text)
        #expect(workspace.pages.first?.title == "Page")
        #expect(workspace.strip == .standard)
        #expect(workspace.preferences.pomodoroMinutes == 25)
    }

    @Test("Every built-in page fills the 12 × 12 landscape grid exactly")
    func pagesFillGrid() {
        for page in DefaultWorkspace.make().pages {
            let placements = GridPacker.pack(page.tiles)
            #expect(GridPacker.height(of: placements) == 12, "\(page.id) packs to \(GridPacker.height(of: placements)) rows")
            let area = placements.reduce(0) { $0 + $1.cols * $1.rows }
            #expect(area == 144, "\(page.id) leaves holes (\(area)/144 cells)")
        }
    }

    @Test("Home is four quadrants")
    func homeQuadrants() throws {
        let home = try #require(DefaultWorkspace.make().page("home"))
        let spots = GridPacker.pack(home.tiles).map { [$0.col, $0.row] }
        #expect(spots == [[0, 0], [6, 0], [0, 6], [6, 6]])
    }

    @Test("Every rule points at a page that exists")
    func rulesResolve() {
        let workspace = DefaultWorkspace.make()
        let pages = Set(workspace.pages.map(\.id))
        for rule in workspace.rules { #expect(pages.contains(rule.page), "\(rule.id) → \(rule.page)") }
        for scene in workspace.scenes { #expect(scene.page.map(pages.contains) ?? true) }
    }

    @Test func densePacking() {
        let placements = GridPacker.pack([(id: "a", cols: 8, rows: 2), (id: "b", cols: 6, rows: 1), (id: "c", cols: 4, rows: 1)], columns: 12)
        // "c" back-fills the hole next to "a".
        #expect(placements.first { $0.id == "c" }.map { [$0.col, $0.row] } == [8, 0])
    }
}

@Suite("Context engine")
struct ContextEngineTests {
    let workspace = DefaultWorkspace.make()
    let noon: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    func input(_ bundleID: String, url: String? = nil, daily: DailyState? = nil, focus: FocusInfo? = nil, calendar: CalendarState? = nil, audio: AudioState? = nil, at date: Date? = nil) -> ContextInput {
        ContextInput(context: ActiveContext(bundleID: bundleID, appName: bundleID, url: url), focus: focus, calendar: calendar, daily: daily, timers: nil, audio: audio, now: date ?? noon, cal: Calendar(identifier: .gregorian))
    }

    @Test func appMappings() {
        #expect(ContextEngine.resolve(workspace, input(Bundles.safari)).pageID == "app.safari")
        #expect(ContextEngine.resolve(workspace, input(Bundles.xcode)).pageID == "app.xcode")
        #expect(ContextEngine.resolve(workspace, input(Bundles.iterm)).pageID == "app.terminal")
        #expect(ContextEngine.resolve(workspace, input(Bundles.preview)).pageID == "study")
        #expect(ContextEngine.resolve(workspace, input("com.unknown.app")).pageID == "home")
    }

    @Test("Safari becomes the Study page while Study mode is on")
    func studyModeWinsOverSafari() {
        var daily = DailyState(date: "2026-09-25")
        daily.studyMode = true
        #expect(ContextEngine.resolve(workspace, input(Bundles.safari, daily: daily)).pageID == "study")
    }

    @Test("A lecture on the calendar switches Safari to Study")
    func lectureOnCalendar() {
        let lecture = CalendarEvent(id: "l", title: "Les Statistiek", start: noon.addingTimeInterval(-600), end: noon.addingTimeInterval(3000), calendarName: "Uni", colorHex: "#fff")
        let calendar = CalendarState(access: .granted, events: [lecture])
        #expect(ContextEngine.resolve(workspace, input(Bundles.safari, calendar: calendar)).pageID == "study")
    }

    @Test("Morning Brief only inside the window, until the day starts")
    func morning() {
        var daily = DailyState(date: "2026-09-25")
        daily.briefPending = true
        let seven = noon.addingTimeInterval(-5 * 3600)
        #expect(ContextEngine.resolve(workspace, input(Bundles.xcode, daily: daily, at: seven)).pageID == "brief")
        #expect(ContextEngine.resolve(workspace, input(Bundles.xcode, daily: daily)).pageID == "app.xcode")
        daily.dayStarted = true
        #expect(ContextEngine.resolve(workspace, input(Bundles.xcode, daily: daily, at: seven)).pageID == "app.xcode")
    }

    @Test func meetingAndBot() {
        #expect(ContextEngine.resolve(workspace, input("us.zoom.xos")).pageID == "meeting")
        #expect(ContextEngine.resolve(workspace, input(Bundles.chrome, url: "https://meet.google.com/abc")).pageID == "meeting")
        #expect(ContextEngine.resolve(workspace, input(Bundles.safari, url: "http://localhost:8000/dashboard")).pageID == "bot")
    }

    @Test func wholeWords() {
        #expect(ContextEngine.containsAnyWord("Les Statistiek", ["les"]))
        #expect(!ContextEngine.containsAnyWord("Charles & sales files", ["les"]))
        #expect(ContextEngine.containsAnyWord("Hoorcollege Économie", ["economie", "hoorcollege"]))
    }

    @Test func timeWindows() {
        let rule = RuleMatch(timeStart: "22:00", timeEnd: "06:00")
        let late = noon.addingTimeInterval(11 * 3600)
        #expect(ContextEngine.matches(rule, input("x", at: late), []))
        #expect(!ContextEngine.matches(rule, input("x"), []))
    }
}

@Suite("Helpers")
struct HelperTests {
    @Test func jsonPath() throws {
        let object = try JSONSerialization.jsonObject(with: Data(#"{"stats":{"daily":{"pnl":"1,234.5"}},"positions":[{"qty":2}],"ok":true,"ts":1790000000000}"#.utf8))
        #expect(JSONPath.double(at: "stats.daily.pnl", in: object) == 1234.5)
        #expect(JSONPath.double(at: "positions[0].qty", in: object) == 2)
        #expect(JSONPath.bool(at: "ok", in: object) == true)
        #expect(JSONPath.date(at: "ts", in: object) == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(JSONPath.value(at: "missing.path", in: object) == nil)
    }

    @Test func templates() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let text = TemplateEngine.expand("{{date:yyyy}} {{url}} {{nope}}", now: date, locale: Locale(identifier: "en_US_POSIX")) { $0 == "url" ? "https://x" : nil }
        #expect(text == "2026 https://x {{nope}}")
    }

    @Test func briefHeadlines() {
        #expect(BriefComposer.recoveryHeadline(DemoData.whoop(now: .now)).1 == .great)
        var low = DemoData.whoop(now: .now)
        low.recovery = 21
        #expect(BriefComposer.recoveryHeadline(low).1 == .careful)
        #expect(BriefComposer.recoveryHeadline(nil).1 == .neutral)
    }

    @Test func formatting() {
        #expect(Fmt.countdown(25 * 60) == "25:00")
        #expect(Fmt.countdown(3725) == "1:02:05")
        #expect(Fmt.hoursMinutes(7.7) == "7h 42m")
        #expect(Fmt.percent(0.0184) == "+1.84%")
        #expect(Fmt.percent(-0.5, fraction: false, decimals: 1) == "−0.5%")
    }
}

@Suite("Bot simulation")
struct SimulationTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func deterministic() {
        let a = BotSimulation(now: start, seed: 7)
        let b = BotSimulation(now: start, seed: 7)
        #expect(a.state(now: start) == b.state(now: start))
        #expect(!a.series.isEmpty)
    }

    @Test func pauseStopsTrading() {
        var sim = BotSimulation(now: start, seed: 3)
        _ = sim.pause(at: start)
        let before = sim.tradesToday
        let events = sim.step(to: start.addingTimeInterval(3600))
        #expect(events.isEmpty)
        #expect(sim.tradesToday == before)
        #expect(sim.state(now: start).status == .paused)
    }

    @Test func closeAllRealises() {
        var sim = BotSimulation(now: start, seed: 5)
        _ = sim.step(to: start.addingTimeInterval(1800))
        let pnl = sim.state(now: start).pnlToday
        _ = sim.closeAll(at: start.addingTimeInterval(1800))
        let after = sim.state(now: start)
        #expect(after.positions.isEmpty)
        #expect(abs(after.pnlToday - pnl) < 0.02)
    }
}
