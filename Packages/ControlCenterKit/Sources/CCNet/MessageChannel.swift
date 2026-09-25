import CCCore
import CryptoKit
import Foundation

/// Length-prefixed JSON messages over a `ByteStream`, optionally encrypted.
///
/// Frame: 4-byte big-endian length ‖ body. The body is the JSON-encoded
/// `MCCMessage` during the handshake and a `SecureBox` frame afterwards.
public actor MessageChannel {
    public static let maxFrame = 8 * 1024 * 1024

    public nonisolated let stream: ByteStream
    private var sealer: SecureBox?
    private var opener: SecureBox?
    private var timedOut = false
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(stream: ByteStream) {
        self.stream = stream
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    public var isEncrypted: Bool { sealer != nil }

    public func enableEncryption(sendKey: SymmetricKey, sendRole: Role, receiveKey: SymmetricKey, receiveRole: Role) {
        sealer = SecureBox(key: sendKey, direction: sendRole)
        opener = SecureBox(key: receiveKey, direction: receiveRole)
    }

    public func send(_ message: MCCMessage) async throws {
        var body = try encoder.encode(message)
        if sealer != nil { body = try sealer!.seal(body) }
        guard body.count <= Self.maxFrame else { throw StreamError.frameTooLarge(body.count) }
        var frame = Data(capacity: body.count + 4)
        frame.append(contentsOf: withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) })
        frame.append(body)
        try await stream.send(frame)
    }

    public func send(_ body: MCCBody, id: UInt32? = nil, replyTo: UInt32? = nil) async throws {
        try await send(MCCMessage(body, id: id, replyTo: replyTo))
    }

    public func receive() async throws -> MCCMessage {
        let header = try await stream.receive(exactly: 4)
        let length = header.reduce(0) { $0 << 8 | Int($1) }
        guard length > 0, length <= Self.maxFrame else { throw StreamError.frameTooLarge(length) }
        var body = try await stream.receive(exactly: length)
        if opener != nil { body = try opener!.open(body) }
        return try decoder.decode(MCCMessage.self, from: body)
    }

    /// Receives with a deadline. On timeout the stream is closed — a half-read
    /// frame would otherwise desynchronise the channel.
    public func receive(timeout seconds: TimeInterval) async throws -> MCCMessage {
        let watchdog = Task { [weak self] in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await self?.expire()
        }
        defer { watchdog.cancel() }
        do {
            return try await receive()
        } catch {
            if timedOut { throw StreamError.timeout }
            throw error
        }
    }

    public nonisolated func close() {
        stream.close()
    }

    private func expire() {
        timedOut = true
        stream.close()
    }
}
