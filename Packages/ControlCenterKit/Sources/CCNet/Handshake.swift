import CCCore
import CryptoKit
import Foundation

// MARK: - Identities & records

public struct DeviceIdentity: Sendable, Hashable {
    public var deviceID: String
    public var deviceName: String
    public var platform: DevicePlatform
    public var appVersion: String

    public init(deviceID: String, deviceName: String, platform: DevicePlatform, appVersion: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
    }
}

public struct MacIdentity: Sendable, Hashable {
    public var macID: String
    public var macName: String
    public var helperVersion: String

    public init(macID: String, macName: String, helperVersion: String) {
        self.macID = macID
        self.macName = macName
        self.helperVersion = helperVersion
    }
}

/// What an iPad remembers about a Mac it paired with (stored in its Keychain).
public struct PairedMac: Codable, Sendable, Hashable, Identifiable {
    public var macID: String
    public var macName: String
    public var ltk: Data
    public var pairedAt: Date
    /// Last address that worked — lets widgets and intents dial in without Bonjour.
    public var lastHost: String?
    public var lastPort: UInt16?
    /// Bonjour service name, the fallback when the address changed.
    public var serviceName: String?

    public var id: String { macID }

    public init(macID: String, macName: String, ltk: Data, pairedAt: Date = .now, lastHost: String? = nil, lastPort: UInt16? = nil, serviceName: String? = nil) {
        self.macID = macID
        self.macName = macName
        self.ltk = ltk
        self.pairedAt = pairedAt
        self.lastHost = lastHost
        self.lastPort = lastPort
        self.serviceName = serviceName
    }
}

/// What a Mac remembers about a paired device (stored in its Keychain).
public struct PairedDevice: Codable, Sendable, Hashable, Identifiable {
    public var deviceID: String
    public var deviceName: String
    public var platform: DevicePlatform
    public var ltk: Data
    public var pairedAt: Date
    public var lastSeen: Date?

    public var id: String { deviceID }

    public init(deviceID: String, deviceName: String, platform: DevicePlatform, ltk: Data, pairedAt: Date = .now, lastSeen: Date? = nil) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.ltk = ltk
        self.pairedAt = pairedAt
        self.lastSeen = lastSeen
    }
}

public enum HandshakeError: Error, LocalizedError, Equatable {
    case unknownDevice
    case wrongMac
    case authenticationFailed(String)
    case pairingRejected(String)
    case codeMismatch
    case protocolMismatch(Int)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .unknownDevice: "This Mac doesn't recognise this device anymore. Pair again."
        case .wrongMac: "Connected to a different Mac than expected."
        case .authenticationFailed(let reason): "Authentication failed: \(reason)"
        case .pairingRejected(let reason): reason
        case .codeMismatch: "That code doesn't match the one on your Mac."
        case .protocolMismatch(let version): "The Mac speaks protocol v\(version); update both apps."
        case .unexpected(let what): "Unexpected message: \(what)"
        }
    }
}

// MARK: - Client (iPad / iPhone / widget)

public struct AuthOutcome: Sendable {
    public var macName: String
    public var helperVersion: String?
}

public enum ClientHandshake {
    /// Authenticates to a paired Mac and switches the channel to encryption.
    public static func authenticate(channel: MessageChannel, device: DeviceIdentity, mac: PairedMac, transport: LinkTransport, timeout: TimeInterval = 8) async throws -> AuthOutcome {
        let expected = mac
        let (outcome, _) = try await authenticate(channel: channel, device: device, transport: transport, timeout: timeout) { macID in
            macID == expected.macID ? expected : nil
        }
        return outcome
    }

    /// Authenticates to whichever paired Mac answers — used over USB, where
    /// the Mac dials in and only the challenge says who it is.
    public static func authenticate(channel: MessageChannel, device: DeviceIdentity, transport: LinkTransport, timeout: TimeInterval = 8, resolve: @Sendable (_ macID: String) -> PairedMac?) async throws -> (AuthOutcome, PairedMac) {
        let initiatorNonce = CCRandom.bytes(32)
        try await channel.send(.hello(Hello(deviceID: device.deviceID, deviceName: device.deviceName, platform: device.platform, appVersion: device.appVersion, nonce: initiatorNonce, transport: transport)))

        let first = try await channel.receive(timeout: timeout)
        if case .authResult(let result) = first.body, !result.ok {
            if (result.reason ?? "").contains("protocol") { throw HandshakeError.protocolMismatch(ccProtocolVersion) }
            throw HandshakeError.authenticationFailed(result.reason ?? "rejected")
        }
        guard case .challenge(let challenge) = first.body else { throw HandshakeError.unexpected(first.type.rawValue) }
        guard let mac = resolve(challenge.macID) else { throw HandshakeError.wrongMac }
        guard challenge.known else { throw HandshakeError.unknownDevice }

        let ltk = SymmetricKey(data: mac.ltk)
        let proof = SessionCrypto.proof(ltk: ltk, role: .initiator, deviceID: device.deviceID, macID: mac.macID, initiatorNonce: initiatorNonce, responderNonce: challenge.nonce)
        try await channel.send(.auth(AuthProof(proof: proof)))

        let reply = try await channel.receive(timeout: timeout)
        guard case .authResult(let result) = reply.body else { throw HandshakeError.unexpected(reply.type.rawValue) }
        guard result.ok else { throw HandshakeError.authenticationFailed(result.reason ?? "rejected") }
        guard let serverProof = result.proof,
              SessionCrypto.verify(serverProof, ltk: ltk, role: .responder, deviceID: device.deviceID, macID: mac.macID, initiatorNonce: initiatorNonce, responderNonce: challenge.nonce)
        else { throw HandshakeError.authenticationFailed("the Mac could not prove its identity") }

        let keys = SessionCrypto.sessionKeys(ltk: ltk, initiatorNonce: initiatorNonce, responderNonce: challenge.nonce)
        await channel.enableEncryption(sendKey: keys.initiatorToResponder, sendRole: .initiator, receiveKey: keys.responderToInitiator, receiveRole: .responder)
        return (AuthOutcome(macName: challenge.macName, helperVersion: result.helperVersion), mac)
    }

    /// Pairs with a Mac. `enterCode` is called when the Mac is showing its
    /// code; it returns what the user typed (called again after a typo).
    /// `codeAccepted` fires once the typed code matches, while the Mac stores
    /// the key — that can take a while if macOS asks about Keychain access.
    public static func pair(
        channel: MessageChannel,
        device: DeviceIdentity,
        codeAccepted: (@Sendable () async -> Void)? = nil,
        enterCode: @Sendable (_ attempt: Int) async throws -> String
    ) async throws -> PairedMac {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let initiatorKey = ephemeral.publicKey.rawRepresentation
        let initiatorNonce = CCRandom.bytes(32)

        try await channel.send(.pairBegin(PairBegin(deviceID: device.deviceID, deviceName: device.deviceName, platform: device.platform, commitment: PairingCrypto.commitment(publicKey: initiatorKey, nonce: initiatorNonce))))

        let keyMessage = try await channel.receive(timeout: 15)
        if case .pairResult(let result) = keyMessage.body {
            throw HandshakeError.pairingRejected(result.reason ?? "The Mac declined.")
        }
        guard case .pairKey(let pairKey) = keyMessage.body else { throw HandshakeError.unexpected(keyMessage.type.rawValue) }

        try await channel.send(.pairReveal(PairReveal(publicKey: initiatorKey, nonce: initiatorNonce)))

        let responderKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pairKey.publicKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: responderKey)
        let transcript = PairingCrypto.transcript(initiatorKey: initiatorKey, responderKey: pairKey.publicKey, initiatorNonce: initiatorNonce, responderNonce: pairKey.nonce, deviceID: device.deviceID, macID: pairKey.macID)
        let code = PairingCrypto.shortCode(transcript: transcript)
        let keys = PairingCrypto.derive(shared: shared, transcript: transcript)

        var attempt = 0
        while true {
            attempt += 1
            let typed = try await enterCode(attempt).filter(\.isNumber)
            if constantTimeEquals(typed, code) { break }
            if attempt >= 5 {
                try? await channel.send(.pairResult(PairResult(ok: false, reason: "Too many wrong codes")))
                throw HandshakeError.codeMismatch
            }
        }

        await codeAccepted?()
        try await channel.send(.pairConfirm(PairConfirm(mac: PairingCrypto.confirmation(key: keys.confirm, role: .initiator, transcript: transcript))))
        let resultMessage = try await channel.receive(timeout: 60)
        guard case .pairResult(let result) = resultMessage.body else { throw HandshakeError.unexpected(resultMessage.type.rawValue) }
        guard result.ok else { throw HandshakeError.pairingRejected(result.reason ?? "The Mac declined.") }
        guard let mac = result.mac, PairingCrypto.verifyConfirmation(mac, key: keys.confirm, role: .responder, transcript: transcript) else {
            throw HandshakeError.pairingRejected("The Mac's confirmation did not verify.")
        }
        return PairedMac(macID: pairKey.macID, macName: pairKey.macName, ltk: keys.longTerm.rawData)
    }
}

// MARK: - Server (Mac)

public protocol DeviceRegistry: Sendable {
    func device(_ id: String) async -> PairedDevice?
    func store(_ device: PairedDevice) async
    func touch(_ id: String) async
}

/// Shows the pairing code on the Mac. `present` must return promptly; call
/// `reject` if the user declines the request on the Mac.
public protocol PairingPresenter: Sendable {
    func present(code: String, deviceName: String, platform: DevicePlatform, reject: @escaping @Sendable () -> Void) async
    func finish(deviceName: String, success: Bool) async
}

public struct AuthenticatedPeer: Sendable {
    public var device: PairedDevice
    public var hello: Hello
}

public enum ServerHandshake {
    public static func run(channel: MessageChannel, mac: MacIdentity, registry: DeviceRegistry, presenter: PairingPresenter, allowPairing: Bool = true) async throws -> AuthenticatedPeer {
        var message = try await channel.receive(timeout: 15)

        if case .pairBegin(let begin) = message.body {
            guard allowPairing else {
                try? await channel.send(.pairResult(PairResult(ok: false, reason: "Pairing is turned off on this Mac.")))
                throw HandshakeError.pairingRejected("pairing disabled")
            }
            try await pair(begin: begin, channel: channel, mac: mac, registry: registry, presenter: presenter)
            message = try await channel.receive(timeout: 15)
        }

        guard case .hello(let hello) = message.body else { throw HandshakeError.unexpected(message.type.rawValue) }
        guard hello.protocolVersion == ccProtocolVersion else {
            try? await channel.send(.authResult(AuthResult(ok: false, reason: "protocol v\(ccProtocolVersion) required", helperVersion: mac.helperVersion)))
            throw HandshakeError.protocolMismatch(hello.protocolVersion)
        }

        let responderNonce = CCRandom.bytes(32)
        let known = await registry.device(hello.deviceID)
        try await channel.send(.challenge(Challenge(macID: mac.macID, macName: mac.macName, nonce: responderNonce, known: known != nil)))
        guard let device = known else { throw HandshakeError.unknownDevice }

        let authMessage = try await channel.receive(timeout: 15)
        guard case .auth(let auth) = authMessage.body else { throw HandshakeError.unexpected(authMessage.type.rawValue) }
        let ltk = SymmetricKey(data: device.ltk)
        guard SessionCrypto.verify(auth.proof, ltk: ltk, role: .initiator, deviceID: device.deviceID, macID: mac.macID, initiatorNonce: hello.nonce, responderNonce: responderNonce) else {
            try? await channel.send(.authResult(AuthResult(ok: false, reason: "Authentication failed", helperVersion: mac.helperVersion)))
            throw HandshakeError.authenticationFailed("bad proof")
        }

        let proof = SessionCrypto.proof(ltk: ltk, role: .responder, deviceID: device.deviceID, macID: mac.macID, initiatorNonce: hello.nonce, responderNonce: responderNonce)
        try await channel.send(.authResult(AuthResult(ok: true, proof: proof, helperVersion: mac.helperVersion)))

        let keys = SessionCrypto.sessionKeys(ltk: ltk, initiatorNonce: hello.nonce, responderNonce: responderNonce)
        await channel.enableEncryption(sendKey: keys.responderToInitiator, sendRole: .responder, receiveKey: keys.initiatorToResponder, receiveRole: .initiator)
        await registry.touch(device.deviceID)
        return AuthenticatedPeer(device: device, hello: hello)
    }

    static func pair(begin: PairBegin, channel: MessageChannel, mac: MacIdentity, registry: DeviceRegistry, presenter: PairingPresenter) async throws {
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let responderKey = ephemeral.publicKey.rawRepresentation
        let responderNonce = CCRandom.bytes(32)
        try await channel.send(.pairKey(PairKey(macID: mac.macID, macName: mac.macName, publicKey: responderKey, nonce: responderNonce)))

        let revealMessage = try await channel.receive(timeout: 15)
        guard case .pairReveal(let reveal) = revealMessage.body else { throw HandshakeError.unexpected(revealMessage.type.rawValue) }
        guard PairingCrypto.commitment(publicKey: reveal.publicKey, nonce: reveal.nonce) == begin.commitment else {
            throw HandshakeError.pairingRejected("commitment mismatch")
        }

        let initiatorKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: reveal.publicKey)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: initiatorKey)
        let transcript = PairingCrypto.transcript(initiatorKey: reveal.publicKey, responderKey: responderKey, initiatorNonce: reveal.nonce, responderNonce: responderNonce, deviceID: begin.deviceID, macID: mac.macID)
        let code = PairingCrypto.shortCode(transcript: transcript)
        let keys = PairingCrypto.derive(shared: shared, transcript: transcript)

        // Show the code and wait (up to three minutes) for the iPad's confirmation.
        await presenter.present(code: code, deviceName: begin.deviceName, platform: begin.platform, reject: {
            Task {
                try? await channel.send(.pairResult(PairResult(ok: false, reason: "Declined on the Mac.")))
                channel.close()
            }
        })
        let confirmMessage: MCCMessage
        do {
            confirmMessage = try await channel.receive(timeout: 180)
        } catch {
            await presenter.finish(deviceName: begin.deviceName, success: false)
            throw HandshakeError.pairingRejected("Pairing was cancelled.")
        }

        guard case .pairConfirm(let confirm) = confirmMessage.body,
              PairingCrypto.verifyConfirmation(confirm.mac, key: keys.confirm, role: .initiator, transcript: transcript)
        else {
            await presenter.finish(deviceName: begin.deviceName, success: false)
            if case .pairResult = confirmMessage.body { throw HandshakeError.codeMismatch }
            try? await channel.send(.pairResult(PairResult(ok: false, reason: "Confirmation failed.")))
            throw HandshakeError.pairingRejected("bad confirmation")
        }

        await registry.store(PairedDevice(deviceID: begin.deviceID, deviceName: begin.deviceName, platform: begin.platform, ltk: keys.longTerm.rawData))
        try await channel.send(.pairResult(PairResult(ok: true, mac: PairingCrypto.confirmation(key: keys.confirm, role: .responder, transcript: transcript))))
        await presenter.finish(deviceName: begin.deviceName, success: true)
    }
}

// MARK: - Bonjour

public enum Bonjour {
    public static let serviceType = "_ccontrol._tcp"
    public static let defaultPort: UInt16 = 52_520
    public static let localAPIPort: UInt16 = 52_521
    /// The iPad listens here on loopback for the USB-C (usbmux) tunnel.
    public static let usbPort: UInt16 = 52_530

    public enum TXT {
        public static let macID = "id"
        public static let protocolVersion = "v"
        public static let model = "model"
        public static let host = "host"
    }
}
