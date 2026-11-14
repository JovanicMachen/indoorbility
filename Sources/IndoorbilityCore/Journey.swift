import Foundation

/// Requires sustained AR world-map relocalization before automatically placing
/// a user on a saved route. GPS proximity and OCR alone cannot satisfy this.
public struct SavedRouteRelocalization {
    private var stableSince: TimeInterval?
    private var previousTime: TimeInterval?
    private var previousPosition: SpatialPoint?
    public init() {}
    public mutating func reset() { stableSince = nil; previousTime = nil; previousPosition = nil }
    public mutating func update(mapMatched: Bool, trackingStable: Bool, position: SpatialPoint?, time: TimeInterval) -> Bool {
        guard mapMatched, trackingStable, let position, position.isFinite, time.isFinite else { reset(); return false }
        if let previousTime, let previousPosition {
            let dt = time-previousTime
            if dt <= 0 || dt > 0.8 || position.distance(to: previousPosition) > max(0.6, Float(dt)*2.5) {
                reset()
            }
        }
        previousTime = time; previousPosition = position
        if stableSince == nil { stableSince = time }
        return time-(stableSince ?? time) >= 2
    }
}

public struct JourneyDestination: Codable, Equatable, Identifiable {
    public let id: UUID
    public let routeID: UUID
    public let scanID: UUID
    public let room: String
    public let building: String
    public var lastVisited: Date?
    public var successfulVisits: Int? // Optional for existing saved catalogs.
    public init(route: HallwayRoute, building: String) {
        id = route.id; routeID = route.id; scanID = route.scanID; room = route.room.label; self.building = building
    }
}

/// Outdoor proximity may prepare a camera session; it is never indoor location evidence.
public struct EntranceHandoff {
    public enum Phase: Equatable { case outdoor, locatingEntrance, indoor }
    public private(set) var phase: Phase = .outdoor
    private var stableSince: TimeInterval?
    private var lastTime: TimeInterval?
    public init(preparingIndoor: Bool = false) { if preparingIndoor { phase = .locatingEntrance } }
    public mutating func update(distanceToBuilding: Double?, horizontalAccuracy: Double?, mapMatches: Bool,
                                entranceLabelMatches: Bool, positionNearEntrance: Bool, trackingNormal: Bool,
                                headingAvailable: Bool, time: TimeInterval) -> Phase {
        guard time.isFinite else { resetEvidence(); return phase }
        if let previous = lastTime, time <= previous || time-previous > 0.8 { stableSince = nil }
        lastTime = time
        if phase == .indoor && (!trackingNormal || !mapMatches) { phase = .locatingEntrance; stableSince = nil }
        if phase == .outdoor, let distanceToBuilding, let horizontalAccuracy,
           distanceToBuilding >= 0, distanceToBuilding < 50, horizontalAccuracy >= 0, horizontalAccuracy <= 20 {
            phase = .locatingEntrance
        }
        guard phase == .locatingEntrance else { return phase }
        guard mapMatches, entranceLabelMatches, positionNearEntrance, trackingNormal, headingAvailable else {
            stableSince = nil; return phase
        }
        if let since = stableSince, time >= since, time-since >= 2 { phase = .indoor }
        else if stableSince == nil || time < stableSince! { stableSince = time }
        return phase
    }
    public mutating func resetEvidence() { stableSince = nil; lastTime = nil; if phase == .indoor { phase = .locatingEntrance } }
}

public enum LocalNavigationIntent: Equatable {
    case destination(UUID), shopping([String]), unknown, ambiguous
}

/// Deterministic fallback. It returns identifiers from an explicit catalog, never generated locations.
public enum LocalNavigationAgent {
    public static func constraints(for text: String, base: Preferences) -> Preferences {
        var result = base
        if ["without stairs", "avoid stairs", "no stairs"].contains(where: text.lowercased().contains) { result.avoidStairs = true }
        return result
    }
    public static func interpret(_ text: String, destinations: [JourneyDestination]) -> LocalNavigationIntent {
        var query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.hasPrefix("cancel"), !query.contains("do not take"), !query.contains("don't take") else { return .unknown }
        for phrase in ["without stairs", "avoid stairs", "no stairs", "then take me to checkout"] { query = query.replacingOccurrences(of: phrase, with: "") }
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 1000 else { return .unknown }
        if query.hasPrefix("buy ") || query.hasPrefix("shopping:") || query.hasPrefix("find everything:") {
            let content = query.hasPrefix("buy ") ? String(query.dropFirst(4)) : String(query.split(separator: ":", maxSplits: 1).last ?? "")
            let items = content.replacingOccurrences(of: " and ", with: ",").components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            return items.isEmpty ? .unknown : .shopping(items)
        }
        let matches = destinations.filter {
            let room = $0.room.lowercased()
            // Exact room token boundaries avoid Room 20 matching Room 204.
            return query.range(of: "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: room) + "(?![a-z0-9])", options: .regularExpression) != nil
        }
        let qualified = matches.filter { query.contains($0.building.lowercased()) }
        let candidates = qualified.isEmpty ? matches : qualified
        if candidates.count == 1 { return .destination(candidates[0].id) }
        return candidates.isEmpty ? .unknown : .ambiguous
    }
}


public enum ArrivalEvidence {
    public static func canConfirm(state: HallwayFollower.State, trackingStable: Bool, poseFresh: Bool, labelMatches: Bool, routeAvailable: Bool) -> Bool {
        state == .nearRoom && trackingStable && poseFresh && labelMatches && routeAvailable
    }
}

public enum LandmarkTextEvidence {
    public static func matches(_ observed: String, expected: String, confidence: Float, entrance: Bool) -> Bool {
        func normalized(_ text: String) -> String {
            let value = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
            return entrance ? value : value.replacingOccurrences(of: "^(room|rm)\\s+", with: "", options: .regularExpression)
        }
        let expected = normalized(expected)
        guard confidence.isFinite, confidence >= 0.8, expected.count >= (entrance ? 5 : 2),
              !entrance || !["entrance", "door", "lobby"].contains(expected) else { return false }
        return normalized(observed) == expected
    }
}
