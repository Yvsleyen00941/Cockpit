import Foundation

// MARK: - Workspace

/// The whole user-configurable surface in one document: pages, the bottom
/// strip, context rules, scenes and preferences. It lives on the Mac
/// (`~/Library/Application Support/ControlCenter/workspace.json`), is pushed to
/// every client, and is what "Export layout as JSON" exports. Secrets never
/// live here.
public struct Workspace: Codable, Hashable, Sendable {
    public static let currentSchema = 1

    public var schema: Int
    public var revision: Int
    public var pages: [Page]
    public var strip: StripConfig
    public var rules: [ContextRule]
    public var scenes: [SceneDef]
    public var preferences: WorkspacePreferences

    public init(schema: Int = Workspace.currentSchema, revision: Int = 1, pages: [Page], strip: StripConfig, rules: [ContextRule], scenes: [SceneDef], preferences: WorkspacePreferences) {
        self.schema = schema
        self.revision = revision
        self.pages = pages
        self.strip = strip
        self.rules = rules
        self.scenes = scenes
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey { case schema, revision, pages, strip, rules, scenes, preferences }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.value(.schema, default: Workspace.currentSchema)
        revision = try c.value(.revision, default: 1)
        pages = try c.value(.pages, default: [])
        strip = try c.value(.strip, default: StripConfig.standard)
        rules = try c.value(.rules, default: [])
        scenes = try c.value(.scenes, default: [])
        preferences = try c.value(.preferences, default: WorkspacePreferences())
    }

    public func page(_ id: String) -> Page? { pages.first { $0.id == id } }

    public func scene(_ id: String) -> SceneDef? { scenes.first { $0.id == id } }

    public mutating func updatePage(_ page: Page) {
        if let index = pages.firstIndex(where: { $0.id == page.id }) {
            pages[index] = page
        } else {
            pages.append(page)
        }
    }

    /// All keys anywhere in the workspace (for Siri/Shortcuts entity queries).
    public var allButtons: [ButtonDef] {
        var result: [ButtonDef] = []
        for page in pages {
            for tile in page.tiles {
                if case .keys(let group) = tile.content { result += group.keys }
            }
        }
        return result + strip.keys
    }

    /// The page an app maps to through a plain bundle-ID rule (the "App
    /// mappings" list in Settings).
    public func mappedPage(for bundleID: String) -> String? {
        rules
            .filter { $0.enabled && $0.match.isSimpleAppMapping && $0.match.bundleIDs.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) }
            .max { $0.priority < $1.priority }?
            .page
    }

    /// The keys that best represent an app — used by "app keys" tiles.
    public func keys(forApp bundleID: String) -> [ButtonDef] {
        guard let pageID = mappedPage(for: bundleID), let page = page(pageID) else { return [] }
        return page.tiles.flatMap { tile -> [ButtonDef] in
            if case .keys(let group) = tile.content { return group.keys }
            return []
        }
    }
}

// MARK: - Page & tiles

public struct Page: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var symbol: String
    /// For app pages: the app whose icon represents the page.
    public var appBundleID: String?
    public var tiles: [Tile]
    /// Shown as a tab in the top bar.
    public var pinnedToBar: Bool

    public init(id: String, title: String, symbol: String, appBundleID: String? = nil, tiles: [Tile], pinnedToBar: Bool = false) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.appBundleID = appBundleID
        self.tiles = tiles
        self.pinnedToBar = pinnedToBar
    }

    enum CodingKeys: String, CodingKey { case id, title, symbol, appBundleID, tiles, pinnedToBar }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.value(.title, default: "Page")
        symbol = try c.value(.symbol, default: "square.grid.2x2")
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        tiles = try c.value(.tiles, default: [])
        pinnedToBar = try c.value(.pinnedToBar, default: false)
    }

    /// Channels the page's tiles need — what the client subscribes to.
    public var channels: Set<Channel> {
        tiles.reduce(into: Set<Channel>()) { $0.formUnion($1.content.channels) }
    }
}

/// A tile occupies `cols × rows` cells of a 12-column grid and is packed in
/// order (dense, top-left first) — the same model as the iOS Home Screen, so
/// rearranging is just reordering.
public struct Tile: Codable, Hashable, Sendable, Identifiable {
    public static let gridColumns = 12
    public static let gridRows = 12

    public var id: String
    public var cols: Int
    public var rows: Int
    public var content: TileContent

    public init(id: String = UUID().uuidString, cols: Int, rows: Int, content: TileContent) {
        self.id = id
        self.cols = min(max(cols, 1), Tile.gridColumns)
        self.rows = max(rows, 1)
        self.content = content
    }

    public static func widget(_ kind: WidgetKind, _ cols: Int? = nil, _ rows: Int? = nil, id: String? = nil) -> Tile {
        Tile(id: id ?? "w.\(kind.rawValue)", cols: cols ?? kind.defaultSize.cols, rows: rows ?? kind.defaultSize.rows, content: .widget(kind))
    }

    public static func keys(_ title: String?, _ cols: Int, _ rows: Int, style: KeyStyle = .standard, id: String? = nil, _ keys: [ButtonDef]) -> Tile {
        Tile(id: id ?? "k.\((title ?? "keys").lowercased().replacingOccurrences(of: " ", with: "-"))", cols: cols, rows: rows, content: .keys(KeyGroup(title: title, keys: keys, style: style)))
    }
}

public enum TileContent: Hashable, Sendable {
    case widget(WidgetKind)
    case keys(KeyGroup)
    /// The frontmost Mac app's own keys (from its mapped page), up to `limit`.
    case appKeys(limit: Int)
    case spacer

    public var channels: Set<Channel> {
        switch self {
        case .widget(let kind): kind.channels
        case .keys: []
        case .appKeys: [.context]
        case .spacer: []
        }
    }
}

extension TileContent: Codable {
    private enum Keys: String, CodingKey { case kind, widget, group, limit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "widget":
            let raw = try c.decode(String.self, forKey: .widget)
            self = WidgetKind(rawValue: raw).map(TileContent.widget) ?? .spacer
        case "keys": self = .keys(try c.decode(KeyGroup.self, forKey: .group))
        case "appKeys": self = .appKeys(limit: try c.value(.limit, default: 8))
        default: self = .spacer
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .widget(let kind):
            try c.encode("widget", forKey: .kind)
            try c.encode(kind.rawValue, forKey: .widget)
        case .keys(let group):
            try c.encode("keys", forKey: .kind)
            try c.encode(group, forKey: .group)
        case .appKeys(let limit):
            try c.encode("appKeys", forKey: .kind)
            try c.encode(limit, forKey: .limit)
        case .spacer:
            try c.encode("spacer", forKey: .kind)
        }
    }
}

public enum KeyStyle: String, Codable, Hashable, Sendable, CaseIterable {
    /// Square keys, SF Symbol above the label (72 × 72 pt minimum).
    case standard
    /// Full-width 80 pt action buttons with a bold label (PAUSE, RESUME, START).
    case large
    /// Horizontal pills — icon left, label right — for text-heavy keys (terminal commands, domains).
    case row

    public var title: String {
        switch self {
        case .standard: "Keys"
        case .large: "Large buttons"
        case .row: "Rows"
        }
    }
}

public struct KeyGroup: Codable, Hashable, Sendable {
    public var title: String?
    public var keys: [ButtonDef]
    public var style: KeyStyle

    public init(title: String?, keys: [ButtonDef], style: KeyStyle = .standard) {
        self.title = title
        self.keys = keys
        self.style = style
    }

    enum CodingKeys: String, CodingKey { case title, keys, style }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        keys = try c.value(.keys, default: [])
        style = try c.value(.style, default: .standard)
    }
}

public enum KeyColor: String, Codable, Hashable, Sendable, CaseIterable {
    case neutral, blue, orange, green, red, yellow, purple, pink, teal, indigo

    public var title: String { rawValue.capitalized }
}

public enum ConfirmMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Fires on tap.
    case none
    /// Tap opens a confirmation dialog.
    case dialog
    /// Press and hold (the key fills and turns red), then confirm.
    case hold
}

public struct ButtonDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var symbol: String?
    public var color: KeyColor
    public var action: ButtonAction
    public var confirm: ConfirmMode
    /// Overrides the automatic caption (the shortcut glyphs). Empty hides it.
    public var caption: String?
    /// Optional second action on long press.
    public var longPress: ButtonAction?

    public init(id: String = UUID().uuidString, label: String, symbol: String? = nil, color: KeyColor = .neutral, action: ButtonAction, confirm: ConfirmMode = .none, caption: String? = nil, longPress: ButtonAction? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.color = color
        self.action = action
        self.confirm = confirm
        self.caption = caption
        self.longPress = longPress
    }

    enum CodingKeys: String, CodingKey { case id, label, symbol, color, action, confirm, caption, longPress }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID().uuidString)
        label = try c.value(.label, default: "")
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        color = try c.value(.color, default: .neutral)
        action = try c.value(.action, default: .none)
        confirm = try c.value(.confirm, default: action.isDestructive ? .dialog : .none)
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        longPress = try c.decodeIfPresent(ButtonAction.self, forKey: .longPress)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        if color != .neutral { try c.encode(color, forKey: .color) }
        try c.encode(action, forKey: .action)
        if confirm != .none { try c.encode(confirm, forKey: .confirm) }
        try c.encodeIfPresent(caption, forKey: .caption)
        try c.encodeIfPresent(longPress, forKey: .longPress)
    }

    /// What is printed under the label.
    public var displayCaption: String {
        if let caption { return caption }
        if case .keyCombo(let combo) = action { return combo.display }
        return ""
    }
}

// MARK: - Bottom strip

public struct StripConfig: Codable, Hashable, Sendable {
    /// The four always-visible quick actions.
    public var keys: [ButtonDef]
    public var showsMic: Bool
    public var showsNowPlaying: Bool
    public var showsTimer: Bool
    public var showsVolume: Bool

    public init(keys: [ButtonDef], showsMic: Bool = true, showsNowPlaying: Bool = true, showsTimer: Bool = true, showsVolume: Bool = true) {
        self.keys = keys
        self.showsMic = showsMic
        self.showsNowPlaying = showsNowPlaying
        self.showsTimer = showsTimer
        self.showsVolume = showsVolume
    }

    enum CodingKeys: String, CodingKey { case keys, showsMic, showsNowPlaying, showsTimer, showsVolume }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = try c.value(.keys, default: StripConfig.standard.keys)
        showsMic = try c.value(.showsMic, default: true)
        showsNowPlaying = try c.value(.showsNowPlaying, default: true)
        showsTimer = try c.value(.showsTimer, default: true)
        showsVolume = try c.value(.showsVolume, default: true)
    }

    public static let standard = StripConfig(keys: [
        ButtonDef(id: "strip.mission", label: "Mission", symbol: "rectangle.3.group", action: .system(.missionControl)),
        ButtonDef(id: "strip.shot", label: "Capture", symbol: "camera.viewfinder", action: .keyCombo(KeyCombo(keys: ["cmd", "shift", "4"]))),
        ButtonDef(id: "strip.play", label: "Play", symbol: "playpause.fill", action: .media(.playPause)),
        ButtonDef(id: "strip.lock", label: "Lock", symbol: "lock.fill", action: .system(.lockScreen)),
    ])
}

// MARK: - Context rules

/// "When this is true on the Mac, show that page." Evaluated on each client,
/// highest priority first; the first match wins.
public struct ContextRule: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var priority: Int
    public var match: RuleMatch
    public var page: String

    public init(id: String, name: String, enabled: Bool = true, priority: Int, match: RuleMatch, page: String) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.match = match
        self.page = page
    }

    enum CodingKeys: String, CodingKey { case id, name, enabled, priority, match, page }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID().uuidString)
        name = try c.value(.name, default: "Rule")
        enabled = try c.value(.enabled, default: true)
        priority = try c.value(.priority, default: 50)
        match = try c.value(.match, default: RuleMatch())
        page = try c.decode(String.self, forKey: .page)
    }

    /// An "App mapping": frontmost app → page.
    public static func app(_ bundleIDs: [String], page: String, name: String, priority: Int = 50) -> ContextRule {
        ContextRule(id: "map.\(page)", name: name, priority: priority, match: RuleMatch(bundleIDs: bundleIDs), page: page)
    }
}

/// Every non-empty condition must hold. Lists match if *any* entry matches,
/// except `modes`, which must *all* be active.
public struct RuleMatch: Codable, Hashable, Sendable {
    public var bundleIDs: [String]
    public var urlContains: [String]
    public var titleContains: [String]
    public var focusNames: [String]
    public var modes: [String]
    /// "HH:mm", inclusive start, exclusive end. May wrap past midnight.
    public var timeStart: String?
    public var timeEnd: String?
    /// 1 = Sunday … 7 = Saturday (Calendar.weekday).
    public var weekdays: [Int]

    public init(bundleIDs: [String] = [], urlContains: [String] = [], titleContains: [String] = [], focusNames: [String] = [], modes: [String] = [], timeStart: String? = nil, timeEnd: String? = nil, weekdays: [Int] = []) {
        self.bundleIDs = bundleIDs
        self.urlContains = urlContains
        self.titleContains = titleContains
        self.focusNames = focusNames
        self.modes = modes
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.weekdays = weekdays
    }

    enum CodingKeys: String, CodingKey { case bundleIDs, urlContains, titleContains, focusNames, modes, timeStart, timeEnd, weekdays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleIDs = try c.value(.bundleIDs, default: [])
        urlContains = try c.value(.urlContains, default: [])
        titleContains = try c.value(.titleContains, default: [])
        focusNames = try c.value(.focusNames, default: [])
        modes = try c.value(.modes, default: [])
        timeStart = try c.decodeIfPresent(String.self, forKey: .timeStart)
        timeEnd = try c.decodeIfPresent(String.self, forKey: .timeEnd)
        weekdays = try c.value(.weekdays, default: [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !bundleIDs.isEmpty { try c.encode(bundleIDs, forKey: .bundleIDs) }
        if !urlContains.isEmpty { try c.encode(urlContains, forKey: .urlContains) }
        if !titleContains.isEmpty { try c.encode(titleContains, forKey: .titleContains) }
        if !focusNames.isEmpty { try c.encode(focusNames, forKey: .focusNames) }
        if !modes.isEmpty { try c.encode(modes, forKey: .modes) }
        try c.encodeIfPresent(timeStart, forKey: .timeStart)
        try c.encodeIfPresent(timeEnd, forKey: .timeEnd)
        if !weekdays.isEmpty { try c.encode(weekdays, forKey: .weekdays) }
    }

    public var isSimpleAppMapping: Bool {
        !bundleIDs.isEmpty && urlContains.isEmpty && titleContains.isEmpty && focusNames.isEmpty && modes.isEmpty && timeStart == nil && timeEnd == nil && weekdays.isEmpty
    }
}

// MARK: - Scenes

/// A named routine: a macro plus (optionally) the page to land on.
/// "Start the day", "Lecture", "End the day"… Triggerable from keys, Siri,
/// widgets and Control Center.
public struct SceneDef: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var symbol: String
    public var color: KeyColor
    public var steps: [MacroStep]
    public var page: String?

    public init(id: String, name: String, symbol: String, color: KeyColor = .blue, steps: [MacroStep], page: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.color = color
        self.steps = steps
        self.page = page
    }
}

// MARK: - Preferences

public struct WorkspacePreferences: Codable, Hashable, Sendable {
    public var ownerName: String
    /// Morning Brief window, minutes after midnight.
    public var morningStart: Int
    public var morningEnd: Int
    public var pomodoroMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    public var sessionsPerCycle: Int
    public var autoStartBreaks: Bool
    public var deepWorkMinutes: Double
    /// Focus used by deep work, "Start the day" and Pomodoro "do not disturb".
    public var focusName: String
    /// Focus that means "studying".
    public var studyFocusName: String
    /// Whole words in a calendar title that mean "lecture".
    public var studyKeywords: [String]
    public var morningApps: [String]
    public var weatherLocation: String
    public var latitude: Double
    public var longitude: Double
    /// Show the ambient clock after the Mac has been idle this long.
    public var ambientAfterMinutes: Double
    /// Screen brightness in ambient mode (0…1).
    public var ambientBrightness: Double
    public var autoSwitch: Bool
    public var keyClicks: Bool
    public var courseFolder: String
    public var projectsFolder: String
    public var mirrorPrioritiesToReminders: Bool

    public init(ownerName: String = "Yorben", morningStart: Int = 6 * 60, morningEnd: Int = 10 * 60, pomodoroMinutes: Double = 25, shortBreakMinutes: Double = 5, longBreakMinutes: Double = 15, sessionsPerCycle: Int = 4, autoStartBreaks: Bool = false, deepWorkMinutes: Double = 90, focusName: String = "Deep Work", studyFocusName: String = "Study", studyKeywords: [String] = WorkspacePreferences.defaultStudyKeywords, morningApps: [String] = ["notion.id", "com.apple.Safari"], weatherLocation: String = "Wortegem", latitude: Double = 50.853, longitude: Double = 3.511, ambientAfterMinutes: Double = 5, ambientBrightness: Double = 0.2, autoSwitch: Bool = true, keyClicks: Bool = true, courseFolder: String = "~/OneDrive - Universiteit Antwerpen", projectsFolder: String = "~/Developer", mirrorPrioritiesToReminders: Bool = false) {
        self.ownerName = ownerName
        self.morningStart = morningStart
        self.morningEnd = morningEnd
        self.pomodoroMinutes = pomodoroMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.sessionsPerCycle = sessionsPerCycle
        self.autoStartBreaks = autoStartBreaks
        self.deepWorkMinutes = deepWorkMinutes
        self.focusName = focusName
        self.studyFocusName = studyFocusName
        self.studyKeywords = studyKeywords
        self.morningApps = morningApps
        self.weatherLocation = weatherLocation
        self.latitude = latitude
        self.longitude = longitude
        self.ambientAfterMinutes = ambientAfterMinutes
        self.ambientBrightness = ambientBrightness
        self.autoSwitch = autoSwitch
        self.keyClicks = keyClicks
        self.courseFolder = courseFolder
        self.projectsFolder = projectsFolder
        self.mirrorPrioritiesToReminders = mirrorPrioritiesToReminders
    }

    public static let defaultStudyKeywords = ["lecture", "les", "hoorcollege", "werkcollege", "college", "seminar", "tutorial", "practicum", "exam", "examen", "class"]

    enum CodingKeys: String, CodingKey {
        case ownerName, morningStart, morningEnd, pomodoroMinutes, shortBreakMinutes, longBreakMinutes, sessionsPerCycle, autoStartBreaks, deepWorkMinutes, focusName, studyFocusName, studyKeywords, morningApps, weatherLocation, latitude, longitude, ambientAfterMinutes, ambientBrightness, autoSwitch, keyClicks, courseFolder, projectsFolder, mirrorPrioritiesToReminders
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WorkspacePreferences()
        ownerName = try c.value(.ownerName, default: d.ownerName)
        morningStart = try c.value(.morningStart, default: d.morningStart)
        morningEnd = try c.value(.morningEnd, default: d.morningEnd)
        pomodoroMinutes = try c.value(.pomodoroMinutes, default: d.pomodoroMinutes)
        shortBreakMinutes = try c.value(.shortBreakMinutes, default: d.shortBreakMinutes)
        longBreakMinutes = try c.value(.longBreakMinutes, default: d.longBreakMinutes)
        sessionsPerCycle = try c.value(.sessionsPerCycle, default: d.sessionsPerCycle)
        autoStartBreaks = try c.value(.autoStartBreaks, default: d.autoStartBreaks)
        deepWorkMinutes = try c.value(.deepWorkMinutes, default: d.deepWorkMinutes)
        focusName = try c.value(.focusName, default: d.focusName)
        studyFocusName = try c.value(.studyFocusName, default: d.studyFocusName)
        studyKeywords = try c.value(.studyKeywords, default: d.studyKeywords)
        morningApps = try c.value(.morningApps, default: d.morningApps)
        weatherLocation = try c.value(.weatherLocation, default: d.weatherLocation)
        latitude = try c.value(.latitude, default: d.latitude)
        longitude = try c.value(.longitude, default: d.longitude)
        ambientAfterMinutes = try c.value(.ambientAfterMinutes, default: d.ambientAfterMinutes)
        ambientBrightness = try c.value(.ambientBrightness, default: d.ambientBrightness)
        autoSwitch = try c.value(.autoSwitch, default: d.autoSwitch)
        keyClicks = try c.value(.keyClicks, default: d.keyClicks)
        courseFolder = try c.value(.courseFolder, default: d.courseFolder)
        projectsFolder = try c.value(.projectsFolder, default: d.projectsFolder)
        mirrorPrioritiesToReminders = try c.value(.mirrorPrioritiesToReminders, default: d.mirrorPrioritiesToReminders)
    }

    public func minutes(for kind: TimerKind) -> Double {
        switch kind {
        case .pomodoro: pomodoroMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        case .deepWork: deepWorkMinutes
        case .custom: pomodoroMinutes
        }
    }
}

// MARK: - Decoding helper

extension KeyedDecodingContainer {
    /// `decodeIfPresent` with a default — hand-edited JSON may omit anything.
    func value<T: Decodable>(_ key: Key, default fallback: @autoclosure () -> T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback()
    }
}
