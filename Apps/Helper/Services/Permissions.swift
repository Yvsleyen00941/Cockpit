import AppKit
import ApplicationServices
import CCCore
import CoreGraphics
import EventKit
import Observation
import ServiceManagement

/// Tracks the macOS privacy permissions the helper can use. Only Accessibility
/// is essential (keystrokes); the rest unlock individual features.
@MainActor
@Observable
final class PermissionsMonitor {
    private(set) var statuses: [PermissionStatus] = []

    func refresh() {
        let dndPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json").path
        statuses = [
            PermissionStatus(kind: .accessibility, granted: AXIsProcessTrusted(), required: true),
            PermissionStatus(kind: .automation, granted: automationGranted(), required: false),
            PermissionStatus(kind: .calendar, granted: EKEventStore.authorizationStatus(for: .event) == .fullAccess, required: false),
            PermissionStatus(kind: .reminders, granted: EKEventStore.authorizationStatus(for: .reminder) == .fullAccess, required: false),
            PermissionStatus(kind: .fullDiskAccess, granted: FileManager.default.isReadableFile(atPath: dndPath), required: false),
            PermissionStatus(kind: .inputMonitoring, granted: CGPreflightListenEventAccess(), required: false),
        ]
    }

    func granted(_ kind: PermissionKind) -> Bool {
        statuses.first { $0.kind == kind }?.granted ?? false
    }

    /// Best effort: asks without prompting whether we may script System Events.
    private func automationGranted() -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        guard let desc = target.aeDesc else { return false }
        let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, false)
        return status == noErr
    }

    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            // "AXTrustedCheckOptionPrompt" — the value of kAXTrustedCheckOptionPrompt.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            open("Privacy_Accessibility")
        case .automation:
            Task {
                _ = await AppleScriptRunner.shared.run("tell application \"System Events\" to return name of first process")
                refresh()
            }
            open("Privacy_Automation")
        case .calendar:
            Task {
                await Hub.shared.calendar.requestAccess()
                refresh()
            }
        case .reminders:
            Task {
                _ = try? await Hub.shared.calendar.store.requestFullAccessToReminders()
                refresh()
            }
        case .fullDiskAccess:
            open("Privacy_AllFiles")
        case .inputMonitoring:
            CGRequestListenEventAccess()
            open("Privacy_ListenEvent")
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            self.refresh()
            Hub.shared.scheduleHelperStatus()
        }
    }

    private func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Launch at login via SMAppService (the modern LaunchAgent).
@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            Log.shared.error("Launch at login: \(error.localizedDescription)")
        }
    }
}
