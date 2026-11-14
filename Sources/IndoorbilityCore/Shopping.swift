import Foundation

public struct ShoppingPlan: Equatable {
    public let stops: [String]
    public let legs: [Route]
    public let unknownItems: [String]
    public var cost: Double { legs.reduce(0) { $0 + $1.cost } }
}

public enum ShoppingRoutePlanner {
    public static let demoProducts = ["milk":"milk", "cereal":"cereal", "paper towels":"paper", "shampoo":"shampoo"]
    public static func retailDemo() throws -> Building {
        guard let url = Bundle.module.url(forResource: "retail_demo", withExtension: "json") else { throw MapError.invalid("Retail demo is missing.") }
        return try Building.load(Data(contentsOf: url))
    }
    /// Exact permutation search for the deliberately small demo, using graph distances, not straight lines.
    public static func plan(items: [String], catalog: [String: String], in building: Building, from start: String,
                            checkout: String, avoidStairs: Bool = true, blocked: Set<String> = []) throws -> ShoppingPlan {
        let normalized = Array(Set(items.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        let unknown = normalized.filter { catalog[$0] == nil }
        let targets = Array(Set(normalized.compactMap { catalog[$0] })).filter { $0 != checkout }.sorted()
        guard targets.count <= 8 else { throw MapError.invalid("This local demo supports up to eight known stops.") }
        guard building.node(start) != nil, building.node(checkout) != nil, targets.allSatisfy({ building.node($0) != nil }) else { throw MapError.invalid("A product or checkout references an unknown mapped location.") }
        let points = Array(Set([start,checkout]+targets))
        var routes: [String: Route] = [:]
        func key(_ a: String, _ b: String) -> String { "\(a)\u{0}\(b)" }
        for a in points { for b in points {
            if let route = try Router.plan(in: building, from: a, to: b, avoidStairs: avoidStairs, excluding: blocked) { routes[key(a,b)] = route }
        } }
        var best: ShoppingPlan?
        func visit(_ current: String, _ remaining: [String], _ order: [String], _ legs: [Route], _ cost: Double) {
            if let best, cost >= best.cost { return }
            if remaining.isEmpty {
                guard let finish = routes[key(current,checkout)] else { return }
                let result = ShoppingPlan(stops: order+[checkout], legs: legs+[finish], unknownItems: unknown)
                if best == nil || result.cost < best!.cost { best = result }; return
            }
            for next in remaining {
                guard let route = routes[key(current,next)] else { continue }
                visit(next, remaining.filter { $0 != next }, order+[next], legs+[route], cost+route.cost)
            }
        }
        visit(start, targets, [], [], 0)
        guard let best else { throw MapError.invalid("No verified accessible route is currently available for all known stops and checkout.") }
        return best
    }
}

public enum VerifiedNavigationTools {
    public static func calculateRoute(in building: Building, start: String, destination: String, preferences: Preferences, blocked: Set<String>) throws -> Route {
        guard let route = try Router.plan(in: building, from: start, to: destination, avoidStairs: preferences.avoidStairs, excluding: blocked) else {
            throw MapError.invalid("No verified accessible route is currently available.")
        }
        return route
    }
}
