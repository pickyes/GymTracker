import Foundation
import LocalAuthentication
import Network
import UIKit

// MARK: - Phone foreground MCP server (MCP P1, Layer 2)
//
// A local HTTP server that runs ONLY while the app is foregrounded AND the
// user has enabled it in Settings (default OFF). Backgrounding stops it
// (up to ~5 min grace via a background task — no background modes, no daemon).
// LAN-only binding. This is the pattern that ships in the App Store today
// (OwnChart, Health Auto Export at http://{LAN_IP}:9000/mcp).
//
// ⚠️ AUTH IS PROVISIONAL (P0-3 minimal slice, 2026-11-10) — DO NOT FINALIZE.
// The bare bearer token is replaced by a grant record (MCPGrant below):
// clientName is always "muse", scopes are gym:read (+ gym:write only on a
// second explicit approval), and the grant expires (30 days) and is deleted
// on Disconnect. dispatch() checks the grant after the bearer compare and
// handleToolCall() enforces gym:write on write tools (403 otherwise).
// Full OAuth 2.0 + PKCE is still deferred to the next pass (Mac companion
// authorization server). Do not ship, document, or present the bearer token
// as the final auth. MCP connections will be allowed ONLY to Muse — DaRon's
// directive (2026-11-09 19:32): "instead of agent mcp make it muse connect
// only." No other agent (ChatGPT, Claude, Cursor, Codex, Grok) may connect.
// The allowlist itself is `OAuthClientAllowlist` below — the single source
// of truth the Mac companion authorization server enforces.
//
// Transport: Streamable HTTP (MCP spec 2026-07-28, stateless). One JSON-RPC
// request per POST to /mcp; the response is a single JSON-RPC object.
// No cloud endpoint, ever. No analytics on tool calls. No account/identity.
// The privacy manifest stays "Data Not Collected" — the server serves the
// user's own data back to the user's own agents, on the user's own network.
//
// Needs in Info.plist:
//   NSLocalNetworkUsageDescription (purpose string)
//   NSBonjourServices: ["_gymtracker._tcp"]
//   NSAppTransportSecurity → NSAllowsLocalNetworking = true

// MARK: - Grant store (P0-3 minimal slice)
//
// Replaces the bare bearer token. A grant is created by CONNECT (pending,
// no token yet), becomes usable only after DaRon approves it with Face ID
// (Approve mints the token once), and is deleted by Disconnect. The token
// lives only inside the grant record, in standard UserDefaults — MCP keys
// must NOT move into any shared defaults / App Group (the widget extension
// must never be able to read them).

/// One approved connection. clientName is ALWAYS "muse" (see
/// OAuthClientAllowlist); any other name is rejected at the grant check.
struct MCPGrant: Codable, Equatable {
    enum Status: String, Codable { case pending, active }

    var clientName: String
    var scopes: [String]
    /// nil while the grant is pending — no token exists until approval.
    var token: String?
    var issuedAt: Date?
    var expiresAt: Date?
    var status: Status

    /// Grants live 30 days, then stop working until DaRon re-approves.
    /// (Matches the refresh-token horizon in the OAuth design.)
    static let grantLifetime: TimeInterval = 30 * 24 * 60 * 60

    static let readScopes = ["gym:read"]
    static let readWriteScopes = ["gym:read", "gym:write"]
}

/// Errors from the grant approval flow, surfaced to the CONNECT UI.
enum MCPGrantError: Error, LocalizedError {
    case noPendingGrant
    case biometricsUnavailable
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .noPendingGrant:
            return "No connection is waiting for approval. Tap CONNECT first."
        case .biometricsUnavailable:
            return "Face ID is not available on this device."
        case .authenticationFailed:
            return "Approval failed — Face ID did not confirm it was you."
        }
    }
}

@MainActor
final class MCPServer: ObservableObject {
    static let defaultPort: UInt16 = 8080

    @Published var isEnabled: Bool = false {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    @Published var isRunning: Bool = false
    /// The active grant's token ("" when there is no active grant). Mirrors
    /// the grant record — never persisted on its own.
    @Published var token: String = ""
    @Published var port: UInt16 = defaultPort {
        didSet { UserDefaults.standard.set(Int(port), forKey: Self.portKey) }
    }
    /// The current grant, if any. Published so the CONNECT UI can show the
    /// pending -> approved state. Persisted as JSON in standard defaults.
    @Published private(set) var grant: MCPGrant?

    /// The grant that can actually authenticate right now: active, holding
    /// a token, and not expired. A pending, expired, or deleted grant
    /// authenticates nothing.
    var activeGrant: MCPGrant? {
        guard let grant, grant.status == .active,
              let token = grant.token, !token.isEmpty,
              let expiresAt = grant.expiresAt, expiresAt > Date() else { return nil }
        return grant
    }

    /// True only while an active, unexpired grant exists.
    var hasActiveGrant: Bool { activeGrant != nil }

    /// The URL an agent connects to (shown in Settings when running).
    var url: String? {
        guard isRunning else { return nil }
        guard let ip = localIPAddress() else { return nil }
        return "http://\(ip):\(port)/mcp"
    }

    private static let enabledKey = "gymtracker.mcp.enabled.v1"
    private static let grantKey = "gymtracker.mcp.grant.v1"
    /// Legacy bare-token key — read once for migration, then deleted.
    /// The token now lives only inside the grant record (grantKey).
    private static let tokenKey = "gymtracker.mcp.token.v1"
    private static let portKey = "gymtracker.mcp.port.v1"

    private weak var store: WorkoutStore?
    private var listener: NWListener?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(store: WorkoutStore? = nil) {
        self.store = store
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // Load the grant record; one-time migration from the old bare token.
        if let data = UserDefaults.standard.data(forKey: Self.grantKey),
           let saved = try? JSONDecoder().decode(MCPGrant.self, from: data) {
            grant = saved
        } else if let legacy = UserDefaults.standard.string(forKey: Self.tokenKey), !legacy.isEmpty {
            // Adopt the pre-grant token so an existing Muse connection keeps
            // working. New grants always go through the Face ID-gated
            // approval flow; this migration runs once and deletes the key.
            grant = MCPGrant(clientName: OAuthClientAllowlist.allowedClientName,
                             scopes: MCPGrant.readWriteScopes, token: legacy,
                             issuedAt: Date(),
                             expiresAt: Date().addingTimeInterval(MCPGrant.grantLifetime),
                             status: .active)
            saveGrant()
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
        }
        token = activeGrant?.token ?? ""
        let savedPort = UserDefaults.standard.integer(forKey: Self.portKey)
        port = savedPort > 0 ? UInt16(savedPort) : Self.defaultPort
    }

    func attach(store: WorkoutStore) {
        self.store = store
    }

    /// Mint a fresh token inside the active grant (same scopes, same
    /// expiry). No-op when there is no active grant — a token only exists
    /// as part of a grant.
    func regenerateToken() {
        guard var current = grant, current.status == .active else { return }
        let fresh = UUID().uuidString
        current.token = fresh
        grant = current
        saveGrant()
        token = fresh
    }

    // MARK: - Grant flow (CONNECT -> Face ID Approve -> token issued once)

    /// CONNECT: create a pending grant for Muse. Holds NO token — nothing
    /// can authenticate until DaRon approves it. Also turns the server on
    /// (it answers health checks; /mcp still 401s until approval).
    func requestGrant() {
        grant = MCPGrant(clientName: OAuthClientAllowlist.allowedClientName,
                         scopes: MCPGrant.readScopes, token: nil,
                         issuedAt: nil, expiresAt: nil, status: .pending)
        saveGrant()
        token = ""
        isEnabled = true
        start()
    }

    /// Approve a pending grant and issue its token exactly once. Call only
    /// after Face ID confirms it is DaRon (see approveGrantWithBiometrics).
    /// `includeWrite` is the second explicit tap: read-only by default,
    /// gym:write only when he asks for it. Returns the issued token, or
    /// nil when there is no pending grant.
    @discardableResult
    func approveGrant(includeWrite: Bool = false) -> String? {
        guard var pending = grant, pending.status == .pending else { return nil }
        let issued = UUID().uuidString
        pending.token = issued
        pending.scopes = includeWrite ? MCPGrant.readWriteScopes : MCPGrant.readScopes
        pending.issuedAt = Date()
        pending.expiresAt = Date().addingTimeInterval(MCPGrant.grantLifetime)
        pending.status = .active
        grant = pending
        saveGrant()
        token = issued
        return issued
    }

    /// Face ID-gated approval: evaluates biometrics, then issues the token
    /// via approveGrant. The UI's Approve button should call this, not
    /// approveGrant directly. Requires NSFaceIDUsageDescription in
    /// Info.plist (Face ID crashes without it).
    func approveGrantWithBiometrics(includeWrite: Bool = false,
                                    completion: @escaping (Result<String, MCPGrantError>) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(.failure(.biometricsUnavailable))
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "Approve Muse to connect to Status") { [weak self] success, _ in
            Task { @MainActor in
                guard let self else { return }
                if success, let issued = self.approveGrant(includeWrite: includeWrite) {
                    completion(.success(issued))
                } else {
                    completion(.failure(success ? .noPendingGrant : .authenticationFailed))
                }
            }
        }
    }

    /// Disconnect: delete the grant entirely (token dies with it), turn
    /// the server off, and stop listening. A later CONNECT starts over
    /// from a pending grant.
    func disconnect() {
        grant = nil
        UserDefaults.standard.removeObject(forKey: Self.grantKey)
        token = ""
        isEnabled = false
        stop()
    }

    /// Persist the grant record (standard UserDefaults only — never shared
    /// defaults / App Group). A nil grant removes the record.
    private func saveGrant() {
        if let grant, let data = try? JSONEncoder().encode(grant) {
            UserDefaults.standard.set(data, forKey: Self.grantKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.grantKey)
        }
    }

    // MARK: - Lifecycle (foreground-only)

    /// Start the server. Called when the app enters the foreground and the
    /// toggle is on. Stops automatically on background.
    func start() {
        guard isEnabled, listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
            listener.service = NWListener.Service(name: "Status", type: "_gymtracker._tcp")
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                        self?.listener = nil
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handle(connection: connection)
                }
            }
            listener.start(queue: .main)
            self.listener = listener
            // Up to ~5 min grace after backgrounding (the documented,
            // review-safe behavior — the server stops, it is not kept alive).
            backgroundTask = UIApplication.shared.beginBackgroundTask {
                Task { @MainActor in
                    self.stop()
                    if self.backgroundTask != .invalid {
                        UIApplication.shared.endBackgroundTask(self.backgroundTask)
                        self.backgroundTask = .invalid
                    }
                }
            }
        } catch {
            isRunning = false
            listener = nil
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - HTTP handling (NWListener, one request per connection)

    /// Reference-type buffer so the async receive callbacks can accumulate
    /// bytes without an inout capture (inout + an escaping closure + a
    /// MainActor hop do not mix). Only ever touched from one connection's
    /// serial receive callbacks, so no synchronization is needed.
    private final class HTTPBuffer: @unchecked Sendable {
        var data = Data()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        receiveMore(connection: connection, buffer: HTTPBuffer())
    }

    private func receiveMore(connection: NWConnection, buffer: HTTPBuffer) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                buffer.data.append(data)
            }
            Task { @MainActor in
                if let request = self.parseHTTPRequest(from: buffer.data) {
                    self.respond(to: request, on: connection)
                    return
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receiveMore(connection: connection, buffer: buffer)
            }
        }
    }

    private struct HTTPRequest {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data
    }

    private func parseHTTPRequest(from data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2 {
                headers[String(kv[0]).trimmingCharacters(in: .whitespaces).lowercased()] =
                    String(kv[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: body)
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        Task { @MainActor in
            let (status, jsonData) = self.dispatch(request: request)
            let response = self.httpResponse(status: status, json: jsonData)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func httpResponse(status: Int, json: Data) -> Data {
        let statusText = status == 200 ? "OK" : status == 401 ? "Unauthorized" : status == 403 ? "Forbidden" : status == 404 ? "Not Found" : "Bad Request"
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(json.count)\r\n"
        response += "Connection: close\r\n\r\n"
        var data = Data(response.utf8)
        data.append(json)
        return data
    }

    // MARK: - JSON-RPC dispatch (MCP, stateless)

    private func dispatch(request: HTTPRequest) -> (Int, Data) {
        // Health check.
        if request.method == "GET" && request.path == "/health" {
            return (200, jsonData(["status": "ok", "server": "gym-tracker-mcp"]))
        }
        guard request.method == "POST", request.path == "/mcp" else {
            return (404, jsonData(["error": "Not found. POST JSON-RPC to /mcp."]))
        }
        // Bearer token + grant check (P0-3 minimal slice — provisional,
        // NOT full OAuth; the OAuth design still replaces this).
        let auth = request.headers["authorization"] ?? ""
        guard !token.isEmpty, auth == "Bearer \(token)" else {
            return (401, rpcError(id: nil, code: -32001, message: "Unauthorized — missing or invalid bearer token."))
        }
        // HONEST LIMIT: a copied bearer token is still usable by any local
        // process until expiry or revocation. This grant check is a filter
        // and revocation boundary, not client-identity proof: the token is
        // a bearer credential and the server cannot tell which local
        // process presents it. The real fix is the Mac companion
        // authorization server (next pass).
        guard let grant = activeGrant,
              grant.clientName == OAuthClientAllowlist.allowedClientName,
              grant.token == token else {
            return (401, rpcError(id: nil, code: -32001, message: "Unauthorized — no active grant for this token."))
        }
        guard let rpc = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
              let method = rpc["method"] as? String else {
            return (400, rpcError(id: nil, code: -32700, message: "Parse error — expected a JSON-RPC object."))
        }
        let id = rpc["id"]
        let params = rpc["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            return (200, rpcResult(id: id, result: [
                "protocolVersion": "2026-07-28",
                "serverInfo": ["name": "gym-tracker", "version": "1.0.0"],
                "capabilities": ["tools": [:], "resources": [:], "prompts": [:]],
            ]))
        case "ping":
            return (200, rpcResult(id: id, result: [:]))
        case "tools/list":
            return (200, rpcResult(id: id, result: ["tools": MCPTools.definitions]))
        case "tools/call":
            return handleToolCall(id: id, params: params, scopes: grant.scopes)
        case "resources/list":
            return (200, rpcResult(id: id, result: ["resources": MCPTools.resources]))
        case "resources/read":
            return handleResourceRead(id: id, params: params)
        case "prompts/list":
            return (200, rpcResult(id: id, result: ["prompts": MCPTools.prompts]))
        case "prompts/get":
            return handlePromptGet(id: id, params: params)
        default:
            return (200, rpcError(id: id, code: -32601, message: "Method not found: \(method)"))
        }
    }

    /// Tools that change data. They require the gym:write scope; a
    /// read-only grant gets 403 (insufficient_scope). Read tools need only
    /// gym:read, which every grant has.
    private static let writeTools: Set<String> = [
        "log_set", "start_workout", "finish_workout", "swap_exercise",
        "set_bodyweight", "start_rest_timer", "cancel_rest_timer",
    ]

    private func handleToolCall(id: Any?, params: [String: Any], scopes: [String]) -> (Int, Data) {
        guard let name = params["name"] as? String else {
            return (200, rpcError(id: id, code: -32602, message: "Missing tool name."))
        }
        if Self.writeTools.contains(name), !scopes.contains("gym:write") {
            return (403, rpcError(id: id, code: -32003,
                                  message: "Forbidden — this grant does not include the gym:write scope."))
        }
        let args = params["arguments"] as? [String: Any] ?? [:]
        guard let store else {
            return (200, rpcError(id: id, code: -32603, message: "Store not attached."))
        }
        let (text, isError) = MCPTools.call(name: name, arguments: args, store: store)
        if isError {
            return (200, rpcResult(id: id, result: [
                "content": [["type": "text", "text": "Error: \(text)"]],
                "isError": true,
            ]))
        }
        return (200, rpcResult(id: id, result: [
            "content": [["type": "text", "text": text]],
            "structuredContent": (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? [:],
        ]))
    }

    private func handleResourceRead(id: Any?, params: [String: Any]) -> (Int, Data) {
        guard let uri = params["uri"] as? String, let store else {
            return (200, rpcError(id: id, code: -32602, message: "Missing resource URI."))
        }
        guard let text = MCPTools.resource(uri: uri, store: store) else {
            return (200, rpcError(id: id, code: -32602, message: "Unknown resource: \(uri)"))
        }
        return (200, rpcResult(id: id, result: [
            "contents": [["uri": uri, "mimeType": "application/json", "text": text]],
        ]))
    }

    private func handlePromptGet(id: Any?, params: [String: Any]) -> (Int, Data) {
        guard let name = params["name"] as? String, let store else {
            return (200, rpcError(id: id, code: -32602, message: "Missing prompt name."))
        }
        guard let prompt = MCPTools.prompt(name: name, store: store) else {
            return (200, rpcError(id: id, code: -32602, message: "Unknown prompt: \(name)"))
        }
        return (200, rpcResult(id: id, result: prompt))
    }

    // MARK: - Helpers

    private func jsonData(_ value: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private func rpcResult(id: Any?, result: Any) -> Data {
        var envelope: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { envelope["id"] = id }
        return jsonData(envelope)
    }

    private func rpcError(id: Any?, code: Int, message: String) -> Data {
        var envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id { envelope["id"] = id }
        return jsonData(envelope)
    }

    /// The phone's LAN IP (for the Settings URL). Best-effort — returns the
    /// first non-loopback IPv4 address.
    private func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee
            guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                  addr.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                           &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if ip != "127.0.0.1" {
                    address = ip
                    break
                }
            }
        }
        return address
    }
}

// MARK: - OAuth client allowlist (Muse only)
//
// DaRon's directive (2026-11-09 19:32): "instead of agent mcp make it
// muse connect only." Only Muse may connect via MCP. Every other agent
// (ChatGPT, Claude, Cursor, Codex, Grok) is rejected at the authorization
// step — no redirect URI, no pre-registration, and no manual approval
// will let it through.
//
// The gate has two layers, and BOTH must pass:
//   1. Client identity: the client's claimed name must be Muse.
//      OAuth client identity is self-asserted — a client can claim any
//      name — so this layer alone is not proof. It is the first filter;
//      DaRon's manual approval (with Face ID) is the real gate.
//   2. Redirect URI: only loopback URIs (127.0.0.1 / localhost, any
//      port) are accepted. Muse runs on DaRon's own Mac. Hosted agents
//      (ChatGPT, Grok, claude.ai) use fixed https callbacks — those are
//      now rejected outright, which is what makes Muse-only real at the
//      network layer. No tunnel or public URL is ever needed.
//
// The Mac companion authorization server enforces this same list at
// /oauth/register and /oauth/authorize; the phone resource server
// re-checks the token's client on every call. Everything else is
// unchanged: OAuth 2.1, scopes gym:read (default) / gym:write (second
// tap), access tokens 15 min, refresh tokens 30 days, revocation +
// master kill switch.
enum OAuthClientAllowlist {
    /// The only agent allowed to connect. Everything else is rejected.
    static let allowedClientName = "muse"

    /// Redirect-URI hosts the authorization server accepts. Loopback
    /// only — Muse runs on DaRon's Mac. No hosted https callbacks.
    static let allowedRedirectHosts: Set<String> = ["127.0.0.1", "localhost"]

    /// True only for a client claiming to be Muse.
    static func isAllowedClient(name: String?) -> Bool {
        guard let name else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == allowedClientName
    }

    /// True only for loopback redirect URIs (any port). Hosted-agent
    /// https callbacks (chatgpt.com, claude.ai, grok.com, x.ai, …) fail
    /// the scheme check and are rejected.
    static func isAllowedRedirectURI(_ uri: String) -> Bool {
        guard let url = URL(string: uri),
              let host = url.host?.lowercased(),
              url.scheme == "http" else { return false }
        return allowedRedirectHosts.contains(host)
    }

    /// The full gate: Muse identity AND a loopback redirect URI.
    /// Call this at /oauth/register and /oauth/authorize; reject anything
    /// else with 400 and no redirect.
    static func mayAuthorize(clientName: String?, redirectURI: String) -> Bool {
        isAllowedClient(name: clientName) && isAllowedRedirectURI(redirectURI)
    }
}

// MARK: - Tool definitions, calls, resources, prompts

enum MCPTools {
    static let definitions: [[String: Any]] = [
        tool("get_today_workout", "Today's workout plan (title, exercises with sets/reps/weight, finisher), or that today is a rest day.", [:]),
        tool("get_next_workout", "The next scheduled workout (day, date, exercises).", [:]),
        tool("get_workout_history", "Sessions with date range and limit.", [
            "limit": ["type": "integer", "description": "Max sessions to return. Default 20."],
            "since": ["type": "string", "description": "ISO-8601 date. Only sessions on/after this date."],
        ]),
        tool("get_exercise_history", "All logged sets for one exercise.", [
            "exercise": ["type": "string", "description": "Exercise id or name."],
        ]),
        tool("get_personal_records", "Best weight × reps per exercise, computed from sessions.", [:]),
        tool("get_current_workout", "The in-progress workout (what is done, what is left, rest timer state).", [:]),
        tool("get_profile", "The user's profile: goal, experience, days/week, equipment, limits, bodyweight.", [:]),
        tool("get_program", "The active program (days, swaps) and whether it is the generated program or DaRon's preset.", [:]),
        tool("list_exercises", "The exercise library (name, muscle, equipment, substitutes).", [:]),
        tool("get_progression", "The progression hint for an exercise (what to lift next, based on last time).", [
            "exercise": ["type": "string", "description": "Exercise id or name."],
        ]),
        tool("log_set", "Mark one set done with weight and reps.", [
            "exercise": ["type": "string", "description": "Exercise id or name."],
            "weightLb": ["type": "number", "description": "Weight in lb. Omit for bodyweight."],
            "reps": ["type": "integer", "description": "Reps."],
        ]),
        tool("start_workout", "Begin today's workout (creates the in-progress draft).", [:]),
        tool("finish_workout", "Save the in-progress workout as a completed session.", [:]),
        tool("swap_exercise", "Replace an exercise in today's workout with a substitute.", [
            "exercise": ["type": "string", "description": "Exercise id or name to replace."],
            "replacement": ["type": "string", "description": "Substitute exercise id or name."],
        ]),
        tool("set_bodyweight", "Record bodyweight in lb.", [
            "weightLb": ["type": "number", "description": "Bodyweight in lb."],
        ]),
        tool("start_rest_timer", "Start the rest countdown.", [
            "seconds": ["type": "number", "description": "Rest length in seconds. Default 90."],
        ]),
        tool("cancel_rest_timer", "Cancel the rest countdown.", [:]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": [],
            ] as [String: Any],
        ]
    }

    static let resources: [[String: Any]] = [
        ["uri": "gymtracker://program/active", "name": "Active program", "mimeType": "application/json"],
        ["uri": "gymtracker://history/recent", "name": "Recent sessions", "mimeType": "application/json"],
        ["uri": "gymtracker://profile", "name": "User profile", "mimeType": "application/json"],
        ["uri": "gymtracker://exercise-library", "name": "Exercise library", "mimeType": "application/json"],
    ]

    static let prompts: [[String: Any]] = [
        ["name": "weekly-review", "description": "Summarize this week's training: sessions done, volume trend, what progressed, what stalled."],
        ["name": "next-workout-brief", "description": "What is my next workout and what weights should I use, based on last time?"],
        ["name": "suggest-swap", "description": "My shoulder hurts today — what swaps should I make to today's plan?"],
    ]

    // MARK: - Tool execution (one source of truth: the WorkoutStore)

    static func call(name: String, arguments: [String: Any], store: WorkoutStore) -> (text: String, isError: Bool) {
        switch name {
        case "get_today_workout":
            guard let plan = store.programDay(for: Date()) else {
                return ("Rest day — no workout scheduled today.", false)
            }
            return (encode(plan), false)
        case "get_next_workout":
            guard let next = store.nextWorkout(after: Date()) else {
                return ("No upcoming workout found.", false)
            }
            return (encode([
                "key": next.key, "date": iso(next.date),
                "title": next.plan.title, "subtitle": next.plan.subtitle,
                "exercises": next.plan.exercises.map { exerciseJSON($0) },
            ] as [String: Any]), false)
        case "get_workout_history":
            let limit = arguments["limit"] as? Int ?? 20
            var sessions = store.sessions
            if let since = arguments["since"] as? String,
               let date = ISO8601DateFormatter().date(from: since) {
                sessions = sessions.filter { $0.date >= date }
            }
            return (encode(Array(sessions.prefix(limit))), false)
        case "get_exercise_history":
            guard let exercise = arguments["exercise"] as? String,
                  let template = findExercise(exercise, store: store) else {
                return ("Exercise not found. Pass an exercise id or name.", true)
            }
            // Explicit loops with concrete types — nested flatMap/map tuple
            // chains time out the Swift 6 type checker.
            var logs: [(date: Date, log: ExerciseLog)] = []
            let sortedSessions = store.sessions.sorted { $0.date > $1.date }
            for session in sortedSessions {
                for exercise in session.exercises where exercise.exerciseId == template.id {
                    logs.append((date: session.date, log: exercise))
                }
            }
            let items = logs.map { (date, log) in
                ["date": iso(date), "sets": log.sets.map { setJSON($0) }] as [String: Any]
            }
            return (encode(items), false)
        case "get_personal_records":
            var records: [[String: Any]] = []
            // One lookup pass instead of re-flattening per id.
            var byId: [String: ExerciseLog] = [:]
            for session in store.sessions {
                for exercise in session.exercises where byId[exercise.exerciseId] == nil {
                    byId[exercise.exerciseId] = exercise
                }
            }
            for id in byId.keys {
                guard let best = store.bestSet(for: id) else { continue }
                let name = byId[id]?.name ?? id
                var record: [String: Any] = ["exercise": name, "exerciseId": id]
                if let weight = best.weightLb { record["bestWeightLb"] = weight }
                record["bestReps"] = best.reps
                if let oneRM = store.oneRepMax(for: id) {
                    record["estimatedOneRepMaxLb"] = oneRM
                }
                records.append(record)
            }
            return (encode(records), false)
        case "get_current_workout":
            guard let plan = store.programDay(for: Date()) else {
                return ("Rest day — no workout in progress.", false)
            }
            store.ensureDraft(for: plan)
            let items = store.draftExercises.map { template in
                let sets = store.draftLogs[template.id] ?? []
                return [
                    "exercise": template.name, "exerciseId": template.id,
                    "sets": sets.map { setJSON($0) },
                    "done": sets.filter { $0.done }.count, "total": sets.count,
                ] as [String: Any]
            }
            var result: [String: Any] = [
                "day": plan.title, "dayKey": plan.key, "exercises": items,
                "finisherChecks": store.draftFinisherChecks,
            ]
            if let endsAt = store.restEndsAt {
                result["restEndsAt"] = iso(endsAt)
                result["restSecondsRemaining"] = max(0, endsAt.timeIntervalSinceNow)
            }
            return (encode(result), false)
        case "get_profile":
            guard let profile = store.profile else {
                return ("No profile yet — onboarding not completed.", false)
            }
            return (encode(profile), false)
        case "get_program":
            guard let program = store.activeProgram else {
                return ("No active program.", false)
            }
            return (encode(program), false)
        case "list_exercises":
            return (encode(ExerciseLibrary.all(plus: store.customExercises)), false)
        case "get_progression":
            guard let exercise = arguments["exercise"] as? String,
                  let template = findExercise(exercise, store: store) else {
                return ("Exercise not found. Pass an exercise id or name.", true)
            }
            return (store.progressionHint(for: template), false)
        case "log_set":
            guard let exercise = arguments["exercise"] as? String,
                  let plan = store.programDay(for: Date()) else {
                return ("No workout today (rest day).", true)
            }
            store.ensureDraft(for: plan)
            guard let template = findExercise(exercise, store: store) else {
                return ("Exercise '\(exercise)' is not in today's workout.", true)
            }
            var sets = store.draftLogs[template.id] ?? []
            guard let index = sets.firstIndex(where: { !$0.done }) else {
                return ("All sets for \(template.name) are already done.", false)
            }
            sets[index].done = true
            if let weight = arguments["weightLb"] as? Double { sets[index].weightLb = weight }
            if let reps = arguments["reps"] as? Int { sets[index].reps = reps }
            store.draftLogs[template.id] = sets
            if sets[index].kind != .warmup {
                store.startRest(for: template)
            }
            return ("Logged set \(index + 1) of \(sets.count) for \(template.name).", false)
        case "start_workout":
            guard let plan = store.programDay(for: Date()) else {
                return ("Rest day — no workout scheduled today.", true)
            }
            store.ensureDraft(for: plan)
            return ("Started \(plan.title) — \(plan.exercises.count) exercises.", false)
        case "finish_workout":
            guard let plan = store.programDay(for: Date()) else {
                return ("Rest day — no workout in progress.", true)
            }
            store.ensureDraft(for: plan)
            // Save the workout that was actually done: the draft's source
            // plan, not whatever plan is current now — the label comes
            // from the session itself (its date and the exercises
            // actually logged), never copied from a plan. See
            // WorkoutStore.sessionLabel.
            let sourcePlan = store.draftSourcePlan ?? plan
            let exerciseLogs = store.draftExercises.map { template in
                ExerciseLog(exerciseId: template.id, name: template.name,
                            isPair: template.isPair, sets: store.draftLogs[template.id] ?? [],
                            unitOverride: template.unitOverride)
            }
            let savedAt = Date()
            let label = WorkoutStore.sessionLabel(date: savedAt, plan: sourcePlan, exercises: exerciseLogs, customs: store.customExercises)
            let session = SessionLog(
                id: UUID(), date: savedAt, dayKey: label.dayKey, dayTitle: label.dayTitle,
                exercises: exerciseLogs,
                finisherDone: store.draftFinisherChecks.allSatisfy { $0 },
                finisherNotes: sourcePlan.finisher.joined(separator: "; ")
            )
            store.saveSession(session)
            store.clearDraft()
            ReminderScheduler.cancelMissedDayNudge()
            let doneSets = exerciseLogs.flatMap { $0.sets }.filter { $0.done }.count
            return ("Finished \(label.dayTitle). \(setsDoneText(done: doneSets)).", false)
        case "swap_exercise":
            guard let exercise = arguments["exercise"] as? String,
                  let replacement = arguments["replacement"] as? String,
                  let plan = store.programDay(for: Date()) else {
                return ("Pass an exercise and a replacement, and make sure today is a workout day.", true)
            }
            store.ensureDraft(for: plan)
            guard let template = findExercise(exercise, store: store) else {
                return ("Exercise '\(exercise)' not found in today's workout.", true)
            }
            // Exact id first, then exact name, then name-contains as a
            // last resort: a typo must not resolve the wrong exercise
            // out of the 1,600-entry library by first-contains-match.
            let library = ExerciseLibrary.all(plus: store.customExercises)
            guard let replacementLib = library.first(where: { $0.id == replacement })
                ?? library.first(where: { $0.name.localizedCaseInsensitiveCompare(replacement) == .orderedSame })
                ?? library.first(where: { $0.name.localizedCaseInsensitiveContains(replacement) }) else {
                return ("Replacement '\(replacement)' not found in the library.", true)
            }
            let profile = store.profile ?? UserProfile.starter
            let replacementTemplate = ProgramGenerator.template(for: replacementLib, profile: profile)
            store.swapDraftExercise(id: template.id, with: replacementTemplate)
            return ("Swapped \(template.name) → \(replacementTemplate.name) for today.", false)
        case "set_bodyweight":
            guard let weight = arguments["weightLb"] as? Double, weight > 0 else {
                return ("Pass a bodyweight in lb (weightLb).", true)
            }
            store.saveBodyWeight(weight)
            return ("Bodyweight set to \(weight) lb.", false)
        case "start_rest_timer":
            let seconds = arguments["seconds"] as? Double ?? 90
            store.restEndsAt = Date().addingTimeInterval(seconds)
            return ("Rest timer started for \(Int(seconds)) seconds.", false)
        case "cancel_rest_timer":
            store.cancelRest()
            return ("Rest timer cancelled.", false)
        default:
            return ("Unknown tool: \(name)", true)
        }
    }

    static func resource(uri: String, store: WorkoutStore) -> String? {
        switch uri {
        case "gymtracker://program/active":
            guard let program = store.activeProgram else { return nil }
            return encode(program)
        case "gymtracker://history/recent":
            return encode(Array(store.sessions.prefix(20)))
        case "gymtracker://profile":
            guard let profile = store.profile else { return nil }
            return encode(profile)
        case "gymtracker://exercise-library":
            return encode(ExerciseLibrary.all(plus: store.customExercises))
        default:
            return nil
        }
    }

    static func prompt(name: String, store: WorkoutStore) -> [String: Any]? {
        switch name {
        case "weekly-review":
            let weekStart = weekStartDate(for: Date())
            let thisWeek = store.sessions.filter { $0.date >= weekStart }
            var setsDone = 0
            for session in thisWeek {
                for exercise in session.exercises {
                    for set in exercise.sets where set.done {
                        setsDone += 1
                    }
                }
            }
            return [
                "description": "Summarize this week's training.",
                "messages": [[
                    "role": "user",
                    "content": ["type": "text", "text":
                        "Summarize my training this week. Sessions done: \(thisWeek.count). Sets done: \(setsDone). Total sessions ever: \(store.sessions.count). What progressed, what stalled?"],
                ]],
            ]
        case "next-workout-brief":
            guard let next = store.nextWorkout(after: Date()) else { return nil }
            let lines = next.plan.exercises.map { template in
                let weight = store.lastWeight(for: template) ?? template.defaultWeightLb
                let hint = store.progressionHint(for: template)
                return "• \(template.name): \(template.sets) × \(template.repRange), \(weight.map { "\($0) lb" } ?? "set weight"). \(hint)"
            }
            return [
                "description": "What is my next workout and what weights should I use?",
                "messages": [[
                    "role": "user",
                    "content": ["type": "text", "text":
                        "My next workout is \(next.plan.title) on \(next.date.formatted(date: .abbreviated, time: .omitted)).\n" + lines.joined(separator: "\n")],
                ]],
            ]
        case "suggest-swap":
            guard let plan = store.programDay(for: Date()) else { return nil }
            let names = plan.exercises.map { $0.name }.joined(separator: ", ")
            return [
                "description": "Suggest swaps for today's plan (shoulder-safe).",
                "messages": [[
                    "role": "user",
                    "content": ["type": "text", "text":
                        "My shoulder hurts today. Today's plan (\(plan.title)) is: \(names). Which exercises should I swap, and for what? Prefer shoulder-safe substitutes (no overhead press, no incline press)."],
                ]],
            ]
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private static func findExercise(_ query: String, store: WorkoutStore) -> ExerciseTemplate? {
        let pool = store.draftExercises.isEmpty
            ? (store.programDay(for: Date())?.exercises ?? [])
            : store.draftExercises
        // Exact id first, then exact name, then name-contains as a last
        // resort: a typo must not resolve the wrong exercise by
        // first-contains-match.
        if let exact = pool.first(where: { $0.id == query }) { return exact }
        if let named = pool.first(where: { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }) { return named }
        return pool.first {
            $0.name.localizedCaseInsensitiveContains(query)
                || query.localizedCaseInsensitiveContains($0.name)
        }
    }

    private static func exerciseJSON(_ template: ExerciseTemplate) -> [String: Any] {
        var dict: [String: Any] = [
            "id": template.id, "name": template.name, "sets": template.sets,
            "repRange": template.repRange, "topReps": template.topReps, "isPair": template.isPair,
        ]
        if let weight = template.defaultWeightLb { dict["defaultWeightLb"] = weight }
        if let cues = template.cues { dict["cues"] = cues }
        return dict
    }

    private static func setJSON(_ set: SetLog) -> [String: Any] {
        var dict: [String: Any] = ["reps": set.reps, "done": set.done, "kind": set.kind.rawValue]
        if let weight = set.weightLb { dict["weightLb"] = weight }
        return dict
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func encode(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
