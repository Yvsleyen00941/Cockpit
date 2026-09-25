import Foundation

/// Well-known bundle identifiers.
public enum Bundles {
    public static let safari = "com.apple.Safari"
    public static let chrome = "com.google.Chrome"
    public static let arc = "company.thebrowser.Browser"
    public static let xcode = "com.apple.dt.Xcode"
    public static let notion = "notion.id"
    public static let terminal = "com.apple.Terminal"
    public static let iterm = "com.googlecode.iterm2"
    public static let warp = "dev.warp.Warp-Stable"
    public static let ghostty = "com.mitchellh.ghostty"
    public static let finder = "com.apple.finder"
    public static let preview = "com.apple.Preview"
    public static let notes = "com.apple.Notes"
    public static let goodnotes = "com.goodnotesapp.x"
    public static let obsidian = "md.obsidian"
    public static let word = "com.microsoft.Word"
    public static let powerpoint = "com.microsoft.Powerpoint"
    public static let activityMonitor = "com.apple.ActivityMonitor"
    public static let mail = "com.apple.mail"
    public static let calendar = "com.apple.iCal"

    public static let terminals = [terminal, iterm, warp, ghostty]
    public static let studyApps = [preview, notes, goodnotes, obsidian]
}

/// The factory workspace: every screen in the blueprint, built from the same
/// primitives the user edits (tiles, keys, actions, rules, scenes).
public enum DefaultWorkspace {
    public static func make(preferences p: WorkspacePreferences = WorkspacePreferences()) -> Workspace {
        Workspace(
            pages: [
                home, brief, bot, study(p), meeting, mac, markets,
                safari, xcode, notion, terminal, finder(p),
            ],
            strip: .standard,
            rules: rules,
            scenes: scenes(p),
            preferences: p
        )
    }

    // MARK: Screen 1 — Home dashboard (four quadrants)

    static let home = Page(id: "home", title: "Home", symbol: "house.fill", tiles: [
        .widget(.botSummary, 6, 6),
        .widget(.whoopSummary, 6, 6),
        .widget(.focusSchedule, 6, 6),
        .widget(.systemSummary, 6, 6),
    ], pinnedToBar: true)

    // MARK: Screen 5 — Morning Brief

    static let brief = Page(id: "brief", title: "Brief", symbol: "sun.horizon.fill", tiles: [
        .widget(.greeting, 12, 2),
        .widget(.recoveryBrief, 4, 5),
        .widget(.weather, 4, 5),
        .widget(.botOvernight, 4, 5),
        .widget(.agenda, 6, 5),
        .widget(.priorities, 6, 3),
        .widget(.startDay, 6, 2),
    ], pinnedToBar: true)

    // MARK: Screen 2 — Trading bot dashboard

    static let bot = Page(id: "bot", title: "Bot", symbol: "chart.line.uptrend.xyaxis", tiles: [
        .widget(.botHealth, 12, 1),
        .widget(.botChart, 8, 6),
        .widget(.botActions, 4, 6),
        .widget(.botPositions, 7, 5),
        .widget(.botLog, 5, 5),
    ], pinnedToBar: true)

    // MARK: Screen 3 — Study / University mode

    static func study(_ p: WorkspacePreferences) -> Page {
        Page(id: "study", title: "Study", symbol: "book.fill", tiles: [
            .widget(.pomodoro, 7, 8),
            .widget(.nextEvent, 5, 3),
            .keys("Quick Launch", 5, 5, style: .row, id: "k.study-launch", [
                act("study.notion", "Open Notion", "doc.richtext", .openApp(AppRef(bundleID: Bundles.notion, name: "Notion"))),
                act("study.course", "Course Folder", "graduationcap.fill", .openPath(p.courseFolder), .blue),
                act("study.note", "New Note", "square.and.pencil", .macro([
                    MacroStep(.openApp(AppRef(bundleID: Bundles.notes, name: "Notes")), delay: 0.6),
                    MacroStep(.keyCombo(.cmd("n"))),
                ])),
            ]),
            .keys("Shortcuts", 7, 4, id: "k.study-shortcuts", [
                combo("study.shot", "Screenshot", "camera.viewfinder", "cmd+shift+4"),
                combo("study.highlight", "Highlight", "highlighter", "cmd+shift+h", .yellow),
                combo("study.copy", "Copy", "doc.on.doc", "cmd+c"),
                combo("study.paste", "Paste", "doc.on.clipboard", "cmd+v"),
                combo("study.undo", "Undo", "arrow.uturn.backward", "cmd+z"),
            ]),
            Tile(id: "t.study-appkeys", cols: 5, rows: 4, content: .appKeys(limit: 6)),
        ], pinnedToBar: true)
    }

    // MARK: Meeting (extra)

    static let meeting = Page(id: "meeting", title: "Meeting", symbol: "video.fill", tiles: [
        .widget(.meeting, 8, 5),
        .widget(.micControl, 4, 5),
        .keys("Call", 8, 4, id: "k.call", [
            act("call.mute", "Mute", "mic.slash.fill", .call(.toggleMute)),
            act("call.video", "Camera", "video.slash.fill", .call(.toggleVideo)),
            act("call.hand", "Raise Hand", "hand.raised.fill", .call(.raiseHand), .yellow),
            act("call.share", "Share", "rectangle.on.rectangle", .call(.shareScreen), .blue),
            act("call.leave", "Leave", "phone.down.fill", .call(.leave), .red, confirm: .hold),
        ]),
        .widget(.volume, 4, 4),
        .widget(.nextEvent, 6, 3),
        .keys("Tools", 6, 3, id: "k.meeting-tools", [
            act("meet.notes", "Notes", "note.text", .openApp(AppRef(bundleID: Bundles.notes, name: "Notes"))),
            combo("meet.shot", "Screenshot", "camera.viewfinder", "cmd+shift+4"),
            act("meet.dnd", "Focus", "moon.fill", .focus(FocusCommand(.toggle)), .indigo),
        ]),
    ])

    // MARK: Mac (system monitor, window management, app switcher)

    static let mac = Page(id: "mac", title: "Mac", symbol: "laptopcomputer", tiles: [
        .widget(.systemDetail, 8, 7),
        .widget(.processes, 4, 7),
        .widget(.appSwitcher, 6, 5),
        .keys("Windows", 6, 5, id: "k.windows", [
            window(.leftHalf), window(.rightHalf), window(.maximize), window(.center), window(.nextDisplay),
            window(.leftThird), window(.centerThird), window(.rightThird), window(.minimize), window(.fullScreen),
        ]),
    ], pinnedToBar: true)

    // MARK: Markets (PortTracker + bot)

    static let markets = Page(id: "markets", title: "Markets", symbol: "briefcase.fill", tiles: [
        .widget(.portfolio, 8, 7),
        .widget(.movers, 4, 7),
        .widget(.botSummary, 8, 5),
        .widget(.turbos, 4, 5),
    ], pinnedToBar: true)

    // MARK: Screen 4 — Contextual app layouts

    static let safari = Page(id: "app.safari", title: "Safari", symbol: "safari", appBundleID: Bundles.safari, tiles: [
        .keys("Tabs", 6, 4, id: "k.safari-tabs", [
            combo("sf.new", "New Tab", "plus.square.on.square", "cmd+t", .blue),
            combo("sf.close", "Close", "xmark.square", "cmd+w"),
            combo("sf.reopen", "Reopen", "arrow.uturn.backward.square", "cmd+shift+t"),
            act("sf.dup", "Duplicate", "square.on.square", .appleScript(duplicateSafariTab), caption: "AppleScript"),
            combo("sf.prev", "Prev Tab", "arrow.left.square", "cmd+shift+["),
            combo("sf.next", "Next Tab", "arrow.right.square", "cmd+shift+]"),
        ]),
        .keys("Navigate", 6, 4, id: "k.safari-nav", [
            combo("sf.back", "Back", "chevron.left", "cmd+["),
            combo("sf.fwd", "Forward", "chevron.right", "cmd+]"),
            combo("sf.reload", "Reload", "arrow.clockwise", "cmd+r"),
            combo("sf.hard", "Hard Reload", "arrow.triangle.2.circlepath", "cmd+opt+r", .orange),
            combo("sf.address", "Address", "link", "cmd+l"),
            combo("sf.find", "Find", "magnifyingglass", "cmd+f"),
        ]),
        .keys("Develop", 4, 4, id: "k.safari-dev", [
            combo("sf.reader", "Reader", "doc.plaintext", "cmd+shift+r"),
            combo("sf.inspector", "Inspector", "wrench.and.screwdriver", "cmd+opt+i", .purple),
            combo("sf.source", "Source", "chevron.left.forwardslash.chevron.right", "cmd+opt+u"),
            combo("sf.responsive", "Responsive", "ipad.and.iphone", "ctrl+cmd+r"),
        ]),
        .widget(.appContext, 8, 4),
        .keys("Favorites", 12, 4, style: .row, id: "k.safari-favorites", [
            link("fav.github", "GitHub", "chevron.left.forwardslash.chevron.right", "https://github.com"),
            link("fav.notion", "Notion", "doc.richtext", "https://www.notion.so"),
            link("fav.blackboard", "Blackboard", "graduationcap", "https://blackboard.uantwerpen.be"),
            link("fav.outlook", "Outlook", "envelope", "https://outlook.office.com/mail"),
            link("fav.claude", "Claude", "sparkles", "https://claude.ai"),
            link("fav.tradingview", "TradingView", "chart.xyaxis.line", "https://www.tradingview.com/chart"),
            link("fav.youtube", "YouTube", "play.rectangle", "https://www.youtube.com"),
            link("fav.search", "Search…", "magnifyingglass", "https://www.google.com/search?q={{input}}"),
        ]),
    ])

    static let xcode = Page(id: "app.xcode", title: "Xcode", symbol: "hammer.fill", appBundleID: Bundles.xcode, tiles: [
        .keys("Build", 6, 4, id: "k.xcode-build", [
            combo("xc.build", "Build", "hammer.fill", "cmd+b", .blue),
            combo("xc.run", "Run", "play.fill", "cmd+r", .green),
            combo("xc.stop", "Stop", "stop.fill", "cmd+.", .red),
            combo("xc.clean", "Clean", "sparkles", "cmd+shift+k"),
            combo("xc.test", "Test", "checkmark.diamond", "cmd+u"),
            combo("xc.preview", "Preview", "arrow.clockwise.circle", "cmd+opt+p"),
        ]),
        .keys("Debug", 6, 4, id: "k.xcode-debug", [
            combo("xc.bp", "Breakpoint", "arrowshape.right.fill", "cmd+\\", .blue),
            combo("xc.over", "Step Over", "arrow.right.to.line", "f6"),
            combo("xc.into", "Step Into", "arrow.down.to.line", "f7"),
            combo("xc.out", "Step Out", "arrow.up.to.line", "f8"),
            combo("xc.continue", "Continue", "play.circle", "ctrl+cmd+y", .green),
            combo("xc.debugarea", "Debug Area", "rectangle.bottomthird.inset.filled", "cmd+shift+y"),
        ]),
        .keys("View", 6, 4, id: "k.xcode-view", [
            combo("xc.nav", "Navigator", "sidebar.left", "cmd+0"),
            combo("xc.insp", "Inspector", "sidebar.right", "cmd+opt+0"),
            combo("xc.console", "Console", "terminal", "cmd+shift+c"),
            combo("xc.open", "Quick Open", "magnifyingglass", "cmd+shift+o"),
            combo("xc.canvas", "Canvas", "rectangle.split.2x1", "cmd+opt+return"),
            combo("xc.find", "Find in Project", "text.magnifyingglass", "cmd+shift+f"),
        ]),
        .widget(.git, 6, 4),
        .keys("Git", 12, 4, style: .row, id: "k.xcode-git", [
            act("xc.commit", "Commit…", "checkmark.circle", .git(GitCommand(.commitAll, message: "{{input}}")), .green),
            act("xc.push", "Push", "arrow.up.circle", .git(GitCommand(.push)), .blue),
            act("xc.pull", "Pull", "arrow.down.circle", .git(GitCommand(.pull))),
            act("xc.fetch", "Fetch", "arrow.triangle.2.circlepath", .git(GitCommand(.fetch))),
            act("xc.status", "Status", "list.bullet.clipboard", .git(GitCommand(.status))),
            act("xc.stash", "Stash", "tray.and.arrow.down", .git(GitCommand(.stash))),
            combo("xc.xcommit", "Xcode Commit", "arrow.triangle.branch", "cmd+opt+c"),
            combo("xc.blame", "Blame", "person.text.rectangle", "cmd+ctrl+shift+b"),
        ]),
    ])

    static let notion = Page(id: "app.notion", title: "Notion", symbol: "doc.richtext", appBundleID: Bundles.notion, tiles: [
        .keys("Page", 6, 4, id: "k.notion-page", [
            combo("no.new", "New Page", "square.and.pencil", "cmd+n", .blue),
            combo("no.search", "Search", "magnifyingglass", "cmd+p"),
            act("no.today", "Today", "sun.max", .macro([
                MacroStep(.keyCombo(.cmd("p")), delay: 0.4),
                MacroStep(.text(TextInput(text: "{{date:d MMMM yyyy}}")), delay: 0.7),
                MacroStep(.keyCombo(KeyCombo(keys: ["return"]))),
            ]), .orange, caption: "Daily note"),
            act("no.entry", "New Entry", "tablecells.badge.ellipsis", .openURL(URLRef(url: "https://www.notion.so/YOUR_DATABASE_ID", bundleID: Bundles.notion))),
            combo("no.back", "Back", "chevron.left", "cmd+["),
            combo("no.fwd", "Forward", "chevron.right", "cmd+]"),
        ]),
        .keys("Blocks", 6, 4, id: "k.notion-blocks", [
            combo("no.h1", "Heading 1", "textformat.size.larger", "cmd+opt+1"),
            combo("no.h2", "Heading 2", "textformat.size", "cmd+opt+2"),
            combo("no.h3", "Heading 3", "textformat.size.smaller", "cmd+opt+3"),
            combo("no.todo", "To-do", "checkmark.square", "cmd+opt+4"),
            combo("no.bullet", "Bullet", "list.bullet", "cmd+opt+5"),
            combo("no.toggle", "Toggle", "arrowtriangle.right.fill", "cmd+opt+7"),
        ]),
        .keys("Insert", 6, 4, id: "k.notion-insert", [
            act("no.callout", "Callout", "exclamationmark.bubble", .text(TextInput(text: "/callout", submit: true)), .yellow),
            combo("no.code", "Code", "curlybraces", "cmd+opt+8"),
            act("no.divider", "Divider", "minus", .text(TextInput(text: "---"))),
            act("no.quote", "Quote", "quote.opening", .text(TextInput(text: "/quote", submit: true))),
            act("no.table", "Table", "tablecells", .text(TextInput(text: "/table", submit: true))),
            act("no.date", "Date", "calendar", .text(TextInput(text: "@today", submit: true))),
        ]),
        .keys("Format", 6, 4, id: "k.notion-format", [
            combo("no.bold", "Bold", "bold", "cmd+b"),
            combo("no.italic", "Italic", "italic", "cmd+i"),
            combo("no.underline", "Underline", "underline", "cmd+u"),
            combo("no.strike", "Strike", "strikethrough", "cmd+shift+s"),
            combo("no.link", "Link", "link", "cmd+k"),
            combo("no.comment", "Comment", "text.bubble", "cmd+shift+m"),
        ]),
        .keys("Workspace", 12, 4, style: .row, id: "k.notion-workspace", [
            combo("no.sidebar", "Toggle Sidebar", "sidebar.left", "cmd+\\"),
            combo("no.dark", "Dark Mode", "circle.lefthalf.filled", "cmd+shift+l"),
            combo("no.copylink", "Copy Page Link", "link.badge.plus", "cmd+l"),
            combo("no.dupe", "Duplicate", "plus.square.on.square", "cmd+d"),
            combo("no.move", "Move To…", "arrow.right.doc.on.clipboard", "cmd+shift+p"),
            combo("no.inline", "Inline Code", "chevron.left.forwardslash.chevron.right", "cmd+e"),
        ]),
    ])

    static let terminal = Page(id: "app.terminal", title: "Terminal", symbol: "terminal.fill", appBundleID: Bundles.terminal, tiles: [
        .keys("Git", 6, 5, style: .row, id: "k.term-git", [
            type("tm.status", "git status", "list.bullet.clipboard", "git status"),
            type("tm.add", "git add .", "plus.circle", "git add ."),
            type("tm.commit", "git commit…", "checkmark.circle", "git commit -m \"{{input}}\"", .green),
            type("tm.push", "git push", "arrow.up.circle", "git push", .blue),
            type("tm.pull", "git pull", "arrow.down.circle", "git pull"),
            type("tm.log", "git log", "clock.arrow.circlepath", "git log --oneline -15"),
        ]),
        .keys("Shell", 6, 5, style: .row, id: "k.term-shell", [
            type("tm.ls", "ls -la", "list.bullet", "ls -la"),
            type("tm.up", "cd ..", "arrow.up.left", "cd .."),
            type("tm.clear", "clear", "clear", "clear"),
            type("tm.pwd", "pwd", "location", "pwd"),
            combo("tm.int", "Interrupt", "stop.circle", "ctrl+c", .red),
            combo("tm.hist", "Previous", "arrow.up", "up"),
        ]),
        .keys("Bot Scripts", 6, 3, style: .row, id: "k.term-scripts", [
            act("tm.botstart", "Start bot", "play.circle.fill", .shell(ShellCommand(command: "./start.sh", cwd: "YOUR_BOT_DIRECTORY")), .green),
            act("tm.botstop", "Stop bot", "stop.circle.fill", .shell(ShellCommand(command: "./stop.sh", cwd: "YOUR_BOT_DIRECTORY")), .red, confirm: .dialog),
            type("tm.open", "Open in Finder", "folder", "open ."),
        ]),
        .widget(.git, 6, 3),
        .keys("Keys", 12, 4, id: "k.term-keys", [
            combo("tm.tab", "Tab", "arrow.right.to.line", "tab"),
            combo("tm.esc", "Esc", "escape", "escape"),
            combo("tm.ctrld", "EOF", "eject", "ctrl+d"),
            combo("tm.ctrlr", "History", "clock.arrow.circlepath", "ctrl+r"),
            combo("tm.ctrla", "Line Start", "arrow.left.to.line", "ctrl+a"),
            combo("tm.ctrle", "Line End", "arrow.right.to.line", "ctrl+e"),
            combo("tm.cmdk", "Clear", "trash", "cmd+k"),
            combo("tm.newtab", "New Tab", "plus.square.on.square", "cmd+t", .blue),
            combo("tm.closetab", "Close Tab", "xmark.square", "cmd+w"),
            combo("tm.split", "Split", "rectangle.split.2x1", "cmd+d"),
        ]),
    ])

    static func finder(_ p: WorkspacePreferences) -> Page {
        Page(id: "app.finder", title: "Finder", symbol: "folder.fill", appBundleID: Bundles.finder, tiles: [
            .keys("File", 6, 4, id: "k.finder-file", [
                combo("fd.newfolder", "New Folder", "folder.badge.plus", "cmd+shift+n", .blue),
                combo("fd.rename", "Rename", "character.cursor.ibeam", "return"),
                ButtonDef(id: "fd.trash", label: "Trash", symbol: "trash", color: .red, action: .keyCombo(KeyCombo("cmd+delete")), confirm: .dialog),
                combo("fd.dup", "Duplicate", "plus.square.on.square", "cmd+d"),
                combo("fd.info", "Get Info", "info.circle", "cmd+i"),
                combo("fd.look", "Quick Look", "eye", "space"),
            ]),
            .keys("Go", 6, 4, id: "k.finder-go", [
                combo("fd.downloads", "Downloads", "arrow.down.circle", "cmd+opt+l", .blue),
                combo("fd.desktop", "Desktop", "menubar.dock.rectangle", "cmd+shift+d"),
                act("fd.projects", "Projects", "hammer", .openPath(p.projectsFolder)),
                combo("fd.home", "Home", "house", "cmd+shift+h"),
                combo("fd.apps", "Applications", "square.grid.3x3", "cmd+shift+a"),
                combo("fd.icloud", "iCloud", "icloud", "cmd+shift+i"),
                combo("fd.airdrop", "AirDrop", "dot.radiowaves.left.and.right", "cmd+shift+r"),
                act("fd.uni", "UAntwerpen", "graduationcap", .openPath(p.courseFolder), .indigo),
            ]),
            .keys("View", 6, 4, id: "k.finder-view", [
                combo("fd.icons", "Icons", "square.grid.2x2", "cmd+1"),
                combo("fd.list", "List", "list.bullet", "cmd+2"),
                combo("fd.columns", "Columns", "rectangle.split.3x1", "cmd+3"),
                combo("fd.gallery", "Gallery", "rectangle.stack", "cmd+4"),
                combo("fd.hidden", "Hidden Files", "eye.slash", "cmd+shift+.", .orange),
                combo("fd.path", "Path Bar", "ellipsis.rectangle", "cmd+opt+p"),
            ]),
            .keys("Windows", 6, 4, id: "k.finder-windows", [
                combo("fd.newwin", "New Window", "macwindow.badge.plus", "cmd+n"),
                combo("fd.newtab", "New Tab", "plus.square.on.square", "cmd+t"),
                combo("fd.close", "Close", "xmark.square", "cmd+w"),
                combo("fd.preview", "Preview Pane", "sidebar.right", "cmd+shift+p"),
                combo("fd.sidebar", "Sidebar", "sidebar.left", "ctrl+cmd+s"),
                window(.leftHalf),
            ]),
            .widget(.appSwitcher, 12, 4),
        ])
    }

    // MARK: Context rules

    public static let rules: [ContextRule] = [
        ContextRule(id: "rule.brief", name: "Morning Brief", priority: 95, match: RuleMatch(modes: [Mode.morning]), page: "brief"),
        ContextRule(id: "rule.meeting", name: "In a call", priority: 90, match: RuleMatch(modes: [Mode.meeting]), page: "meeting"),
        ContextRule(id: "rule.bot", name: "Bot command center", priority: 85, match: RuleMatch(urlContains: ["localhost:8000", "127.0.0.1:8000"]), page: "bot"),
        ContextRule(id: "rule.study-mode", name: "Study mode", priority: 80, match: RuleMatch(bundleIDs: [Bundles.safari, Bundles.chrome, Bundles.arc, Bundles.notion, Bundles.word, Bundles.powerpoint] + Bundles.studyApps, modes: [Mode.study]), page: "study"),
        ContextRule(id: "map.study", name: "Preview, Notes, GoodNotes, Obsidian", priority: 60, match: RuleMatch(bundleIDs: Bundles.studyApps), page: "study"),
        .app([Bundles.safari], page: "app.safari", name: "Safari"),
        .app([Bundles.xcode], page: "app.xcode", name: "Xcode"),
        .app([Bundles.notion], page: "app.notion", name: "Notion"),
        .app(Bundles.terminals, page: "app.terminal", name: "Terminal, iTerm, Warp, Ghostty"),
        .app([Bundles.finder], page: "app.finder", name: "Finder"),
        .app([Bundles.activityMonitor], page: "mac", name: "Activity Monitor"),
    ]

    // MARK: Scenes

    static func scenes(_ p: WorkspacePreferences) -> [SceneDef] {
        [
            SceneDef(id: "startDay", name: "Start the Day", symbol: "sunrise.fill", color: .orange, steps: [
                MacroStep(.daily(DailyCommand(.startDay))),
                MacroStep(.focus(FocusCommand(.on, name: p.focusName)), delay: 0.3),
            ] + p.morningApps.map { MacroStep(.openApp(AppRef(bundleID: $0)), delay: 0.4) } + [
                MacroStep(.timer(TimerCommand(.start, preset: TimerPreset(kind: .deepWork, minutes: p.deepWorkMinutes, label: "Deep Work", focus: false)))),
            ], page: "home"),
            SceneDef(id: "lecture", name: "Lecture Mode", symbol: "graduationcap.fill", color: .blue, steps: [
                MacroStep(.daily(DailyCommand(.setStudyMode, enabled: true))),
                MacroStep(.focus(FocusCommand(.on, name: p.studyFocusName)), delay: 0.3),
                MacroStep(.openApp(AppRef(bundleID: Bundles.notion, name: "Notion")), delay: 0.4),
                MacroStep(.openPath(p.courseFolder)),
            ], page: "study"),
            SceneDef(id: "trading", name: "Trading Session", symbol: "chart.line.uptrend.xyaxis", color: .green, steps: [
                MacroStep(.bot(.refresh)),
            ], page: "bot"),
            SceneDef(id: "endDay", name: "End the Day", symbol: "moon.stars.fill", color: .indigo, steps: [
                MacroStep(.timer(TimerCommand(.stop))),
                MacroStep(.focus(FocusCommand(.off))),
                MacroStep(.daily(DailyCommand(.setStudyMode, enabled: false))),
            ], page: "home"),
        ]
    }

    // MARK: Builders

    static func combo(_ id: String, _ label: String, _ symbol: String, _ spec: String, _ color: KeyColor = .neutral) -> ButtonDef {
        ButtonDef(id: id, label: label, symbol: symbol, color: color, action: .keyCombo(KeyCombo(spec)))
    }

    static func act(_ id: String, _ label: String, _ symbol: String, _ action: ButtonAction, _ color: KeyColor = .neutral, confirm: ConfirmMode = .none, caption: String? = nil) -> ButtonDef {
        ButtonDef(id: id, label: label, symbol: symbol, color: color, action: action, confirm: confirm, caption: caption)
    }

    static func type(_ id: String, _ label: String, _ symbol: String, _ text: String, _ color: KeyColor = .neutral) -> ButtonDef {
        ButtonDef(id: id, label: label, symbol: symbol, color: color, action: .text(TextInput(text: text, submit: true)), caption: "")
    }

    static func link(_ id: String, _ label: String, _ symbol: String, _ url: String) -> ButtonDef {
        ButtonDef(id: id, label: label, symbol: symbol, action: .openURL(URLRef(url: url, bundleID: Bundles.safari)))
    }

    static func window(_ command: WindowCommand) -> ButtonDef {
        ButtonDef(id: "win.\(command.rawValue)", label: command.title, symbol: command.symbol, action: .window(command), caption: "")
    }

    static let duplicateSafariTab = """
    tell application "Safari"
        tell front window
            set theURL to URL of current tab
            set newTab to make new tab with properties {URL:theURL}
            set current tab to newTab
        end tell
    end tell
    """
}
