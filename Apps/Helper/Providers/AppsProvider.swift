import AppKit
import CCCore
import Foundation

/// Running apps (for the app switcher), app icons (so the iPad shows the real
/// ones) and the installed-app list for the key editor.
@MainActor
final class AppsProvider: Provider {
    var channels: Set<Channel> { [.apps] }
    private var active = false
    private var iconCache: [String: Data] = [:]
    private var installedCache: [(bundleID: String, name: String)]?

    func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Hub.shared.apps.changed() }
            }
        }
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active { publish() }
    }

    func refreshNow() async { publish() }

    private var pending: Task<Void, Never>?

    private func changed() {
        guard active else { return }
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    private func publish() {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != own }
            .map { RunningApp(bundleID: $0.bundleIdentifier!, name: $0.localizedName ?? $0.bundleIdentifier!, isActive: $0.isActive, isHidden: $0.isHidden, pid: $0.processIdentifier) }
        Hub.shared.publish(.apps(RunningApps(apps: apps)))
    }

    // MARK: Icons

    func icons(for bundleIDs: [String], size: Int) async -> [String: Data] {
        var result: [String: Data] = [:]
        for bundleID in bundleIDs.prefix(64) {
            let key = "\(bundleID)@\(size)"
            if let cached = iconCache[key] {
                result[bundleID] = cached
                continue
            }
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { continue }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if let png = Self.png(icon, size: size) {
                iconCache[key] = png
                result[bundleID] = png
            }
        }
        return result
    }

    static func png(_ image: NSImage, size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Installed apps

    func installedApps() async -> [(bundleID: String, name: String)] {
        if let installedCache { return installedCache }
        let found = await Task.detached(priority: .utility) { () -> [(String, String)] in
            let fm = FileManager.default
            let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
            var seen = Set<String>()
            var apps: [(String, String)] = []
            for root in roots {
                guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for item in items where item.hasSuffix(".app") {
                    let path = (root as NSString).appendingPathComponent(item)
                    guard let bundle = Bundle(path: path), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                    seen.insert(id)
                    let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? (item as NSString).deletingPathExtension
                    apps.append((id, name))
                }
            }
            return apps.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        }.value
        let mapped = found.map { (bundleID: $0.0, name: $0.1) }
        installedCache = mapped
        return mapped
    }
}
