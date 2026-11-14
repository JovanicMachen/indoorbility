import Foundation

/// A visual trend along a loaded route, not an arrival or positioning decision.
public struct ApproachFeedback {
    public enum Trend: String { case steady, closer, farther }
    public private(set) var trend: Trend = .steady
    private var anchor: Double?
    private var anchorAccuracy = 0.0
    private var lastTime: Double?
    private var changedAt = 0.0
    private var candidate: Trend = .steady
    private var evidence = 0
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func update(distance: Double, accuracy: Double, timestamp: Double, now: Double) {
        guard distance.isFinite, distance >= 0, accuracy.isFinite, (0...12).contains(accuracy),
              timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp <= 3 else { reset(); return }
        if let lastTime, timestamp <= lastTime { return }
        if let lastTime, timestamp-lastTime > 5 { reset() }
        lastTime = timestamp
        guard let anchor else { self.anchor = distance; anchorAccuracy = accuracy; return }
        let delta = anchor-distance
        // Require displacement larger than the combined accuracy estimates and two fixes.
        let threshold = max(3, hypot(anchorAccuracy, accuracy))
        let next: Trend = abs(delta) >= threshold ? (delta > 0 ? .closer : .farther) : .steady
        if next == .steady { evidence = 0; candidate = .steady }
        else {
            if next == candidate { evidence += 1 } else { candidate = next; evidence = 1 }
            if evidence >= 2 {
                trend = next; changedAt = timestamp; self.anchor = distance; anchorAccuracy = accuracy
                evidence = 0; candidate = .steady
            }
        }
        if timestamp-changedAt > 5 { trend = .steady }
    }
}
