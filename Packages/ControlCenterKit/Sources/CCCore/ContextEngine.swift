import Foundation

/// Modes are derived states that rules can depend on. They are what lets one
/// app mean different things: Safari is the Safari page on a normal afternoon,
/// but part of the Study page while a lecture is on the calendar.
public enum Mode {
    /// First connection of the day inside the morning window, Brief not dismissed.
    public static let morning = "morning"
    /// Study mode toggled on, the study Focus active, or a lecture on the calendar right now.
    public static let study = "study"
    /// A Pomodoro or deep-work timer is running.
    public static let focusSession = "focusSession"
    /// A call: meeting app frontmost, or the mic is live during a calendar event.
    public static let meeting = "meeting"
    /// The Mac is locked, asleep or idle — the iPad can go ambient.
    public static let away = "away"
}

public struct ContextInput: Sendable {
    public var context: ActiveContext?
    public var focus: FocusInfo?
    public var calendar: CalendarState?
    public var daily: DailyState?
    public var timers: TimersState?
    public var audio: AudioState?
    public var now: Date
    public var cal: Calendar

    public init(context: ActiveContext?, focus: FocusInfo?, calendar: CalendarState?, daily: DailyState?, timers: TimersState?, audio: AudioState?, now: Date = .now, cal: Calendar = .current) {
        self.context = context
        self.focus = focus
        self.calendar = calendar
        self.daily = daily
        self.timers = timers
        self.audio = audio
        self.now = now
        self.cal = cal
    }

    public init(state: LiveState, now: Date = .now, cal: Calendar = .current) {
        self.init(context: state.context, focus: state.focus, calendar: state.calendar, daily: state.daily, timers: state.timers, audio: state.audio, now: now, cal: cal)
    }
}

public struct Resolution: Hashable, Sendable {
    public var pageID: String
    public var ruleID: String?
    public var reason: String
    public var modes: Set<String>

    public init(pageID: String, ruleID: String?, reason: String, modes: Set<String>) {
        self.pageID = pageID
        self.ruleID = ruleID
        self.reason = reason
        self.modes = modes
    }
}

public enum ContextEngine {
    public static let meetingApps: Set<String> = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "Cisco-Systems.Spark", "com.hnc.Discord", "com.apple.FaceTime"]
    public static let meetingHosts = ["meet.google.com", "teams.microsoft.com", "zoom.us/wc", "whereby.com"]

    // MARK: Modes

    public static func modes(_ input: ContextInput, preferences p: WorkspacePreferences) -> Set<String> {
        var modes = Set<String>()
        let minute = input.cal.component(.hour, from: input.now) * 60 + input.cal.component(.minute, from: input.now)

        if let daily = input.daily, daily.briefPending, !daily.dayStarted,
           minute >= p.morningStart, minute < p.morningEnd {
            modes.insert(Mode.morning)
        }

        let studyFocus = input.focus.map { $0.active && ($0.name ?? "").localizedCaseInsensitiveContains(p.studyFocusName) } ?? false
        let lecture = input.calendar?.ongoing(at: input.now).map { containsAnyWord($0.title, p.studyKeywords) } ?? false
        if (input.daily?.studyMode ?? false) || studyFocus || lecture {
            modes.insert(Mode.study)
        }

        if let timer = input.timers?.primary, timer.state == .running, !timer.kind.isBreak {
            modes.insert(Mode.focusSession)
        }

        if let context = input.context {
            let meetingFront = meetingApps.contains(context.bundleID) || meetingHosts.contains { (context.url ?? "").contains($0) }
            let liveDuringEvent = (input.audio?.micInUse ?? false) && input.calendar?.ongoing(at: input.now) != nil
            if meetingFront || liveDuringEvent { modes.insert(Mode.meeting) }
            if context.presence != .active { modes.insert(Mode.away) }
        }
        return modes
    }

    // MARK: Resolution

    public static func resolve(_ workspace: Workspace, _ input: ContextInput) -> Resolution {
        let modes = modes(input, preferences: workspace.preferences)
        let pageIDs = Set(workspace.pages.map(\.id))
        let rules = workspace.rules
            .filter { $0.enabled && pageIDs.contains($0.page) }
            .sorted { $0.priority > $1.priority }

        for rule in rules where matches(rule.match, input, modes) {
            return Resolution(pageID: rule.page, ruleID: rule.id, reason: rule.name, modes: modes)
        }
        let fallback = pageIDs.contains("home") ? "home" : (workspace.pages.first?.id ?? "home")
        return Resolution(pageID: fallback, ruleID: nil, reason: "Default", modes: modes)
    }

    public static func matches(_ m: RuleMatch, _ input: ContextInput, _ modes: Set<String>) -> Bool {
        if !m.bundleIDs.isEmpty {
            guard let id = input.context?.bundleID,
                  m.bundleIDs.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) else { return false }
        }
        if !m.urlContains.isEmpty {
            guard let url = input.context?.url?.lowercased(),
                  m.urlContains.contains(where: { url.contains($0.lowercased()) }) else { return false }
        }
        if !m.titleContains.isEmpty {
            guard let title = input.context?.windowTitle,
                  m.titleContains.contains(where: { title.localizedCaseInsensitiveContains($0) }) else { return false }
        }
        if !m.focusNames.isEmpty {
            guard let focus = input.focus, focus.active, let name = focus.name,
                  m.focusNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        }
        if !m.modes.isEmpty {
            guard m.modes.allSatisfy(modes.contains) else { return false }
        }
        if m.timeStart != nil || m.timeEnd != nil {
            let minute = input.cal.component(.hour, from: input.now) * 60 + input.cal.component(.minute, from: input.now)
            let start = m.timeStart.flatMap(parseClock) ?? 0
            let end = m.timeEnd.flatMap(parseClock) ?? 24 * 60
            let inside = start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
            guard inside else { return false }
        }
        if !m.weekdays.isEmpty {
            guard m.weekdays.contains(input.cal.component(.weekday, from: input.now)) else { return false }
        }
        return true
    }

    /// Stable key describing "where the user is" — a manual page choice holds
    /// until this changes (switching apps, a tab to another site, a mode flip).
    public static func contextKey(_ input: ContextInput, modes: Set<String>) -> String {
        let id = input.context?.bundleID ?? "-"
        let host = input.context?.urlHost ?? "-"
        return "\(id)|\(host)|\(modes.subtracting([Mode.away]).sorted().joined(separator: ","))"
    }

    // MARK: Helpers

    /// "HH:mm" → minutes after midnight.
    public static func parseClock(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }

    /// Whole-word, case- and diacritic-insensitive: "les" matches "Les
    /// Statistiek" but not "Charles" or "sales".
    public static func containsAnyWord(_ text: String, _ words: [String]) -> Bool {
        let tokens = Set(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty })
        return words.contains { word in
            let w = word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if w.contains(" ") { return text.localizedCaseInsensitiveContains(word) }
            return tokens.contains(w)
        }
    }
}
