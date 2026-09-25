import ActivityKit
import AppIntents
import BackgroundTasks
import CCCore
import SwiftUI
import UIKit

@main
struct ControlCenterApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = UIDevice.current.userInterfaceIdiom == .pad
                }
                .onOpenURL { model.open($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register()
        MainActor.assumeIsolated {
            AppModel.shared.start()
            LiveActivityController.shared.resume()
        }
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .landscape : .portrait
    }
}

// MARK: - Background refresh (iPhone Live Activity & widgets)

enum BackgroundRefresh {
    static let identifier = "be.yorben.controlcenter.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { bgTask in
            schedule()
            let task = UncheckedBox(bgTask)
            let work = Task {
                if let state = await HubBridge.snapshot([.bot, .whoop, .timers, .calendar, .weather, .portfolio, .focus]) {
                    await MainActor.run {
                        var snapshot = WidgetSnapshot(state: state, workspace: nil, macName: SharedStore.preferredMac?.macName, connected: true)
                        snapshot.pages = SharedStore.loadSnapshot()?.pages ?? []
                        snapshot.scenes = SharedStore.loadSnapshot()?.scenes ?? []
                        SharedStore.saveSnapshot(snapshot)
                        LiveActivityController.shared.update(with: state, macName: SharedStore.preferredMac?.macName ?? "Mac", force: true)
                        HubBridge.refreshSurfaces()
                    }
                }
                task.value.setTaskCompleted(success: true)
            }
            bgTask.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - Live Activity (iPhone)

/// Bot P&L, recovery and the running timer on the iPhone Lock Screen and in
/// the Dynamic Island. Updated whenever the app has fresh data (throttled),
/// from background refresh, or — with an APNs key on the Mac — by push.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var lastUpdate = Date.distantPast
    private var lastState: DeskActivityAttributes.ContentState?

    var isSupported: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool { !Activity<DeskActivityAttributes>.activities.isEmpty }

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "liveActivityEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "liveActivityEnabled") }
    }

    func resume() {
        for activity in Activity<DeskActivityAttributes>.activities {
            observePushToken(activity)
        }
    }

    func start(state: LiveState, macName: String) {
        guard isSupported, !isRunning else { return }
        enabled = true
        let content = ActivityContent(state: DeskActivityAttributes.ContentState(state: state), staleDate: Date().addingTimeInterval(1800))
        let attributes = DeskActivityAttributes(macName: macName)
        do {
            // Push updates need the APNs entitlement (paid membership); fall back without.
            let activity: Activity<DeskActivityAttributes>
            if let pushed = try? Activity.request(attributes: attributes, content: content, pushType: .token) {
                activity = pushed
            } else {
                activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            }
            observePushToken(activity)
        } catch {
            AppModel.shared.show(Toast(title: "Live Activity unavailable", message: error.localizedDescription, style: .warning))
        }
    }

    func stop() {
        enabled = false
        Task {
            for activity in Activity<DeskActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(with state: LiveState, macName: String, force: Bool = false) {
        guard isSupported else { return }
        if !isRunning {
            if enabled { start(state: state, macName: macName) }
            return
        }
        let content = DeskActivityAttributes.ContentState(state: state)
        let significant = content.botStatus != lastState?.botStatus || content.timerEnd != lastState?.timerEnd || content.timerPaused != lastState?.timerPaused || content.recovery != lastState?.recovery
        guard force || significant || Date().timeIntervalSince(lastUpdate) > 30 else { return }
        lastUpdate = .now
        lastState = content
        Task {
            for activity in Activity<DeskActivityAttributes>.activities {
                await activity.update(ActivityContent(state: content, staleDate: Date().addingTimeInterval(1800)))
            }
        }
    }

    private func observePushToken(_ activity: Activity<DeskActivityAttributes>) {
        let id = activity.id
        Task {
            guard let activity = Activity<DeskActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            for await token in activity.pushTokenUpdates {
                #if DEBUG
                let sandbox = true
                #else
                let sandbox = false
                #endif
                AppModel.shared.link.send(.registerPushToken(PushTokenRegistration(kind: .liveActivity, token: token, bundleID: Bundle.main.bundleIdentifier ?? "be.yorben.controlcenter", sandbox: sandbox)))
            }
        }
    }
}

// MARK: - Siri & Shortcuts

struct ControlCenterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowTradingViewIntent(), phrases: [
            "Open trading view on my iPad with \(.applicationName)",
            "Show the trading bot in \(.applicationName)",
        ], shortTitle: "Trading View", systemImageName: "chart.line.uptrend.xyaxis")
        AppShortcut(intent: PauseBotIntent(), phrases: [
            "Pause the bot with \(.applicationName)",
            "Pause trading in \(.applicationName)",
        ], shortTitle: "Pause Bot", systemImageName: "pause.circle")
        AppShortcut(intent: BotStatusIntent(), phrases: [
            "How's my bot doing in \(.applicationName)",
            "Check the bot in \(.applicationName)",
        ], shortTitle: "Bot Status", systemImageName: "chart.bar.xaxis")
        AppShortcut(intent: StartFocusSessionIntent(), phrases: [
            "Start a focus session with \(.applicationName)",
            "Block focus time in \(.applicationName)",
        ], shortTitle: "Focus Session", systemImageName: "timer")
        AppShortcut(intent: StartTheDayIntent(), phrases: [
            "Start the day with \(.applicationName)",
            "Good morning \(.applicationName)",
        ], shortTitle: "Start the Day", systemImageName: "sunrise.fill")
        AppShortcut(intent: ToggleMicIntent(), phrases: [
            "Mute my Mac with \(.applicationName)",
            "Toggle the mic in \(.applicationName)",
        ], shortTitle: "Toggle Mic", systemImageName: "mic.slash")
        AppShortcut(intent: RunSceneIntent(), phrases: [
            "Run \(\.$scene) in \(.applicationName)",
        ], shortTitle: "Run Scene", systemImageName: "sparkles")
        AppShortcut(intent: ShowPageOnDeskIntent(), phrases: [
            "Show \(\.$page) on my iPad with \(.applicationName)",
        ], shortTitle: "Show Page", systemImageName: "ipad.landscape")
    }
}


/// Carries a non-Sendable system object across a task boundary it provably
/// isn't shared across (a BGTask handed to exactly one task).
struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
