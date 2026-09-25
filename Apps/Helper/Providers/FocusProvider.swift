import CCCore
import Foundation

/// Focus modes.
///
/// **Setting** Focus uses the only public route macOS offers: Shortcuts. Create
/// one shortcut per mode named `Focus: <Name>` (a single "Set Focus → On"
/// action) plus `Focus: Off`. The helper discovers them automatically.
///
/// **Reading** the active Focus needs Full Disk Access (the Do Not Disturb
/// database lives in `~/Library/DoNotDisturb`). Without it the helper reports
/// the last Focus it set itself.
@MainActor
final class FocusProvider: PollingProvider {
    override var channels: Set<Channel> { [.focus] }
    override var interval: TimeInterval { 20 }

    private var shortcutNames: [String] = []
    private var lastShortcutRefresh = Date.distantPast
    private var lastSet: (active: Bool, name: String?)?
    private var watcher: FileWatcher?

    static let prefix = "Focus: "
    static let offName = "Focus: Off"
    private let assertionsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    private let modesURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/ModeConfigurations.json")

    override func didActivate() {
        if FileManager.default.isReadableFile(atPath: assertionsURL.path) {
            watcher = FileWatcher(url: assertionsURL) { Task { await Hub.shared.focus.tick() } }
        }
    }

    override func didDeactivate() {
        watcher?.stop()
        watcher = nil
    }

    override func tick() async {
        if Date().timeIntervalSince(lastShortcutRefresh) > 600 { await refreshShortcuts() }
        Hub.shared.publish(.focus(read()))
    }

    func refreshShortcuts() async {
        shortcutNames = await ShortcutsCLI.list()
        lastShortcutRefresh = .now
    }

    var available: [String] {
        shortcutNames
            .filter { $0.hasPrefix(Self.prefix) && $0 != Self.offName }
            .map { String($0.dropFirst(Self.prefix.count)) }
            .sorted()
    }

    var canTurnOff: Bool { shortcutNames.contains(Self.offName) }

    private func read() -> FocusState {
        if let system = readSystem() {
            return FocusState(known: true, active: system.active, name: system.name, available: available, canTurnOff: canTurnOff)
        }
        return FocusState(known: false, active: lastSet?.active ?? false, name: lastSet?.name, available: available, canTurnOff: canTurnOff)
    }

    private func readSystem() -> (active: Bool, name: String?)? {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        let records = entries.flatMap { ($0["storeAssertionRecords"] as? [[String: Any]]) ?? [] }
        guard let record = records.last,
              let details = record["assertionDetails"] as? [String: Any],
              let modeID = details["assertionDetailsModeIdentifier"] as? String else {
            return (false, nil)
        }
        return (true, modeName(for: modeID))
    }

    private func modeName(for id: String) -> String? {
        guard let data = try? Data(contentsOf: modesURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        for entry in entries {
            if let configs = entry["modeConfigurations"] as? [String: Any],
               let config = configs[id] as? [String: Any],
               let mode = config["mode"] as? [String: Any],
               let name = mode["name"] as? String {
                return name
            }
        }
        return id.contains("donotdisturb") ? "Do Not Disturb" : nil
    }

    // MARK: Commands

    func set(on: Bool, name requested: String?) async -> ActionResult {
        if shortcutNames.isEmpty { await refreshShortcuts() }
        let name = requested ?? Hub.shared.workspace.preferences.focusName
        let shortcut = on ? "\(Self.prefix)\(name)" : Self.offName
        guard shortcutNames.contains(shortcut) else {
            return .failure("Create a shortcut named “\(shortcut)” with a Set Focus action (see the helper's Focus settings).")
        }
        let result = await ShortcutsCLI.run(shortcut)
        if result.ok {
            lastSet = (on, on ? name : nil)
            try? await Task.sleep(for: .milliseconds(400))
            Hub.shared.publish(.focus(read()))
        }
        return result
    }

    func toggle(name: String?) async -> ActionResult {
        let current = read()
        if current.active {
            return await set(on: false, name: nil)
        }
        return await set(on: true, name: name)
    }
}

/// `/usr/bin/shortcuts` — list and run.
enum ShortcutsCLI {
    static func list() async -> [String] {
        let result = await ShellRunner.run(executable: "/usr/bin/shortcuts", arguments: ["list"], timeout: 10)
        guard result.status == 0 else { return [] }
        return result.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func run(_ name: String, input: String? = nil) async -> ActionResult {
        var arguments = ["run", name]
        var inputURL: URL?
        if let input {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cc-shortcut-\(UUID().uuidString).txt")
            try? input.write(to: url, atomically: true, encoding: .utf8)
            arguments += ["--input-path", url.path]
            inputURL = url
        }
        let result = await ShellRunner.run(executable: "/usr/bin/shortcuts", arguments: arguments, timeout: 60)
        if let inputURL { try? FileManager.default.removeItem(at: inputURL) }
        if result.status == 0 {
            return ActionResult(ok: true, output: result.output.nilIfEmpty)
        }
        return .failure(result.errorOutput.nilIfEmpty ?? "Shortcut “\(name)” failed")
    }
}
