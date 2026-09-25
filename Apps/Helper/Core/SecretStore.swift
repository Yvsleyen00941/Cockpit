import CCNet
import Foundation

/// Where the helper keeps secrets: the login Keychain. A throwaway
/// `CC_INSTANCE` hub uses a 0600 file in its own data folder instead —
/// every ad-hoc test build has a new code signature, and macOS would stop
/// each Keychain read or write with an access prompt.
struct SecretStore: Sendable {
    private let keychain: Keychain?
    private let file: URL?
    private static let lock = NSLock()

    init(service: String) {
        if MacInfo.instance == nil {
            keychain = Keychain(service: service)
            file = nil
        } else {
            keychain = nil
            file = Paths.support.appendingPathComponent("\(service).secrets.json")
        }
    }

    func data(_ account: String) -> Data? {
        if let keychain { return keychain.data(account) }
        return Self.lock.withLock { readFile()[account] }
    }

    @discardableResult
    func set(_ data: Data?, for account: String) -> Bool {
        if let keychain { return keychain.set(data, for: account) }
        return Self.lock.withLock {
            var all = readFile()
            all[account] = data
            return writeFile(all)
        }
    }

    func string(_ account: String) -> String? {
        data(account).flatMap { String(data: $0, encoding: .utf8) }
    }

    @discardableResult
    func set(_ string: String?, for account: String) -> Bool {
        set(string.map { Data($0.utf8) }, for: account)
    }

    func codable<T: Decodable>(_ type: T.Type, _ account: String) -> T? {
        data(account).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    @discardableResult
    func setCodable<T: Encodable>(_ value: T?, for account: String) -> Bool {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: account)
    }

    private func readFile() -> [String: Data] {
        guard let file, let raw = try? Data(contentsOf: file) else { return [:] }
        return (try? JSONDecoder().decode([String: Data].self, from: raw)) ?? [:]
    }

    private func writeFile(_ all: [String: Data]) -> Bool {
        guard let file, let raw = try? JSONEncoder().encode(all) else { return false }
        do {
            try raw.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return true
        } catch {
            return false
        }
    }
}
