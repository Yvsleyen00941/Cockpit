import AppKit
import CCCore
import CCNet
import Foundation
@preconcurrency import Network
import Observation

/// The hub: one live state, one action pipeline, one workspace, many clients.
///
/// Providers publish channel values here; the hub diffs them against what it
/// already has and forwards only real changes, only to clients subscribed to
/// that channel. A provider runs only while somebody is looking at its channel,
/// so with no iPad connected the helper does nothing at all.
@MainActor
@Observable
final class Hub {
    static let shared = Hub()

    struct SessionRecord {
        let session: ClientSession
        var device: ConnectedDevice
        var subscriptions: Set<Channel>
        var lastSeen: Date
    }

    let identity = MacInfo.identity
    let devices = DeviceStore()
    let pairing = PairingCenter()
    let server = HubServer()
    let localAPI = LocalAPI()
    let usb = USBBridge()
    let executor = ActionExecutor()
    let permissions = PermissionsMonitor()
    let apns = APNsPusher()

    let context = ContextProvider()
    let apps = AppsProvider()
    let system = SystemProvider()
    let media = MediaProvider()
    let audio = AudioProvider()
    let calendar = CalendarProvider()
    let focus = FocusProvider()
    let bot = BotProvider()
    let whoop = WhoopProvider()
    let weather = WeatherProvider()
    let portfolio = PortfolioProvider()
    let git = GitProvider()
    let timers = TimerEngine()
    let daily = DailyStore()

    private(set) var state = LiveState()
    private(set) var workspace: Workspace
    private(set) var integrations: IntegrationSettings
    private(set) var sessions: [UUID: SessionRecord] = [:]
    private(set) var pairedDevices: [PairedDevice] = []
    private(set) var startedAt = Date()
    private var workspaceWatcher: FileWatcher?
    private var lastWorkspaceWrite = Date.distantPast
    private var heartbeat: Task<Void, Never>?
    private var helperStatusTask: Task<Void, Never>?

    private var providers: [any Provider] {
        [apps, system, media, calendar, focus, bot, whoop, weather, portfolio, git]
    }

    private init() {
        workspace = JSONStore.load(Workspace.self, from: Paths.workspace) ?? DefaultWorkspace.make()
        integrations = JSONStore.load(IntegrationSettings.self, from: Paths.integrations) ?? IntegrationSettings()
    }

    // MARK: Lifecycle

    func start() {
        startedAt = .now
        if !FileManager.default.fileExists(atPath: Paths.workspace.path) { saveWorkspace() }
        if !FileManager.default.fileExists(atPath: Paths.integrations.path) { saveIntegrations() }
        workspaceWatcher = FileWatcher(url: Paths.workspace) { [weak self] in self?.workspaceFileChanged() }

        server.onConnection = { [weak self] connection in
            self?.accept(NWByteStream(connection), transport: .wifi)
        }
        server.start()
        localAPI.start()
        usb.start()

        // Event-driven, effectively free: always on.
        context.start()
        audio.start()
        apps.startObserving()
        daily.load()
        timers.load()
        permissions.refresh()
        apns.load()
        bot.configure(integrations.bot)
        whoop.configure(integrations.whoop)
        portfolio.configure(integrations.portfolio)

        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.pruneStaleSessions()
            }
        }
        observeSleep()
        scheduleHelperStatus()
        Log.shared.info("ControlCenter Helper \(MacInfo.helperVersion) started on \(MacInfo.model)")
    }

    func shutdown() {
        for record in sessions.values {
            record.session.send(.bye(Bye(.quitting)))
        }
        server.stop()
        localAPI.stop()
    }

    // MARK: Sessions

    @discardableResult
    func accept(_ stream: ByteStream, transport: LinkTransport) -> ClientSession {
        let session = ClientSession(stream: stream, transport: transport)
        Task {
            if let nw = stream as? NWByteStream {
                do {
                    try await nw.start(timeout: 10)
                } catch {
                    Log.shared.warning("Incoming connection failed: \(error.localizedDescription)")
                    session.close()
                    return
                }
            }
            await session.run(
                identity: identity,
                registry: devices,
                presenter: pairing,
                onAuthenticated: { [weak self] session, peer in self?.authenticated(session, peer) },
                onMessage: { [weak self] session, message in self?.handle(message, from: session) },
                onEnd: { [weak self] session, error in self?.ended(session, error) }
            )
        }
        return session
    }

    private func authenticated(_ session: ClientSession, _ peer: AuthenticatedPeer) {
        // A device reconnecting over USB replaces its Wi-Fi session (and vice versa).
        for (id, record) in sessions where record.device.id == peer.device.deviceID && peer.hello.platform != .widget {
            record.session.send(.bye(Bye(.replaced)))
            record.session.close()
            sessions[id] = nil
        }
        let device = ConnectedDevice(id: peer.device.deviceID, name: peer.device.deviceName, platform: peer.hello.platform, transport: session.transport, latencyMs: nil, connectedAt: .now)
        sessions[session.id] = SessionRecord(session: session, device: device, subscriptions: [], lastSeen: .now)
        if peer.hello.platform != .widget {
            Log.shared.info("\(device.name) connected over \(session.transport.title)")
            daily.clientConnected(workspace.preferences)
        }
        scheduleHelperStatus()
    }

    private func ended(_ session: ClientSession, _ error: Error?) {
        guard let record = sessions.removeValue(forKey: session.id) else {
            if let error, !(error is CancellationError) {
                Log.shared.warning("Handshake ended: \(error.localizedDescription)")
            }
            return
        }
        if record.device.platform != .widget {
            Log.shared.info("\(record.device.name) disconnected")
        }
        recomputeDemand()
        scheduleHelperStatus()
    }

    private func pruneStaleSessions() {
        let now = Date()
        for (id, record) in sessions where now.timeIntervalSince(record.lastSeen) > 20 {
            Log.shared.warning("\(record.device.name) timed out")
            record.session.close()
            sessions[id] = nil
        }
        recomputeDemand()
    }

    var connectedDevices: [ConnectedDevice] {
        sessions.values.map(\.device).filter { $0.platform != .widget }.sorted { $0.connectedAt < $1.connectedAt }
    }

    var hasClients: Bool { !connectedDevices.isEmpty }

    func pairedDevicesChanged(_ devices: [PairedDevice]) {
        pairedDevices = devices.sorted { $0.pairedAt < $1.pairedAt }
    }

    func forget(deviceID: String) {
        Task {
            await devices.remove(deviceID)
            for (id, record) in sessions where record.device.id == deviceID {
                record.session.send(.bye(Bye(.revoked)))
                record.session.close()
                sessions[id] = nil
            }
        }
    }

    // MARK: Messages

    private func handle(_ message: MCCMessage, from session: ClientSession) {
        guard var record = sessions[session.id] else { return }
        record.lastSeen = .now
        sessions[session.id] = record

        switch message.body {
        case .ping(let ping):
            session.send(.pong(ping), replyTo: message.id)

        case .pong(let ping):
            // Clients echo our latency probes; also accept client-reported RTT.
            let rtt = (Date().timeIntervalSince1970 - ping.t) * 1000
            sessions[session.id]?.device.latencyMs = rtt

        case .subscribe(let subscribe):
            let channels = Set(subscribe.channels).union(Channel.always)
            sessions[session.id]?.subscriptions = channels
            recomputeDemand()
            session.send(.liveDataUpdate(LiveDataUpdate(values: state.values(for: channels), full: true)), replyTo: message.id)

        case .requestSnapshot(let subscribe):
            Task {
                await refresh(Set(subscribe.channels))
                session.send(.liveDataUpdate(LiveDataUpdate(values: state.values(for: subscribe.channels), full: true)), replyTo: message.id)
            }

        case .requestLayout(let request):
            if request.knownRevision != workspace.revision {
                session.send(.buttonConfigUpdate(workspace), replyTo: message.id)
            } else {
                session.send(.actionResult(.success), replyTo: message.id)
            }

        case .updateLayout(let update):
            if update.baseRevision == workspace.revision {
                applyWorkspace(update.workspace, from: session)
                session.send(.actionResult(.success), replyTo: message.id)
            } else {
                session.send(.actionResult(.failure("Layout changed on another device — reloaded.")), replyTo: message.id)
                session.send(.buttonConfigUpdate(workspace))
            }

        case .buttonTap(let tap):
            let origin = ActionOrigin(sessionID: session.id, deviceName: record.device.name, platform: record.device.platform, pageID: tap.pageID)
            Task {
                let started = Date()
                var result = await executor.run(tap.action, origin: origin)
                result.durationMs = Int(Date().timeIntervalSince(started) * 1000)
                session.send(.actionResult(result), replyTo: message.id)
            }

        case .requestIcons(let request):
            Task {
                let icons = await apps.icons(for: request.bundleIDs, size: request.size)
                session.send(.icons(Icons(icons: icons)), replyTo: message.id)
            }

        case .requestArtwork(let request):
            Task {
                let data = await media.artwork(id: request.id)
                session.send(.artwork(Artwork(id: request.id, data: data)), replyTo: message.id)
            }

        case .query(let query):
            Task {
                let result = await answer(query)
                session.send(.queryResult(result), replyTo: message.id)
            }

        case .recordMacro(let record):
            MacroRecorder.shared.handle(record.command, for: session)

        case .registerPushToken(let registration):
            apns.register(registration, deviceID: record.device.id)
            session.send(.actionResult(.success), replyTo: message.id)

        case .updateIntegrations(let settings):
            applyIntegrations(settings)
            session.send(.actionResult(.success), replyTo: message.id)

        default:
            break
        }
    }

    // MARK: Publishing

    func publish(_ value: ChannelValue) {
        guard state.apply(value) else { return }
        let channel = value.channel
        for record in sessions.values where record.subscriptions.contains(channel) {
            if case .context(let context) = value {
                record.session.send(.appDidChange(context))
            } else {
                record.session.send(.liveDataUpdate(LiveDataUpdate(values: [value], full: false)))
            }
        }
        switch channel {
        case .bot, .timers, .whoop:
            apns.stateChanged(state)
        case .context:
            git.contextChanged()
        default:
            break
        }
    }

    func broadcast(_ body: MCCBody, platforms: Set<DevicePlatform> = [.iPad, .iPhone, .mac]) {
        for record in sessions.values where platforms.contains(record.device.platform) {
            record.session.send(body)
        }
    }

    func send(_ body: MCCBody, to sessionID: UUID) {
        sessions[sessionID]?.session.send(body)
    }

    func toast(_ toast: Toast) {
        broadcast(.toast(toast))
    }

    // MARK: Demand

    /// Start the providers someone is watching, stop the rest.
    func recomputeDemand() {
        let wanted = sessions.values.reduce(into: Set<Channel>()) { $0.formUnion($1.subscriptions) }
        for provider in providers {
            provider.setActive(!provider.channels.isDisjoint(with: wanted))
        }
        context.setClientsConnected(hasClients)
    }

    /// One-shot refresh for widgets and intents, bounded to 2.5 s.
    func refresh(_ channels: Set<Channel>) async {
        let targets = providers.filter { !$0.channels.isDisjoint(with: channels) }
        let (signal, finish) = AsyncStream.makeStream(of: Void.self)
        Task { @MainActor in
            for provider in targets { await provider.refreshNow() }
            finish.finish()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            finish.finish()
        }
        for await _ in signal {}
    }

    // MARK: Workspace

    func applyWorkspace(_ incoming: Workspace, from session: ClientSession? = nil) {
        var next = incoming
        next.revision = workspace.revision + 1
        workspace = next
        saveWorkspace()
        broadcast(.buttonConfigUpdate(workspace))
        weather.preferencesChanged()
        Log.shared.info("Layout updated (revision \(workspace.revision))")
    }

    func resetWorkspace() {
        var fresh = DefaultWorkspace.make(preferences: workspace.preferences)
        fresh.revision = workspace.revision
        applyWorkspace(fresh)
    }

    private func saveWorkspace() {
        lastWorkspaceWrite = .now
        JSONStore.save(workspace, to: Paths.workspace)
    }

    /// You edited workspace.json in your editor: hot-reload every iPad.
    private func workspaceFileChanged() {
        guard Date().timeIntervalSince(lastWorkspaceWrite) > 1.5 else { return }
        guard let edited = JSONStore.load(Workspace.self, from: Paths.workspace), edited != workspace else { return }
        var next = edited
        next.revision = workspace.revision + 1
        workspace = next
        broadcast(.buttonConfigUpdate(workspace))
        Log.shared.info("Reloaded workspace.json from disk (revision \(workspace.revision))")
    }

    // MARK: Integrations

    func applyIntegrations(_ incoming: IntegrationSettings) {
        var settings = incoming
        if let secrets = incoming.secrets {
            for (key, value) in secrets {
                Secrets.set(value.isEmpty ? nil : value, for: key)
            }
            settings.secrets = nil
        }
        settings.bot.hasAPIKey = Secrets.get(IntegrationSettings.SecretKey.botAPIKey) != nil
        settings.whoop.hasClientSecret = Secrets.get(IntegrationSettings.SecretKey.whoopClientSecret) != nil
        settings.whoop.connected = whoop.isConnected
        settings.portfolio.hasAuthValue = Secrets.get(IntegrationSettings.SecretKey.portfolioAuth) != nil
        integrations = settings
        saveIntegrations()
        bot.configure(settings.bot)
        whoop.configure(settings.whoop)
        portfolio.configure(settings.portfolio)
        git.configure(settings.gitRepositories)
        recomputeDemand()
        scheduleHelperStatus()
    }

    func updateIntegrations(_ change: (inout IntegrationSettings) -> Void) {
        var copy = integrations
        change(&copy)
        applyIntegrations(copy)
    }

    private func saveIntegrations() {
        JSONStore.save(integrations, to: Paths.integrations)
    }

    // MARK: Queries

    private func answer(_ query: Query) async -> QueryResult {
        switch query.kind {
        case .shortcuts:
            let names = await ShortcutsCLI.list()
            return QueryResult(kind: .shortcuts, items: names.map { QueryItem(id: $0, title: $0) })
        case .installedApps:
            let found = await apps.installedApps()
            return QueryResult(kind: .installedApps, items: found.map { QueryItem(id: $0.bundleID, title: $0.name, subtitle: $0.bundleID) })
        case .runningApps:
            let running = state.apps?.apps ?? []
            return QueryResult(kind: .runningApps, items: running.map { QueryItem(id: $0.bundleID, title: $0.name, subtitle: $0.bundleID) })
        case .focusModes:
            await focus.refreshShortcuts()
            return QueryResult(kind: .focusModes, items: (state.focus?.available ?? []).map { QueryItem(id: $0, title: $0) })
        case .integrations:
            var settings = integrations
            settings.whoop.connected = whoop.isConnected
            return QueryResult(kind: .integrations, items: [], integrations: settings)
        case .repositories:
            return QueryResult(kind: .repositories, items: (state.git?.repos ?? []).map { QueryItem(id: $0.path, title: $0.name, subtitle: $0.branch) })
        case .permissions:
            permissions.refresh()
            return QueryResult(kind: .permissions, items: permissions.statuses.map { QueryItem(id: $0.kind.rawValue, title: $0.kind.title, subtitle: $0.granted ? "Granted" : "Not granted") })
        }
    }

    // MARK: Helper status channel

    func scheduleHelperStatus() {
        helperStatusTask?.cancel()
        helperStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            self.publish(.helper(self.helperStatus()))
        }
    }

    func helperStatus() -> HelperStatus {
        HelperStatus(
            version: MacInfo.helperVersion,
            macName: identity.macName,
            model: MacInfo.model,
            osVersion: MacInfo.osVersion,
            permissions: permissions.statuses,
            integrations: integrationStatuses(),
            devices: connectedDevices
        )
    }

    func integrationStatuses() -> [IntegrationStatus] {
        var result: [IntegrationStatus] = []
        switch integrations.bot.mode {
        case .off: result.append(IntegrationStatus(id: .bot, health: .off, detail: "Off"))
        case .simulated: result.append(IntegrationStatus(id: .bot, health: .ok, detail: "Simulated"))
        case .live:
            let bot = state.bot
            if bot?.apiConnected == true {
                result.append(IntegrationStatus(id: .bot, health: .ok, detail: bot?.status.title ?? "Connected"))
            } else {
                result.append(IntegrationStatus(id: .bot, health: .error, detail: bot?.error ?? "Not reachable"))
            }
        }
        if !whoop.isConfigured {
            result.append(IntegrationStatus(id: .whoop, health: .needsSetup, detail: "Add client ID and secret"))
        } else if !whoop.isConnected {
            result.append(IntegrationStatus(id: .whoop, health: .needsSetup, detail: "Not signed in"))
        } else if let error = state.whoop?.error {
            result.append(IntegrationStatus(id: .whoop, health: .warning, detail: error))
        } else {
            result.append(IntegrationStatus(id: .whoop, health: .ok, detail: state.whoop?.recovery.map { "Recovery \(Int($0))%" } ?? "Connected"))
        }
        result.append(IntegrationStatus(id: .weather, health: integrations.weatherEnabled ? .ok : .off, detail: workspace.preferences.weatherLocation))
        if integrations.portfolio.enabled {
            let error = state.portfolio?.error
            result.append(IntegrationStatus(id: .portfolio, health: error == nil ? .ok : .warning, detail: error ?? state.portfolio?.totalEur.map { Fmt.compactMoney($0) } ?? "Waiting"))
        } else {
            result.append(IntegrationStatus(id: .portfolio, health: .off, detail: "Off"))
        }
        switch calendar.access {
        case .granted: result.append(IntegrationStatus(id: .calendar, health: .ok, detail: "\(state.calendar?.events.count ?? 0) events"))
        case .denied: result.append(IntegrationStatus(id: .calendar, health: .error, detail: "Access denied"))
        default: result.append(IntegrationStatus(id: .calendar, health: .needsSetup, detail: "Not yet granted"))
        }
        let focusCount = state.focus?.available.count ?? 0
        result.append(IntegrationStatus(id: .focus, health: focusCount > 0 ? .ok : .needsSetup, detail: focusCount > 0 ? "\(focusCount) Focus shortcuts" : "Create “Focus: …” shortcuts"))
        result.append(IntegrationStatus(id: .media, health: .ok, detail: state.media?.nowPlaying?.source.title ?? "Nothing playing"))
        result.append(IntegrationStatus(id: .git, health: .ok, detail: state.git?.current?.name ?? "No repository"))
        return result
    }

    // MARK: Sleep

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Log.shared.info("Mac going to sleep")
                Hub.shared.broadcast(.bye(Bye(.sleeping)))
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Log.shared.info("Mac woke up")
                Hub.shared.server.start()
            }
        }
    }
}

/// Where an action came from — lets `navigate` reach the right screen.
struct ActionOrigin: Sendable {
    var sessionID: UUID?
    var deviceName: String
    var platform: DevicePlatform
    var pageID: String?

    static let local = ActionOrigin(sessionID: nil, deviceName: "Mac", platform: .mac, pageID: nil)
}

/// Secrets live in the helper's Keychain, never in JSON.
enum Secrets {
    private static let keychain = Keychain(service: "be.yorben.controlcenter.helper.secrets")

    static func get(_ key: String) -> String? { keychain.string(key) }

    static func set(_ value: String?, for key: String) {
        keychain.set(value, for: key)
    }
}
