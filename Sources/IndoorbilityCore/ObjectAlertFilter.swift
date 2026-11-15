import Foundation

/// Require repeated fresh evidence; never interpret missing detections as a clear path.
public struct ObjectAlertFilter {
    private var candidate: String?
    private var count = 0
    private var lastSample = -Double.infinity
    private var lastAlert = -Double.infinity
    private var lastAlertKind: String?
    public init() {}
    public mutating func update(kind: String?, capturedAt: Double, now: Double, reliable: Bool) -> Bool {
        guard reliable, capturedAt.isFinite, now.isFinite, now >= capturedAt,
              now - capturedAt <= 1, capturedAt > lastSample else {
            candidate = nil; count = 0; return false
        }
        if capturedAt - lastSample > 2 { candidate = nil; count = 0 }
        lastSample = capturedAt
        guard let kind else { candidate = nil; count = 0; return false }
        count = candidate == kind ? count + 1 : 1; candidate = kind
        // Same object: remind at most every 8 s. A different object: 3 s.
        guard count >= 2, now - lastAlert >= (kind == lastAlertKind ? 8 : 3) else { return false }
        lastAlert = now; lastAlertKind = kind; return true
    }
}

/// A spoken heads-up about something in the walking path, e.g.
/// "Chair ahead, about 4 feet. Watch out." Distances come from LiDAR
/// surfaces; a person seen only by the camera has no distance.
public struct ObstacleNotice: Equatable, Sendable {
    public enum Kind: String, Sendable { case chair, table, person }
    public let kind: Kind
    /// Metres in front of the camera, if measured.
    public let distance: Float?
    /// Metres to the right (+) or left (−) of the camera's centre line.
    public let lateral: Float?
    public init(kind: Kind, distance: Float?, lateral: Float?) {
        self.kind = kind
        self.distance = distance.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.lateral = lateral.flatMap { $0.isFinite ? $0 : nil }
    }
    /// Within about 12° of straight ahead counts as "ahead".
    public var side: String {
        guard let lateral else { return "ahead" }
        let forward = max(distance ?? 1, 0.3)
        if abs(atan2(lateral, forward)) < 0.21 { return "ahead" }
        return lateral > 0 ? "on your right" : "on your left"
    }
    public var noun: String { kind.rawValue.prefix(1).uppercased() + kind.rawValue.dropFirst() }
    public func text(feet: Bool) -> String {
        guard let distance else {
            return side == "ahead" ? "\(noun) in front of you. Watch out." : "\(noun) \(side). Watch out."
        }
        if distance < 1, side == "ahead" { return "\(noun) right in front of you. Stop and go around it." }
        let place = side == "ahead" ? "ahead" : side
        let warning = side == "ahead" ? " Watch out." : ""
        return "\(noun) \(place), about \(LiveGuidance.distance(distance, feet: feet))." + warning
    }
}
