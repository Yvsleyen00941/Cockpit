import CCCore
import Foundation
@preconcurrency import Network

/// Connect → authenticate → one request → one reply → close. Used by widgets,
/// App Intents, Control Center controls and background refresh, which cannot
/// hold a session open. A round trip on a LAN is ~20 ms.
public enum HubOneShot {
    public static func endpoints(for mac: PairedMac) -> [NWEndpoint] {
        var result: [NWEndpoint] = []
        if let host = mac.lastHost, let port = mac.lastPort, let nwPort = NWEndpoint.Port(rawValue: port) {
            result.append(.hostPort(host: NWEndpoint.Host(host), port: nwPort))
        }
        if let name = mac.serviceName {
            result.append(.service(name: name, type: Bonjour.serviceType, domain: "local.", interface: nil))
        }
        return result
    }

    /// Sends `body` and returns the first reply whose `replyTo` matches, or the
    /// first `liveDataUpdate` for snapshot requests.
    public static func request(_ body: MCCBody, mac: PairedMac, device: DeviceIdentity, timeout: TimeInterval = 6) async throws -> MCCMessage {
        var lastError: Error = StreamError.connectFailed("No known address for \(mac.macName)")
        for endpoint in endpoints(for: mac) {
            do {
                return try await request(body, endpoint: endpoint, mac: mac, device: device, timeout: timeout)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func request(_ body: MCCBody, endpoint: NWEndpoint, mac: PairedMac, device: DeviceIdentity, timeout: TimeInterval) async throws -> MCCMessage {
        let stream = NWByteStream(NWConnection(to: endpoint, using: .controlCenter()))
        try await stream.start(timeout: min(timeout, 4))
        let channel = MessageChannel(stream: stream)
        defer { channel.close() }
        _ = try await ClientHandshake.authenticate(channel: channel, device: device, mac: mac, transport: .wifi, timeout: timeout)
        let requestID: UInt32 = 1
        try await channel.send(body, id: requestID)
        while true {
            let message = try await channel.receive(timeout: timeout)
            if message.replyTo == requestID { return message }
            if case .liveDataUpdate(let update) = message.body, update.full, case .requestSnapshot = body { return message }
        }
    }

    /// Fresh values for the given channels.
    public static func snapshot(_ channels: [Channel], mac: PairedMac, device: DeviceIdentity) async throws -> LiveState {
        let reply = try await request(.requestSnapshot(Subscribe(channels: channels)), mac: mac, device: device)
        var state = LiveState()
        if case .liveDataUpdate(let update) = reply.body {
            for value in update.values { state.apply(value) }
        }
        return state
    }

    /// Runs an action on the Mac.
    public static func run(_ action: ButtonAction, mac: PairedMac, device: DeviceIdentity) async throws -> ActionResult {
        let reply = try await request(.buttonTap(ButtonTap(action: action)), mac: mac, device: device)
        if case .actionResult(let result) = reply.body { return result }
        return .failure("Unexpected reply")
    }
}
