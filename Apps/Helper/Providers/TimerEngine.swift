import AppKit
import CCCore
import Foundation
import UserNotifications

/// Pomodoro and deep-work timers, owned by the Mac so every surface agrees:
/// clients receive `endsAt` and count down locally (the iPad, the iPhone Live
/// Activity and the menu bar never drift, and no tick crosses the network).
///
/// A timer can own Focus: turning it on at start and off at the end — the
/// Study page's "do not disturb until the timer ends".
@MainActor
final class TimerEngine {
    private(set) var state = TimersState(timers: [], nextSession: 1)
    private var completion: Task<Void, Never>?
    private var focusOwnedByTimer = false

    var primary: TimerState? { state.primary }

    func load() {
        if let saved = JSONStore.load(TimersState.self, from: Paths.timers) {
            state = saved
            state.timers.removeAll { $0.state == .finished }
            if let running = state.timers.first(where: { $0.state == .running }), let end = running.endsAt, end < .now {
                state.timers.removeAll()
            }
        }
        schedule()
        publish()
    }

    private func publish() {
        Hub.shared.publish(.timers(state))
        JSONStore.save(state, to: Paths.timers)
    }

    // MARK: Commands

    func handle(_ command: TimerCommand) async -> ActionResult {
        let preferences = Hub.shared.workspace.preferences
        switch command.command {
        case .start:
            await start(command.preset ?? TimerPreset(kind: .pomodoro))
            return ActionResult(ok: true, message: "\(primary?.label ?? "Timer") started")
        case .pause:
            pause()
        case .resume:
            resume()
        case .toggle:
            if let timer = primary {
                timer.state == .running ? pause() : resume()
            } else {
                await start(TimerPreset(kind: .pomodoro, minutes: preferences.pomodoroMinutes))
            }
        case .reset:
            guard var timer = primary else { break }
            timer.state = .paused
            timer.remainingWhenPaused = timer.duration
            timer.endsAt = nil
            replace(timer)
        case .stop:
            completion?.cancel()
            state.timers.removeAll()
            publish()
            await releaseFocus()
        case .skip:
            guard let timer = primary else { break }
            await complete(timer, counted: false)
        case .extend:
            guard var timer = primary else { break }
            let seconds = command.seconds ?? 300
            timer.duration += seconds
            if timer.state == .running { timer.endsAt = timer.endsAt?.addingTimeInterval(seconds) }
            else { timer.remainingWhenPaused = (timer.remainingWhenPaused ?? 0) + seconds }
            replace(timer)
        case .setFocus:
            guard var timer = primary else { return .failure("No timer running") }
            let enabled = command.enabled ?? !timer.focusDuring
            timer.focusDuring = enabled
            replace(timer)
            if enabled, timer.state == .running {
                let result = await Hub.shared.focus.set(on: true, name: preferences.focusName)
                focusOwnedByTimer = result.ok
                if !result.ok { return result }
            } else if !enabled {
                await releaseFocus()
            }
        }
        return .success
    }

    private func start(_ preset: TimerPreset) async {
        let preferences = Hub.shared.workspace.preferences
        let minutes = preset.minutes ?? preferences.minutes(for: preset.kind)
        let wantsFocus = preset.focus ?? false
        if focusOwnedByTimer, !wantsFocus { await releaseFocus() }
        let now = Date()
        let timer = TimerState(
            kind: preset.kind,
            label: preset.label ?? preset.kind.title,
            duration: minutes * 60,
            state: .running,
            startedAt: now,
            endsAt: now.addingTimeInterval(minutes * 60),
            session: preset.kind == .pomodoro ? state.nextSession : (primary?.session ?? state.nextSession),
            sessionsPerCycle: preferences.sessionsPerCycle,
            focusDuring: wantsFocus
        )
        state.timers = [timer]
        schedule()
        publish()
        Log.shared.action("Timer: \(timer.label) \(Int(minutes)) min")
        if wantsFocus, !focusOwnedByTimer {
            let result = await Hub.shared.focus.set(on: true, name: preset.focusName ?? preferences.focusName)
            focusOwnedByTimer = result.ok
        }
    }

    private func pause() {
        guard var timer = primary, timer.state == .running else { return }
        timer.remainingWhenPaused = timer.remaining(at: .now)
        timer.state = .paused
        timer.endsAt = nil
        replace(timer)
    }

    private func resume() {
        guard var timer = primary, timer.state == .paused else { return }
        timer.endsAt = Date().addingTimeInterval(timer.remainingWhenPaused ?? timer.duration)
        timer.remainingWhenPaused = nil
        timer.state = .running
        replace(timer)
    }

    private func replace(_ timer: TimerState) {
        state.timers = [timer]
        schedule()
        publish()
    }

    private func schedule() {
        completion?.cancel()
        guard let timer = primary, timer.state == .running, let end = timer.endsAt else { return }
        completion = Task { @MainActor [weak self] in
            let wait = max(0, end.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self, let current = self.primary, current.id == timer.id, current.state == .running else { return }
            await self.complete(current, counted: true)
        }
    }

    private func complete(_ timer: TimerState, counted: Bool) async {
        completion?.cancel()
        let preferences = Hub.shared.workspace.preferences
        state.timers.removeAll()
        var next: TimerPreset?
        var title = "\(timer.label) complete"
        var message = ""

        switch timer.kind {
        case .pomodoro:
            if counted { Hub.shared.daily.pomodoroCompleted(minutes: timer.duration / 60) }
            let longBreak = timer.session >= timer.sessionsPerCycle
            state.nextSession = longBreak ? 1 : timer.session + 1
            let breakKind: TimerKind = longBreak ? .longBreak : .shortBreak
            message = longBreak ? "Cycle done — take \(Int(preferences.longBreakMinutes)) minutes." : "Take \(Int(preferences.shortBreakMinutes)) minutes."
            if preferences.autoStartBreaks { next = TimerPreset(kind: breakKind) }
        case .deepWork, .custom:
            if counted { Hub.shared.daily.addFocusMinutes(timer.duration / 60) }
            message = "\(Fmt.duration(timer.duration)) of focus logged."
        case .shortBreak, .longBreak:
            title = "Break over"
            message = "Ready for session \(state.nextSession)?"
        }

        if timer.focusDuring || focusOwnedByTimer { await releaseFocus() }
        publish()

        Hub.shared.toast(Toast(title: title, message: message, style: .success, symbol: timer.kind.isBreak ? "cup.and.saucer.fill" : "checkmark.seal.fill"))
        Hub.shared.broadcast(.directive(Directive(.chime)))
        NSSound(named: "Glass")?.play()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "timer", content: content, trigger: nil))

        if let next { await start(next) }
    }

    private func releaseFocus() async {
        guard focusOwnedByTimer else { return }
        focusOwnedByTimer = false
        _ = await Hub.shared.focus.set(on: false, name: nil)
    }
}

/// The day: priorities, Pomodoro count, focus minutes, study mode and the
/// Morning Brief's "first connection of the day" trigger.
@MainActor
final class DailyStore {
    private struct Persisted: Codable {
        var state: DailyState
        var briefShownDate: String?
    }

    private(set) var state = DailyState(date: DailyStore.today())
    private var briefShownDate: String?
    private var midnight: Task<Void, Never>?

    static func today(_ date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func load() {
        if let saved = JSONStore.load(Persisted.self, from: Paths.daily) {
            state = saved.state
            briefShownDate = saved.briefShownDate
        }
        rollIfNeeded()
        publish()
        scheduleMidnight()
    }

    private func save() {
        JSONStore.save(Persisted(state: state, briefShownDate: briefShownDate), to: Paths.daily)
    }

    private func publish() {
        Hub.shared.publish(.daily(state))
        save()
    }

    private func rollIfNeeded() {
        let today = Self.today()
        guard state.date != today else { return }
        let unfinished = state.priorities.filter { !$0.done && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        state = DailyState(date: today, carryOver: unfinished)
    }

    private func scheduleMidnight() {
        midnight?.cancel()
        let next = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 0, minute: 0, second: 5), matchingPolicy: .nextTime) ?? .now.addingTimeInterval(3600)
        midnight = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(60, next.timeIntervalSinceNow)))
            guard let self, !Task.isCancelled else { return }
            self.rollIfNeeded()
            self.publish()
            self.scheduleMidnight()
        }
    }

    /// First client of the day inside the morning window → show the Brief.
    func clientConnected(_ preferences: WorkspacePreferences) {
        rollIfNeeded()
        let calendar = Calendar.current
        let now = Date()
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if briefShownDate != state.date, minute >= preferences.morningStart, minute < preferences.morningEnd, !state.dayStarted {
            briefShownDate = state.date
            state.briefPending = true
        }
        publish()
    }

    func handle(_ command: DailyCommand) async -> ActionResult {
        rollIfNeeded()
        switch command.command {
        case .setPriority:
            guard let index = command.index, state.priorities.indices.contains(index) else { return .failure("No such priority") }
            state.priorities[index].text = command.text ?? ""
        case .togglePriority:
            guard let index = command.index, state.priorities.indices.contains(index) else { return .failure("No such priority") }
            state.priorities[index].done.toggle()
        case .clearPriorities:
            state.priorities = [Priority(text: ""), Priority(text: ""), Priority(text: "")]
        case .carryOver:
            var queue = state.carryOver
            for index in state.priorities.indices where state.priorities[index].text.isEmpty && !queue.isEmpty {
                state.priorities[index] = Priority(text: queue.removeFirst().text)
            }
            state.carryOver = queue
        case .setStudyMode:
            state.studyMode = command.enabled ?? !state.studyMode
        case .dismissBrief:
            state.briefPending = false
        case .startDay:
            state.dayStarted = true
            state.briefPending = false
        }
        publish()
        if Hub.shared.workspace.preferences.mirrorPrioritiesToReminders,
           [.setPriority, .togglePriority, .clearPriorities, .carryOver].contains(command.command) {
            await Hub.shared.calendar.mirror(state.priorities)
        }
        return .success
    }

    func pomodoroCompleted(minutes: Double) {
        rollIfNeeded()
        state.pomodorosCompleted += 1
        state.focusMinutes += minutes
        publish()
    }

    func addFocusMinutes(_ minutes: Double) {
        rollIfNeeded()
        state.focusMinutes += minutes
        publish()
    }
}
