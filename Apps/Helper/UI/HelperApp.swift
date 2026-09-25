import AppKit
import CCCore
import SwiftUI
import UserNotifications

@main
struct ControlCenterHelperApp: App {
    @NSApplicationDelegateAdaptor(HelperAppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("ControlCenter Helper", id: "preferences") {
            PreferencesView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class HelperAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        if !MacInfo.isTestRun {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        MainActor.assumeIsolated {
            Hub.shared.start()
            if MacInfo.isInstalled, !MacInfo.isTestRun, !UserDefaults.standard.bool(forKey: "didOnboard") {
                UserDefaults.standard.set(true, forKey: "didOnboard")
                LoginItem.set(true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Hub.shared.shutdown() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { PreferencesOpener.open() }
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Opens the preferences window from anywhere (an LSUIElement app must
/// activate itself first or the window opens behind everything).
@MainActor
enum PreferencesOpener {
    static var openWindow: OpenWindowAction?

    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow?(id: "preferences")
    }
}

/// The menu bar item. The countdown comes from `MenuBarTicker` as a plain
/// string, never from `Text(timerInterval:)` with a moving lower bound — in a
/// MenuBarExtra label that re-renders in a tight loop and starves the main
/// actor (and with it every connection).
struct MenuBarLabel: View {
    @State private var hub = Hub.shared
    @State private var ticker = MenuBarTicker.shared

    var body: some View {
        let connected = hub.hasClients
        let pairing = hub.pairing.current != nil
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(connected: connected, pairing: pairing))
            if let text = ticker.text {
                Text(text).monospacedDigit()
            }
        }
    }
}

/// Publishes the running timer as text once per second, only while one runs.
@MainActor
@Observable
final class MenuBarTicker {
    static let shared = MenuBarTicker()

    private(set) var text: String?
    private var task: Task<Void, Never>?

    func update(_ timers: TimersState?) {
        task?.cancel()
        task = nil
        guard let timer = timers?.primary else {
            text = nil
            return
        }
        guard timer.state == .running else {
            text = Fmt.countdown(timer.remaining(at: .now))
            return
        }
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let remaining = timer.remaining(at: .now)
                let next = Fmt.countdown(remaining)
                if self?.text != next { self?.text = next }
                if remaining <= 0 { break }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
