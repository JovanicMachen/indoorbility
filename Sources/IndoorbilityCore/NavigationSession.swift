import Foundation

public struct NavigationSession {
    public let building: Building
    public private(set) var saved: SavedState
    public private(set) var checkpointID: String?
    public private(set) var checkpointDate: Date?
    public private(set) var destinationID: String?
    public private(set) var route: Route?
    public private(set) var isGuiding = false
    public private(set) var routeDelta: Double?
    public private(set) var updateMessage: String?

    public init(building: Building, saved: SavedState? = nil) throws {
        try building.validate()
        let state = saved ?? SavedState(buildingID: building.buildingID)
        try state.validate(for: building)
        self.building = building; self.saved = state
    }
    public var nextCheckpoint: Checkpoint? { route?.nodeIDs.dropFirst().first.flatMap(building.node) }
    public var arrived: Bool { route?.nodeIDs.count == 1 }
    public var needsPosition: Bool { checkpointID == nil }

    public mutating func confirmCheckpoint(_ id: String, at date: Date = Date()) throws {
        guard building.node(id) != nil else { throw MapError.invalid("That checkpoint is not in this map.") }
        checkpointID = id; checkpointDate = date
        try replan(compare: false)
        updateMessage = "Starting point confirmed."
    }
    public mutating func forgetPosition() {
        checkpointID = nil; checkpointDate = nil; route = nil; routeDelta = nil; isGuiding = false
        updateMessage = "Confirm a checkpoint to continue."
    }
    public mutating func selectDestination(_ id: String) throws {
        guard building.node(id) != nil else { throw MapError.invalid("Choose a destination from the list.") }
        destinationID = id; isGuiding = false; updateMessage = nil
        try replan(compare: false)
    }
    public mutating func setPreferences(_ preferences: Preferences) throws {
        let changed = saved.preferences.avoidStairs != preferences.avoidStairs
        saved.preferences = preferences
        if changed {
            try replan(compare: false)
            updateMessage = "Route preferences updated."
        }
    }
    public mutating func startGuidance() {
        isGuiding = route != nil && !arrived
    }
    public mutating func stopGuidance() { isGuiding = false }
    public mutating func confirmReport(_ proposal: BarrierReport, at date: Date = Date()) throws {
        guard proposal.lifecycle == .proposed,
              building.edges.contains(where: { $0.id == proposal.targetEdgeID }),
              !saved.reports.contains(where: { $0.id == proposal.id }) else {
            throw MapError.invalid("This report cannot be confirmed.")
        }
        var report = proposal
        report.confirm(at: date)
        saved.reports.append(report)
        try replan(compare: true)
        updateMessage = "\(building.edgeLabel(report.targetEdgeID)) excluded by your local report."
    }
    public mutating func reviewReport(_ id: UUID, at date: Date = Date()) {
        guard let index = saved.reports.firstIndex(where: { $0.id == id }), saved.reports[index].isActive else { return }
        saved.reports[index].lastReviewedAt = date
        updateMessage = "Closure reviewed. It remains excluded from routes."
    }
    public mutating func resolveReport(_ id: UUID, at date: Date = Date()) throws {
        guard let index = saved.reports.firstIndex(where: { $0.id == id }), saved.reports[index].isActive else { return }
        saved.reports[index].resolve(at: date)
        try replan(compare: true)
        updateMessage = "Report resolved. Remaining closures still apply."
    }
    public mutating func reset() {
        saved = SavedState(buildingID: building.buildingID)
        forgetPosition(); destinationID = nil; updateMessage = nil
    }
    private mutating func replan(compare: Bool) throws {
        let prior = route
        routeDelta = nil
        guard let start = checkpointID, let goal = destinationID else { route = nil; isGuiding = false; return }
        route = try Router.plan(in: building, from: start, to: goal,
                                avoidStairs: saved.preferences.avoidStairs, excluding: saved.blockedEdges)
        if compare, let prior, let route, prior.nodeIDs.first == route.nodeIDs.first {
            routeDelta = route.cost - prior.cost
        }
        if route == nil || arrived { isGuiding = false }
    }
}
