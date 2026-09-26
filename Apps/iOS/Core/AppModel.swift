import ActivityKit
import CCCore
import CCNet
import Foundation
import Observation
import SwiftUI
import UIKit
import WidgetKit

/// What a key is doing right now — drives the acknowledgement glow.
enum KeyFeedback: Equatable {
    case pending
    case success
    case failure(String)
}

struct ToastItem: Identifiable, Equatable {
    let id = UUID()
    let toast: Toast
    let date = Date()
}

struct InputPrompt: Identifiable {
    let id = UUID()
    let title: String
    let action: ButtonAction
    let buttonID: String?
    let pageID: String?
}

struct PendingConfirmation: Identifiable {
    let id = UUID()
    let key: ButtonDef
    let pageID: String?
}

struct OutputItem: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    let ok: Bool
}

/// The app's single source of truth on the device: the link (real or demo),
/// the live store, the workspace, the navigator and every piece of UI state
/// that outlives a view.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let store = LiveStore()
    let navigator = Navigator()
    let images = ImageCache()
    let connection = HubConnection()
    let demo = DemoHub()

    private(set) var isDemo: Bool
    private(set) var workspace: Workspace
    var editing = false
    var showSettings = false
    var toasts: [ToastItem] = []
    var keyFeedback: [String: KeyFeedback] = [:]
    var prompt: InputPrompt?
    var confirmation: PendingConfirmation?
    var output: OutputItem?
    var recording: MacroRecording?
    var lastTouch = Date()
    var theme: ThemeChoice {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "theme") }
    }
    var keyClicks: Bool {
        didSet { UserDefaults.standard.set(keyClicks, forKey: "keyClicks") }
    }

    private var navigationTicker: Task<Void, Never>?
    private var cacheTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var subscribed: Set<Channel> = []
    private var lastWidgetReload = Date.distantPast

    var link: any HubLink { isDemo ? demo : connection }

    private init() {
        let arguments = ProcessInfo.processInfo.arguments
        isDemo = arguments.contains("-CCDemo") || UserDefaults.standard.bool(forKey: "demoMode")
        workspace = OfflineCache.loadWorkspace() ?? DefaultWorkspace.make()
        theme = ThemeChoice(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .dark
        keyClicks = UserDefaults.standard.object(forKey: "keyClicks") as? Bool ?? true
        if !isDemo, let cached = OfflineCache.loadState() { store.load(cached) }
        if let page = arguments.firstIndex(of: "-CCPage").flatMap({ arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }) {
            navigator.show(page)
            navigator.togglePin()
        }
    }

    // MARK: Lifecycle

    func start() {
        wire(link)
        link.start()
        // `-CCPairing` opens the pairing flow even when a Mac is paired (screenshots, testing).
        if !isDemo, ProcessInfo.processInfo.arguments.contains("-CCPairing") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(0.6))
                self?.connection.forceShowPairing()
            }
        }
        navigator.update(workspace: workspace, store: store)
        navigationTicker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.refreshNavigation()
            }
        }
        HubBridge.live = { [weak self] action in
            guard let self, self.link.status.isConnected else { return nil }
            return await self.perform(action)
        }
    }

    private func wire(_ link: any HubLink) {
        link.onMessage = { [weak self] message in self?.handle(message) }
        link.onConnected = { [weak self] in self?.connected() }
    }

    func setDemo(_ enabled: Bool) {
        guard enabled != isDemo else { return }
        link.stop()
        isDemo = enabled
        UserDefaults.standard.set(enabled, forKey: "demoMode")
        if !enabled {
            workspace = OfflineCache.loadWorkspace() ?? DefaultWorkspace.make()
        }
        subscribed = []
        wire(link)
        link.start()
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            link.appBecameActive()
            lastTouch = .now
        case .background:
            connection.appWillResignActive()
            saveCache()
        default:
            break
        }
    }

    private func connected() {
        subscribed = []
        updateSubscriptions(force: true)
        link.send(.requestLayout(RequestLayout(knownRevision: workspace.revision)))
        requestIcons()
    }

    // MARK: Incoming

    private func handle(_ message: MCCMessage) {
        switch message.body {
        case .appDidChange(let context):
            store.apply(.context(context))
            images.request([context.bundleID], via: link)
            refreshNavigation()
        case .liveDataUpdate(let update):
            var navigationRelevant = false
            for value in update.values {
                store.apply(value)
                switch value.channel {
                case .context, .daily, .focus, .calendar, .timers, .audio: navigationRelevant = true
                case .media: images.requestArtwork(store.media?.nowPlaying?.artworkID, via: link)
                case .apps: images.request(store.apps?.apps.map(\.bundleID) ?? [], via: link)
                default: break
                }
            }
            if navigationRelevant { refreshNavigation() }
            scheduleSideEffects()
        case .buttonConfigUpdate(let workspace):
            if workspace != self.workspace {
                withAnimation(.easeInOut(duration: 0.25)) { self.workspace = workspace }
                if !isDemo { OfflineCache.save(workspace) }
                refreshNavigation()
                updateSubscriptions()
                requestIcons()
            }
        case .toast(let toast):
            show(toast)
        case .directive(let directive):
            switch directive.command {
            case .navigate:
                if let page = directive.page {
                    withAnimation(.easeOut(duration: 0.25)) { navigator.show(page) }
                    updateSubscriptions()
                }
            case .chime:
                Feedback.chime()
            case .ambient, .wake:
                lastTouch = directive.command == .wake ? .now : .distantPast
            }
        case .macroRecording(let recording):
            self.recording = recording
        case .bye(let bye):
            if bye.reason == .revoked { connection.forget(connection.currentMac?.macID ?? "") }
        default:
            break
        }
    }

    // MARK: Navigation & subscriptions

    var currentPage: Page? { workspace.page(navigator.pageID) ?? workspace.page("home") ?? workspace.pages.first }

    func refreshNavigation() {
        let before = navigator.pageID
        navigator.update(workspace: workspace, store: store)
        if navigator.pageID != before { updateSubscriptions() }
    }

    func show(page: String) {
        withAnimation(.easeOut(duration: 0.25)) { navigator.show(page) }
        updateSubscriptions()
        if page != "brief", store.daily?.briefPending == true, navigator.modes.contains(Mode.morning) {
            // Leaving the Brief by hand counts as having seen it.
            link.send(.buttonTap(ButtonTap(action: .daily(DailyCommand(.dismissBrief)))))
        }
    }

    /// Channels = what's on screen + the chrome + what the widgets and the
    /// context engine need. Everything else stays off on the Mac.
    func updateSubscriptions(force: Bool = false) {
        var channels = Channel.always.union([.bot, .botSeries, .whoop, .calendar])
        channels.formUnion(currentPage?.channels ?? [])
        guard force || channels != subscribed else { return }
        subscribed = channels
        link.send(.subscribe(Subscribe(channels: channels)))
    }

    private func requestIcons() {
        var ids = Set(workspace.pages.compactMap(\.appBundleID))
        for rule in workspace.rules { ids.formUnion(rule.match.bundleIDs) }
        for key in workspace.allButtons {
            if case .openApp(let app) = key.action { ids.insert(app.bundleID) }
        }
        if let context = store.context { ids.insert(context.bundleID) }
        ids.formUnion(store.apps?.apps.map(\.bundleID) ?? [])
        images.request(ids, via: link)
    }

    // MARK: Keys & actions

    /// A key was tapped: confirmation, input prompt, local navigation, or off
    /// to the Mac — with acknowledgement feedback on the key itself.
    func tap(_ key: ButtonDef, pageID: String?, confirmed: Bool = false) {
        lastTouch = .now
        if editing { return }
        if key.confirm == .dialog, !confirmed {
            confirmation = PendingConfirmation(key: key, pageID: pageID)
            return
        }
        if key.action.promptsForInput {
            prompt = InputPrompt(title: key.label, action: key.action, buttonID: key.id, pageID: pageID)
            return
        }
        Feedback.tap()
        Task { await perform(key.action, buttonID: key.id, pageID: pageID) }
    }

    @discardableResult
    func perform(_ action: ButtonAction, buttonID: String? = nil, pageID: String? = nil) async -> ActionResult {
        if case .navigate(let page) = action {
            show(page: page)
            return .success
        }
        if case .none = action { return .success }
        guard link.status.isConnected else {
            let result = ActionResult.failure("Not connected to your Mac")
            flash(buttonID, result)
            return result
        }
        if let buttonID { keyFeedback[buttonID] = .pending }
        let result: ActionResult
        do {
            let reply = try await link.request(.buttonTap(ButtonTap(action: action, buttonID: buttonID, pageID: pageID)), timeout: 75)
            if case .actionResult(let payload) = reply.body {
                result = payload
            } else {
                result = .success
            }
        } catch {
            result = .failure(error.localizedDescription)
        }
        flash(buttonID, result)
        if !result.ok {
            Feedback.failure()
            show(Toast(title: result.message ?? "That didn't work", style: .error, symbol: "exclamationmark.triangle.fill"))
        } else if let text = result.output, !text.isEmpty {
            output = OutputItem(title: result.message ?? action.summary, text: text, ok: true)
        } else if let message = result.message, message.hasPrefix("Demo") {
            show(Toast(title: message, style: .info, symbol: "sparkles"))
        }
        return result
    }

    private func flash(_ buttonID: String?, _ result: ActionResult) {
        guard let buttonID else { return }
        keyFeedback[buttonID] = result.ok ? .success : .failure(result.message ?? "Failed")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            if keyFeedback[buttonID] != .pending { keyFeedback[buttonID] = nil }
        }
    }

    func submitPrompt(_ prompt: InputPrompt, input: String) {
        self.prompt = nil
        Feedback.tap()
        Task { await perform(prompt.action.fillingInput(input), buttonID: prompt.buttonID, pageID: prompt.pageID) }
    }

    func send(_ action: ButtonAction) {
        Task { await perform(action) }
    }

    // MARK: Toasts

    func show(_ toast: Toast) {
        let item = ToastItem(toast: toast)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            toasts.append(item)
            if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(toast.style == .error ? 5 : 3.6))
            withAnimation(.easeOut(duration: 0.25)) { toasts.removeAll { $0.id == item.id } }
        }
    }

    // MARK: Workspace editing

    func commit(_ workspace: Workspace) {
        let base = self.workspace.revision
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { self.workspace = workspace }
        if !isDemo { OfflineCache.save(workspace) }
        updateSubscriptions()
        Task {
            if let reply = try? await link.request(.updateLayout(UpdateLayout(baseRevision: base, workspace: workspace)), timeout: 10),
               case .actionResult(let result) = reply.body, !result.ok {
                show(Toast(title: result.message ?? "Layout conflict", style: .warning, symbol: "arrow.triangle.2.circlepath"))
            }
        }
    }

    func updatePage(_ page: Page) {
        var copy = workspace
        copy.updatePage(page)
        commit(copy)
    }

    func query(_ kind: Query.Kind) async -> QueryResult? {
        guard let reply = try? await link.request(.query(Query(kind)), timeout: 10), case .queryResult(let result) = reply.body else { return nil }
        return result
    }

    // MARK: Side effects (cache, widgets, Live Activity)

    private func scheduleSideEffects() {
        guard snapshotTask == nil else { return }
        snapshotTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            self.snapshotTask = nil
            let snapshot = WidgetSnapshot(state: self.store.snapshot, workspace: self.workspace, macName: self.link.macName, connected: self.link.status.isConnected)
            SharedStore.saveSnapshot(snapshot)
            if Date().timeIntervalSince(self.lastWidgetReload) > 60 {
                self.lastWidgetReload = .now
                WidgetCenter.shared.reloadAllTimelines()
            }
            LiveActivityController.shared.update(with: self.store.snapshot, macName: self.link.macName ?? "Mac")
        }
        guard cacheTask == nil, !isDemo else { return }
        cacheTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.saveCache()
            self?.cacheTask = nil
        }
    }

    private func saveCache() {
        guard !isDemo else { return }
        OfflineCache.save(store.snapshot)
    }

    // MARK: Deep links

    func open(_ url: URL) {
        guard url.scheme == "controlcenter" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "page": if let id = parts.first { show(page: id) }
        case "scene": if let id = parts.first { send(.scene(id)) }
        case "settings": showSettings = true
        default: break
        }
    }
}
