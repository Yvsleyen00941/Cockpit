import Foundation

/// Protocol version spoken by this build. Bumped on incompatible changes.
public let ccProtocolVersion = 1

// MARK: - Message types

/// Every message on the wire. The blueprint's names are kept verbatim
/// (`appDidChange`, `liveDataUpdate`, `buttonConfigUpdate`, `buttonTap`,
/// `requestLayout`, `ping`); the rest extend them.
public enum MessageType: String, Codable, Sendable, CaseIterable {
    // Handshake (plaintext, before keys exist)
    case hello, challenge, auth, authResult
    case pairBegin, pairKey, pairReveal, pairConfirm, pairResult
    // iPad → Mac
    case buttonTap, requestLayout, ping, subscribe, updateLayout
    case requestIcons, requestArtwork, query, recordMacro
    case registerPushToken, updateIntegrations, requestSnapshot
    // Mac → iPad
    case appDidChange, liveDataUpdate, buttonConfigUpdate, actionResult
    case pong, icons, artwork, queryResult, macroRecording
    case toast, directive, bye
}

/// One message: `{ "type": "buttonTap", "id": 7, "payload": { … } }`.
public struct MCCMessage: Sendable {
    /// Request id, echoed as `replyTo` in the response.
    public var id: UInt32?
    public var replyTo: UInt32?
    public var body: MCCBody

    public init(_ body: MCCBody, id: UInt32? = nil, replyTo: UInt32? = nil) {
        self.body = body
        self.id = id
        self.replyTo = replyTo
    }

    public var type: MessageType { body.type }
}

public enum MCCBody: Sendable {
    case hello(Hello)
    case challenge(Challenge)
    case auth(AuthProof)
    case authResult(AuthResult)
    case pairBegin(PairBegin)
    case pairKey(PairKey)
    case pairReveal(PairReveal)
    case pairConfirm(PairConfirm)
    case pairResult(PairResult)

    case buttonTap(ButtonTap)
    case requestLayout(RequestLayout)
    case ping(Ping)
    case subscribe(Subscribe)
    case updateLayout(UpdateLayout)
    case requestIcons(RequestIcons)
    case requestArtwork(RequestArtwork)
    case query(Query)
    case recordMacro(RecordMacro)
    case registerPushToken(PushTokenRegistration)
    case updateIntegrations(IntegrationSettings)
    case requestSnapshot(Subscribe)

    case appDidChange(ActiveContext)
    case liveDataUpdate(LiveDataUpdate)
    case buttonConfigUpdate(Workspace)
    case actionResult(ActionResult)
    case pong(Ping)
    case icons(Icons)
    case artwork(Artwork)
    case queryResult(QueryResult)
    case macroRecording(MacroRecording)
    case toast(Toast)
    case directive(Directive)
    case bye(Bye)

    public var type: MessageType {
        switch self {
        case .hello: .hello
        case .challenge: .challenge
        case .auth: .auth
        case .authResult: .authResult
        case .pairBegin: .pairBegin
        case .pairKey: .pairKey
        case .pairReveal: .pairReveal
        case .pairConfirm: .pairConfirm
        case .pairResult: .pairResult
        case .buttonTap: .buttonTap
        case .requestLayout: .requestLayout
        case .ping: .ping
        case .subscribe: .subscribe
        case .updateLayout: .updateLayout
        case .requestIcons: .requestIcons
        case .requestArtwork: .requestArtwork
        case .query: .query
        case .recordMacro: .recordMacro
        case .registerPushToken: .registerPushToken
        case .updateIntegrations: .updateIntegrations
        case .requestSnapshot: .requestSnapshot
        case .appDidChange: .appDidChange
        case .liveDataUpdate: .liveDataUpdate
        case .buttonConfigUpdate: .buttonConfigUpdate
        case .actionResult: .actionResult
        case .pong: .pong
        case .icons: .icons
        case .artwork: .artwork
        case .queryResult: .queryResult
        case .macroRecording: .macroRecording
        case .toast: .toast
        case .directive: .directive
        case .bye: .bye
        }
    }
}

extension MCCMessage: Codable {
    private enum Keys: String, CodingKey { case type, id, replyTo, payload }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decodeIfPresent(UInt32.self, forKey: .id)
        replyTo = try c.decodeIfPresent(UInt32.self, forKey: .replyTo)
        let type = try c.decode(MessageType.self, forKey: .type)
        func p<T: Decodable>(_: T.Type) throws -> T { try c.decode(T.self, forKey: .payload) }
        switch type {
        case .hello: body = .hello(try p(Hello.self))
        case .challenge: body = .challenge(try p(Challenge.self))
        case .auth: body = .auth(try p(AuthProof.self))
        case .authResult: body = .authResult(try p(AuthResult.self))
        case .pairBegin: body = .pairBegin(try p(PairBegin.self))
        case .pairKey: body = .pairKey(try p(PairKey.self))
        case .pairReveal: body = .pairReveal(try p(PairReveal.self))
        case .pairConfirm: body = .pairConfirm(try p(PairConfirm.self))
        case .pairResult: body = .pairResult(try p(PairResult.self))
        case .buttonTap: body = .buttonTap(try p(ButtonTap.self))
        case .requestLayout: body = .requestLayout(try p(RequestLayout.self))
        case .ping: body = .ping(try p(Ping.self))
        case .subscribe: body = .subscribe(try p(Subscribe.self))
        case .updateLayout: body = .updateLayout(try p(UpdateLayout.self))
        case .requestIcons: body = .requestIcons(try p(RequestIcons.self))
        case .requestArtwork: body = .requestArtwork(try p(RequestArtwork.self))
        case .query: body = .query(try p(Query.self))
        case .recordMacro: body = .recordMacro(try p(RecordMacro.self))
        case .registerPushToken: body = .registerPushToken(try p(PushTokenRegistration.self))
        case .updateIntegrations: body = .updateIntegrations(try p(IntegrationSettings.self))
        case .requestSnapshot: body = .requestSnapshot(try p(Subscribe.self))
        case .appDidChange: body = .appDidChange(try p(ActiveContext.self))
        case .liveDataUpdate: body = .liveDataUpdate(try p(LiveDataUpdate.self))
        case .buttonConfigUpdate: body = .buttonConfigUpdate(try p(Workspace.self))
        case .actionResult: body = .actionResult(try p(ActionResult.self))
        case .pong: body = .pong(try p(Ping.self))
        case .icons: body = .icons(try p(Icons.self))
        case .artwork: body = .artwork(try p(Artwork.self))
        case .queryResult: body = .queryResult(try p(QueryResult.self))
        case .macroRecording: body = .macroRecording(try p(MacroRecording.self))
        case .toast: body = .toast(try p(Toast.self))
        case .directive: body = .directive(try p(Directive.self))
        case .bye: body = .bye(try p(Bye.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(replyTo, forKey: .replyTo)
        switch body {
        case .hello(let v): try c.encode(v, forKey: .payload)
        case .challenge(let v): try c.encode(v, forKey: .payload)
        case .auth(let v): try c.encode(v, forKey: .payload)
        case .authResult(let v): try c.encode(v, forKey: .payload)
        case .pairBegin(let v): try c.encode(v, forKey: .payload)
        case .pairKey(let v): try c.encode(v, forKey: .payload)
        case .pairReveal(let v): try c.encode(v, forKey: .payload)
        case .pairConfirm(let v): try c.encode(v, forKey: .payload)
        case .pairResult(let v): try c.encode(v, forKey: .payload)
        case .buttonTap(let v): try c.encode(v, forKey: .payload)
        case .requestLayout(let v): try c.encode(v, forKey: .payload)
        case .ping(let v): try c.encode(v, forKey: .payload)
        case .subscribe(let v): try c.encode(v, forKey: .payload)
        case .updateLayout(let v): try c.encode(v, forKey: .payload)
        case .requestIcons(let v): try c.encode(v, forKey: .payload)
        case .requestArtwork(let v): try c.encode(v, forKey: .payload)
        case .query(let v): try c.encode(v, forKey: .payload)
        case .recordMacro(let v): try c.encode(v, forKey: .payload)
        case .registerPushToken(let v): try c.encode(v, forKey: .payload)
        case .updateIntegrations(let v): try c.encode(v, forKey: .payload)
        case .requestSnapshot(let v): try c.encode(v, forKey: .payload)
        case .appDidChange(let v): try c.encode(v, forKey: .payload)
        case .liveDataUpdate(let v): try c.encode(v, forKey: .payload)
        case .buttonConfigUpdate(let v): try c.encode(v, forKey: .payload)
        case .actionResult(let v): try c.encode(v, forKey: .payload)
        case .pong(let v): try c.encode(v, forKey: .payload)
        case .icons(let v): try c.encode(v, forKey: .payload)
        case .artwork(let v): try c.encode(v, forKey: .payload)
        case .queryResult(let v): try c.encode(v, forKey: .payload)
        case .macroRecording(let v): try c.encode(v, forKey: .payload)
        case .toast(let v): try c.encode(v, forKey: .payload)
        case .directive(let v): try c.encode(v, forKey: .payload)
        case .bye(let v): try c.encode(v, forKey: .payload)
        }
    }
}

// MARK: - Handshake payloads

public struct Hello: Codable, Sendable, Hashable {
    public var protocolVersion: Int
    public var deviceID: String
    public var deviceName: String
    public var platform: DevicePlatform
    public var appVersion: String
    public var nonce: Data
    public var transport: LinkTransport

    public init(protocolVersion: Int = ccProtocolVersion, deviceID: String, deviceName: String, platform: DevicePlatform, appVersion: String, nonce: Data, transport: LinkTransport) {
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.appVersion = appVersion
        self.nonce = nonce
        self.transport = transport
    }
}

public struct Challenge: Codable, Sendable, Hashable {
    public var macID: String
    public var macName: String
    public var nonce: Data
    /// The Mac knows this device (it can authenticate instead of pairing).
    public var known: Bool

    public init(macID: String, macName: String, nonce: Data, known: Bool) {
        self.macID = macID
        self.macName = macName
        self.nonce = nonce
        self.known = known
    }
}

public struct AuthProof: Codable, Sendable, Hashable {
    public var proof: Data
    public init(proof: Data) { self.proof = proof }
}

public struct AuthResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var proof: Data?
    public var reason: String?
    public var helperVersion: String?

    public init(ok: Bool, proof: Data? = nil, reason: String? = nil, helperVersion: String? = nil) {
        self.ok = ok
        self.proof = proof
        self.reason = reason
        self.helperVersion = helperVersion
    }
}

public struct PairBegin: Codable, Sendable, Hashable {
    public var protocolVersion: Int
    public var deviceID: String
    public var deviceName: String
    public var platform: DevicePlatform
    /// SHA-256 over the initiator's public key and nonce — it commits to them
    /// before seeing the Mac's, so the 6-digit code cannot be ground.
    public var commitment: Data

    public init(protocolVersion: Int = ccProtocolVersion, deviceID: String, deviceName: String, platform: DevicePlatform, commitment: Data) {
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.platform = platform
        self.commitment = commitment
    }
}

public struct PairKey: Codable, Sendable, Hashable {
    public var macID: String
    public var macName: String
    public var publicKey: Data
    public var nonce: Data

    public init(macID: String, macName: String, publicKey: Data, nonce: Data) {
        self.macID = macID
        self.macName = macName
        self.publicKey = publicKey
        self.nonce = nonce
    }
}

public struct PairReveal: Codable, Sendable, Hashable {
    public var publicKey: Data
    public var nonce: Data

    public init(publicKey: Data, nonce: Data) {
        self.publicKey = publicKey
        self.nonce = nonce
    }
}

public struct PairConfirm: Codable, Sendable, Hashable {
    public var mac: Data
    public init(mac: Data) { self.mac = mac }
}

public struct PairResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var mac: Data?
    public var reason: String?

    public init(ok: Bool, mac: Data? = nil, reason: String? = nil) {
        self.ok = ok
        self.mac = mac
        self.reason = reason
    }
}

// MARK: - Session payloads

public struct ButtonTap: Codable, Sendable, Hashable {
    public var action: ButtonAction
    public var buttonID: String?
    public var pageID: String?

    public init(action: ButtonAction, buttonID: String? = nil, pageID: String? = nil) {
        self.action = action
        self.buttonID = buttonID
        self.pageID = pageID
    }
}

public struct ActionResult: Codable, Sendable, Hashable {
    public var ok: Bool
    public var message: String?
    public var output: String?
    public var durationMs: Int?

    public init(ok: Bool, message: String? = nil, output: String? = nil, durationMs: Int? = nil) {
        self.ok = ok
        self.message = message
        self.output = output
        self.durationMs = durationMs
    }

    public static let success = ActionResult(ok: true)
    public static func failure(_ message: String) -> ActionResult { ActionResult(ok: false, message: message) }
}

public struct RequestLayout: Codable, Sendable, Hashable {
    /// The revision the client has cached; the Mac replies only if it differs.
    public var knownRevision: Int?
    public init(knownRevision: Int?) { self.knownRevision = knownRevision }
}

public struct UpdateLayout: Codable, Sendable, Hashable {
    /// Optimistic concurrency: rejected if the Mac's revision moved on.
    public var baseRevision: Int
    public var workspace: Workspace

    public init(baseRevision: Int, workspace: Workspace) {
        self.baseRevision = baseRevision
        self.workspace = workspace
    }
}

public struct Ping: Codable, Sendable, Hashable {
    public var seq: UInt32
    /// Sender's clock, echoed back.
    public var t: Double

    public init(seq: UInt32, t: Double) {
        self.seq = seq
        self.t = t
    }
}

public struct Subscribe: Codable, Sendable, Hashable {
    public var channels: [Channel]
    public init(channels: some Sequence<Channel>) { self.channels = Array(Set(channels)).sorted { $0.rawValue < $1.rawValue } }
}

public struct LiveDataUpdate: Codable, Sendable, Hashable {
    public var values: [ChannelValue]
    /// A full snapshot (after subscribe) rather than a patch.
    public var full: Bool

    public init(values: [ChannelValue], full: Bool) {
        self.values = values
        self.full = full
    }
}

public struct RequestIcons: Codable, Sendable, Hashable {
    public var bundleIDs: [String]
    /// Pixel edge length.
    public var size: Int

    public init(bundleIDs: [String], size: Int = 128) {
        self.bundleIDs = bundleIDs
        self.size = size
    }
}

public struct Icons: Codable, Sendable, Hashable {
    /// bundle ID → PNG.
    public var icons: [String: Data]
    public init(icons: [String: Data]) { self.icons = icons }
}

public struct RequestArtwork: Codable, Sendable, Hashable {
    public var id: String
    public init(id: String) { self.id = id }
}

public struct Artwork: Codable, Sendable, Hashable {
    public var id: String
    public var data: Data?

    public init(id: String, data: Data?) {
        self.id = id
        self.data = data
    }
}

public struct Query: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case shortcuts, installedApps, runningApps, focusModes, integrations, repositories, permissions
    }

    public var kind: Kind
    public init(_ kind: Kind) { self.kind = kind }
}

public struct QueryItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?

    public init(id: String, title: String, subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

public struct QueryResult: Codable, Sendable, Hashable {
    public var kind: Query.Kind
    public var items: [QueryItem]
    public var integrations: IntegrationSettings?

    public init(kind: Query.Kind, items: [QueryItem], integrations: IntegrationSettings? = nil) {
        self.kind = kind
        self.items = items
        self.integrations = integrations
    }
}

public struct RecordMacro: Codable, Sendable, Hashable {
    public enum Command: String, Codable, Sendable, Hashable { case start, stop, cancel }
    public var command: Command
    public init(_ command: Command) { self.command = command }
}

public struct MacroRecording: Codable, Sendable, Hashable {
    public var steps: [MacroStep]
    public var recording: Bool
    public var error: String?

    public init(steps: [MacroStep], recording: Bool, error: String? = nil) {
        self.steps = steps
        self.recording = recording
        self.error = error
    }
}

public struct PushTokenRegistration: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable { case liveActivity, pushToStart }
    public var kind: Kind
    public var token: Data
    public var bundleID: String
    public var sandbox: Bool

    public init(kind: Kind, token: Data, bundleID: String, sandbox: Bool) {
        self.kind = kind
        self.token = token
        self.bundleID = bundleID
        self.sandbox = sandbox
    }
}

public struct Toast: Codable, Sendable, Hashable {
    public enum Style: String, Codable, Sendable, Hashable { case info, success, warning, error, trade }
    public var title: String
    public var message: String?
    public var style: Style
    public var symbol: String?

    public init(title: String, message: String? = nil, style: Style = .info, symbol: String? = nil) {
        self.title = title
        self.message = message
        self.style = style
        self.symbol = symbol
    }
}

public struct Directive: Codable, Sendable, Hashable {
    public enum Command: String, Codable, Sendable, Hashable { case navigate, chime, ambient, wake }
    public var command: Command
    public var page: String?

    public init(_ command: Command, page: String? = nil) {
        self.command = command
        self.page = page
    }
}

public struct Bye: Codable, Sendable, Hashable {
    public enum Reason: String, Codable, Sendable, Hashable { case sleeping, quitting, replaced, revoked, error }
    public var reason: Reason
    public var message: String?

    public init(_ reason: Reason, message: String? = nil) {
        self.reason = reason
        self.message = message
    }
}

// MARK: - Integration settings (editable from the iPad; secrets stay on the Mac)

public struct BotSettings: Codable, Sendable, Hashable {
    public var mode: BotMode
    public var baseURL: String
    public var statusPath: String
    public var eventsPath: String
    public var seriesPath: String
    public var pausePath: String
    public var resumePath: String
    public var closeAllPath: String
    public var pollSeconds: Double
    /// JSON paths into the status response (`pnl_today`, `stats.daily.pnl`…).
    public var fieldMap: [String: String]
    /// Frontmost-app bundle IDs that mean "the bot's command center".
    public var commandCenterBundleIDs: [String]
    public var hasAPIKey: Bool

    public init(mode: BotMode = .simulated, baseURL: String = "http://127.0.0.1:8000", statusPath: String = "/status", eventsPath: String = "/events", seriesPath: String = "/pnl", pausePath: String = "/pause", resumePath: String = "/resume", closeAllPath: String = "/close-all", pollSeconds: Double = 2, fieldMap: [String: String] = [:], commandCenterBundleIDs: [String] = [], hasAPIKey: Bool = false) {
        self.mode = mode
        self.baseURL = baseURL
        self.statusPath = statusPath
        self.eventsPath = eventsPath
        self.seriesPath = seriesPath
        self.pausePath = pausePath
        self.resumePath = resumePath
        self.closeAllPath = closeAllPath
        self.pollSeconds = pollSeconds
        self.fieldMap = fieldMap
        self.commandCenterBundleIDs = commandCenterBundleIDs
        self.hasAPIKey = hasAPIKey
    }
}

public struct WhoopSettings: Codable, Sendable, Hashable {
    public var clientID: String
    public var redirectURI: String
    public var hasClientSecret: Bool
    public var connected: Bool

    public init(clientID: String = "", redirectURI: String = "http://localhost:8080", hasClientSecret: Bool = false, connected: Bool = false) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.hasClientSecret = hasClientSecret
        self.connected = connected
    }
}

public struct PortfolioSettings: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// PortTracker deployment, e.g. https://your-app.vercel.app
    public var baseURL: String
    /// Header used to authenticate (`Cookie` or `Authorization`).
    public var authHeader: String
    public var hasAuthValue: Bool
    public var pollSeconds: Double

    public init(enabled: Bool = false, baseURL: String = "", authHeader: String = "Cookie", hasAuthValue: Bool = false, pollSeconds: Double = 30) {
        self.enabled = enabled
        self.baseURL = baseURL
        self.authHeader = authHeader
        self.hasAuthValue = hasAuthValue
        self.pollSeconds = pollSeconds
    }
}

public struct IntegrationSettings: Codable, Sendable, Hashable {
    public var bot: BotSettings
    public var whoop: WhoopSettings
    public var portfolio: PortfolioSettings
    public var weatherEnabled: Bool
    public var gitRepositories: [String]
    public var browserURLTracking: Bool
    public var windowTitleTracking: Bool
    /// Secrets travel iPad → Mac only, once, over the encrypted session; the
    /// Mac stores them in its Keychain and never sends them back.
    public var secrets: [String: String]?

    public init(bot: BotSettings = BotSettings(), whoop: WhoopSettings = WhoopSettings(), portfolio: PortfolioSettings = PortfolioSettings(), weatherEnabled: Bool = true, gitRepositories: [String] = [], browserURLTracking: Bool = true, windowTitleTracking: Bool = true, secrets: [String: String]? = nil) {
        self.bot = bot
        self.whoop = whoop
        self.portfolio = portfolio
        self.weatherEnabled = weatherEnabled
        self.gitRepositories = gitRepositories
        self.browserURLTracking = browserURLTracking
        self.windowTitleTracking = windowTitleTracking
        self.secrets = secrets
    }

    public enum SecretKey {
        public static let botAPIKey = "bot.apiKey"
        public static let whoopClientSecret = "whoop.clientSecret"
        public static let portfolioAuth = "portfolio.auth"
    }
}
