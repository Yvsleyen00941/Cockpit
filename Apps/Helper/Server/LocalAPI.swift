import CCCore
import CCNet
import Foundation
@preconcurrency import Network

/// Loopback-only HTTP API (127.0.0.1:52521) for things running on this Mac:
/// your bot's webhook, scripts, cron jobs, Raycast, Alfred…
///
///     curl -H "Authorization: Bearer $TOKEN" -X POST localhost:52521/v1/toast -d '{"title":"Build done"}'
///
/// Every request except `/v1/health` needs the bearer token shown in the
/// helper's Preferences → Advanced (also readable with
/// `defaults read be.yorben.controlcenter.helper localAPIToken`).
@MainActor
final class LocalAPI {
    private var listener: NWListener?

    static var token: String {
        if let token = UserDefaults.standard.string(forKey: "localAPIToken") { return token }
        let token = CCRandomToken.make()
        UserDefaults.standard.set(token, forKey: "localAPIToken")
        return token
    }

    static func regenerateToken() {
        UserDefaults.standard.set(CCRandomToken.make(), forKey: "localAPIToken")
    }

    func start() {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Bonjour.localAPIPort)!)
            listener.newConnectionHandler = { connection in
                connection.start(queue: .global(qos: .userInitiated))
                Task {
                    guard let request = try? await HTTPIO.read(connection) else {
                        connection.cancel()
                        return
                    }
                    await LocalAPI.handle(request, on: connection)
                }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Log.shared.warning("Local API unavailable: \(error.localizedDescription)")
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            Log.shared.warning("Local API unavailable: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private struct Message: Encodable {
        let ok: Bool
        let message: String?
    }

    static func handle(_ request: HTTPRequest, on connection: NWConnection) async {
        let route = "\(request.method) \(request.path)"
        if route == "GET /v1/health" {
            HTTPIO.respondJSON(connection, Message(ok: true, message: "ControlCenter Helper \(MacInfo.helperVersion)"))
            return
        }
        guard request.header("authorization") == "Bearer \(token)" else {
            HTTPIO.respondJSON(connection, status: 401, Message(ok: false, message: "Missing or wrong bearer token"))
            return
        }
        let hub = Hub.shared
        switch route {
        case "GET /v1/state":
            HTTPIO.respondJSON(connection, hub.state)

        case "GET /v1/workspace":
            HTTPIO.respondJSON(connection, hub.workspace)

        case "POST /v1/action":
            guard let action = try? JSONDecoder().decode(ButtonAction.self, from: request.body) else {
                return HTTPIO.respondJSON(connection, status: 400, Message(ok: false, message: "Body must be a ButtonAction, e.g. {\"type\":\"media\",\"command\":\"next\"}"))
            }
            let result = await hub.executor.run(action, origin: ActionOrigin(sessionID: nil, deviceName: "Local API", platform: .mac, pageID: nil))
            HTTPIO.respondJSON(connection, result)

        case "POST /v1/scene":
            guard let id = request.json.flatMap({ JSONPath.string(at: "id", in: $0) }) else {
                return HTTPIO.respondJSON(connection, status: 400, Message(ok: false, message: "{\"id\": \"startDay\"}"))
            }
            let result = await hub.executor.run(.scene(id), origin: ActionOrigin(sessionID: nil, deviceName: "Local API", platform: .mac, pageID: nil))
            HTTPIO.respondJSON(connection, result)

        case "POST /v1/navigate":
            guard let page = request.json.flatMap({ JSONPath.string(at: "page", in: $0) }) else {
                return HTTPIO.respondJSON(connection, status: 400, Message(ok: false, message: "{\"page\": \"bot\"}"))
            }
            hub.broadcast(.directive(Directive(.navigate, page: page)), platforms: [.iPad])
            HTTPIO.respondJSON(connection, Message(ok: true, message: "Showing \(page)"))

        case "POST /v1/toast":
            let json = request.json ?? [:]
            let style = Toast.Style(rawValue: JSONPath.string(at: "style", in: json) ?? "info") ?? .info
            hub.toast(Toast(title: JSONPath.string(at: "title", in: json) ?? "Message", message: JSONPath.string(at: "message", in: json), style: style, symbol: JSONPath.string(at: "symbol", in: json)))
            HTTPIO.respondJSON(connection, Message(ok: true, message: nil))

        case "POST /v1/bot/event":
            guard let json = request.json else { return HTTPIO.respondJSON(connection, status: 400, Message(ok: false, message: "JSON event or array expected")) }
            hub.bot.ingestEvents(json, announce: true)
            HTTPIO.respondJSON(connection, Message(ok: true, message: nil))

        case "POST /v1/bot/status":
            guard let json = request.json else { return HTTPIO.respondJSON(connection, status: 400, Message(ok: false, message: "JSON status expected")) }
            hub.bot.ingestStatus(json)
            HTTPIO.respondJSON(connection, Message(ok: true, message: nil))

        default:
            HTTPIO.respondJSON(connection, status: 404, Message(ok: false, message: "Unknown route \(route)"))
        }
    }
}

enum CCRandomToken {
    static func make() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in alphabet.randomElement(using: &generator)! })
    }
}
