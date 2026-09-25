import CryptoKit
import Foundation

/// Which side of a handshake: the iPad/iPhone initiates, the Mac responds —
/// independent of who opened the TCP connection (over USB the Mac dials in).
public enum Role: String, Sendable {
    case initiator = "I"
    case responder = "R"

    var byte: UInt8 { self == .initiator ? 0x49 : 0x52 }
}

public enum CCRandom {
    public static func bytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}

// MARK: - Pairing

/// Commitment-based short-authentication-string pairing (the ZRTP / Bluetooth
/// "passkey" family):
///
/// 1. iPad → Mac  `pairBegin`   commitment = H(pkI ‖ nI)
/// 2. Mac  → iPad `pairKey`     pkR, nR
/// 3. iPad → Mac  `pairReveal`  pkI, nI          (Mac checks the commitment)
/// 4. Both derive X25519(pkI, pkR) and a 6-digit code from the transcript. The
///    Mac displays it; you type it on the iPad; the iPad compares locally.
/// 5. iPad → Mac  `pairConfirm` HMAC(k, "I" ‖ transcript)
/// 6. Mac  → iPad `pairResult`  HMAC(k, "R" ‖ transcript)
///
/// Because the iPad commits before it sees the Mac's key, a man in the middle
/// cannot grind keys until both codes collide: it gets one 1-in-a-million guess
/// per attempt. The result is a 256-bit long-term key stored in both Keychains.
public enum PairingCrypto {
    public static func commitment(publicKey: Data, nonce: Data) -> Data {
        Data(SHA256.hash(data: Data("cc-commit-v1".utf8) + publicKey + nonce))
    }

    public static func transcript(initiatorKey: Data, responderKey: Data, initiatorNonce: Data, responderNonce: Data, deviceID: String, macID: String) -> Data {
        var data = Data("cc-transcript-v1".utf8)
        data += initiatorKey + responderKey + initiatorNonce + responderNonce
        data += Data(deviceID.utf8) + [0] + Data(macID.utf8)
        return Data(SHA256.hash(data: data))
    }

    /// Six decimal digits.
    public static func shortCode(transcript: Data) -> String {
        let digest = Array(SHA256.hash(data: Data("cc-sas-v1".utf8) + transcript))
        let value = (UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3])) % 1_000_000
        return String(format: "%06u", value)
    }

    public static func derive(shared: SharedSecret, transcript: Data) -> (confirm: SymmetricKey, longTerm: SymmetricKey) {
        let confirm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("cc-confirm-v1".utf8), outputByteCount: 32)
        let longTerm = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("cc-ltk-v1".utf8), outputByteCount: 32)
        return (confirm, longTerm)
    }

    public static func confirmation(key: SymmetricKey, role: Role, transcript: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data("cc-confirm-\(role.rawValue)".utf8) + transcript, using: key))
    }

    public static func verifyConfirmation(_ mac: Data, key: SymmetricKey, role: Role, transcript: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data("cc-confirm-\(role.rawValue)".utf8) + transcript, using: key)
    }
}

// MARK: - Session

/// Every connection after pairing: fresh nonces from both sides, mutual HMAC
/// proofs over the long-term key, then per-direction ChaCha20-Poly1305 keys.
public enum SessionCrypto {
    private static func proofMessage(role: Role, deviceID: String, macID: String, initiatorNonce: Data, responderNonce: Data) -> Data {
        var data = Data("cc-auth-\(role.rawValue)".utf8)
        data += Data(deviceID.utf8) + [0] + Data(macID.utf8) + [0]
        data += initiatorNonce + responderNonce
        return data
    }

    public static func proof(ltk: SymmetricKey, role: Role, deviceID: String, macID: String, initiatorNonce: Data, responderNonce: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: proofMessage(role: role, deviceID: deviceID, macID: macID, initiatorNonce: initiatorNonce, responderNonce: responderNonce), using: ltk))
    }

    public static func verify(_ proof: Data, ltk: SymmetricKey, role: Role, deviceID: String, macID: String, initiatorNonce: Data, responderNonce: Data) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: proofMessage(role: role, deviceID: deviceID, macID: macID, initiatorNonce: initiatorNonce, responderNonce: responderNonce), using: ltk)
    }

    public static func sessionKeys(ltk: SymmetricKey, initiatorNonce: Data, responderNonce: Data) -> (initiatorToResponder: SymmetricKey, responderToInitiator: SymmetricKey) {
        let salt = initiatorNonce + responderNonce
        let i2r = HKDF<SHA256>.deriveKey(inputKeyMaterial: ltk, salt: salt, info: Data("cc-i2r-v1".utf8), outputByteCount: 32)
        let r2i = HKDF<SHA256>.deriveKey(inputKeyMaterial: ltk, salt: salt, info: Data("cc-r2i-v1".utf8), outputByteCount: 32)
        return (i2r, r2i)
    }
}

// MARK: - Frame encryption

public enum SecureBoxError: Error, LocalizedError {
    case malformed
    case replay(expected: UInt64, got: UInt64)

    public var errorDescription: String? {
        switch self {
        case .malformed: "Malformed encrypted frame"
        case .replay(let expected, let got): "Out-of-order frame (expected \(expected), got \(got))"
        }
    }
}

/// One direction of an encrypted session. Frame = counter (8, big-endian) ‖
/// ciphertext ‖ tag (16). The counter is the nonce, so it must strictly
/// increase — a replayed or reordered frame is rejected.
public struct SecureBox {
    private let key: SymmetricKey
    private let direction: Role
    private var counter: UInt64 = 0

    public init(key: SymmetricKey, direction: Role) {
        self.key = key
        self.direction = direction
    }

    public mutating func seal(_ plaintext: Data) throws -> Data {
        counter += 1
        let counterBytes = Self.bigEndian(counter)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + counterBytes)
        let box = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce, authenticating: Data([direction.byte]))
        return counterBytes + box.ciphertext + box.tag
    }

    public mutating func open(_ frame: Data) throws -> Data {
        guard frame.count >= 24 else { throw SecureBoxError.malformed }
        let bytes = [UInt8](frame)
        let received = bytes[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard received == counter + 1 else { throw SecureBoxError.replay(expected: counter + 1, got: received) }
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + Data(bytes[0..<8]))
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: Data(bytes[8..<(bytes.count - 16)]), tag: Data(bytes[(bytes.count - 16)...]))
        let plaintext = try ChaChaPoly.open(box, using: key, authenticating: Data([direction.byte]))
        counter = received
        return plaintext
    }

    static func bigEndian(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}

public extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}

/// Constant-time comparison for codes typed by a human.
public func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let x = Array(a.utf8)
    let y = Array(b.utf8)
    guard x.count == y.count else { return false }
    var diff: UInt8 = 0
    for i in x.indices { diff |= x[i] ^ y[i] }
    return diff == 0
}
