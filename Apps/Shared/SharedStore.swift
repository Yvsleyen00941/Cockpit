import CCCore
import CCNet
import Foundation
import UIKit

/// Everything the app and its widget extension share: the device identity,
/// paired Macs (Keychain, shared access group) and the widget snapshot (App
/// Group container).
enum SharedStore {
    static let appGroup = "group.be.yorben.controlcenter"
    static let keychainService = "be.yorben.controlcenter"

    static var accessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "CCAppIdentifierPrefix") as? String, !prefix.isEmpty, !prefix.hasPrefix("$(") else { return nil }
        return prefix + "be.yorben.controlcenter.shared"
    }

    /// Shared keychain, falling back to the app's own if the entitlement is missing.
    static let keychain: Keychain = {
        let shared = Keychain(service: keychainService, accessGroup: accessGroup)
        if accessGroup != nil, shared.set(Data([1]), for: "probe") {
            return shared
        }
        return Keychain(service: keychainService)
    }()

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) { return url }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    // MARK: Identity

    static var deviceIdentity: DeviceIdentity {
        let keychain = self.keychain
        let deviceID: String
        if let existing = keychain.string("deviceID") {
            deviceID = existing
        } else {
            deviceID = UUID().uuidString
            keychain.set(deviceID, for: "deviceID")
        }
        let idiom: DevicePlatform = UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return DeviceIdentity(deviceID: deviceID, deviceName: deviceName, platform: isExtension ? .widget : idiom, appVersion: version)
    }

    /// iOS no longer exposes the user-assigned name; "iPad Pro" / "iPhone" is
    /// what the Mac shows unless the user renames it in Settings.
    static var deviceName: String {
        if let custom = UserDefaults(suiteName: appGroup)?.string(forKey: "deviceName"), !custom.isEmpty { return custom }
        let model = UIDevice.current.model
        return UIDevice.current.userInterfaceIdiom == .pad ? "\(model) Pro" : model
    }

    static var isExtension: Bool {
        Bundle.main.bundlePath.hasSuffix(".appex")
    }

    // MARK: Paired Macs

    static var pairedMacs: [PairedMac] {
        keychain.codable([PairedMac].self, "pairedMacs") ?? []
    }

    static func savePairedMacs(_ macs: [PairedMac]) {
        keychain.setCodable(macs, for: "pairedMacs")
    }

    static func upsert(_ mac: PairedMac) {
        var macs = pairedMacs.filter { $0.macID != mac.macID }
        macs.insert(mac, at: 0)
        savePairedMacs(macs)
    }

    static func forget(_ macID: String) {
        savePairedMacs(pairedMacs.filter { $0.macID != macID })
    }

    /// The Mac to talk to from widgets and intents.
    static var preferredMac: PairedMac? { pairedMacs.first }

    // MARK: Widget snapshot

    static var snapshotURL: URL { containerURL.appendingPathComponent("snapshot.json") }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
    }
}

/// What widgets, controls and the Live Activity read without a connection.
struct WidgetSnapshot: Codable, Hashable {
    struct PageRef: Codable, Hashable, Identifiable {
        var id: String
        var title: String
        var symbol: String
    }

    struct SceneRef: Codable, Hashable, Identifiable {
        var id: String
        var name: String
        var symbol: String
    }

    var macName: String?
    var connected: Bool
    var bot: BotState?
    var botSeries: [PnLPoint]
    var whoop: WhoopState?
    var timer: TimerState?
    var nextEvent: CalendarEvent?
    var weather: WeatherState?
    var portfolio: PortfolioState?
    var focus: FocusInfo?
    var micMuted: Bool?
    var pages: [PageRef]
    var scenes: [SceneRef]
    var updatedAt: Date

    static let empty = WidgetSnapshot(macName: nil, connected: false, bot: nil, botSeries: [], whoop: nil, timer: nil, nextEvent: nil, weather: nil, portfolio: nil, focus: nil, micMuted: nil, pages: [], scenes: [], updatedAt: .distantPast)

    init(macName: String?, connected: Bool, bot: BotState?, botSeries: [PnLPoint], whoop: WhoopState?, timer: TimerState?, nextEvent: CalendarEvent?, weather: WeatherState?, portfolio: PortfolioState?, focus: FocusInfo?, micMuted: Bool?, pages: [PageRef], scenes: [SceneRef], updatedAt: Date) {
        self.macName = macName
        self.connected = connected
        self.bot = bot
        self.botSeries = botSeries
        self.whoop = whoop
        self.timer = timer
        self.nextEvent = nextEvent
        self.weather = weather
        self.portfolio = portfolio
        self.focus = focus
        self.micMuted = micMuted
        self.pages = pages
        self.scenes = scenes
        self.updatedAt = updatedAt
    }

    init(state: LiveState, workspace: Workspace?, macName: String?, connected: Bool, now: Date = .now) {
        var weather = state.weather
        if let hourly = weather?.hourly { weather?.hourly = Array(hourly.prefix(6)) }
        var portfolio = state.portfolio
        if let series = portfolio?.series { portfolio?.series = Array(series.suffix(30)) }
        self.init(
            macName: macName,
            connected: connected,
            bot: state.bot,
            botSeries: WidgetSnapshot.downsample(state.botSeries?.points ?? [], to: 48),
            whoop: state.whoop,
            timer: state.timers?.primary,
            nextEvent: state.calendar?.featured(at: now),
            weather: weather,
            portfolio: portfolio,
            focus: state.focus,
            micMuted: state.audio?.inputMuted,
            pages: (workspace?.pages ?? []).map { PageRef(id: $0.id, title: $0.title, symbol: $0.symbol) },
            scenes: (workspace?.scenes ?? []).map { SceneRef(id: $0.id, name: $0.name, symbol: $0.symbol) },
            updatedAt: now
        )
    }

    static func downsample(_ points: [PnLPoint], to count: Int) -> [PnLPoint] {
        guard points.count > count, count > 1 else { return points }
        let step = Double(points.count - 1) / Double(count - 1)
        return (0..<count).map { points[Int((Double($0) * step).rounded())] }
    }
}
