import AppKit
import ApplicationServices
import CCCore

/// Tiles the frontmost window through the Accessibility API — halves, thirds,
/// maximise, centre, next display. Rectangle-style, from the iPad.
@MainActor
enum WindowManager {
    static func perform(_ command: WindowCommand) -> ActionResult {
        guard AXIsProcessTrusted() else { return .failure(KeySynth.accessibilityMessage) }
        guard let app = NSWorkspace.shared.frontmostApplication else { return .failure("No app in front") }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success, let windowRef else {
            return .failure("\(app.localizedName ?? "The app") has no window in front")
        }
        // swiftlint:disable:next force_cast
        let window = windowRef as! AXUIElement

        switch command {
        case .minimize:
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            return .success
        case .fullScreen:
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
            let isFull = (value as? Bool) ?? false
            AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (!isFull) as CFBoolean)
            return .success
        default:
            break
        }

        guard let frame = frame(of: window) else { return .failure("Couldn't read the window frame") }
        let screens = NSScreen.screens
        guard let primary = screens.first else { return .failure("No display") }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let current = screens.first { axRect(of: $0, primary: primary).contains(center) } ?? NSScreen.main ?? primary
        var area = axRect(of: current, primary: primary, visible: true)

        let target: CGRect
        switch command {
        case .leftHalf: target = CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)
        case .rightHalf: target = CGRect(x: area.midX, y: area.minY, width: area.width / 2, height: area.height)
        case .topHalf: target = CGRect(x: area.minX, y: area.minY, width: area.width, height: area.height / 2)
        case .bottomHalf: target = CGRect(x: area.minX, y: area.midY, width: area.width, height: area.height / 2)
        case .leftThird: target = CGRect(x: area.minX, y: area.minY, width: area.width / 3, height: area.height)
        case .centerThird: target = CGRect(x: area.minX + area.width / 3, y: area.minY, width: area.width / 3, height: area.height)
        case .rightThird: target = CGRect(x: area.minX + area.width * 2 / 3, y: area.minY, width: area.width / 3, height: area.height)
        case .leftTwoThirds: target = CGRect(x: area.minX, y: area.minY, width: area.width * 2 / 3, height: area.height)
        case .rightTwoThirds: target = CGRect(x: area.minX + area.width / 3, y: area.minY, width: area.width * 2 / 3, height: area.height)
        case .maximize: target = area
        case .center:
            let size = CGSize(width: min(frame.width, area.width * 0.8), height: min(frame.height, area.height * 0.85))
            target = CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
        case .nextDisplay:
            guard screens.count > 1, let index = screens.firstIndex(of: current) else { return .failure("Only one display") }
            let next = screens[(index + 1) % screens.count]
            let from = area
            area = axRect(of: next, primary: primary, visible: true)
            let relX = (frame.minX - from.minX) / max(1, from.width)
            let relY = (frame.minY - from.minY) / max(1, from.height)
            let width = min(frame.width, area.width)
            let height = min(frame.height, area.height)
            target = CGRect(x: area.minX + relX * area.width, y: area.minY + relY * area.height, width: width, height: height)
        case .minimize, .fullScreen:
            return .success
        }
        set(window, to: target.integral)
        return .success
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable force_cast
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        // swiftlint:enable force_cast
        return CGRect(origin: position, size: size)
    }

    private static func set(_ window: AXUIElement, to rect: CGRect) {
        var position = rect.origin
        var size = rect.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        // Position, size, position: some apps clamp size against the old origin.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    }

    /// Cocoa (bottom-left origin) → Accessibility (top-left origin of the primary display).
    private static func axRect(of screen: NSScreen, primary: NSScreen, visible: Bool = false) -> CGRect {
        let frame = visible ? screen.visibleFrame : screen.frame
        return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

/// One set of call keys for every meeting app.
@MainActor
enum CallControls {
    private static let shortcuts: [String: [CallCommand: String]] = [
        "us.zoom.xos": [.toggleMute: "cmd+shift+a", .toggleVideo: "cmd+shift+v", .raiseHand: "opt+y", .leave: "cmd+w", .shareScreen: "cmd+shift+s"],
        "com.microsoft.teams2": [.toggleMute: "cmd+shift+m", .toggleVideo: "cmd+shift+o", .raiseHand: "cmd+shift+k", .leave: "cmd+shift+h", .shareScreen: "cmd+shift+e"],
        "com.microsoft.teams": [.toggleMute: "cmd+shift+m", .toggleVideo: "cmd+shift+o", .raiseHand: "cmd+shift+k", .leave: "cmd+shift+h", .shareScreen: "cmd+shift+e"],
        "Cisco-Systems.Spark": [.toggleMute: "cmd+shift+m", .toggleVideo: "cmd+shift+v"],
        "com.hnc.Discord": [.toggleMute: "cmd+shift+m"],
        "meet.google.com": [.toggleMute: "cmd+d", .toggleVideo: "cmd+e", .raiseHand: "ctrl+cmd+h", .leave: "cmd+w"],
    ]

    static func perform(_ command: CallCommand) async -> ActionResult {
        let front = NSWorkspace.shared.frontmostApplication
        let context = Hub.shared.state.context
        let running = NSWorkspace.shared.runningApplications

        // Google Meet lives in a browser tab — only usable while it's in front.
        if let url = context?.url, url.contains("meet.google.com"), let spec = shortcuts["meet.google.com"]?[command] {
            return KeySynth.post(KeyCombo(spec))
        }
        let candidates = ["us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "Cisco-Systems.Spark", "com.hnc.Discord"]
        let target: NSRunningApplication? = {
            if let front, let id = front.bundleIdentifier, candidates.contains(id) { return front }
            return candidates.lazy.compactMap { id in running.first { $0.bundleIdentifier == id } }.first
        }()
        guard let target, let id = target.bundleIdentifier, let spec = shortcuts[id]?[command] else {
            if command == .toggleMute {
                let muted = Hub.shared.audio.toggleMic()
                return ActionResult(ok: true, message: muted ? "Microphone muted" : "Microphone live")
            }
            return .failure("No meeting app found for \(command.title)")
        }
        let previous = front
        if target != front {
            target.activate()
            try? await Task.sleep(for: .milliseconds(250))
        }
        let result = KeySynth.post(KeyCombo(spec))
        if let previous, previous != target, command != .leave {
            try? await Task.sleep(for: .milliseconds(150))
            previous.activate()
        }
        return result
    }
}

/// Mission Control, lock, screenshots, brightness, appearance.
@MainActor
enum SystemControls {
    static func perform(_ command: SystemCommand) async -> ActionResult {
        switch command {
        case .missionControl: return launchMissionControl(argument: nil)
        case .appWindows: return launchMissionControl(argument: "2")
        case .showDesktop: return launchMissionControl(argument: "1")
        case .launchpad:
            for path in ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"] where FileManager.default.fileExists(atPath: path) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                return .success
            }
            return .failure("Launchpad isn't available")
        case .spotlight: return KeySynth.post(KeyCombo("cmd+space"))
        case .lockScreen:
            if AXIsProcessTrusted() { return KeySynth.post(KeyCombo("ctrl+cmd+q")) }
            _ = await ShellRunner.run(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
            return .success
        case .sleepDisplay:
            _ = await ShellRunner.run(executable: "/usr/bin/pmset", arguments: ["displaysleepnow"])
            return .success
        case .screenshotArea: return KeySynth.post(KeyCombo("cmd+shift+4"))
        case .screenshotScreen: return KeySynth.post(KeyCombo("cmd+shift+3"))
        case .screenshotTool: return KeySynth.post(KeyCombo("cmd+shift+5"))
        case .brightnessUp: return KeySynth.post(.brightnessUp)
        case .brightnessDown: return KeySynth.post(.brightnessDown)
        case .toggleDarkMode:
            let result = await AppleScriptRunner.shared.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
            if case .failure(let error) = result { return .failure(error.localizedDescription) }
            return .success
        }
    }

    private static func launchMissionControl(argument: String?) -> ActionResult {
        let binary = "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = argument.map { [$0] } ?? []
        do {
            try process.run()
            return .success
        } catch {
            return .failure("Mission Control failed: \(error.localizedDescription)")
        }
    }
}
