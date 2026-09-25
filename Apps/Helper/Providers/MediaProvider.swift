import AppKit
import CCCore
import Foundation

/// Spotify and Music. Track changes arrive instantly through the players'
/// distributed notifications; a slow poll only corrects drift. Players are
/// only queried while running — AppleScript would otherwise launch them.
@MainActor
final class MediaProvider: PollingProvider {
    override var channels: Set<Channel> { [.media] }
    override var interval: TimeInterval { (last?.isPlaying ?? false) ? 5 : 10 }

    private var last: NowPlaying?
    private var observers: [NSObjectProtocol] = []
    private var artworkCache: [String: Data] = [:]
    private var artworkOrder: [String] = []
    private var spotifyArtworkURLs: [String: String] = [:]

    private static let spotifyScript = """
    with timeout of 2 seconds
    tell application id "com.spotify.client"
        if player state is stopped then return {"stopped"}
        set t to current track
        return {player state as string, name of t, artist of t, album of t, duration of t, player position, artwork url of t, id of t}
    end tell
    end timeout
    """

    private static let musicScript = """
    with timeout of 2 seconds
    tell application id "com.apple.Music"
        if player state is stopped then return {"stopped"}
        set t to current track
        return {player state as string, name of t, artist of t, album of t, duration of t, player position, persistent ID of t}
    end tell
    end timeout
    """

    override func didActivate() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            observers.append(center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Task { await Hub.shared.media.tick() }
                }
            })
        }
    }

    override func didDeactivate() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
    }

    override func tick() async {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var candidates: [NowPlaying] = []
        if running.contains(MediaSource.spotify.bundleID), let track = await spotify() { candidates.append(track) }
        if running.contains(MediaSource.music.bundleID), let track = await music() { candidates.append(track) }
        let chosen = candidates.first(where: \.isPlaying) ?? candidates.first
        publish(chosen)
    }

    private func publish(_ track: NowPlaying?) {
        // Skip updates that only moved the clock forward — clients extrapolate.
        if let track, let last, track.title == last.title, track.artist == last.artist, track.isPlaying == last.isPlaying, track.source == last.source,
           abs(last.position(at: track.positionAt) - track.position) < 2 {
            return
        }
        last = track
        Hub.shared.publish(.media(MediaState(nowPlaying: track)))
    }

    private func spotify() async -> NowPlaying? {
        guard case .success(let value) = await AppleScriptRunner.shared.run(Self.spotifyScript), value.list.count >= 8 else { return nil }
        let state = value[0]?.string ?? ""
        let id = value[7]?.string ?? UUID().uuidString
        let artworkID = "spotify:\(id)"
        if let url = value[6]?.string { spotifyArtworkURLs[artworkID] = url }
        return NowPlaying(
            source: .spotify,
            title: value[1]?.string ?? "",
            artist: value[2]?.string ?? "",
            album: value[3]?.string ?? "",
            isPlaying: state == "playing",
            position: value[5]?.number ?? 0,
            duration: (value[4]?.number ?? 0) / 1000,
            positionAt: .now,
            artworkID: artworkID,
            artworkURL: value[6]?.string
        )
    }

    private func music() async -> NowPlaying? {
        guard case .success(let value) = await AppleScriptRunner.shared.run(Self.musicScript), value.list.count >= 7 else { return nil }
        let state = value[0]?.string ?? ""
        return NowPlaying(
            source: .music,
            title: value[1]?.string ?? "",
            artist: value[2]?.string ?? "",
            album: value[3]?.string ?? "",
            isPlaying: state == "playing",
            position: value[5]?.number ?? 0,
            duration: value[4]?.number ?? 0,
            positionAt: .now,
            artworkID: "music:\(value[6]?.string ?? "")"
        )
    }

    // MARK: Artwork

    func artwork(id: String) async -> Data? {
        if let cached = artworkCache[id] { return cached }
        var raw: Data?
        if id.hasPrefix("spotify:"), let urlString = spotifyArtworkURLs[id], let url = URL(string: urlString) {
            raw = try? await URLSession.shared.data(from: url).0
        } else if id.hasPrefix("music:") {
            let script = "tell application id \"com.apple.Music\" to return raw data of artwork 1 of current track"
            if case .success(let value) = await AppleScriptRunner.shared.run(script) { raw = value.data }
        }
        guard let raw, let scaled = Self.downscale(raw, maxPixels: 360) else { return nil }
        artworkCache[id] = scaled
        artworkOrder.append(id)
        if artworkOrder.count > 24 {
            artworkCache[artworkOrder.removeFirst()] = nil
        }
        return scaled
    }

    static func downscale(_ data: Data, maxPixels: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxPixels / max(size.width, size.height, 1))
        let target = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
    }
}
