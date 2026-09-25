import AppIntents
import CCCore
import CCNet
import Foundation
import WidgetKit

// MARK: - Bridge to the Mac

enum HubBridgeError: Error, CustomLocalizedStringResourceConvertible {
    case notPaired
    case failed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notPaired: "Pair Control Center with your Mac first."
        case .failed(let message): "\(message)"
        }
    }
}

/// Routes an action to the Mac: through the app's live session when the app
/// is running, otherwise over a one-shot encrypted connection (widgets,
/// Control Center, Siri with the app closed).
enum HubBridge {
    @MainActor static var live: (@MainActor (ButtonAction) async -> ActionResult?)?

    static func run(_ action: ButtonAction) async throws -> ActionResult {
        // `navigate` from an intent means "on the iPad on my desk": it goes
        // through a one-shot session so the Mac broadcasts it to every iPad.
        let isNavigation: Bool = if case .navigate = action { true } else { false }
        if !isNavigation, let live = await MainActor.run(body: { HubBridge.live }), let result = await live(action) {
            return result
        }
        guard let mac = SharedStore.preferredMac else { throw HubBridgeError.notPaired }
        do {
            return try await HubOneShot.run(action, mac: mac, device: SharedStore.deviceIdentity)
        } catch {
            throw HubBridgeError.failed("Couldn't reach \(mac.macName): \(error.localizedDescription)")
        }
    }

    static func snapshot(_ channels: [Channel]) async -> LiveState? {
        guard let mac = SharedStore.preferredMac else { return nil }
        return try? await HubOneShot.snapshot(channels, mac: mac, device: SharedStore.deviceIdentity)
    }

    static func refreshSurfaces() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }

    static func dialog(_ result: ActionResult, success: String) -> IntentDialog {
        IntentDialog(stringLiteral: result.ok ? (result.message ?? success) : (result.message ?? "That didn't work."))
    }
}

// MARK: - Entities

struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let defaultQuery = SceneQuery()

    var id: String
    var name: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }
}

struct SceneQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SceneEntity] { all() }

    private func all() -> [SceneEntity] {
        if let scenes = SharedStore.loadSnapshot()?.scenes, !scenes.isEmpty {
            return scenes.map { SceneEntity(id: $0.id, name: $0.name, symbol: $0.symbol) }
        }
        return DefaultWorkspace.make().scenes.map { SceneEntity(id: $0.id, name: $0.name, symbol: $0.symbol) }
    }
}

struct PageEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Page"
    static let defaultQuery = PageQuery()

    var id: String
    var title: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }
}

struct PageQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [PageEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [PageEntity] { all() }

    private func all() -> [PageEntity] {
        if let pages = SharedStore.loadSnapshot()?.pages, !pages.isEmpty {
            return pages.map { PageEntity(id: $0.id, title: $0.title, symbol: $0.symbol) }
        }
        return DefaultWorkspace.make().pages.map { PageEntity(id: $0.id, title: $0.title, symbol: $0.symbol) }
    }
}

// MARK: - Trading bot

struct PauseBotIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause Trading Bot"
    static let description = IntentDescription("Pauses the trading bot on your Mac.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.bot(.pause))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "Bot paused."))
    }
}

struct ResumeBotIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Trading Bot"
    static let description = IntentDescription("Resumes the trading bot on your Mac.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.bot(.resume))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "Bot resumed."))
    }
}

/// Pause when running, resume when paused — the Control Center toggle.
struct SetBotRunningIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Bot Running"

    @Parameter(title: "Running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        _ = try await HubBridge.run(.bot(value ? .resume : .pause))
        HubBridge.refreshSurfaces()
        return .result()
    }
}

struct BotStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "How's My Bot Doing"
    static let description = IntentDescription("Today's P&L, status and open positions.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Double> {
        let state = await HubBridge.snapshot([.bot])
        guard let bot = state?.bot ?? SharedStore.loadSnapshot()?.bot, bot.mode != .off else {
            return .result(value: 0, dialog: "The trading bot isn't connected.")
        }
        let direction = bot.pnlToday >= 0 ? "up" : "down"
        let text = "The bot is \(bot.status.title.lowercased()), \(direction) \(Fmt.money(abs(bot.pnlToday), currency: bot.currency)) today with \(bot.positions.count) open position\(bot.positions.count == 1 ? "" : "s")."
        return .result(value: bot.pnlToday, dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - Focus & timers

struct StartFocusSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Focus Session"
    static let description = IntentDescription("Starts a Pomodoro on your Mac and turns on Focus until it ends.")

    @Parameter(title: "Minutes", default: 25)
    var minutes: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.timer(.start(.pomodoro, minutes: Double(minutes), focus: true)))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "Focus for \(minutes) minutes."))
    }
}

struct ToggleTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Pause or Resume Timer"

    func perform() async throws -> some IntentResult {
        _ = try await HubBridge.run(.timer(TimerCommand(.toggle)))
        HubBridge.refreshSurfaces()
        return .result()
    }
}

struct StopTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Timer"

    func perform() async throws -> some IntentResult {
        _ = try await HubBridge.run(.timer(TimerCommand(.stop)))
        HubBridge.refreshSurfaces()
        return .result()
    }
}

// MARK: - Microphone

struct SetMicMutedIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Mute Mac Microphone"
    static let description = IntentDescription("Mutes or unmutes your Mac's microphone system-wide.")

    @Parameter(title: "Muted")
    var value: Bool

    func perform() async throws -> some IntentResult {
        _ = try await HubBridge.run(.audio(AudioCommand(value ? .micMute : .micUnmute)))
        if var snapshot = SharedStore.loadSnapshot() {
            snapshot.micMuted = value
            SharedStore.saveSnapshot(snapshot)
        }
        HubBridge.refreshSurfaces()
        return .result()
    }
}

struct ToggleMicIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Mac Microphone"

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.audio(AudioCommand(.micToggle)))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "Done."))
    }
}

// MARK: - Scenes & pages

struct RunSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Scene"
    static let description = IntentDescription("Runs a Control Center scene — Start the Day, Lecture Mode, End the Day…")

    @Parameter(title: "Scene")
    var scene: SceneEntity

    init() {}

    init(scene: SceneEntity) {
        self.scene = scene
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.scene(scene.id))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "\(scene.name) done."))
    }
}

struct StartTheDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Start the Day"
    static let description = IntentDescription("Sets your Focus, opens your morning apps and starts a deep work session.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.scene("startDay"))
        HubBridge.refreshSurfaces()
        return .result(dialog: HubBridge.dialog(result, success: "Have a great day."))
    }
}

/// "Open trading view on my iPad": switches every connected iPad to a page —
/// from your iPhone, your Mac or Siri, without opening anything.
struct ShowPageOnDeskIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Page on iPad"
    static let description = IntentDescription("Switches the iPad on your desk to a page.")

    @Parameter(title: "Page")
    var page: PageEntity

    init() {}

    init(page: PageEntity) {
        self.page = page
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.navigate(page.id))
        return .result(dialog: HubBridge.dialog(result, success: "Showing \(page.title) on your iPad."))
    }
}

struct ShowTradingViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Trading View on iPad"
    static let description = IntentDescription("Shows the trading bot dashboard on the iPad on your desk.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await HubBridge.run(.navigate("bot"))
        return .result(dialog: HubBridge.dialog(result, success: "Trading view is up on your iPad."))
    }
}
