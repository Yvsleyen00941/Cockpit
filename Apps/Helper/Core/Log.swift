import Foundation
import Observation
import os

/// Thread-safe logging front: os.Logger plus a tail kept for the Preferences
/// "Activity" pane.
final class Log: Sendable {
    static let shared = Log()

    private let hub = Logger(subsystem: "be.yorben.controlcenter.helper", category: "hub")
    private let actions = Logger(subsystem: "be.yorben.controlcenter.helper", category: "action")

    func info(_ message: String) {
        hub.info("\(message, privacy: .public)")
        LogStore.append(.info, message)
    }

    func action(_ message: String) {
        actions.notice("\(message, privacy: .public)")
        LogStore.append(.action, message)
    }

    func warning(_ message: String) {
        hub.warning("\(message, privacy: .public)")
        LogStore.append(.warning, message)
    }

    func error(_ message: String) {
        hub.error("\(message, privacy: .public)")
        LogStore.append(.error, message)
    }
}

@MainActor
@Observable
final class LogStore {
    static let shared = LogStore()

    struct Entry: Identifiable, Hashable {
        enum Level: String, Sendable { case info, action, warning, error }
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    private(set) var entries: [Entry] = []

    nonisolated static func append(_ level: Entry.Level, _ message: String) {
        let date = Date()
        Task { @MainActor in
            shared.entries.append(Entry(date: date, level: level, message: message))
            if shared.entries.count > 400 { shared.entries.removeFirst(shared.entries.count - 400) }
        }
    }

    func clear() { entries.removeAll() }
}
