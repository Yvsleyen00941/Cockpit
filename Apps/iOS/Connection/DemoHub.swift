import CCCore
import Foundation
import Observation

/// An in-process stand-in for the Mac: a simulated bot, WHOOP, calendar,
/// weather, system stats and music, with working timers, Focus, priorities,
/// mic and scenes. Lets you explore every screen before pairing — and makes
/// screenshots and previews honest to the real layouts.
@MainActor
@Observable
final class DemoHub: HubLink {
    private(set) var status: LinkStatus = .idle
    let transport: LinkTransport = .demo
    private(set) var latencyMs: Double? = 3.4
    let isDegraded = false
    let macName: String? = "MacBook Pro"
    let lastError: String? = nil
    var onMessage: ((MCCMessage) -> Void)?
    var onConnected: (() -> Void)?

    private var state = LiveState()
    private var workspace = DefaultWorkspace.make()
    private var bot = BotSimulation(now: .now)
    private var botPaused = false
    private var ticker: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var contextIndex = 0

    private static let contexts: [ActiveContext] = [
        DemoData.context(now: .now),
        ActiveContext(bundleID: Bundles.xcode, appName: "Xcode", windowTitle: "ControlCenter — HubConnection.swift"),
        ActiveContext(bundleID: Bundles.notion, appName: "Notion", windowTitle: "Statistics — Week 4"),
        ActiveContext(bundleID: Bundles.terminal, appName: "Terminal", windowTitle: "yorben — zsh — 120×32"),
        ActiveContext(bundleID: Bundles.finder, appName: "Finder", windowTitle: "Downloads"),
    ]

    func start() {
        let now = Date()
        state.context = ProcessInfo.processInfo.arguments.contains("-CCDemoHome")
            ? ActiveContext(bundleID: "com.apple.systempreferences", appName: "System Settings")
            : DemoData.context(now: now)
        if ProcessInfo.processInfo.arguments.contains("-CCDemoLocked") {
            // Screenshots and testing: the demo Mac is locked, so the iPad goes ambient.
            state.context?.presence = .locked
        }
        state.apps = DemoData.apps
        state.system = DemoData.system(now: now)
        state.media = DemoData.media(now: now)
        state.audio = DemoData.audio
        state.calendar = DemoData.calendar(now: now)
        state.focus = DemoData.focusOff
        state.whoop = DemoData.whoop(now: now)
        state.weather = DemoData.weather(now: now)
        state.timers = TimersState(timers: [], nextSession: 2)
        state.daily = DemoData.daily(now: now)
        state.portfolio = DemoData.portfolio(now: now)
        state.git = DemoData.git(now: now)
        state.helper = DemoData.helper(now: now)
        publishBot(now: now)
        status = .connected
        onConnected?()
        emit(.buttonConfigUpdate(workspace))
        emit(.liveDataUpdate(LiveDataUpdate(values: state.values(for: Channel.allCases), full: true)))

        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        timerTask?.cancel()
        status = .idle
    }

    func appBecameActive() {}

    // MARK: Ticking

    private func tick() {
        let now = Date()
        let fresh = bot.step(to: now)
        publishBot(now: now)
        for event in fresh where event.isTrade {
            emit(.toast(Toast(title: "\(event.kind == .buy ? "BUY" : "SELL") \(event.symbol ?? "")", message: [event.quantity.map { "\(Fmt.quantity($0)) @ \(Fmt.price(event.price ?? 0))" }, event.pnl.map { Fmt.money($0, signed: true) }].compactMap { $0 }.joined(separator: " · "), style: .trade, symbol: event.kind == .buy ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")))
        }
        update(.system(DemoData.system(now: now)))
        latencyMs = 2.6 + Double.random(in: 0...1.8)
    }

    private func publishBot(now: Date) {
        var botState = bot.state(now: now)
        if botPaused { botState.status = .paused }
        update(.bot(botState))
        update(.botSeries(bot.pnlSeries))
        update(.botEvents(bot.eventLog))
    }

    private func update(_ value: ChannelValue) {
        guard state.apply(value) else { return }
        if case .context(let context) = value {
            emit(.appDidChange(context))
        } else {
            emit(.liveDataUpdate(LiveDataUpdate(values: [value], full: false)))
        }
    }

    private func emit(_ body: MCCBody, replyTo: UInt32? = nil) {
        let message = MCCMessage(body, replyTo: replyTo)
        onMessage?(message)
    }

    // MARK: Requests

    func send(_ body: MCCBody) {
        Task { @MainActor in _ = await respond(to: body) }
    }

    func request(_ body: MCCBody, timeout: TimeInterval) async throws -> MCCMessage {
        await respond(to: body)
    }

    @discardableResult
    private func respond(to body: MCCBody) async -> MCCMessage {
        switch body {
        case .buttonTap(let tap):
            let result = await run(tap.action)
            return MCCMessage(.actionResult(result))
        case .subscribe(let subscribe):
            let message = MCCMessage(.liveDataUpdate(LiveDataUpdate(values: state.values(for: Set(subscribe.channels).union(Channel.always)), full: true)))
            onMessage?(message)
            return message
        case .requestSnapshot(let subscribe):
            return MCCMessage(.liveDataUpdate(LiveDataUpdate(values: state.values(for: subscribe.channels), full: true)))
        case .requestLayout:
            emit(.buttonConfigUpdate(workspace))
            return MCCMessage(.buttonConfigUpdate(workspace))
        case .updateLayout(let update):
            var next = update.workspace
            next.revision = workspace.revision + 1
            workspace = next
            emit(.buttonConfigUpdate(workspace))
            return MCCMessage(.actionResult(.success))
        case .query(let query):
            return MCCMessage(.queryResult(demoQuery(query)))
        case .ping(let ping):
            return MCCMessage(.pong(ping))
        case .recordMacro(let record):
            if record.command == .start {
                emit(.macroRecording(MacroRecording(steps: [], recording: true)))
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.2))
                    let steps = [MacroStep(.keyCombo(KeyCombo("cmd+c")), delay: 0.3), MacroStep(.keyCombo(KeyCombo("cmd+tab")), delay: 0.4), MacroStep(.keyCombo(KeyCombo("cmd+v")))]
                    self?.emit(.macroRecording(MacroRecording(steps: steps, recording: true)))
                }
            } else {
                emit(.macroRecording(MacroRecording(steps: [MacroStep(.keyCombo(KeyCombo("cmd+c")), delay: 0.3), MacroStep(.keyCombo(KeyCombo("cmd+tab")), delay: 0.4), MacroStep(.keyCombo(KeyCombo("cmd+v")))], recording: false)))
            }
            return MCCMessage(.actionResult(.success))
        default:
            return MCCMessage(.actionResult(.success))
        }
    }

    private func demoQuery(_ query: Query) -> QueryResult {
        switch query.kind {
        case .shortcuts:
            return QueryResult(kind: .shortcuts, items: ["Focus: Deep Work", "Focus: Study", "Focus: Off", "Desk Lamp On", "Log Water"].map { QueryItem(id: $0, title: $0) })
        case .installedApps, .runningApps:
            return QueryResult(kind: query.kind, items: (state.apps?.apps ?? []).map { QueryItem(id: $0.bundleID, title: $0.name, subtitle: $0.bundleID) })
        case .focusModes:
            return QueryResult(kind: .focusModes, items: ["Deep Work", "Study", "Do Not Disturb"].map { QueryItem(id: $0, title: $0) })
        case .integrations:
            return QueryResult(kind: .integrations, items: [], integrations: IntegrationSettings())
        default:
            return QueryResult(kind: query.kind, items: [])
        }
    }

    // MARK: Actions

    private func run(_ action: ButtonAction) async -> ActionResult {
        let now = Date()
        switch action {
        case .bot(let command):
            switch command {
            case .pause:
                botPaused = true
                _ = bot.pause(at: now)
            case .resume:
                botPaused = false
                _ = bot.resume(at: now)
            case .closeAll:
                _ = bot.closeAll(at: now)
            case .refresh:
                break
            }
            publishBot(now: now)
            return ActionResult(ok: true, message: command.title)

        case .timer(let command):
            return handleTimer(command)

        case .focus(let command):
            var focus = state.focus ?? DemoData.focusOff
            switch command.command {
            case .on:
                focus.active = true
                focus.name = command.name ?? workspace.preferences.focusName
            case .off:
                focus.active = false
                focus.name = nil
            case .toggle:
                focus.active.toggle()
                focus.name = focus.active ? (command.name ?? workspace.preferences.focusName) : nil
            }
            update(.focus(focus))
            return .success

        case .audio(let command):
            guard var audio = state.audio else { return .success }
            switch command.command {
            case .micToggle: audio.inputMuted.toggle()
            case .micMute: audio.inputMuted = true
            case .micUnmute: audio.inputMuted = false
            case .outputMuteToggle: audio.outputMuted.toggle()
            case .setOutputVolume: audio.outputVolume = command.value ?? audio.outputVolume
            case .setInputVolume: audio.inputVolume = command.value ?? audio.inputVolume
            }
            update(.audio(audio))
            return .success

        case .call(.toggleMute):
            return await run(.audio(AudioCommand(.micToggle)))

        case .media(let command):
            if command == .playPause, var media = state.media, var track = media.nowPlaying {
                track.position = track.position(at: now)
                track.positionAt = now
                track.isPlaying.toggle()
                media.nowPlaying = track
                update(.media(media))
            }
            return .success

        case .daily(let command):
            guard var daily = state.daily else { return .success }
            switch command.command {
            case .setPriority:
                if let index = command.index, daily.priorities.indices.contains(index) { daily.priorities[index].text = command.text ?? "" }
            case .togglePriority:
                if let index = command.index, daily.priorities.indices.contains(index) { daily.priorities[index].done.toggle() }
            case .clearPriorities:
                daily.priorities = [Priority(text: ""), Priority(text: ""), Priority(text: "")]
            case .carryOver:
                break
            case .setStudyMode:
                daily.studyMode = command.enabled ?? !daily.studyMode
            case .dismissBrief:
                daily.briefPending = false
            case .startDay:
                daily.dayStarted = true
                daily.briefPending = false
            }
            update(.daily(daily))
            return .success

        case .scene(let id):
            guard let scene = workspace.scene(id) else { return .failure("Unknown scene") }
            for step in scene.steps { _ = await run(step.action) }
            if let page = scene.page { emit(.directive(Directive(.navigate, page: page))) }
            return ActionResult(ok: true, message: scene.name)

        case .macro(let steps):
            for step in steps { _ = await run(step.action) }
            return .success

        case .navigate(let page):
            emit(.directive(Directive(.navigate, page: page)))
            return .success

        case .app(let control) where control.command == .activate:
            if let app = state.apps?.apps.first(where: { $0.bundleID == control.bundleID }) {
                update(.context(ActiveContext(bundleID: app.bundleID, appName: app.name)))
            }
            return .success

        case .openApp(let ref):
            let name = state.apps?.apps.first { $0.bundleID == ref.bundleID }?.name ?? ref.name ?? ref.bundleID
            update(.context(ActiveContext(bundleID: ref.bundleID, appName: name)))
            return .success

        case .git(let command):
            return ActionResult(ok: true, message: "git \(command.command.rawValue) · ControlCenter", output: command.command == .status ? "## main...origin/main [ahead 1]\n M Apps/iOS/Chrome/TopBar.swift\n M Apps/iOS/Tiles/BotTiles.swift\n?? docs/DESIGN.md" : nil)

        default:
            // Everything else would run on the Mac.
            return ActionResult(ok: true, message: "Demo · \(action.summary)")
        }
    }

    private func handleTimer(_ command: TimerCommand) -> ActionResult {
        let now = Date()
        var timers = state.timers ?? TimersState(timers: [], nextSession: 1)
        let preferences = workspace.preferences
        switch command.command {
        case .start:
            let preset = command.preset ?? TimerPreset(kind: .pomodoro)
            let minutes = preset.minutes ?? preferences.minutes(for: preset.kind)
            timers.timers = [TimerState(kind: preset.kind, label: preset.label ?? preset.kind.title, duration: minutes * 60, state: .running, startedAt: now, endsAt: now.addingTimeInterval(minutes * 60), session: timers.nextSession, sessionsPerCycle: preferences.sessionsPerCycle, focusDuring: preset.focus ?? false)]
            if preset.focus == true { Task { _ = await run(.focus(FocusCommand(.on))) } }
        case .pause:
            if var timer = timers.primary, timer.state == .running {
                timer.remainingWhenPaused = timer.remaining(at: now)
                timer.state = .paused
                timer.endsAt = nil
                timers.timers = [timer]
            }
        case .resume:
            if var timer = timers.primary, timer.state == .paused {
                timer.endsAt = now.addingTimeInterval(timer.remainingWhenPaused ?? timer.duration)
                timer.remainingWhenPaused = nil
                timer.state = .running
                timers.timers = [timer]
            }
        case .toggle:
            if let timer = timers.primary {
                return handleTimer(TimerCommand(timer.state == .running ? .pause : .resume))
            }
            return handleTimer(.start(.pomodoro))
        case .reset:
            if var timer = timers.primary {
                timer.state = .paused
                timer.remainingWhenPaused = timer.duration
                timer.endsAt = nil
                timers.timers = [timer]
            }
        case .stop, .skip:
            if timers.primary?.focusDuring == true { Task { _ = await run(.focus(FocusCommand(.off))) } }
            timers.timers = []
        case .extend:
            if var timer = timers.primary {
                let seconds = command.seconds ?? 300
                timer.duration += seconds
                timer.endsAt = timer.endsAt?.addingTimeInterval(seconds)
                timer.remainingWhenPaused = timer.remainingWhenPaused.map { $0 + seconds }
                timers.timers = [timer]
            }
        case .setFocus:
            if var timer = timers.primary {
                timer.focusDuring = command.enabled ?? !timer.focusDuring
                timers.timers = [timer]
                let on = timer.focusDuring
                Task { _ = await run(.focus(FocusCommand(on ? .on : .off))) }
            }
        }
        update(.timers(timers))
        return .success
    }

    /// Cycles the pretend frontmost app — "Next app" in demo settings.
    func cycleContext() {
        contextIndex = (contextIndex + 1) % Self.contexts.count
        var context = Self.contexts[contextIndex]
        context.since = .now
        update(.context(context))
    }

    func setContext(_ bundleID: String) {
        guard let context = Self.contexts.first(where: { $0.bundleID == bundleID }) else { return }
        update(.context(context))
    }
}
