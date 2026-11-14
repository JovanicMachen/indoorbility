import Foundation

public struct Route: Equatable {
    public let nodeIDs: [String]
    public let edgeIDs: [String]
    public let cost: Double
}

public enum Router {
    /// Dijkstra on explicit edge costs. Diagram coordinates never influence routing.
    public static func plan(in building: Building, from start: String, to goal: String,
                            avoidStairs: Bool = true, excluding blocked: Set<String> = []) throws -> Route? {
        try building.validate()
        guard building.node(start) != nil, building.node(goal) != nil else {
            throw MapError.invalid("Choose a known starting checkpoint and destination.")
        }
        if start == goal { return Route(nodeIDs: [start], edgeIDs: [], cost: 0) }
        let eligible = building.edges.filter {
            $0.verified && !$0.blocked && !blocked.contains($0.id) && !(avoidStairs && $0.kind == .stairs)
        }.sorted { $0.id < $1.id }
        var costs: [String: Double] = [start: 0]
        var pending: Set<String> = [start]
        var settled = Set<String>()
        var previous: [String: (node: String, edge: String)] = [:]
        while let current = pending.min(by: {
            let lhs = costs[$0, default: .infinity], rhs = costs[$1, default: .infinity]
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }) {
            pending.remove(current)
            if current == goal {
                var nodes = [goal], edges: [String] = [], cursor = goal
                while let step = previous[cursor] {
                    nodes.append(step.node); edges.append(step.edge); cursor = step.node
                }
                return Route(nodeIDs: nodes.reversed(), edgeIDs: edges.reversed(), cost: costs[goal]!)
            }
            settled.insert(current)
            for edge in eligible where edge.from == current || edge.to == current {
                let next = edge.from == current ? edge.to : edge.from
                guard !settled.contains(next) else { continue }
                let cost = costs[current, default: .infinity] + edge.distance
                if cost < costs[next, default: .infinity] {
                    costs[next] = cost
                    previous[next] = (current, edge.id)
                    pending.insert(next)
                }
            }
        }
        return nil
    }
}
