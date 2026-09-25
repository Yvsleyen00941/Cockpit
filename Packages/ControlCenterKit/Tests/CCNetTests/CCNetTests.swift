import CCCore
import CryptoKit
import Foundation
import Testing
@testable import CCNet

actor MemoryRegistry: DeviceRegistry {
    var devices: [String: PairedDevice] = [:]
    func device(_ id: String) async -> PairedDevice? { devices[id] }
    func store(_ device: PairedDevice) async { devices[device.deviceID] = device }
    func touch(_ id: String) async { devices[id]?.lastSeen = .now }
}

/// Records the code the Mac would display, so the "user" can type it.
final class CodeBoard: PairingPresenter, @unchecked Sendable {
    private let lock = NSLock()
    private var code: String?
    private var rejectHandler: (@Sendable () -> Void)?
    var rejectImmediately = false

    func present(code: String, deviceName: String, platform: DevicePlatform, reject: @escaping @Sendable () -> Void) async {
        lock.withLock {
            self.code = code
            rejectHandler = reject
        }
        if rejectImmediately { reject() }
    }

    func finish(deviceName: String, success: Bool) async {}

    func waitForCode() async -> String {
        while true {
            let current = lock.withLock { code }
            if let current { return current }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

@Suite("Crypto")
struct CryptoTests {
    @Test func secureBoxRoundTrip() throws {
        let key = SymmetricKey(size: .bits256)
        var sealer = SecureBox(key: key, direction: .initiator)
        var opener = SecureBox(key: key, direction: .initiator)
        for text in ["hello", "", String(repeating: "x", count: 10_000)] {
            let frame = try sealer.seal(Data(text.utf8))
            #expect(try opener.open(frame) == Data(text.utf8))
        }
    }

    @Test func replayAndTamperRejected() throws {
        let key = SymmetricKey(size: .bits256)
        var sealer = SecureBox(key: key, direction: .responder)
        var opener = SecureBox(key: key, direction: .responder)
        let first = try sealer.seal(Data("one".utf8))
        _ = try opener.open(first)
        #expect(throws: SecureBoxError.self) { try opener.open(first) }

        var tampered = try sealer.seal(Data("two".utf8))
        tampered[tampered.count - 1] ^= 0xFF
        #expect(throws: (any Error).self) { try opener.open(tampered) }
    }

    @Test func directionIsBound() throws {
        let key = SymmetricKey(size: .bits256)
        var sealer = SecureBox(key: key, direction: .initiator)
        var wrongWay = SecureBox(key: key, direction: .responder)
        let frame = try sealer.seal(Data("reflect me".utf8))
        #expect(throws: (any Error).self) { try wrongWay.open(frame) }
    }

    @Test func shortCodeIsSixDigits() {
        for _ in 0..<50 {
            let code = PairingCrypto.shortCode(transcript: CCRandom.bytes(32))
            #expect(code.count == 6)
            #expect(code.allSatisfy { $0.isNumber })
        }
    }
}

@Suite("Handshake")
struct HandshakeTests {
    let mac = MacIdentity(macID: "mac-1", macName: "MacBook Pro", helperVersion: "1.0")
    let device = DeviceIdentity(deviceID: "ipad-1", deviceName: "iPad Pro", platform: .iPad, appVersion: "1.0")

    @Test("Pair, then authenticate, then talk encrypted")
    func fullFlow() async throws {
        let registry = MemoryRegistry()
        let board = CodeBoard()
        let (clientStream, serverStream) = PipeByteStream.pair()
        let client = MessageChannel(stream: clientStream)
        let server = MessageChannel(stream: serverStream)

        let serverTask = Task {
            try await ServerHandshake.run(channel: server, mac: mac, registry: registry, presenter: board)
        }
        let paired = try await ClientHandshake.pair(channel: client, device: device) { _ in await board.waitForCode() }
        #expect(paired.macID == "mac-1")
        #expect(paired.ltk.count == 32)

        let outcome = try await ClientHandshake.authenticate(channel: client, device: device, mac: paired, transport: .wifi)
        #expect(outcome.macName == "MacBook Pro")
        let peer = try await serverTask.value
        #expect(peer.device.ltk == paired.ltk)
        #expect(await client.isEncrypted)
        #expect(await server.isEncrypted)

        try await client.send(.buttonTap(ButtonTap(action: .media(.playPause))), id: 42)
        let received = try await server.receive()
        guard case .buttonTap(let tap) = received.body else { Issue.record("wrong body"); return }
        #expect(tap.action == .media(.playPause))
        #expect(received.id == 42)

        try await server.send(.actionResult(.success), replyTo: 42)
        let reply = try await client.receive()
        #expect(reply.replyTo == 42)
    }

    @Test("A wrong code never completes pairing")
    func wrongCode() async throws {
        let registry = MemoryRegistry()
        let board = CodeBoard()
        let (clientStream, serverStream) = PipeByteStream.pair()
        let client = MessageChannel(stream: clientStream)
        let server = MessageChannel(stream: serverStream)
        let serverTask = Task { try await ServerHandshake.run(channel: server, mac: mac, registry: registry, presenter: board) }

        await #expect(throws: HandshakeError.codeMismatch) {
            _ = try await ClientHandshake.pair(channel: client, device: device) { attempt in
                let real = await board.waitForCode()
                return real == "000000" ? "111111" : "000000"
            }
        }
        _ = await serverTask.result
        #expect(await registry.device("ipad-1") == nil)
    }

    @Test("Rejecting on the Mac ends pairing")
    func rejected() async throws {
        let registry = MemoryRegistry()
        let board = CodeBoard()
        board.rejectImmediately = true
        let (clientStream, serverStream) = PipeByteStream.pair()
        let client = MessageChannel(stream: clientStream)
        let server = MessageChannel(stream: serverStream)
        let serverTask = Task { try await ServerHandshake.run(channel: server, mac: mac, registry: registry, presenter: board) }
        await #expect(throws: (any Error).self) {
            _ = try await ClientHandshake.pair(channel: client, device: device) { _ in
                try await Task.sleep(nanoseconds: 50_000_000)
                return await board.waitForCode()
            }
        }
        _ = await serverTask.result
        #expect(await registry.device("ipad-1") == nil)
    }

    @Test("A forgotten device is told to pair again")
    func unknownDevice() async throws {
        let (clientStream, serverStream) = PipeByteStream.pair()
        let client = MessageChannel(stream: clientStream)
        let server = MessageChannel(stream: serverStream)
        let serverTask = Task { try await ServerHandshake.run(channel: server, mac: mac, registry: MemoryRegistry(), presenter: CodeBoard()) }
        let stale = PairedMac(macID: "mac-1", macName: "MacBook Pro", ltk: CCRandom.bytes(32))
        await #expect(throws: HandshakeError.unknownDevice) {
            _ = try await ClientHandshake.authenticate(channel: client, device: device, mac: stale, transport: .wifi)
        }
        _ = await serverTask.result
    }

    @Test("An impostor key fails authentication")
    func wrongKey() async throws {
        let registry = MemoryRegistry()
        await registry.store(PairedDevice(deviceID: "ipad-1", deviceName: "iPad", platform: .iPad, ltk: CCRandom.bytes(32)))
        let (clientStream, serverStream) = PipeByteStream.pair()
        let client = MessageChannel(stream: clientStream)
        let server = MessageChannel(stream: serverStream)
        let serverTask = Task { try await ServerHandshake.run(channel: server, mac: mac, registry: registry, presenter: CodeBoard()) }
        let impostor = PairedMac(macID: "mac-1", macName: "MacBook Pro", ltk: CCRandom.bytes(32))
        await #expect(throws: (any Error).self) {
            _ = try await ClientHandshake.authenticate(channel: client, device: device, mac: impostor, transport: .wifi)
        }
        await #expect(throws: (any Error).self) { _ = try await serverTask.value }
    }
}
