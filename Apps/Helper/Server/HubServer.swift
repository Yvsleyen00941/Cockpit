import CCCore
import CCNet
import Foundation
@preconcurrency import Network

/// Advertises `_ccontrol._tcp` over Bonjour and accepts connections.
@MainActor
final class HubServer {
    private var listener: NWListener?
    private(set) var port: UInt16?
    private(set) var isListening = false
    private var useAnyPort = MacInfo.instance != nil
    var onConnection: ((NWConnection) -> Void)?

    func start() {
        listener?.cancel()
        let parameters = NWParameters.controlCenter()
        parameters.allowLocalEndpointReuse = true
        do {
            let listener: NWListener
            if useAnyPort {
                listener = try NWListener(using: parameters)
            } else {
                listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Bonjour.defaultPort)!)
            }
            var txt = NWTXTRecord()
            txt[Bonjour.TXT.macID] = MacInfo.macID
            txt[Bonjour.TXT.protocolVersion] = "\(ccProtocolVersion)"
            txt[Bonjour.TXT.model] = MacInfo.model
            txt[Bonjour.TXT.host] = MacInfo.localHostName + ".local"
            listener.service = NWListener.Service(name: MacInfo.computerName, type: Bonjour.serviceType, domain: nil, txtRecord: txt)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.handle(state) }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.onConnection?(connection) }
            }
            listener.start(queue: DispatchQueue(label: "cc.listener", qos: .userInitiated))
            self.listener = listener
        } catch {
            Log.shared.error("Listener could not start: \(error.localizedDescription)")
            retry()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isListening = false
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            port = listener?.port?.rawValue
            isListening = true
            Log.shared.info("Listening on port \(port ?? 0) as “\(MacInfo.computerName)”")
        case .failed(let error):
            isListening = false
            if case .posix(let code) = error, code == .EADDRINUSE, !useAnyPort {
                Log.shared.warning("Port \(Bonjour.defaultPort) is busy; using a random port")
                useAnyPort = true
                start()
            } else {
                Log.shared.error("Listener failed: \(error.localizedDescription)")
                retry()
            }
        case .cancelled:
            isListening = false
        default:
            break
        }
    }

    private func retry() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.start()
        }
    }
}

/// One connected device. Owns its channel; outgoing messages leave in order
/// through a single writer task.
final class ClientSession: @unchecked Sendable {
    let id = UUID()
    let channel: MessageChannel
    let transport: LinkTransport
    private let outbox: AsyncStream<MCCMessage>.Continuation
    private let outboxStream: AsyncStream<MCCMessage>
    private let closedSignal: AsyncStream<Void>
    private let closedContinuation: AsyncStream<Void>.Continuation

    init(stream: ByteStream, transport: LinkTransport) {
        channel = MessageChannel(stream: stream)
        self.transport = transport
        (outboxStream, outbox) = AsyncStream.makeStream(of: MCCMessage.self)
        (closedSignal, closedContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// Returns once the session has ended.
    func waitUntilClosed() async {
        for await _ in closedSignal {}
    }

    func send(_ body: MCCBody, replyTo: UInt32? = nil) {
        outbox.yield(MCCMessage(body, replyTo: replyTo))
    }

    func close() {
        outbox.finish()
        channel.close()
        closedContinuation.finish()
    }

    func run(
        identity: MacIdentity,
        registry: DeviceRegistry,
        presenter: PairingPresenter,
        onAuthenticated: @escaping @MainActor (ClientSession, AuthenticatedPeer) -> Void,
        onMessage: @escaping @MainActor (ClientSession, MCCMessage) -> Void,
        onEnd: @escaping @MainActor (ClientSession, Error?) -> Void
    ) async {
        var failure: Error?
        do {
            let peer = try await ServerHandshake.run(channel: channel, mac: identity, registry: registry, presenter: presenter)
            await onAuthenticated(self, peer)
            let writer = Task { [channel, outboxStream] in
                for await message in outboxStream {
                    do {
                        try await channel.send(message)
                    } catch {
                        channel.close()
                        break
                    }
                }
            }
            defer { writer.cancel() }
            while true {
                let message = try await channel.receive()
                await onMessage(self, message)
            }
        } catch {
            failure = error
        }
        close()
        await onEnd(self, failure)
    }
}
