import Foundation

/// `~/Library/Application Support/ControlCenter/…`
enum Paths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("ControlCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static let workspace = support.appendingPathComponent("workspace.json")
    static let integrations = support.appendingPathComponent("integrations.json")
    static let daily = support.appendingPathComponent("daily.json")
    static let timers = support.appendingPathComponent("timers.json")
    static let botLedger = support.appendingPathComponent("bot-ledger.json")
    static let apns = support.appendingPathComponent("apns.json")

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

enum JSONStore {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            Log.shared.error("Could not read \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.shared.error("Could not write \(url.lastPathComponent): \(error)")
        }
    }
}

/// Watches a file that may be replaced atomically (editors save by rename).
@MainActor
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var debounce: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    private func arm() {
        source?.cancel()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File not there yet — try again shortly.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.arm()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let events = source.data
                self.debounce?.cancel()
                self.debounce = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    self.onChange()
                }
                if events.contains(.rename) || events.contains(.delete) {
                    self.arm()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
