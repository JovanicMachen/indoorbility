import Foundation

public struct BarrierSuggestion: Equatable {
    public let targetEdgeID: String?
    public let message: String
}

public enum BarrierInterpreter {
    /// Text is evidence, never authorization. Ambiguous/contradictory signs require manual selection.
    public static func interpret(_ text: String, in building: Building) -> BarrierSuggestion {
        let normalized = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let outages = ["out of service", "unavailable", "closed", "not working", "under maintenance"]
        let conflicts = ["not out of service", "not closed", "not unavailable", "back in service", "now open", "operational", "in service", "reopened"]
        let withoutOutage = normalized.replacingOccurrences(of: "out of service", with: "")
        guard outages.contains(where: normalized.contains),
              !conflicts.contains(where: withoutOutage.contains),
              !normalized.contains("not out of service") else {
            return .init(targetEdgeID: nil, message: "Check the sign and choose the affected connection yourself.")
        }
        let matches = building.edges.filter { edge in
            if edge.kind == .hallway {
                let names = [building.node(edge.from)?.label.lowercased() ?? "", building.node(edge.to)?.label.lowercased() ?? ""]
                let namedPath = names.allSatisfy { !$0.isEmpty && normalized.range(of: "\\b" + NSRegularExpression.escapedPattern(for: $0) + "\\b", options: .regularExpression) != nil }
                return namedPath || (building.edges.count == 1 && normalized.contains("hallway"))
            }
            guard edge.kind == .elevator else { return false }
            let label = building.edgeLabel(edge.id).lowercased()
            let aliases = [label, label.replacingOccurrences(of: "lift", with: "elevator")]
            return aliases.contains { alias in
                normalized.range(of: "\\b" + NSRegularExpression.escapedPattern(for: alias) + "\\b", options: .regularExpression) != nil
            }
        }
        guard matches.count == 1, let match = matches.first else {
            return .init(targetEdgeID: nil, message: "The sign does not identify one known connection. Choose a connection to continue.")
        }
        return .init(targetEdgeID: match.id, message: "The sign may report \(building.edgeLabel(match.id)) unavailable. Please verify before applying it.")
    }
}
