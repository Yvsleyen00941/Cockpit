import CCCore
import CCNet
import Darwin
import Foundation

/// USB-C wired mode (the blueprint's zero-latency fallback).
///
/// macOS talks to iPads over the cable through `usbmuxd` — the same daemon
/// Xcode uses. The helper listens for devices attaching, then asks usbmuxd to
/// open a TCP tunnel to port 52530 on the iPad, where Control Center listens on
/// loopback while it's in the foreground. The tunnel carries the exact same
/// encrypted protocol, so the iPad simply prefers it over Wi-Fi.
///
/// Requires the iPad to trust this Mac (the usual "Trust This Computer").
@MainActor
final class USBBridge {
    private var devices: [Int: String] = [:] // usbmux device ID → serial
    private var connected: Set<Int> = []
    private var attempts: [Int: Task<Void, Never>] = [:]
    private var listenTask: Task<Void, Never>?
    private(set) var attachedCount = 0

    func start() {
        listenTask?.cancel()
        listenTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                await USBBridge.listen()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    /// Blocking event loop on a background thread.
    private nonisolated static func listen() async {
        guard let fd = USBMux.connect() else { return }
        defer { close(fd) }
        guard USBMux.send(fd, ["MessageType": "Listen", "ClientVersionString": "ControlCenterHelper", "ProgName": "ControlCenterHelper", "kLibUSBMuxVersion": 3]),
              let reply = USBMux.receive(fd), (reply["Number"] as? Int) == 0 else { return }
        while !Task.isCancelled {
            guard let message = USBMux.receive(fd) else { return }
            let type = message["MessageType"] as? String
            let id = message["DeviceID"] as? Int ?? 0
            if type == "Attached", let properties = message["Properties"] as? [String: Any], (properties["ConnectionType"] as? String) == "USB" {
                let serial = properties["SerialNumber"] as? String ?? "\(id)"
                await MainActor.run { Hub.shared.usb.attached(id: id, serial: serial) }
            } else if type == "Detached" {
                await MainActor.run { Hub.shared.usb.detached(id: id) }
            }
        }
    }

    private func attached(id: Int, serial: String) {
        devices[id] = serial
        attachedCount = devices.count
        Log.shared.info("USB device attached (\(serial.prefix(8))…)")
        scheduleConnect(id)
    }

    private func detached(id: Int) {
        devices[id] = nil
        connected.remove(id)
        attempts[id]?.cancel()
        attempts[id] = nil
        attachedCount = devices.count
    }

    /// Keeps trying while the device is attached: Control Center only listens
    /// while it's in the foreground.
    private func scheduleConnect(_ id: Int) {
        attempts[id]?.cancel()
        attempts[id] = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.devices[id] != nil {
                if !self.connected.contains(id) {
                    let fd = await Task.detached { USBMux.tunnel(deviceID: id, port: Bonjour.usbPort) }.value
                    if let fd {
                        self.connected.insert(id)
                        Log.shared.info("USB-C tunnel open")
                        let stream = FDByteStream(fileDescriptor: fd, description: "usb:\(id)")
                        let session = Hub.shared.accept(stream, transport: .usb)
                        // When the tunnel ends (app backgrounded, cable out), dial again.
                        Task { @MainActor in
                            await session.waitUntilClosed()
                            self.connected.remove(id)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Minimal usbmuxd client: 16-byte little-endian header + XML plist.
enum USBMux {
    static let socketPath = "/var/run/usbmuxd"

    static func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            for (index, byte) in pathBytes.enumerated() where index < raw.count { raw[index] = UInt8(bitPattern: byte) }
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func send(_ fd: Int32, _ message: [String: Any], tag: UInt32 = 1) -> Bool {
        guard let payload = try? PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0) else { return false }
        var header = Data()
        for value in [UInt32(16 + payload.count), 1, 8, tag] {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        let packet = header + payload
        return packet.withUnsafeBytes { raw in
            var sent = 0
            while sent < packet.count {
                let n = write(fd, raw.baseAddress!.advanced(by: sent), packet.count - sent)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    static func receive(_ fd: Int32) -> [String: Any]? {
        guard let header = readExactly(fd, 16) else { return nil }
        let length = header.withUnsafeBytes { Int(UInt32(littleEndian: $0.load(as: UInt32.self))) }
        guard length >= 16, length < 1_048_576, let body = readExactly(fd, length - 16) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
    }

    private static func readExactly(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var got = 0
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            while got < count {
                let n = read(fd, raw.baseAddress!.advanced(by: got), count - got)
                if n <= 0 { return false }
                got += n
            }
            return true
        }
        return ok ? data : nil
    }

    /// Opens a tunnel to `port` on the device; returns the connected fd.
    static func tunnel(deviceID: Int, port: UInt16) -> Int32? {
        guard let fd = connect() else { return nil }
        let request: [String: Any] = [
            "MessageType": "Connect",
            "ClientVersionString": "ControlCenterHelper",
            "ProgName": "ControlCenterHelper",
            "DeviceID": deviceID,
            // usbmuxd wants the port in network byte order.
            "PortNumber": Int(port.bigEndian),
        ]
        guard send(fd, request), let reply = receive(fd), (reply["Number"] as? Int) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }
}
