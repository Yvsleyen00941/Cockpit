import Foundation

// MARK: - ButtonAction

/// The one action language. Every key on the iPad, every step of a macro, every
/// scene, Siri intent, widget button and Control Center control resolves to a
/// `ButtonAction`. The wire format is flat and type-tagged, exactly as in the
/// blueprint: `{ "type": "keyCombo", "keys": ["cmd", "shift", "4"] }`.
public indirect enum ButtonAction: Hashable, Sendable {
    /// A keyboard shortcut synthesised with CGEvent.
    case keyCombo(KeyCombo)
    /// Types text (templated) into the frontmost app, optionally pressing Return.
    case text(TextInput)
    /// Runs AppleScript source via NSAppleScript.
    case appleScript(String)
    /// Runs a shell command through a login zsh.
    case shell(ShellCommand)
    /// Runs an Apple Shortcut through the `shortcuts` CLI.
    case shortcut(ShortcutRun)
    /// Launches or activates a Mac app.
    case openApp(AppRef)
    /// Opens a URL on the Mac, optionally in a specific app.
    case openURL(URLRef)
    /// Opens a file or folder on the Mac.
    case openPath(String)
    /// System media keys — works with any player.
    case media(MediaCommand)
    /// Mission Control, lock screen, screenshots, brightness…
    case system(SystemCommand)
    /// Window tiling for the frontmost window (Accessibility API).
    case window(WindowCommand)
    /// Core Audio: mic mute, output volume.
    case audio(AudioCommand)
    /// Universal call controls — translated per meeting app on the Mac.
    case call(CallCommand)
    /// Trading bot commands.
    case bot(BotCommand)
    /// Focus modes.
    case focus(FocusCommand)
    /// Hub-owned timers (Pomodoro, deep work).
    case timer(TimerCommand)
    /// Git in the current (or a named) repository.
    case git(GitCommand)
    /// Client-side: show a page.
    case navigate(String)
    /// Runs a scene from the workspace.
    case scene(String)
    /// A sequence of actions with delays.
    case macro([MacroStep])
    /// Mac pasteboard.
    case clipboard(ClipboardCommand)
    /// Daily state: priorities, study mode, brief.
    case daily(DailyCommand)
    /// Activate / hide / quit a running app.
    case app(AppControl)
    /// Integration lifecycle: connect WHOOP, refresh the bot…
    case integration(IntegrationCommand)
    /// Does nothing (placeholder keys).
    case none
    /// A type this build does not understand (newer helper). Kept so that a
    /// workspace round-trips instead of failing to decode.
    case unsupported(String)
}

// MARK: - Payloads

public struct TextInput: Codable, Hashable, Sendable {
    public var text: String
    public var submit: Bool?

    public init(text: String, submit: Bool = false) {
        self.text = text
        self.submit = submit ? true : nil
    }

    public var pressesReturn: Bool { submit ?? false }
}

public struct ShellCommand: Codable, Hashable, Sendable {
    public var command: String
    public var cwd: String?
    public var timeout: Double?
    /// Send stdout back to the iPad as a sheet rather than a toast.
    public var showOutput: Bool?

    public init(command: String, cwd: String? = nil, timeout: Double? = nil, showOutput: Bool? = nil) {
        self.command = command
        self.cwd = cwd
        self.timeout = timeout
        self.showOutput = showOutput
    }
}

public struct ShortcutRun: Codable, Hashable, Sendable {
    public var name: String
    public var input: String?

    public init(name: String, input: String? = nil) {
        self.name = name
        self.input = input
    }
}

public struct AppRef: Codable, Hashable, Sendable {
    public var bundleID: String
    public var name: String?

    public init(bundleID: String, name: String? = nil) {
        self.bundleID = bundleID
        self.name = name
    }
}

public struct URLRef: Codable, Hashable, Sendable {
    public var url: String
    /// Open with this app instead of the default handler.
    public var bundleID: String?

    public init(url: String, bundleID: String? = nil) {
        self.url = url
        self.bundleID = bundleID
    }
}

public enum MediaCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case playPause, next, previous, volumeUp, volumeDown, mute

    public var title: String {
        switch self {
        case .playPause: "Play / Pause"
        case .next: "Next Track"
        case .previous: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .mute: "Mute"
        }
    }

    public var symbol: String {
        switch self {
        case .playPause: "playpause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .mute: "speaker.slash.fill"
        }
    }
}

public enum SystemCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case missionControl, appWindows, showDesktop, launchpad, spotlight
    case lockScreen, sleepDisplay
    case screenshotArea, screenshotScreen, screenshotTool
    case brightnessUp, brightnessDown
    case toggleDarkMode

    public var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .appWindows: "App Windows"
        case .showDesktop: "Show Desktop"
        case .launchpad: "Apps"
        case .spotlight: "Spotlight"
        case .lockScreen: "Lock Screen"
        case .sleepDisplay: "Sleep Display"
        case .screenshotArea: "Screenshot Area"
        case .screenshotScreen: "Screenshot Screen"
        case .screenshotTool: "Screenshot Tool"
        case .brightnessUp: "Brightness Up"
        case .brightnessDown: "Brightness Down"
        case .toggleDarkMode: "Dark Mode"
        }
    }

    public var symbol: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .appWindows: "macwindow.on.rectangle"
        case .showDesktop: "menubar.dock.rectangle"
        case .launchpad: "square.grid.3x3"
        case .spotlight: "magnifyingglass"
        case .lockScreen: "lock.fill"
        case .sleepDisplay: "display"
        case .screenshotArea: "camera.viewfinder"
        case .screenshotScreen: "camera"
        case .screenshotTool: "camera.aperture"
        case .brightnessUp: "sun.max.fill"
        case .brightnessDown: "sun.min"
        case .toggleDarkMode: "circle.lefthalf.filled"
        }
    }
}

public enum WindowCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
    case maximize, center, nextDisplay, minimize, fullScreen

    public var title: String {
        switch self {
        case .leftHalf: "Left Half"
        case .rightHalf: "Right Half"
        case .topHalf: "Top Half"
        case .bottomHalf: "Bottom Half"
        case .leftThird: "Left Third"
        case .centerThird: "Center Third"
        case .rightThird: "Right Third"
        case .leftTwoThirds: "Left Two Thirds"
        case .rightTwoThirds: "Right Two Thirds"
        case .maximize: "Maximize"
        case .center: "Center"
        case .nextDisplay: "Next Display"
        case .minimize: "Minimize"
        case .fullScreen: "Full Screen"
        }
    }

    public var symbol: String {
        switch self {
        case .leftHalf: "rectangle.lefthalf.filled"
        case .rightHalf: "rectangle.righthalf.filled"
        case .topHalf: "rectangle.tophalf.filled"
        case .bottomHalf: "rectangle.bottomhalf.filled"
        case .leftThird: "rectangle.leadingthird.inset.filled"
        case .centerThird: "rectangle.center.inset.filled"
        case .rightThird: "rectangle.trailingthird.inset.filled"
        case .leftTwoThirds: "rectangle.leadinghalf.inset.filled"
        case .rightTwoThirds: "rectangle.trailinghalf.inset.filled"
        case .maximize: "arrow.up.left.and.arrow.down.right"
        case .center: "rectangle.center.inset.filled"
        case .nextDisplay: "display.2"
        case .minimize: "minus.rectangle"
        case .fullScreen: "arrow.up.backward.and.arrow.down.forward.rectangle"
        }
    }
}

public struct AudioCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case micToggle, micMute, micUnmute, outputMuteToggle, setOutputVolume, setInputVolume
    }

    public var command: Kind
    /// 0…1, for the `set*Volume` commands.
    public var value: Double?

    public init(_ command: Kind, value: Double? = nil) {
        self.command = command
        self.value = value
    }
}

/// Universal call controls. The Mac translates them for whichever meeting app
/// is running — Zoom, Teams, Google Meet, Webex, Discord — and falls back to a
/// system-wide Core Audio mute for the microphone.
public enum CallCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case toggleMute, toggleVideo, raiseHand, leave, shareScreen

    public var title: String {
        switch self {
        case .toggleMute: "Mute"
        case .toggleVideo: "Camera"
        case .raiseHand: "Raise Hand"
        case .leave: "Leave"
        case .shareScreen: "Share"
        }
    }

    public var symbol: String {
        switch self {
        case .toggleMute: "mic.slash.fill"
        case .toggleVideo: "video.slash.fill"
        case .raiseHand: "hand.raised.fill"
        case .leave: "phone.down.fill"
        case .shareScreen: "rectangle.on.rectangle"
        }
    }
}

public enum BotCommand: String, Codable, Hashable, Sendable, CaseIterable {
    case pause, resume, closeAll, refresh

    public var title: String {
        switch self {
        case .pause: "Pause Bot"
        case .resume: "Resume Bot"
        case .closeAll: "Close All Positions"
        case .refresh: "Refresh"
        }
    }
}

public struct FocusCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable { case on, off, toggle }
    public var command: Kind
    /// The Focus to turn on. `nil` means the workspace's default Focus.
    public var name: String?

    public init(_ command: Kind, name: String? = nil) {
        self.command = command
        self.name = name
    }
}

public enum TimerKind: String, Codable, Hashable, Sendable, CaseIterable {
    case pomodoro, shortBreak, longBreak, deepWork, custom

    public var title: String {
        switch self {
        case .pomodoro: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        case .deepWork: "Deep Work"
        case .custom: "Timer"
        }
    }

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

public struct TimerPreset: Codable, Hashable, Sendable {
    public var kind: TimerKind
    /// `nil` = the workspace default for this kind.
    public var minutes: Double?
    public var label: String?
    /// Turn Focus on while the timer runs and off when it ends.
    public var focus: Bool?
    public var focusName: String?

    public init(kind: TimerKind, minutes: Double? = nil, label: String? = nil, focus: Bool? = nil, focusName: String? = nil) {
        self.kind = kind
        self.minutes = minutes
        self.label = label
        self.focus = focus
        self.focusName = focusName
    }
}

public struct TimerCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case start, pause, resume, toggle, reset, stop, skip, extend, setFocus
    }

    public var command: Kind
    public var preset: TimerPreset?
    /// Target timer; `nil` = the primary timer.
    public var id: String?
    /// For `extend` (seconds).
    public var seconds: Double?
    /// For `setFocus`.
    public var enabled: Bool?

    public init(_ command: Kind, preset: TimerPreset? = nil, id: String? = nil, seconds: Double? = nil, enabled: Bool? = nil) {
        self.command = command
        self.preset = preset
        self.id = id
        self.seconds = seconds
        self.enabled = enabled
    }

    public static func start(_ kind: TimerKind, minutes: Double? = nil, focus: Bool? = nil) -> TimerCommand {
        TimerCommand(.start, preset: TimerPreset(kind: kind, minutes: minutes, focus: focus))
    }
}

public struct GitCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case status, pull, push, fetch, commitAll, stash
    }

    public var command: Kind
    public var message: String?
    /// Repository path; `nil` = the repository the Mac considers current.
    public var repo: String?

    public init(_ command: Kind, message: String? = nil, repo: String? = nil) {
        self.command = command
        self.message = message
        self.repo = repo
    }
}

public struct MacroStep: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var action: ButtonAction
    /// Seconds to wait after this step.
    public var delay: Double?

    public init(_ action: ButtonAction, delay: Double? = nil, id: String = UUID().uuidString) {
        self.id = id
        self.action = action
        self.delay = delay
    }

    enum CodingKeys: String, CodingKey { case id, action, delay }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        action = try c.decode(ButtonAction.self, forKey: .action)
        delay = try c.decodeIfPresent(Double.self, forKey: .delay)
    }
}

public struct ClipboardCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable { case setText, copyURL }
    public var command: Kind
    public var text: String?

    public init(_ command: Kind, text: String? = nil) {
        self.command = command
        self.text = text
    }
}

public struct DailyCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable {
        case setPriority, togglePriority, clearPriorities, carryOver
        case setStudyMode, dismissBrief, startDay
    }

    public var command: Kind
    public var index: Int?
    public var text: String?
    public var enabled: Bool?

    public init(_ command: Kind, index: Int? = nil, text: String? = nil, enabled: Bool? = nil) {
        self.command = command
        self.index = index
        self.text = text
        self.enabled = enabled
    }
}

public struct AppControl: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable { case activate, hide, quit }
    public var command: Kind
    public var bundleID: String

    public init(_ command: Kind, bundleID: String) {
        self.command = command
        self.bundleID = bundleID
    }
}

public enum IntegrationID: String, Codable, Hashable, Sendable, CaseIterable {
    case bot, whoop, weather, portfolio, calendar, focus, media, git, system

    public var title: String {
        switch self {
        case .bot: "Trading Bot"
        case .whoop: "WHOOP"
        case .weather: "Weather"
        case .portfolio: "PortTracker"
        case .calendar: "Calendar"
        case .focus: "Focus"
        case .media: "Music"
        case .git: "Git"
        case .system: "System"
        }
    }

    public var symbol: String {
        switch self {
        case .bot: "chart.line.uptrend.xyaxis"
        case .whoop: "heart.circle"
        case .weather: "cloud.sun"
        case .portfolio: "briefcase"
        case .calendar: "calendar"
        case .focus: "moon"
        case .media: "music.note"
        case .git: "arrow.triangle.branch"
        case .system: "cpu"
        }
    }
}

public struct IntegrationCommand: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable, CaseIterable { case connect, disconnect, refresh, test }
    public var integration: IntegrationID
    public var command: Kind

    public init(_ integration: IntegrationID, _ command: Kind) {
        self.integration = integration
        self.command = command
    }
}

// MARK: - Codable (flat, type-tagged)

extension ButtonAction: Codable {
    private enum TypeKey: String, CodingKey { case type }
    private struct Source: Codable { var source: String }
    private struct PathRef: Codable { var path: String }
    private struct PageRef: Codable { var page: String }
    private struct IDRef: Codable { var id: String }
    private struct Steps: Codable { var steps: [MacroStep] }
    private struct Command<T: Codable>: Codable { var command: T }

    public var typeName: String {
        switch self {
        case .keyCombo: "keyCombo"
        case .text: "text"
        case .appleScript: "appleScript"
        case .shell: "shell"
        case .shortcut: "shortcut"
        case .openApp: "openApp"
        case .openURL: "openURL"
        case .openPath: "openPath"
        case .media: "media"
        case .system: "system"
        case .window: "window"
        case .audio: "audio"
        case .call: "call"
        case .bot: "bot"
        case .focus: "focus"
        case .timer: "timer"
        case .git: "git"
        case .navigate: "navigate"
        case .scene: "scene"
        case .macro: "macro"
        case .clipboard: "clipboard"
        case .daily: "daily"
        case .app: "app"
        case .integration: "integration"
        case .none: "none"
        case .unsupported(let type): type
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "keyCombo": self = .keyCombo(try KeyCombo(from: decoder))
        case "text": self = .text(try TextInput(from: decoder))
        case "appleScript": self = .appleScript(try Source(from: decoder).source)
        case "shell": self = .shell(try ShellCommand(from: decoder))
        case "shortcut": self = .shortcut(try ShortcutRun(from: decoder))
        case "openApp": self = .openApp(try AppRef(from: decoder))
        case "openURL": self = .openURL(try URLRef(from: decoder))
        case "openPath": self = .openPath(try PathRef(from: decoder).path)
        case "media": self = .media(try Command<MediaCommand>(from: decoder).command)
        case "system": self = .system(try Command<SystemCommand>(from: decoder).command)
        case "window": self = .window(try Command<WindowCommand>(from: decoder).command)
        case "audio": self = .audio(try AudioCommand(from: decoder))
        case "call": self = .call(try Command<CallCommand>(from: decoder).command)
        case "bot": self = .bot(try Command<BotCommand>(from: decoder).command)
        case "focus": self = .focus(try FocusCommand(from: decoder))
        case "timer": self = .timer(try TimerCommand(from: decoder))
        case "git": self = .git(try GitCommand(from: decoder))
        case "navigate": self = .navigate(try PageRef(from: decoder).page)
        case "scene": self = .scene(try IDRef(from: decoder).id)
        case "macro": self = .macro(try Steps(from: decoder).steps)
        case "clipboard": self = .clipboard(try ClipboardCommand(from: decoder))
        case "daily": self = .daily(try DailyCommand(from: decoder))
        case "app": self = .app(try AppControl(from: decoder))
        case "integration": self = .integration(try IntegrationCommand(from: decoder))
        case "none": self = .none
        default: self = .unsupported(type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        try c.encode(typeName, forKey: .type)
        switch self {
        case .keyCombo(let v): try v.encode(to: encoder)
        case .text(let v): try v.encode(to: encoder)
        case .appleScript(let v): try Source(source: v).encode(to: encoder)
        case .shell(let v): try v.encode(to: encoder)
        case .shortcut(let v): try v.encode(to: encoder)
        case .openApp(let v): try v.encode(to: encoder)
        case .openURL(let v): try v.encode(to: encoder)
        case .openPath(let v): try PathRef(path: v).encode(to: encoder)
        case .media(let v): try Command(command: v).encode(to: encoder)
        case .system(let v): try Command(command: v).encode(to: encoder)
        case .window(let v): try Command(command: v).encode(to: encoder)
        case .audio(let v): try v.encode(to: encoder)
        case .call(let v): try Command(command: v).encode(to: encoder)
        case .bot(let v): try Command(command: v).encode(to: encoder)
        case .focus(let v): try v.encode(to: encoder)
        case .timer(let v): try v.encode(to: encoder)
        case .git(let v): try v.encode(to: encoder)
        case .navigate(let v): try PageRef(page: v).encode(to: encoder)
        case .scene(let v): try IDRef(id: v).encode(to: encoder)
        case .macro(let v): try Steps(steps: v).encode(to: encoder)
        case .clipboard(let v): try v.encode(to: encoder)
        case .daily(let v): try v.encode(to: encoder)
        case .app(let v): try v.encode(to: encoder)
        case .integration(let v): try v.encode(to: encoder)
        case .none, .unsupported: break
        }
    }
}

// MARK: - Semantics

public extension ButtonAction {
    /// Executes on the client without a round trip to the Mac.
    var isLocal: Bool {
        if case .navigate = self { return true }
        return false
    }

    /// Worth a confirmation before running.
    var isDestructive: Bool {
        switch self {
        case .bot(.closeAll): true
        case .app(let control): control.command == .quit
        case .call(.leave): true
        case .macro(let steps): steps.contains { $0.action.isDestructive }
        default: false
        }
    }

    /// Needs the Mac helper to hold the Accessibility permission.
    var needsAccessibility: Bool {
        switch self {
        case .keyCombo, .text, .window, .call: true
        case .media, .system: true
        case .macro(let steps): steps.contains { $0.action.needsAccessibility }
        default: false
        }
    }

    /// The text contains `{{input}}`: the client asks for it before sending.
    var promptsForInput: Bool { inputPlaceholderHost != nil }

    /// A placeholder the user has to replace before the key is useful.
    var needsSetup: Bool {
        let haystack: String
        switch self {
        case .openPath(let p): haystack = p
        case .openURL(let u): haystack = u.url
        case .shell(let s): haystack = s.command + (s.cwd ?? "")
        case .shortcut(let s): haystack = s.name
        case .text(let t): haystack = t.text
        case .macro(let steps): return steps.contains { $0.action.needsSetup }
        default: return false
        }
        return haystack.contains("YOUR_")
    }

    private var inputPlaceholderHost: String? {
        let token = "{{input}}"
        switch self {
        case .text(let t): return t.text.contains(token) ? t.text : nil
        case .shell(let s): return s.command.contains(token) ? s.command : nil
        case .openURL(let u): return u.url.contains(token) ? u.url : nil
        case .git(let g): return (g.message ?? "").contains(token) ? g.message : nil
        case .clipboard(let c): return (c.text ?? "").contains(token) ? c.text : nil
        case .macro(let steps): return steps.lazy.compactMap { $0.action.inputPlaceholderHost }.first
        default: return nil
        }
    }

    /// Replaces `{{input}}` everywhere (URL-encoding inside URLs).
    func fillingInput(_ input: String) -> ButtonAction {
        let token = "{{input}}"
        switch self {
        case .text(var t):
            t.text = t.text.replacingOccurrences(of: token, with: input)
            return .text(t)
        case .shell(var s):
            s.command = s.command.replacingOccurrences(of: token, with: input.replacingOccurrences(of: "\"", with: "\\\""))
            return .shell(s)
        case .openURL(var u):
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            u.url = u.url.replacingOccurrences(of: token, with: encoded)
            return .openURL(u)
        case .git(var g):
            g.message = g.message?.replacingOccurrences(of: token, with: input)
            return .git(g)
        case .clipboard(var c):
            c.text = c.text?.replacingOccurrences(of: token, with: input)
            return .clipboard(c)
        case .macro(let steps):
            return .macro(steps.map { step in
                var step = step
                step.action = step.action.fillingInput(input)
                return step
            })
        default:
            return self
        }
    }

    /// One line describing what the key does — the caption under a key.
    var summary: String {
        switch self {
        case .keyCombo(let k): return k.display
        case .text(let t):
            let body = t.text.count > 22 ? String(t.text.prefix(21)) + "…" : t.text
            return t.pressesReturn ? "\(body) ↩" : body
        case .appleScript: return "AppleScript"
        case .shell(let s):
            let body = s.command.count > 24 ? String(s.command.prefix(23)) + "…" : s.command
            return "$ " + body
        case .shortcut(let s): return "Shortcut · \(s.name)"
        case .openApp(let a): return "Open \(a.name ?? a.bundleID)"
        case .openURL(let u):
            return URL(string: u.url)?.host(percentEncoded: false) ?? u.url
        case .openPath(let p): return (p as NSString).lastPathComponent
        case .media(let m): return m.title
        case .system(let s): return s.title
        case .window(let w): return w.title
        case .audio(let a):
            switch a.command {
            case .micToggle: return "Toggle Mic"
            case .micMute: return "Mute Mic"
            case .micUnmute: return "Unmute Mic"
            case .outputMuteToggle: return "Toggle Sound"
            case .setOutputVolume: return "Volume \(Int((a.value ?? 0) * 100))%"
            case .setInputVolume: return "Mic \(Int((a.value ?? 0) * 100))%"
            }
        case .call(let c): return c.title
        case .bot(let b): return b.title
        case .focus(let f):
            switch f.command {
            case .on: return "Focus · \(f.name ?? "On")"
            case .off: return "Focus Off"
            case .toggle: return "Toggle \(f.name ?? "Focus")"
            }
        case .timer(let t):
            if let preset = t.preset {
                let minutes = preset.minutes.map { "\(Int($0))m" } ?? ""
                return [preset.label ?? preset.kind.title, minutes].filter { !$0.isEmpty }.joined(separator: " · ")
            }
            return t.command.rawValue.capitalized + " Timer"
        case .git(let g): return "git \(g.command == .commitAll ? "commit" : g.command.rawValue)"
        case .navigate(let page): return "Show \(page)"
        case .scene: return "Scene"
        case .macro(let steps): return "\(steps.count) steps"
        case .clipboard(let c): return c.command == .copyURL ? "Copy URL" : "Set Clipboard"
        case .daily(let d): return d.command.rawValue
        case .app(let a): return "\(a.command.rawValue.capitalized) \(a.bundleID)"
        case .integration(let i): return "\(i.command.rawValue.capitalized) \(i.integration.title)"
        case .none: return ""
        case .unsupported(let type): return "Unsupported (\(type))"
        }
    }
}
