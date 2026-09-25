import AudioToolbox
import CCCore
import Foundation
import Observation
import UIKit

/// Last-known workspace and live state, so a disconnected iPad still shows
/// your layout and the latest numbers (dimmed) instead of an empty screen.
enum OfflineCache {
    private static let directory: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ControlCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    static func loadWorkspace() -> Workspace? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("workspace.json")) else { return nil }
        return try? decoder.decode(Workspace.self, from: data)
    }

    static func save(_ workspace: Workspace) {
        if let data = try? encoder.encode(workspace) {
            try? data.write(to: directory.appendingPathComponent("workspace.json"), options: .atomic)
        }
    }

    static func loadState() -> LiveState? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("state.json")) else { return nil }
        return try? decoder.decode(LiveState.self, from: data)
    }

    static func save(_ state: LiveState) {
        var trimmed = state
        trimmed.system?.topProcesses = []
        if let data = try? encoder.encode(trimmed) {
            try? data.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }

    static var iconDirectory: URL {
        let url = directory.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Real Mac app icons (sent once by the helper, cached on disk) and album art.
@MainActor
@Observable
final class ImageCache {
    private(set) var icons: [String: UIImage] = [:]
    private(set) var artwork: [String: UIImage] = [:]
    private var requestedIcons = Set<String>()
    private var requestedArtwork = Set<String>()

    init() {
        let directory = OfflineCache.iconDirectory
        for file in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where file.hasSuffix(".png") {
            if let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path) {
                icons[String(file.dropLast(4))] = image
            }
        }
    }

    func icon(_ bundleID: String?) -> UIImage? {
        guard let bundleID else { return nil }
        return icons[bundleID]
    }

    /// Asks the Mac for any icons we don't have yet.
    func request(_ bundleIDs: some Sequence<String>, via link: any HubLink) {
        let missing = Set(bundleIDs).subtracting(icons.keys).subtracting(requestedIcons)
        guard !missing.isEmpty, link.status.isConnected, link.transport != .demo else { return }
        requestedIcons.formUnion(missing)
        Task { @MainActor in
            guard let reply = try? await link.request(.requestIcons(RequestIcons(bundleIDs: Array(missing), size: 128)), timeout: 10),
                  case .icons(let payload) = reply.body else {
                requestedIcons.subtract(missing)
                return
            }
            for (bundleID, data) in payload.icons {
                guard let image = UIImage(data: data) else { continue }
                icons[bundleID] = image
                try? data.write(to: OfflineCache.iconDirectory.appendingPathComponent("\(bundleID).png"))
            }
        }
    }

    func requestArtwork(_ id: String?, via link: any HubLink) {
        guard let id, artwork[id] == nil, !requestedArtwork.contains(id), link.status.isConnected, link.transport != .demo else { return }
        requestedArtwork.insert(id)
        Task { @MainActor in
            guard let reply = try? await link.request(.requestArtwork(RequestArtwork(id: id)), timeout: 10),
                  case .artwork(let payload) = reply.body, let data = payload.data, let image = UIImage(data: data) else { return }
            artwork[id] = image
            if artwork.count > 16 { artwork.removeValue(forKey: artwork.keys.first { $0 != id } ?? id) }
        }
    }
}

/// Tap feedback. iPads have no Taptic Engine, so on iPad the key click sound
/// and the key's own acknowledgement glow carry the feedback; iPhones also get
/// a medium impact, as the blueprint asks.
@MainActor
enum Feedback {
    private static let impact = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    static var clicksEnabled: Bool {
        UserDefaults.standard.object(forKey: "keyClicks") as? Bool ?? true
    }

    static func tap() {
        impact.impactOccurred()
        if clicksEnabled { AudioServicesPlaySystemSound(1104) }
    }

    static func heavy() {
        rigid.impactOccurred(intensity: 1)
        if clicksEnabled { AudioServicesPlaySystemSound(1105) }
    }

    static func success() {
        notify.notificationOccurred(.success)
    }

    static func failure() {
        notify.notificationOccurred(.error)
    }

    static func chime() {
        AudioServicesPlaySystemSound(1025)
    }
}

enum ThemeChoice: String, CaseIterable, Identifiable {
    case dark, light, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "System"
        }
    }
}
