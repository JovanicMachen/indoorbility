import SwiftUI
import IndoorbilityCore

/// Adapter over the existing demo view state and deterministic graph optimizer.
@MainActor final class ShoppingAgentHost: ObservableObject, NavigationAgentHost {
    @Published var voiceResponse: String?
    let agent = NavigationAgent()
    var read: () -> ([String], [String], String, Set<String>, Bool) = { ([], [], "entrance", [], true) }
    var add: (String) -> Void = { _ in }
    var speak: (String) -> Void = { _ in }
    private var ledger = AgentExecutionLedger()
    private var fingerprint = ""
    private var utterance = ""
    func beginAgentTurn(_ text: String) { utterance = text; _ = agentContext() }
    func agentContext() -> AgentContext {
        let (items, completed, current, blocked, avoid) = read()
        let next = "\(items)|\(completed)|\(current)|\(blocked.sorted())|\(avoid)"
        if next != fingerprint { ledger.invalidate(); fingerprint = next }
        return AgentContext(sessionId: ledger.sessionId, sessionRevision: ledger.revision, buildingId: "fictional-corner-market", floor: 0,
            tracking: "uncertain", destinationId: "checkout", avoidStairs: avoid,
            instruction: "Fictional shopping simulation; checkoffs simulate position. No live camera localization.", knownDestinations: [], knownClosures: blocked.sorted())
    }
    func executeAgent(_ call: AgentCall) async -> AgentToolResult {
        _ = agentContext()
        var validated = false
        var status = AgentToolResult.Status.success
        var message = ""; var data: [String: String] = [:]
        do {
            if let result = try ledger.validate(call) { return result }
            validated = true
            let (items, completed, current, blocked, avoid) = read()
            switch call.tool {
            case .getShoppingList:
                message = "Demo remaining items: \(items.joined(separator: ", ")). Collected: \(completed.joined(separator: ", "))."
            case .addShoppingItem:
                guard utterance.lowercased().contains(call.argument.lowercased()), !call.argument.isEmpty,
                      call.argument.count <= 80, items.count < 30 else { throw MapError.invalid("Name one requested product to add.") }
                add(call.argument.lowercased()); message = "Added \(call.argument) to the fictional store trip. The remaining route was recalculated."
            case .optimizeShoppingRoute, .replanRoute:
                let graph = try ShoppingRoutePlanner.retailDemo()
                let plan = try ShoppingRoutePlanner.plan(items: items, catalog: ShoppingRoutePlanner.demoProducts, in: graph, from: current, checkout: "checkout", avoidStairs: avoid, blocked: blocked)
                let stops = plan.stops.compactMap { graph.node($0)?.label }.joined(separator: " → ")
                message = "Demo route: \(stops)." + (plan.unknownItems.isEmpty ? "" : " Locations unknown: \(plan.unknownItems.joined(separator: ", ")).")
                data = ["mode": "fictional-store", "stops": plan.stops.joined(separator: ","), "cost": String(plan.cost), "unknown": plan.unknownItems.joined(separator: ",")]
            case .getKnownClosures: message = "Simulated closed edges: \(blocked.sorted().joined(separator: ", "))."
            case .getAccessibilityPreferences: message = "Avoid stairs: \(avoid)."; data = ["avoidStairs": String(avoid)]
            case .getNavigationState: message = agentContext().instruction
            default: status = .unavailable; message = "This tool is not available in the fictional shopping simulation."
            }
        } catch { status = .error; message = error.localizedDescription }
        let result = AgentToolResult(callId: call.callId, sessionRevision: agentContext().sessionRevision, status: status, data: data, userSafeExplanation: message)
        // Never cache an invalid incoming call under a valid operation's id.
        if validated { ledger.record(call, result: result) }
        return result
    }
    func presentClarification(_ text: String) { voiceResponse = text; speak(text) }
    func presentAgentResult(_ result: AgentToolResult) {
        guard result.sessionRevision == agentContext().sessionRevision else { return }
        voiceResponse = result.userSafeExplanation; speak(result.userSafeExplanation)
    }
    func handleVoice(_ text: String) {
        let lower = text.lowercased()
        if lower.hasPrefix("add ") {
            let item = lower.dropFirst(4).components(separatedBy: " then ").first?.trimmingCharacters(in: CharacterSet(charactersIn: ", .")) ?? ""
            if !item.isEmpty && item.count <= 80 { add(item) }
        }
        Task {
            let context = agentContext()
            let result = await executeAgent(AgentCall(callId: UUID().uuidString, tool: .optimizeShoppingRoute, expectedRevision: context.sessionRevision, sessionId: context.sessionId))
            presentAgentResult(result)
        }
    }
}
