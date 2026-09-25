import AppKit
import CCCore
import EventKit
import Foundation

/// Today's events and the next 24 hours from every calendar on the Mac,
/// including meeting links (Zoom, Meet, Teams, Webex) turned into "Join" keys.
@MainActor
final class CalendarProvider: PollingProvider {
    override var channels: Set<Channel> { [.calendar] }
    override var interval: TimeInterval { 300 }

    let store = EKEventStore()
    private var observer: NSObjectProtocol?

    var access: AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .denied, .restricted, .writeOnly: .denied
        @unknown default: .denied
        }
    }

    override func didActivate() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { Task { await Hub.shared.calendar.tick() } }
        }
    }

    override func didDeactivate() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    func requestAccess() async {
        guard access == .notDetermined else { return }
        _ = try? await store.requestFullAccessToEvents()
        Hub.shared.permissions.refresh()
        Hub.shared.scheduleHelperStatus()
    }

    override func tick() async {
        if access == .notDetermined { await requestAccess() }
        guard access == .granted else {
            Hub.shared.publish(.calendar(CalendarState(access: access, events: [])))
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = start.addingTimeInterval(36 * 3600)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: "\(event.eventIdentifier ?? UUID().uuidString)@\(Int(event.startDate.timeIntervalSince1970))",
                    title: event.title ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarName: event.calendar?.title ?? "",
                    colorHex: Self.hex(event.calendar?.color),
                    location: event.location?.nilIfEmpty,
                    meetingURL: Self.meetingURL(event)
                )
            }
        Hub.shared.publish(.calendar(CalendarState(access: .granted, events: events)))
    }

    static func meetingURL(_ event: EKEvent) -> String? {
        let haystack = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        let pattern = #"https://[^\s<>"']*(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/(meet|join)|whereby\.com/)[^\s<>"']*"#
        guard let range = haystack.range(of: pattern, options: .regularExpression) else { return nil }
        return String(haystack[range])
    }

    static func hex(_ color: NSColor?) -> String {
        guard let rgb = color?.usingColorSpace(.sRGB) else { return "#2E86AB" }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    // MARK: Reminders mirror

    /// Mirrors the day's top three into a Reminders list, so they're on the
    /// iPhone and Watch too.
    func mirror(_ priorities: [Priority]) async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .notDetermined {
            _ = try? await store.requestFullAccessToReminders()
        }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return }
        let listName = "Top 3 Today"
        let list = store.calendars(for: .reminder).first { $0.title == listName } ?? {
            let created = EKCalendar(for: .reminder, eventStore: store)
            created.title = listName
            created.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local }
            try? store.saveCalendar(created, commit: true)
            return created
        }()
        let predicate = store.predicateForReminders(in: [list])
        let existing: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                nonisolated(unsafe) let result = reminders ?? []
                continuation.resume(returning: result)
            }
        }
        for reminder in existing where (reminder.notes ?? "").contains("ControlCenter") {
            try? store.remove(reminder, commit: false)
        }
        for priority in priorities where !priority.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let reminder = EKReminder(eventStore: store)
            reminder.title = priority.text
            reminder.notes = "ControlCenter"
            reminder.calendar = list
            reminder.isCompleted = priority.done
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            try? store.save(reminder, commit: false)
        }
        try? store.commit()
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
