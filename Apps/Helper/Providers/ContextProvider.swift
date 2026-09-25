import AppKit
import ApplicationServices
import CCCore
import Foundation

/// What's in front of you: frontmost app (NSWorkspace), focused window title
/// (Accessibility observer — event-driven, no polling), current browser tab URL
/// (AppleScript, only on changes and only while a client is connected), and
/// presence (locked / asleep / idle).
@MainActor
final class ContextProvider {
    static let browsers: [String: String] = [
        "com.apple.Safari": "safari",
        "com.apple.SafariTechnologyPreview": "safari",
        "com.google.Chrome": "chromium",
        "com.google.Chrome.canary": "chromium",
        "com.brave.Browser": "chromium",
        "com.microsoft.edgemac": "chromium",
        "com.vivaldi.Vivaldi": "chromium",
        "company.thebrowser.Browser": "chromium",
        "com.operasoftware.Opera": "chromium",
    ]

    private var current = ActiveContext(bundleID: "com.apple.finder", appName: "Finder")
    private var axObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var titleDebounce: Task<Void, Never>?
    private var idleTimer: Task<Void, Never>?
    private var clientsConnected = false
    private var screenLocked = false
    private var displaysAsleep = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { Hub.shared.context.activated(app) }
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.context.setDisplaysAsleep(true) }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.context.setDisplaysAsleep(false) }
        }
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.context.setLocked(true) }
        }
        distributed.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Hub.shared.context.setLocked(false) }
        }
        activated(NSWorkspace.shared.frontmostApplication)
    }

    func setClientsConnected(_ connected: Bool) {
        guard connected != clientsConnected else { return }
        clientsConnected = connected
        idleTimer?.cancel()
        idleTimer = nil
        if connected {
            refreshURL()
            idleTimer = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(20))
                    self?.evaluatePresence()
                }
            }
        }
    }

    // MARK: Activation

    func activated(_ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier else { return }
        // Our own menu bar popover must not hijack the iPad's context.
        if bundleID == Bundle.main.bundleIdentifier { return }
        current = ActiveContext(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            windowTitle: nil,
            url: nil,
            pid: app.processIdentifier,
            since: .now,
            presence: presence()
        )
        observeWindows(of: app.processIdentifier)
        current.windowTitle = focusedWindowTitle(pid: app.processIdentifier)
        publish()
        refreshURL()
    }

    private func publish() {
        Hub.shared.publish(.context(current))
    }

    // MARK: Window titles (Accessibility)

    private func observeWindows(of pid: pid_t) {
        guard Hub.shared.integrations.windowTitleTracking, AXIsProcessTrusted() else { return }
        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(axObserver), .defaultMode)
            self.axObserver = nil
        }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, _, _, _ in
            MainActor.assumeIsolated { Hub.shared.context.windowChanged() }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let element = AXUIElementCreateApplication(pid)
        for notification in [kAXFocusedWindowChangedNotification, kAXTitleChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(observer, element, notification as CFString, nil)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        observedPID = pid
    }

    func windowChanged() {
        titleDebounce?.cancel()
        titleDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            let title = self.focusedWindowTitle(pid: self.observedPID)
            guard title != self.current.windowTitle else { return }
            self.current.windowTitle = title
            self.publish()
            self.refreshURL()
        }
    }

    private func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted(), pid > 0 else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return nil }
        var title: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        let text = title as? String
        return (text?.isEmpty ?? true) ? nil : text
    }

    // MARK: Browser URL

    private func refreshURL() {
        guard clientsConnected, !MacInfo.isTestRun, Hub.shared.integrations.browserURLTracking, let flavor = Self.browsers[current.bundleID] else { return }
        let bundleID = current.bundleID
        let source = flavor == "safari"
            ? "with timeout of 2 seconds\ntell application id \"\(bundleID)\" to if (count of windows) > 0 then return URL of current tab of front window\nend timeout"
            : "with timeout of 2 seconds\ntell application id \"\(bundleID)\" to if (count of windows) > 0 then return URL of active tab of front window\nend timeout"
        Task { @MainActor [weak self] in
            let result = await AppleScriptRunner.shared.run(source)
            guard let self, self.current.bundleID == bundleID else { return }
            let url = (try? result.get())?.stringValue
            guard url != self.current.url else { return }
            self.current.url = url
            self.publish()
        }
    }

    /// Used by `{{url}}` templates and "Copy URL".
    var currentURL: String? { current.url }
    var currentTitle: String? { current.windowTitle }
    var currentAppName: String { current.appName }

    // MARK: Presence

    private func setLocked(_ locked: Bool) {
        screenLocked = locked
        evaluatePresence()
    }

    private func setDisplaysAsleep(_ asleep: Bool) {
        displaysAsleep = asleep
        evaluatePresence()
    }

    private func presence() -> MacPresence {
        if displaysAsleep { return .asleep }
        if screenLocked { return .locked }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let threshold = Hub.shared.workspace.preferences.ambientAfterMinutes * 60
        return idle > threshold ? .idle : .active
    }

    private func evaluatePresence() {
        let next = presence()
        guard next != current.presence else { return }
        current.presence = next
        publish()
    }
}
