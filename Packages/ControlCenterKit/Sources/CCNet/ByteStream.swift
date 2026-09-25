import Foundation
@preconcurrency import Network

// MARK: - Byte streams

/// A reliable, ordered byte pipe. TCP over Wi-Fi (`NWByteStream`), a usbmux
/// tunnel over the USB-C cable (`FDByteStream`) and an in-memory pipe for tests
/// all look the same to the protocol above.
public protocol ByteStream: AnyObject, Sendable {
    func send(_ data: Data) async throws
    func receive(exactly count: Int) async throws -> Data
    func close()
    var peerDescription: String { get }
}

public enum StreamError: Error, LocalizedError, Equatable {
    case closed
    case timeout
    case frameTooLarge(Int)
    case connectFailed(String)

    public var errorDescription: String? {
        switch self {
        case .closed: "The connection closed"
        case .timeout: "The connection timed out"
        case .frameTooLarge(let size): "Frame too large (\(size) bytes)"
        case .connectFailed(let reason): "Could not connect: \(reason)"
        }
    }
}

/// Accumulator touched only from one serial queue.
final class ByteBox: @unchecked Sendable {
    var data = Data()
}

/// Fires once, from any thread.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}

// MARK: - Network framework

public extension NWParameters {
    /// TCP tuned for a control surface: no Nagle, fast keepalive, peer-to-peer
    /// allowed so the iPad can still find the Mac without a shared router.
    static func controlCenter(peerToPeer: Bool = true) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        tcp.connectionTimeout = 6
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.includePeerToPeer = peerToPeer
        return parameters
    }
}

public final class NWByteStream: ByteStream, @unchecked Sendable {
    public let connection: NWConnection
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var isClosed = false
    private var onClose: (@Sendable () -> Void)?

    public init(_ connection: NWConnection, queue: DispatchQueue = DispatchQueue(label: "cc.stream", qos: .userInitiated)) {
        self.connection = connection
        self.queue = queue
    }

    public var peerDescription: String {
        "\(connection.endpoint)"
    }

    /// The remote address once connected (for remembering the Mac's IP).
    public var remoteEndpoint: NWEndpoint? {
        connection.currentPath?.remoteEndpoint
    }

    /// Starts the connection and waits until it is ready.
    public func start(timeout: TimeInterval = 8, onClose: (@Sendable () -> Void)? = nil) async throws {
        self.onClose = onClose
        let once = OnceFlag()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if once.fire() { continuation.resume() }
                case .failed(let error):
                    if once.fire() { continuation.resume(throwing: StreamError.connectFailed(error.localizedDescription)) }
                    self?.markClosed()
                case .waiting(let error):
                    if once.fire() {
                        continuation.resume(throwing: StreamError.connectFailed(error.localizedDescription))
                        self?.connection.cancel()
                    }
                case .cancelled:
                    if once.fire() { continuation.resume(throwing: StreamError.closed) }
                    self?.markClosed()
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                if once.fire() {
                    continuation.resume(throwing: StreamError.timeout)
                    self?.connection.cancel()
                }
            }
        }
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: StreamError.closed)
                } else {
                    continuation.resume(throwing: StreamError.closed)
                }
            }
        }
    }

    public func close() {
        connection.cancel()
        markClosed()
    }

    private func markClosed() {
        lock.lock()
        let wasClosed = isClosed
        isClosed = true
        let handler = onClose
        onClose = nil
        lock.unlock()
        if !wasClosed { handler?() }
    }
}

// MARK: - File descriptor (usbmux tunnel)

/// Wraps a connected socket file descriptor — used for the usbmuxd tunnel that
/// carries the protocol over the USB-C cable.
public final class FDByteStream: ByteStream, @unchecked Sendable {
    private let io: DispatchIO
    private let queue = DispatchQueue(label: "cc.fdstream", qos: .userInitiated)
    public let peerDescription: String

    public init(fileDescriptor: Int32, description: String) {
        peerDescription = description
        io = DispatchIO(type: .stream, fileDescriptor: fileDescriptor, queue: queue) { _ in
            Darwin.close(fileDescriptor)
        }
        io.setLimit(lowWater: 1)
    }

    public func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let payload = data.withUnsafeBytes { DispatchData(bytes: $0) }
            let once = OnceFlag()
            io.write(offset: 0, data: payload, queue: queue) { done, _, error in
                if error != 0 {
                    if once.fire() { continuation.resume(throwing: StreamError.closed) }
                } else if done {
                    if once.fire() { continuation.resume() }
                }
            }
        }
    }

    public func receive(exactly count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let buffer = ByteBox()
            let once = OnceFlag()
            io.read(offset: 0, length: count, queue: queue) { done, chunk, error in
                if let chunk, !chunk.isEmpty {
                    chunk.enumerateBytes { bytes, _, _ in buffer.data.append(contentsOf: bytes) }
                }
                if error != 0 {
                    if once.fire() { continuation.resume(throwing: StreamError.closed) }
                } else if done {
                    if once.fire() {
                        if buffer.data.count == count {
                            continuation.resume(returning: buffer.data)
                        } else {
                            continuation.resume(throwing: StreamError.closed)
                        }
                    }
                }
            }
        }
    }

    public func close() {
        io.close(flags: .stop)
    }
}

// MARK: - In-memory (tests, demo)

public final class PipeByteStream: ByteStream, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var waiter: (count: Int, continuation: CheckedContinuation<Data, Error>)?
    private var isClosed = false
    private weak var peer: PipeByteStream?
    public let peerDescription = "pipe"

    public static func pair() -> (PipeByteStream, PipeByteStream) {
        let a = PipeByteStream()
        let b = PipeByteStream()
        a.peer = b
        b.peer = a
        return (a, b)
    }

    public func send(_ data: Data) async throws {
        guard let peer, !closed else { throw StreamError.closed }
        peer.deliver(data)
    }

    public func receive(exactly count: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if buffer.count >= count {
                let chunk = buffer.prefix(count)
                buffer.removeFirst(count)
                lock.unlock()
                continuation.resume(returning: Data(chunk))
            } else if isClosed {
                lock.unlock()
                continuation.resume(throwing: StreamError.closed)
            } else {
                waiter = (count, continuation)
                lock.unlock()
            }
        }
    }

    public func close() {
        closeLocal()
        peer?.closeLocal()
    }

    private var closed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }

    private func deliver(_ data: Data) {
        lock.lock()
        buffer.append(data)
        if let pending = waiter, buffer.count >= pending.count {
            let chunk = buffer.prefix(pending.count)
            buffer.removeFirst(pending.count)
            waiter = nil
            lock.unlock()
            pending.continuation.resume(returning: Data(chunk))
        } else {
            lock.unlock()
        }
    }

    private func closeLocal() {
        lock.lock()
        isClosed = true
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.continuation.resume(throwing: StreamError.closed)
    }
}
