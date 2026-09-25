import CCCore
import Foundation
import Observation

/// The client's copy of the hub's live state. One observable property per
/// channel, and values are only assigned when they actually change — so a
/// CPU tick re-renders the CPU bar and nothing else.
@MainActor
@Observable
final class LiveStore {
    var context: ActiveContext?
    var apps: RunningApps?
    var system: SystemStats?
    var media: MediaState?
    var audio: AudioState?
    var calendar: CalendarState?
    var focus: FocusInfo?
    var bot: BotState?
    var botSeries: PnLSeries?
    var botEvents: BotEventLog?
    var whoop: WhoopState?
    var weather: WeatherState?
    var timers: TimersState?
    var daily: DailyState?
    var portfolio: PortfolioState?
    var git: GitState?
    var helper: HelperStatus?

    /// Client-side history for sparklines — the Mac never streams history.
    private(set) var cpuHistory: [Double] = []
    private(set) var memoryHistory: [Double] = []
    private(set) var networkHistory: [Double] = []

    func apply(_ value: ChannelValue) {
        switch value {
        case .context(let v): if context != v { context = v }
        case .apps(let v): if apps != v { apps = v }
        case .system(let v):
            if system != v { system = v }
            append(&cpuHistory, v.cpu)
            append(&memoryHistory, v.memFraction)
            append(&networkHistory, v.netIn + v.netOut)
        case .media(let v): if media != v { media = v }
        case .audio(let v): if audio != v { audio = v }
        case .calendar(let v): if calendar != v { calendar = v }
        case .focus(let v): if focus != v { focus = v }
        case .bot(let v): if bot != v { bot = v }
        case .botSeries(let v): if botSeries != v { botSeries = v }
        case .botEvents(let v): if botEvents != v { botEvents = v }
        case .whoop(let v): if whoop != v { whoop = v }
        case .weather(let v): if weather != v { weather = v }
        case .timers(let v): if timers != v { timers = v }
        case .daily(let v): if daily != v { daily = v }
        case .portfolio(let v): if portfolio != v { portfolio = v }
        case .git(let v): if git != v { git = v }
        case .helper(let v): if helper != v { helper = v }
        }
    }

    private func append(_ history: inout [Double], _ value: Double) {
        history.append(value)
        if history.count > 90 { history.removeFirst(history.count - 90) }
    }

    var snapshot: LiveState {
        var state = LiveState()
        state.context = context
        state.apps = apps
        state.system = system
        state.media = media
        state.audio = audio
        state.calendar = calendar
        state.focus = focus
        state.bot = bot
        state.botSeries = botSeries
        state.botEvents = botEvents
        state.whoop = whoop
        state.weather = weather
        state.timers = timers
        state.daily = daily
        state.portfolio = portfolio
        state.git = git
        state.helper = helper
        return state
    }

    func load(_ state: LiveState) {
        for channel in Channel.allCases {
            if let value = state.value(for: channel) { apply(value) }
        }
    }

    var contextInput: ContextInput {
        ContextInput(context: context, focus: focus, calendar: calendar, daily: daily, timers: timers, audio: audio)
    }
}

/// Decides which page is on screen: the context engine's answer, unless you
/// pinned a page, or navigated by hand — a manual choice holds until the
/// context changes (another app, another site, a mode flip).
@MainActor
@Observable
final class Navigator {
    private(set) var pageID = "home"
    private(set) var resolution: Resolution?
    private(set) var pinned: String?
    private var manual: (page: String, key: String)?
    private var currentKey = ""

    var modes: Set<String> { resolution?.modes ?? [] }

    func update(workspace: Workspace, store: LiveStore) {
        let input = store.contextInput
        let resolution = ContextEngine.resolve(workspace, input)
        self.resolution = resolution
        currentKey = ContextEngine.contextKey(input, modes: resolution.modes)

        if let pinned, workspace.page(pinned) != nil {
            set(pinned)
            return
        }
        if let manual {
            if manual.key == currentKey, workspace.page(manual.page) != nil {
                set(manual.page)
                return
            }
            self.manual = nil
        }
        if workspace.preferences.autoSwitch {
            set(resolution.pageID)
        } else if workspace.page(pageID) == nil {
            set("home")
        }
    }

    func show(_ page: String) {
        manual = (page, currentKey)
        if pinned != nil, pinned != page { pinned = page }
        set(page)
    }

    func togglePin() {
        pinned = pinned == nil ? pageID : nil
        if pinned == nil { manual = (pageID, currentKey) }
    }

    private func set(_ id: String) {
        guard id != pageID else { return }
        pageID = id
    }
}
