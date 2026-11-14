import Foundation

public enum AgentTool: String, Codable, CaseIterable {
    case getNavigationState, resolveDestination, calculateAccessibleRoute, changeDestination
    case getKnownClosures, replanRoute, getAccessibilityPreferences, repeatInstruction
    case getNearbyMappedDestinations, describeCurrentView, getShoppingList, addShoppingItem, optimizeShoppingRoute
}
public struct AgentCall: Codable, Equatable {
    public let callId: String
    public let tool: AgentTool
    public let argument: String
    public let expectedRevision: Int
    public let sessionId: String
    public init(callId: String, tool: AgentTool, argument: String = "", expectedRevision: Int, sessionId: String) {
        self.callId = callId; self.tool = tool; self.argument = argument
        self.expectedRevision = expectedRevision; self.sessionId = sessionId
    }
}
public struct AgentToolResult: Codable, Equatable {
    public enum Status: String, Codable { case success, needs_clarification, unverified, unavailable, error }
    public let callId: String
    public let sessionRevision: Int
    public let status: Status
    public let data: [String: String]
    public let userSafeExplanation: String
    public init(callId: String, sessionRevision: Int, status: Status, data: [String: String] = [:], userSafeExplanation: String) {
        self.callId = callId; self.sessionRevision = sessionRevision; self.status = status; self.data = data; self.userSafeExplanation = userSafeExplanation
    }
}
/// A turn's execution ledger. IDs are scoped to one live navigation session, never replayed after relaunch.
public struct AgentExecutionLedger {
    public let sessionId: String
    public private(set) var revision = 0
    private var records: [String: (AgentCall, AgentToolResult)] = [:]
    public init(sessionId: String = UUID().uuidString) { self.sessionId = sessionId }
    public mutating func invalidate() { revision += 1 }
    public func validate(_ call: AgentCall) throws -> AgentToolResult? {
        guard call.sessionId == sessionId, !call.callId.isEmpty, call.callId.count <= 200, call.argument.count <= 500 else { throw MapError.invalid("Invalid agent request.") }
        if let (prior, result) = records[call.callId] {
            guard prior == call else { throw MapError.invalid("A repeated request changed its arguments.") }
            return result
        }
        guard call.expectedRevision == revision else { throw MapError.invalid("Navigation changed while the assistant was thinking. Please try again.") }
        guard records.count < 128 else { throw MapError.invalid("This conversation has reached its tool limit. Start a new navigation session.") }
        return nil
    }
    public mutating func record(_ call: AgentCall, result: AgentToolResult) { records[call.callId] = (call, result) }
}
public struct AgentTaskMemory: Codable, Equatable {
    public var items: [String] = []
    public var completed: [String] = []
    public init() {}
    public mutating func add(_ item: String) throws {
        let item = item.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty, item.count <= 80, items.count < 30 else { throw MapError.invalid("Use one short product name; the list supports 30 items.") }
        if !items.contains(item) { items.append(item) }
    }
}
