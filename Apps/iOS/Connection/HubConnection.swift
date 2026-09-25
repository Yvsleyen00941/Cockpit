import CCCore
import CCNet
import Foundation
@preconcurrency import Network
import Observation
import os

private let linkLog = Logger(subsystem: "be.yorben.controlcenter", category: "link")

enum LinkStatus: Equatable {
    case idle
    case needsPairing
    case searching
    case connecting(String)
    case connected
    case macAsleep(String)

    var isConnected: Bool { self == .connected }
}

/// What the app talks to: the real Mac, or the built-in demo hub.
@MainActor
protocol HubLink: AnyObject {
    var status: LinkStatus { get }
    var transport: LinkTransport { get }
    var latencyMs: Double? { get }
    var isDegraded: Bool { get }
    var macName: String? { get }
    var lastError: String? { get }
    var onMessage: ((MCCMessage) -> Void)? { get set }
    var onConnected: (() -> Void)? { get set }
    func start()
    func stop()
    func appBecameActive()
    func send(_ body: MCCBody)
    func request(_ body: MCCBody, timeout: TimeInterval) async throws -> MCCMessage
}

enum LinkError: Error, LocalizedError {
    case notConnected
    case timeout

    var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to your Mac"
        case .timeout: "Your Mac didn't answer in time"
        }
    }
}

/// One live, authenticated, encrypted session. Outgoing messages leave in
/// order through a single writer.
final class LiveSession: @unchecked Sendable {
    let channel: MessageChannel
    let transport: LinkTransport
    private let outbox: AsyncStream<MCCMessage>.Continuation
    private var writer: Task<Void, Never>?

    init(channel: MessageChannel, transport: LinkTransport) {
        self.channel = channel
        self.transport = transport
        let (stream, continuation) = AsyncStream.makeStream(of: MCCMessage.self)
        outbox = continuation
        writer = Task { [channel] in
            for await message in stream {
                do {
                    try await channel.send(message)
                } catch {
                    channel.close()
                    break
                }
            }
        }
    }

    func enqueue(_ message: MCCMessage) { outbox.yield(message) }

    func close() {
        outbox.finish()
        writer?.cancel()
        channel.close()
    }
}

/// Finds Macs running the helper (Bonjour), pairs, connects, reconnects with
/// exponential backoff (3 s → 30 s), measures latency, and prefers the USB-C
/// tunnel when the Mac dials in over the cable.
@MainActor
@Observable
final class HubConnection: HubLink {
    enum Pairing: Equatable {
        case none
        case connecting(String)
        case enterCode(macName: String, attempt: Int)
        case verifying
        case success(String)
        case failed(String)
    }

    private(set) var status: LinkStatus = .idle {
        didSet { if status != oldValue { linkLog.info("status \(String(describing: oldValue), privacy: .public) → \(String(describing: self.status), privacy: .public)") } }
    }
    private(set) var transport: LinkTransport = .wifi
    private(set) var latencyMs: Double?
    private(set) var macName: String?
    private(set) var lastError: String?
    private(set) var pairing: Pairing = .none
    private(set) var pairedMacs: [PairedMac] = SharedStore.pairedMacs
    private(set) var currentMac: PairedMac?
    private(set) var lastPong = Date()
    let browser = MacBrowser()

    var onMessage: ((MCCMessage) -> Void)?
    var onConnected: (() -> Void)?

    private var session: LiveSession?
    private var reader: Task<Void, Never>?
    private var connectLoop: Task<Void, Never>?
    private var pingLoop: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var pairingAttempt: (token: UUID, macID: String)?
    private var pendingCode: (token: UUID, continuation: CheckedContinuation<String, Error>)?
    private var backoff: TimeInterval = 3
    private var wake: CheckedContinuation<Void, Never>?
    private var nextID: UInt32 = 1
    private var pending: [UInt32: CheckedContinuation<MCCMessage, Error>] = [:]
    private var pingSeq: UInt32 = 0
    private var usbListener: NWListener?
    private let device = SharedStore.deviceIdentity

    var isDegraded: Bool {
        guard status == .connected else { return false }
        return (latencyMs ?? 0) > 50 || Date().timeIntervalSince(lastPong) > 5
    }

    var preferredMacID: String? {
        get { UserDefaults.standard.string(forKey: "preferredMacID") ?? pairedMacs.first?.macID }
        set { UserDefaults.standard.set(newValue, forKey: "preferredMacID") }
    }

    private var preferredMac: PairedMac? {
        pairedMacs.first { $0.macID == preferredMacID } ?? pairedMacs.first
    }

    // MARK: Lifecycle

    func start() {
        browser.onChange = { [weak self] in self?.browserChanged() }
        browser.start()
        startUSBListener()
        if pairedMacs.isEmpty {
            status = .needsPairing
        } else {
            status = .searching
            startConnectLoop()
        }
    }

    func stop() {
        connectLoop?.cancel()
        pingLoop?.cancel()
        reader?.cancel()
        session?.close()
        session = nil
        browser.stop()
        usbListener?.cancel()
        usbListener = nil
        status = .idle
    }

    func appBecameActive() {
        if usbListener == nil { startUSBListener() }
        if session == nil, !pairedMacs.isEmpty {
            backoff = 3
            wakeLoop()
            if connectLoop == nil { startConnectLoop() }
        } else {
            sendPing()
        }
    }

    func appWillResignActive() {
        usbListener?.cancel()
        usbListener = nil
    }

    private func browserChanged() {
        // A paired Mac just appeared: try it now instead of waiting out the backoff.
        if session == nil, let id = preferredMac?.macID, browser.results.contains(where: { $0.macID == id }) {
            backoff = 3
            wakeLoop()
        }
    }

    // MARK: Connecting

    private func startConnectLoop() {
        connectLoop?.cancel()
        connectLoop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.session != nil { break }
                if await self.attemptConnect() {
                    self.backoff = 3
                    break
                }
                let wait = self.backoff
                self.backoff = min(30, self.backoff * 1.5)
                await self.sleep(wait)
            }
            self?.connectLoop = nil
        }
    }

    /// Sleeps for the backoff, or until something worth retrying happens.
    private func sleep(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            wake = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                self?.wakeLoop()
            }
        }
    }

    private func wakeLoop() {
        let continuation = wake
        wake = nil
        continuation?.resume()
    }

    private func attemptConnect() async -> Bool {
        guard let mac = preferredMac else {
            status = .needsPairing
            return false
        }
        var endpoints: [NWEndpoint] = []
        let found = browser.results.first { $0.macID == mac.macID }
        if let found { endpoints.append(found.endpoint) }
        endpoints += HubOneShot.endpoints(for: mac)
        if endpoints.isEmpty {
            if case .macAsleep = status {} else { status = .searching }
            return false
        }
        if case .macAsleep = status {} else { status = .connecting(mac.macName) }

        for endpoint in endpoints {
            do {
                let stream = NWByteStream(NWConnection(to: endpoint, using: .controlCenter()))
                try await stream.start(timeout: 5)
                let channel = MessageChannel(stream: stream)
                let outcome = try await ClientHandshake.authenticate(channel: channel, device: device, mac: mac, transport: .wifi)
                var updated = mac
                updated.macName = outcome.macName
                if let found { updated.serviceName = found.name }
                if case .hostPort(let host, let port) = stream.remoteEndpoint {
                    updated.lastHost = Self.describe(host)
                    updated.lastPort = port.rawValue
                }
                remember(updated)
                activate(channel, transport: .wifi, mac: updated)
                return true
            } catch HandshakeError.unknownDevice {
                lastError = "\(mac.macName) no longer knows this device — pair again."
                forget(mac.macID)
                return false
            } catch {
                lastError = error.localizedDescription
            }
        }
        if case .macAsleep = status {} else { status = .searching }
        return false
    }

    private static func describe(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): "\(address)"
        case .ipv6(let address): "\(address)"
        case .name(let name, _): name
        @unknown default: "\(host)"
        }
    }

    private func activate(_ channel: MessageChannel, transport: LinkTransport, mac: PairedMac) {
        session?.close()
        reader?.cancel()
        let session = LiveSession(channel: channel, transport: transport)
        self.session = session
        self.transport = transport
        currentMac = mac
        macName = mac.macName
        lastError = nil
        latencyMs = nil
        lastPong = .now
        status = .connected
        preferredMacID = mac.macID

        reader = Task { @MainActor [weak self] in
            do {
                while true {
                    let message = try await channel.receive()
                    self?.received(message)
                }
            } catch {
                self?.ended(session, error: error)
            }
        }
        startPing()
        onConnected?()
    }

    private func ended(_ ended: LiveSession, error: Error) {
        linkLog.info("session ended: \(String(describing: error), privacy: .public)")
        ended.close()
        guard session === ended else { return }
        session = nil
        pingLoop?.cancel()
        for continuation in pending.values { continuation.resume(throwing: LinkError.notConnected) }
        pending.removeAll()
        latencyMs = nil
        if case .macAsleep = status {} else { status = .searching }
        if connectLoop == nil { startConnectLoop() }
    }

    // MARK: Messages

    private func received(_ message: MCCMessage) {
        lastPong = .now
        if let replyTo = message.replyTo, let continuation = pending.removeValue(forKey: replyTo) {
            continuation.resume(returning: message)
        }
        switch message.body {
        case .pong(let ping):
            let rtt = (Date().timeIntervalSince1970 - ping.t) * 1000
            latencyMs = latencyMs.map { $0 * 0.7 + rtt * 0.3 } ?? rtt
        case .bye(let bye):
            if bye.reason == .sleeping {
                status = .macAsleep(macName ?? "Your Mac")
                backoff = 10
            }
            session?.close()
            onMessage?(message)
        default:
            onMessage?(message)
        }
    }

    func send(_ body: MCCBody) {
        session?.enqueue(MCCMessage(body))
    }

    func request(_ body: MCCBody, timeout: TimeInterval = 8) async throws -> MCCMessage {
        guard let session else { throw LinkError.notConnected }
        let id = nextID
        nextID &+= 1
        session.enqueue(MCCMessage(body, id: id))
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                if let continuation = self?.pending.removeValue(forKey: id) {
                    continuation.resume(throwing: LinkError.timeout)
                }
            }
        }
    }

    // MARK: Heartbeat

    private func startPing() {
        pingLoop?.cancel()
        pingLoop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sendPing()
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                if Date().timeIntervalSince(self.lastPong) > 12, let session = self.session {
                    // Dead link (Wi-Fi dropped without a FIN): reconnect.
                    session.close()
                }
            }
        }
    }

    private func sendPing() {
        pingSeq &+= 1
        send(.ping(Ping(seq: pingSeq, t: Date().timeIntervalSince1970)))
    }

    // MARK: Pairing

    func pair(with mac: MacBrowser.Result) {
        // A double tap must not open a second handshake next to the first one.
        if pairingAttempt?.macID == mac.id { return }
        abortPairing()
        let token = UUID()
        pairingAttempt = (token, mac.id)
        pairingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Only the current attempt may touch the UI; a superseded one just cleans up.
            var isCurrent: Bool { self.pairingAttempt?.token == token }
            defer {
                if isCurrent {
                    self.pairingTask = nil
                    self.pairingAttempt = nil
                }
            }
            self.pairing = .connecting(mac.name)
            var stage = "connect"
            let stream = NWByteStream(NWConnection(to: mac.endpoint, using: .controlCenter()))
            do {
                try await stream.start(timeout: 6)
                let channel = MessageChannel(stream: stream)
                let device = self.device
                stage = "pair"
                var record = try await ClientHandshake.pair(channel: channel, device: device, codeAccepted: { [weak self] in
                    await self?.codeAccepted(token: token)
                }, enterCode: { [weak self] attempt in
                    guard let self else { throw CancellationError() }
                    return try await self.awaitCode(attempt: attempt, macName: mac.name, token: token)
                })
                stage = "verify"
                record.serviceName = mac.name
                if case .hostPort(let host, let port) = stream.remoteEndpoint {
                    record.lastHost = Self.describe(host)
                    record.lastPort = port.rawValue
                }
                self.remember(record)
                stage = "authenticate"
                _ = try await ClientHandshake.authenticate(channel: channel, device: device, mac: record, transport: .wifi)
                try Task.checkCancellation()
                self.pairing = .success(record.macName)
                self.connectLoop?.cancel()
                self.connectLoop = nil
                self.activate(channel, transport: .wifi, mac: record)
            } catch is CancellationError {
                stream.close()
                if isCurrent { self.pairing = .none }
            } catch {
                stream.close()
                linkLog.error("pairing failed during \(stage, privacy: .public): \(String(describing: error), privacy: .public)")
                if isCurrent {
                    self.pairing = .failed("\(error.localizedDescription) (while trying to \(stage))")
                }
            }
        }
    }

    private func awaitCode(attempt: Int, macName: String, token: UUID) async throws -> String {
        pairing = .enterCode(macName: macName, attempt: attempt)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pendingCode = (token, continuation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.failPendingCode(token: token) }
        }
    }

    /// The code matched; the Mac is now storing the key.
    private func codeAccepted(token: UUID) {
        guard pairingAttempt?.token == token else { return }
        pairing = .verifying
    }

    /// Fails the open code prompt — only `token`'s, when given.
    private func failPendingCode(token: UUID? = nil) {
        guard let pending = pendingCode, token == nil || pending.token == token else { return }
        pendingCode = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    /// Stops an in-flight pairing: fails the pending code prompt and closes its connection.
    private func abortPairing() {
        failPendingCode()
        pairingTask?.cancel()
        pairingTask = nil
        pairingAttempt = nil
    }

    func submitCode(_ code: String) {
        let pending = pendingCode
        pendingCode = nil
        pending?.continuation.resume(returning: code)
    }

    func cancelPairing() {
        abortPairing()
        pairing = .none
    }

    func resetPairingState() {
        pairing = .none
    }

    /// Shows the pairing flow even though Macs are already paired ("Pair Another Mac").
    func forceShowPairing() {
        connectLoop?.cancel()
        connectLoop = nil
        pairing = .none
        status = .needsPairing
    }

    /// Leaves the pairing flow and goes back to the paired Macs.
    func resumeConnecting() {
        guard !pairedMacs.isEmpty else { return }
        pairing = .none
        if session != nil {
            status = .connected
        } else {
            status = .searching
            backoff = 3
            startConnectLoop()
        }
    }

    // MARK: Paired Macs

    private func remember(_ mac: PairedMac) {
        var macs = pairedMacs.filter { $0.macID != mac.macID }
        macs.insert(mac, at: 0)
        pairedMacs = macs
        SharedStore.savePairedMacs(macs)
    }

    func forget(_ macID: String) {
        pairedMacs.removeAll { $0.macID == macID }
        SharedStore.savePairedMacs(pairedMacs)
        if currentMac?.macID == macID {
            session?.close()
            session = nil
            currentMac = nil
        }
        if pairedMacs.isEmpty { status = .needsPairing }
    }

    func switchTo(_ macID: String) {
        preferredMacID = macID
        session?.close()
        session = nil
        backoff = 3
        status = .searching
        startConnectLoop()
    }

    // MARK: USB-C

    /// The Mac dials in over the cable through usbmuxd; we listen on loopback
    /// only while in the foreground.
    private func startUSBListener() {
        let parameters = NWParameters.controlCenter(peerToPeer: false)
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Bonjour.usbPort)!)
        guard let listener = try? NWListener(using: parameters) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.acceptUSB(connection) }
        }
        listener.stateUpdateHandler = { state in
            if case .failed = state { listener.cancel() }
        }
        listener.start(queue: .main)
        usbListener = listener
    }

    private func acceptUSB(_ connection: NWConnection) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = NWByteStream(connection)
                try await stream.start(timeout: 5)
                let channel = MessageChannel(stream: stream)
                let macs = self.pairedMacs
                let (_, mac) = try await ClientHandshake.authenticate(channel: channel, device: self.device, transport: .usb) { id in
                    macs.first { $0.macID == id }
                }
                self.connectLoop?.cancel()
                self.connectLoop = nil
                self.activate(channel, transport: .usb, mac: mac)
            } catch {
                connection.cancel()
            }
        }
    }
}

/// Bonjour discovery of `_ccontrol._tcp`.
@MainActor
@Observable
final class MacBrowser {
    struct Result: Identifiable, Hashable {
        var id: String { macID ?? name }
        let name: String
        let macID: String?
        let model: String?
        let endpoint: NWEndpoint
    }

    private(set) var results: [Result] = []
    private(set) var isBrowsing = false
    var onChange: (() -> Void)?
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Bonjour.serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isBrowsing = true
                case .failed:
                    self?.isBrowsing = false
                    self?.restart()
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func restart() {
        stop()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.start()
        }
    }

    private func update(_ found: Set<NWBrowser.Result>) {
        results = found.compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }
            var macID: String?
            var model: String?
            if case .bonjour(let txt) = result.metadata {
                macID = txt[Bonjour.TXT.macID]
                model = txt[Bonjour.TXT.model]
            }
            return Result(name: name, macID: macID, model: model, endpoint: result.endpoint)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onChange?()
    }
}
