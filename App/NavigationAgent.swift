import SwiftUI
import Security
import IndoorbilityCore

struct AgentContext: Codable {
    let sessionId: String
    let sessionRevision: Int
    let buildingId: String
    let floor: Int?
    let tracking: String
    let destinationId: String
    let avoidStairs: Bool
    let instruction: String
    let knownDestinations: [[String: String]]
    let knownClosures: [String]
}
private struct AgentRequest: Encodable {
    let utterance: String
    let context: AgentContext
    let runId: String?
    let result: AgentToolResult?
}
private struct AgentResponse: Decodable {
    struct Final: Decodable { let responseCallId: String?; let clarification: String }
    let runId: String
    let call: AgentCall?
    let final: Final?
}
@MainActor enum AgentConfiguration {
    // Verified on Railway: HTTPS, real agent/Swift tools, auth and restart persistence.
    static let productionBaseURL = "https://indoorbility-production.up.railway.app"
    static var configuredBase: String {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "agentRailwayURLMigrated") {
            let old = defaults.string(forKey: "agentBaseURL") ?? ""
            if let host = URL(string: old.trimmingCharacters(in: .whitespacesAndNewlines))?.host,
               host == "trycloudflare.com" || host.hasSuffix(".trycloudflare.com") {
                defaults.removeObject(forKey: "agentBaseURL")
            }
            defaults.set(true, forKey: "agentRailwayURLMigrated")
        }
        let override = (defaults.string(forKey: "agentBaseURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return override.isEmpty ? productionBaseURL : override
    }
    static var url: URL? {
        guard UserDefaults.standard.bool(forKey: "agentCloudEnabled") else { return nil }
        return validatedURL(configuredBase)
    }
    static func validatedURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        return url
    }
    private struct Credentials: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Double
        let deviceId: String
        var baseURL: String?
        var pendingRefreshRequestID: String? = nil
    }
    static let service = "com.indoorbility.agent-access"
    private static var credentialVersion = UUID()
    private static var renewal: (id: UUID, base: String, task: Task<String, Error>)?
    private static func storedData() -> Data? {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    private static func stored() -> Credentials? {
        guard let data = storedData(), let value = try? JSONDecoder().decode(Credentials.self, from: data),
              value.baseURL == url?.absoluteString else { return nil }
        return value
    }
    static func token() -> String? {
        guard let value = stored(), value.expiresAt > Date().timeIntervalSince1970+30 else { return nil }
        return value.accessToken
    }
    static func accessToken() async throws -> String {
        if let token = token() { return token }
        guard let base = url, var value = stored() else { throw MapError.invalid("Cloud AI is not connected on this phone.") }
        if let renewal, renewal.base == base.absoluteString { return try await renewal.task.value }
        let renewalID = UUID()
        let version = credentialVersion
        // Persist before sending: after a timeout, crash or reboot the exact
        // same rotation request can recover the server's committed response.
        if value.pendingRefreshRequestID == nil {
            value.pendingRefreshRequestID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try saveData(JSONEncoder().encode(value))
        }
        let saved = value
        let task = Task<String, Error> {
            var result = try await exchange(base: base, path: "auth/refresh", credential: saved.refreshToken, requestID: saved.pendingRefreshRequestID)
            guard url == base, credentialVersion == version else { throw CancellationError() }
            guard result.deviceId == saved.deviceId else { throw MapError.invalid("Cloud device identity changed.") }
            result.baseURL = base.absoluteString
            try saveData(JSONEncoder().encode(result))
            return result.accessToken
        }
        renewal = (renewalID, base.absoluteString, task)
        defer { if renewal?.id == renewalID { renewal = nil } }
        return try await task.value
    }
    static func pair(code: String, base: URL) async throws {
        credentialVersion = UUID(); renewal?.task.cancel(); renewal = nil
        var result = try await exchange(base: base, path: "auth/pair", credential: code)
        guard validatedURL(configuredBase) == base else { throw MapError.invalid("Backend URL changed. Pair with the selected backend.") }
        result.baseURL = base.absoluteString
        try saveData(JSONEncoder().encode(result))
    }
    private static func exchange(base: URL, path: String, credential: String, requestID: String? = nil) async throws -> Credentials {
        var request = URLRequest(url: base.appending(path: path))
        request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = ["credential": credential]
        if let requestID { body["requestId"] = requestID }
        request.httpBody = try JSONEncoder().encode(body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration, delegate: NoAgentRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 8192 else {
            throw MapError.invalid("Cloud AI is unavailable. Check your connection and try again.")
        }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    static func saveToken(_ token: String) throws {
        credentialVersion = UUID(); renewal?.task.cancel(); renewal = nil
        // Legacy operator-issued short-lived tokens remain usable for local development only.
        guard let base = url else { throw MapError.invalid("Enable the assistant and set its HTTPS URL first.") }
        if token.isEmpty { try saveData(nil); return }
        let value = Credentials(accessToken: token, refreshToken: "", expiresAt: Date().timeIntervalSince1970+300,
                                deviceId: "legacy", baseURL: base.absoluteString)
        try saveData(JSONEncoder().encode(value))
    }
    private static func saveData(_ data: Data?) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        guard let data else { SecItemDelete(query as CFDictionary); return }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw MapError.invalid("Could not save phone credentials.") }
        } else if status != errSecSuccess { throw MapError.invalid("Could not update phone credentials.") }
    }
}
@MainActor protocol NavigationAgentHost: AnyObject {
    var voiceResponse: String? { get set }
    func beginAgentTurn(_ text: String)
    func agentContext() -> AgentContext
    func executeAgent(_ call: AgentCall) async -> AgentToolResult
    func presentAgentResult(_ result: AgentToolResult)
    func presentClarification(_ text: String)
    func handleVoice(_ text: String)
}

@MainActor final class NavigationAgent: ObservableObject {
    struct Event: Identifiable { let id = UUID(); let date = Date(); let run: String; let text: String }
    @Published private(set) var events: [Event] = []
    @Published private(set) var busy = false
    @Published private(set) var cloudStatus: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var runID: String?
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: NoAgentRedirect(), delegateQueue: nil)
    }()
    private func log(_ text: String, run: String = "local") {
        events.append(Event(run: run, text: text)); if events.count > 80 { events.removeFirst(events.count-80) }
    }
    func recordDeviceEvent(_ text: String) { log(text, run: "device-confirmation") }
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil; busy = false
        if let runID, let url = AgentConfiguration.url, let token = AgentConfiguration.token() {
            var request = URLRequest(url: url.appending(path: "agent/turn/\(runID)")); request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let session = session
            Task { _ = try? await session.data(for: request) }
        }
        runID = nil
    }
    func submit(_ text: String, model: any NavigationAgentHost) {
        cancel(); let token = generation
        model.beginAgentTurn(text)
        if ["stop", "pause", "pause guidance", "stop guidance", "cancel"].contains(text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
            log("Immediate local pause · model bypassed")
            model.handleVoice(text); return
        }
        guard let base = AgentConfiguration.url else {
            log("Offline fallback · cloud disabled or not configured")
            cloudStatus = UserDefaults.standard.bool(forKey: "agentCloudEnabled") ? "Cloud AI isn’t configured. Local navigation continues." : nil
            model.handleVoice(text); return
        }
        busy = true; cloudStatus = nil
        log("Model turn started · utterance withheld")
        task = Task { [weak self, weak model] in
            guard let self, let model else { return }
            var run: String?; var result: AgentToolResult?
            var results: [String: AgentToolResult] = [:]
            var mutated = false
            let start = Date()
            do {
                for _ in 0..<5 {
                    try Task.checkCancellation()
                    guard token == self.generation else { return }
                    let credential = try await AgentConfiguration.accessToken()
                    let payload = AgentRequest(utterance: run == nil ? text : "", context: model.agentContext(), runId: run, result: result)
                    var request = URLRequest(url: base.appending(path: "agent/turn"))
                    request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONEncoder().encode(payload)
                    let (data, response) = try await session.data(for: request)
                    try Task.checkCancellation()
                    guard token == self.generation else { return }
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 32768 else { throw MapError.invalid("The AI service is unavailable.") }
                    let reply = try JSONDecoder().decode(AgentResponse.self, from: data)
                    guard reply.runId.count <= 100, run == nil || reply.runId == run else { throw MapError.invalid("Invalid agent continuation.") }
                    run = reply.runId; self.runID = run
                    if let call = reply.call {
                        guard reply.final == nil else { throw MapError.invalid("Conflicting agent response.") }
                        log("Requested \(call.tool.rawValue) · revision \(call.expectedRevision)", run: reply.runId)
                        let before = model.agentContext().sessionRevision
                        let actual = await model.executeAgent(call)
                        try Task.checkCancellation()
                        guard token == self.generation else { return }
                        mutated = mutated || model.agentContext().sessionRevision != before
                        result = actual; results[actual.callId] = actual
                        log("Executed \(call.tool.rawValue) · \(actual.status.rawValue) · revision \(actual.sessionRevision)", run: reply.runId)
                        if let preserved = actual.data["arSessionPreserved"] {
                            log("ARSession preserved: \(preserved) · pose preserved: \(actual.data["positionPreserved"] ?? "unknown") · speech generation: \(actual.data["speechGeneration"] ?? "unknown")", run: reply.runId)
                        }
                        // User-facing navigation text comes only from the authoritative local result.
                        model.presentAgentResult(actual)
                    } else if let final = reply.final {
                        if let id = final.responseCallId {
                            guard let actual = results[id] else { throw MapError.invalid("Agent referenced an unexecuted result.") }
                            // Don't repeat an old observation after the user has moved or tracking changed.
                            if actual.sessionRevision == model.agentContext().sessionRevision, model.voiceResponse != actual.userSafeExplanation { model.presentAgentResult(actual) }
                        } else if results.isEmpty {
                            model.presentClarification(final.clarification == "destination" ? "Which room and building?" : final.clarification == "store" ? "Which store?" : "What would you like help with?")
                        }
                        log("Completed in \(Int(Date().timeIntervalSince(start)*1000)) ms · grounded local response", run: reply.runId)
                        self.busy = false; self.runID = nil; return
                    } else { throw MapError.invalid("Missing agent action.") }
                }
                throw MapError.invalid("Agent tool limit reached.")
            } catch {
                guard token == self.generation, !Task.isCancelled else { return }
                log("Model/network failure · \(mutated ? "kept completed actions" : "local fallback")", run: run ?? "local")
                self.cancel()
                self.cloudStatus = "Cloud AI unavailable. Local navigation continues."
                if !mutated { model.handleVoice(text) }
                else { model.voiceResponse = "The AI connection ended. Completed changes are kept; local guidance continues." }
            }
            self.busy = false
        }
    }
}
private final class NoAgentRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
private struct AgentConnectionStatus: Decodable { let authenticated: Bool; let modelConfigured: Bool }

struct AgentSettingsView: View {
    @ObservedObject var store: AppStore
    @AppStorage("agentCloudEnabled") private var enabled = false
    @AppStorage("agentBaseURL") private var url = ""
    @AppStorage("agentDeveloperMode") private var developer = false
    @State private var token = ""
    @State private var pairing = false
    @State private var message = "Offline"
    @State private var checking = false
    @Environment(\.scenePhase) private var phase

    private func check() async {
        guard !checking else { return }
        guard enabled, let base = AgentConfiguration.url else { message = "Offline"; return }
        checking = true; message = "Connecting"
        defer { checking = false }
        do {
            let token = try await AgentConfiguration.accessToken()
            var request = URLRequest(url: base.appending(path: "agent/check"))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let session = URLSession(configuration: .ephemeral, delegate: NoAgentRedirect(), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { message = "Offline"; return }
            let status = try JSONDecoder().decode(AgentConnectionStatus.self, from: data)
            message = status.authenticated && status.modelConfigured ? "Connected" : "Offline"
        } catch { message = "Offline" }
    }
    var body: some View {
        Form {
            Section("Connection") {
                Label(message, systemImage: message == "Connected" ? "checkmark.circle.fill" : "wifi.slash")
                    .accessibilityIdentifier("agentConnectionStatus")
                Toggle("Cloud AI", isOn: $enabled)
                Button(checking ? "Connecting…" : "Check connection") { Task { await check() } }
                    .disabled(checking).accessibilityIdentifier("checkAgentConnection")
                Text("AI needs internet. Saved navigation works offline.").font(.footnote)
                DisclosureGroup("Privacy") {
                    Text("AI receives your command text, destination labels, route status, preferences and requested sign text.")
                    Text("Camera images, audio recordings and position history stay on your phone.")
                }.font(.footnote)
            }
            Section("Developer") {
                Toggle("Show agent timeline", isOn: $developer)
                if developer {
                    NavigationLink("Test navigation") { GuidanceTestView(store: store) }.accessibilityIdentifier("testNavigation")
                    DisclosureGroup("Advanced connection") {
                        TextField("Backend HTTPS URL", text: $url).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("One-time pairing code", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(pairing ? "Pairing…" : "Pair this iPhone") {
                            pairing = true
                            Task {
                                defer { pairing = false }
                                do {
                                    guard let base = AgentConfiguration.validatedURL(AgentConfiguration.configuredBase) else { throw MapError.invalid("Invalid backend URL.") }
                                    try await AgentConfiguration.pair(code: token.trimmingCharacters(in: .whitespacesAndNewlines), base: base)
                                    token = ""; enabled = true; await check()
                                } catch { message = "Offline" }
                            }
                        }.disabled(pairing || token.isEmpty)
                    }
                }
            }
        }.navigationTitle("AI connection")
            .onAppear { url = AgentConfiguration.configuredBase }
            .task { await check() }
            .onChange(of: enabled) { _, _ in Task { await check() } }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await check() } } }
    }
}

struct AgentTimelineView: View {
    @ObservedObject var agent: NavigationAgent
    var body: some View {
        List {
            Text("Actual requests and execution status. Labels, utterances, coordinates and tokens are excluded. No real-model result is implied by an offline event.").font(.footnote)
            ForEach(agent.events) { event in VStack(alignment: .leading) { Text(event.text); Text(event.run).font(.caption.monospaced()).foregroundStyle(.secondary) } }
        }.navigationTitle("Agent timeline")
    }
}

struct AgentActivityView: View {
    @ObservedObject var agent: NavigationAgent
    var body: some View {
        if let status = agent.cloudStatus { Text(status).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("cloudUnavailable") }
        if agent.busy {
            HStack {
                ProgressView().accessibilityLabel("Assistant is checking your request")
                Text("Checking your request…").font(.callout)
                Spacer()
                Button("Cancel") { agent.cancel() }.frame(minHeight: 44)
            }
        }
    }
}
