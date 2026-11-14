import Foundation

/// Session-only GPS breadcrumbs, for visualization rather than routing or obstacle avoidance.
public struct OutdoorTrace {
    public private(set) var segments: [[OutdoorProgress.Point]] = []
    private var previous: OutdoorProgress.Point?
    private var previousTime: Double?
    private var needsBreak = true
    public init() {}
    public mutating func interrupt() { needsBreak = true; previous = nil; previousTime = nil }
    public mutating func update(_ point: OutdoorProgress.Point, accuracy: Double, timestamp: Double, now: Double) {
        guard point.x.isFinite, point.y.isFinite, accuracy.isFinite, (0...20).contains(accuracy),
              timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp <= 10 else { interrupt(); return }
        if let previousTime, timestamp <= previousTime { return }
        if let previous, let previousTime {
            let elapsed = timestamp-previousTime
            if elapsed > 10 || point.distance(previous) > max(15, accuracy) + elapsed*3 { needsBreak = true }
        }
        previous = point; previousTime = timestamp
        if needsBreak || segments.isEmpty { segments.append([point]); needsBreak = false }
        else if let last = segments.last?.last, point.distance(last) >= max(2, accuracy*0.5) {
            segments[segments.count-1].append(point)
        }
        // Bound rendering/storage without joining separate intervals across missing GPS data.
        while segments.count > 24 { segments.removeFirst() }
        while segments.reduce(0, { $0 + $1.count }) > 600 {
            if segments[0].count > 2 { segments[0].removeFirst() } else { segments.removeFirst() }
        }
    }
}
