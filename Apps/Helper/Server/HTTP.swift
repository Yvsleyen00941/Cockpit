import Foundation
@preconcurrency import Network

/// Just enough HTTP/1.1 for the loopback API and the OAuth redirect.
struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var json: Any? {
        body.isEmpty ? nil : try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
    }
}

enum HTTPIO {
    enum Failure: Error { case malformed, tooLarge, closed }

    static func read(_ connection: NWConnection, limit: Int = 1_048_576) async throws -> HTTPRequest {
        var buffer = Data()
        let separator = Data("\r\n\r\n".utf8)
        var headerEnd: Range<Data.Index>?
        while headerEnd == nil {
            let chunk = try await receive(connection)
            guard !chunk.isEmpty else { throw Failure.closed }
            buffer.append(chunk)
            guard buffer.count <= limit else { throw Failure.tooLarge }
            headerEnd = buffer.range(of: separator)
        }
        guard let headerEnd else { throw Failure.malformed }
        let head = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { throw Failure.malformed }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        var body = Data(buffer[headerEnd.upperBound...])
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length <= limit else { throw Failure.tooLarge }
        while body.count < length {
            let chunk = try await receive(connection)
            guard !chunk.isEmpty else { break }
            body.append(chunk)
        }
        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return HTTPRequest(method: String(requestLine[0]), path: components?.path ?? target, query: query, headers: headers, body: body)
    }

    private static func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if isComplete { continuation.resume(returning: Data()) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }

    static func respond(_ connection: NWConnection, status: Int, contentType: String = "application/json", body: Data) {
        let reason: String = switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        default: "Error"
        }
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in connection.cancel() })
    }

    static func respondJSON(_ connection: NWConnection, status: Int = 200, _ object: some Encodable) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        respond(connection, status: status, body: (try? encoder.encode(object)) ?? Data("{}".utf8))
    }
}

/// A one-shot loopback listener for an OAuth redirect (`http://localhost:8080`).
enum OAuthCallbackServer {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func waitForCode(port: UInt16, expectedState: String, timeout: TimeInterval) async throws -> String {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw Failure(message: "Bad port") }
        let listener = try NWListener(using: parameters, on: nwPort)
        defer { listener.cancel() }

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    let once = OnceBox()
                    listener.newConnectionHandler = { connection in
                        connection.start(queue: .global())
                        Task {
                            guard let request = try? await HTTPIO.read(connection) else { return }
                            guard request.path != "/favicon.ico" else {
                                HTTPIO.respond(connection, status: 404, contentType: "text/plain", body: Data())
                                return
                            }
                            if let error = request.query["error"] {
                                HTTPIO.respond(connection, status: 400, contentType: "text/html; charset=utf-8", body: page(title: "WHOOP didn't connect", detail: error))
                                if once.fire() { continuation.resume(throwing: Failure(message: "WHOOP returned \(error)")) }
                            } else if let code = request.query["code"], request.query["state"] == expectedState {
                                HTTPIO.respond(connection, status: 200, contentType: "text/html; charset=utf-8", body: page(title: "WHOOP connected", detail: "You can close this tab — recovery, strain and sleep are on their way to your iPad."))
                                if once.fire() { continuation.resume(returning: code) }
                            } else {
                                HTTPIO.respond(connection, status: 400, contentType: "text/html; charset=utf-8", body: page(title: "Unexpected request", detail: "State did not match. Start again from Control Center."))
                            }
                        }
                    }
                    listener.stateUpdateHandler = { state in
                        if case .failed(let error) = state, once.fire() {
                            continuation.resume(throwing: Failure(message: "Port \(port) is busy: \(error.localizedDescription)"))
                        }
                    }
                    listener.start(queue: .global())
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw Failure(message: "Timed out waiting for the WHOOP sign-in")
            }
            let code = try await group.next()!
            group.cancelAll()
            return code
        }
    }

    private static func page(title: String, detail: String) -> Data {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>\(title)</title>
        <style>
        body{margin:0;height:100vh;display:grid;place-items:center;background:#0A0A0F;color:#F0F0F0;font:16px -apple-system,BlinkMacSystemFont,sans-serif}
        .card{max-width:420px;padding:36px 40px;border-radius:20px;background:linear-gradient(#1D2844,#16213E);border:1px solid rgba(46,134,171,.35);text-align:center}
        h1{font-size:22px;margin:14px 0 8px}p{color:#888;line-height:1.5;margin:0}
        .dot{width:14px;height:14px;border-radius:50%;background:#2ECC71;margin:0 auto;box-shadow:0 0 18px #2ECC71}
        </style></head><body><div class="card"><div class="dot"></div><h1>\(title)</h1><p>\(detail)</p></div></body></html>
        """
        return Data(html.utf8)
    }
}

final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
    }
}
