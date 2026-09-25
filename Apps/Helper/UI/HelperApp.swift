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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        MainActor.assumeIsolated {
            Hub.shared.start()
            if !UserDefaults.standard.bool(forKey: "didOnboard") {
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

struct MenuBarLabel: View {
    @State private var hub = Hub.shared

    var body: some View {
        let connected = hub.hasClients
        let pairing = hub.pairing.current != nil
        HStack(spacing: 4) {
            Image(nsImage: MenuBarGlyph.image(connected: connected, pairing: pairing))
            if let timer = hub.state.timers?.primary {
                if timer.state == .running, let end = timer.endsAt {
                    Text(timerInterval: Date.now...max(Date.now, end), countsDown: true)
                        .monospacedDigit()
                } else {
                    Text(Fmt.countdown(timer.remaining(at: .now)))
                        .monospacedDigit()
                }
            }
        }
    }
}
