import Foundation

/// A single, expiring proposal. A reply cannot activate a replaced or consumed proposal.
public struct DestinationConfirmation {
    public private(set) var id: UUID?
    private var expires: TimeInterval = 0
    public init() {}
    public mutating func propose(_ id: UUID, now: TimeInterval) { self.id = id; expires = now + 30 }
    public mutating func cancel() { id = nil }
    public mutating func accept(_ expected: UUID, now: TimeInterval) -> UUID? {
        guard now.isFinite, now < expires, id == expected else { id = nil; return nil }
        id = nil; return expected
    }
    public func isCurrent(_ expected: UUID, now: TimeInterval) -> Bool { id == expected && now < expires }
}

public enum DestinationSearch {
    public static func matches(_ text: String, in destinations: [JourneyDestination]) -> [JourneyDestination] {
        var query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for phrase in ["take me to", "go to", "please", "avoid stairs", "without stairs", "no stairs"] { query = query.replacingOccurrences(of: phrase, with: " ") }
        query = query.replacingOccurrences(of: "(?i)(room|rm)(?=[0-9])", with: "$1 ", options: .regularExpression)
        let tokens = query.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !["in", "the", "at", "room", "rm"].contains($0) }
        guard !tokens.isEmpty else { return [] }
        return destinations.filter { place in
            let words = (place.room + " " + place.building).lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            return tokens.allSatisfy { token in words.contains { word in token.allSatisfy(\.isNumber) ? word == token : word.hasPrefix(token) } }
        }
    }
}

/// Optional, manually verified floor label. Never inferred from a room number.
public struct VerifiedRoomMetadata: Codable, Equatable {
    public let buildingID: UUID
    public let roomID: UUID
    public let floorLabel: String
    public let source: String
    public let confirmedAt: Date
    public init(buildingID: UUID, roomID: UUID, floorLabel: String, confirmedAt: Date = Date()) {
        self.buildingID = buildingID; self.roomID = roomID; self.floorLabel = floorLabel
        self.source = "manually-confirmed"; self.confirmedAt = confirmedAt
    }
}

/// Depth is evidence about a surface, never a semantic object or a clear path.
public struct SceneAwarenessFilter {
    private var previous: (time: TimeInterval, distance: Float)?
    private var stableCount = 0
    private var lastAlert: TimeInterval = -.infinity
    public init() {}
    public mutating func update(distance: Float?, coverage: Float, timestamp: TimeInterval, now: TimeInterval, tracking: Bool, upright: Bool) -> Float? {
        guard tracking, upright, timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp < 0.5,
              coverage >= 0.65, let distance, distance.isFinite, distance > 0.25, distance < 1.8 else {
            previous = nil; stableCount = 0; return nil
        }
        if let previous {
            guard timestamp > previous.time else { return nil }
            stableCount = timestamp-previous.time < 0.5 && abs(distance-previous.distance) < 0.3 ? stableCount+1 : 1
        } else { stableCount = 1 }
        previous = (timestamp, distance)
        guard stableCount >= 3, now-lastAlert >= 8 else { return nil }
        lastAlert = now; return distance
    }
}

public enum BuildingQualifier {
    /// Explicit building names must agree with the active saved map. GPS never participates.
    public static func matches(_ request: String, building: String) -> Bool {
        var text = request.lowercased()
        guard let range = text.range(of: " in ", options: .backwards) else { return true }
        text = String(text[range.upperBound...])
        for phrase in ["avoid stairs", "without stairs", "no stairs", "please", "instead"] { text = text.replacingOccurrences(of: phrase, with: "") }
        func words(_ value: String) -> String { value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
        return words(text) == words(building)
    }
}

public enum SceneObservationValidity {
    public static func isFresh(capturedAt: TimeInterval, now: TimeInterval, movement: Float, forwardAgreement: Float) -> Bool {
        capturedAt.isFinite && now.isFinite && now >= capturedAt && now-capturedAt < 1.5 &&
        movement.isFinite && movement >= 0 && movement < 0.35 && forwardAgreement.isFinite && forwardAgreement > 0.9
    }
}
