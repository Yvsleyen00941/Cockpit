import AppKit
import CCCore
import CCNet
import Foundation
import IOKit
import SystemConfiguration

/// This Mac's stable identity on the protocol.
enum MacInfo {
    static var macID: String {
        let key = "macID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    static var computerName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac"
    }

    /// `Yorbens-MacBook-Pro` → used as `Yorbens-MacBook-Pro.local`.
    static var localHostName: String {
        (SCDynamicStoreCopyLocalHostName(nil) as String?) ?? "localhost"
    }

    static var helperVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    /// "MacBook Pro · M3 Pro"
    static let model: String = {
        let chip = sysctlString("machdep.cpu.brand_string").replacingOccurrences(of: "Apple ", with: "")
        var product = "Mac"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        if entry != 0 {
            if let data = IORegistryEntryCreateCFProperty(entry, "product-name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data {
                product = String(decoding: data.prefix { $0 != 0 }, as: UTF8.self)
                    .replacingOccurrences(of: #" \(.*\)"#, with: "", options: .regularExpression)
            }
            IOObjectRelease(entry)
        }
        if product == "Mac" {
            product = sysctlString("hw.model").hasPrefix("MacBookPro") ? "MacBook Pro" : "Mac"
        }
        return chip.isEmpty ? product : "\(product) · \(chip)"
    }()

    static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    static var identity: MacIdentity {
        MacIdentity(macID: macID, macName: computerName, helperVersion: helperVersion)
    }
}

/// Paired devices, one Keychain item each, cached in memory.
actor DeviceStore: DeviceRegistry {
    private let keychain = Keychain(service: "be.yorben.controlcenter.helper.devices")
    private let indexKey = "pairedDeviceIDs"
    private var cache: [String: PairedDevice] = [:]
    private var loaded = false

    private func load() {
        guard !loaded else { return }
        loaded = true
        for id in UserDefaults.standard.stringArray(forKey: indexKey) ?? [] {
            if let device = keychain.codable(PairedDevice.self, id) { cache[id] = device }
        }
    }

    func device(_ id: String) async -> PairedDevice? {
        load()
        return cache[id]
    }

    func store(_ device: PairedDevice) async {
        load()
        cache[device.deviceID] = device
        keychain.setCodable(device, for: device.deviceID)
        UserDefaults.standard.set(Array(cache.keys), forKey: indexKey)
        let all = Array(cache.values)
        await MainActor.run { Hub.shared.pairedDevicesChanged(all) }
    }

    func touch(_ id: String) async {
        load()
        guard var device = cache[id] else { return }
        device.lastSeen = .now
        cache[id] = device
        keychain.setCodable(device, for: id)
    }

    func remove(_ id: String) async {
        load()
        cache[id] = nil
        keychain.set(nil as Data?, for: id)
        UserDefaults.standard.set(Array(cache.keys), forKey: indexKey)
        let all = Array(cache.values)
        await MainActor.run { Hub.shared.pairedDevicesChanged(all) }
    }

    func all() async -> [PairedDevice] {
        load()
        return cache.values.sorted { $0.pairedAt < $1.pairedAt }
    }
}
