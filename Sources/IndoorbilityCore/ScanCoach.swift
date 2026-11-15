import Foundation

/// Live feedback for the person recording a LiDAR route. It watches only the
/// measured walk (positions over time) and whether captured surfaces grow,
/// then suggests how to capture corners, open areas and the end stop well.
/// Tips are advice for a smoother map; they never alter what is saved.
public struct ScanCoach {
    public enum Kind: String, Equatable, Sendable {
        case corner, cornerDone, slowDown, surfaces, steady, endStop
    }
    public struct Tip: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public var symbol: String {
            switch kind {
            case .corner: return "arrow.turn.up.right"
            case .cornerDone: return "checkmark.circle.fill"
            case .slowDown: return "tortoise.fill"
            case .surfaces: return "camera.viewfinder"
            case .steady: return "hand.thumbsup.fill"
            case .endStop: return "mappin.and.ellipse"
            }
        }
        /// Whether to announce it aloud (corners, pace and coverage problems).
        public var speak: Bool { kind != .steady }
    }
    private struct Point { let x: Float; let z: Float; let time: Double }
    private var trail: [Point] = []
    private var walked: Float = 0
    private var lastTipTime = -Double.infinity
    private var lastKind: Kind?
    private var inCorner = false
    private var cornerEndedAt: Float = 0
    private var meshCount = 0
    private var meshChangedAt: Double?
    private var meshChangedWalked: Float = 0
    private var straightSince: Float = 0
    private var stillSince: Double?
    public private(set) var current: Tip?
    public private(set) var corners = 0

    /// Minimum seconds between tips so the recorder is not flooded.
    public static let cooldown: Double = 4
    public static let fastSpeed: Float = 1.4

    public init() {}

    /// Feed every pose while recording. Returns a tip when a new one should be shown.
    public mutating func update(x: Float, z: Float, time: Double, meshCount mesh: Int) -> Tip? {
        guard x.isFinite, z.isFinite, time.isFinite else { return nil }
        if meshChangedAt == nil || mesh != meshCount { meshCount = mesh; meshChangedAt = time; meshChangedWalked = walked }
        if let last = trail.last {
            let step = hypot(x-last.x, z-last.z)
            guard step >= 0.15 else {
                if stillSince == nil { stillSince = time }
                if let since = stillSince, time-since >= 6, walked >= 3 {
                    return emit(.endStop, "At your destination? Look slowly around the spot, then tap Stop here.", time)
                }
                return nil
            }
            stillSince = nil
            walked += step
        }
        trail.append(Point(x: x, z: z, time: time))
        trail.removeAll { time - $0.time > 6 }

        // Pace over the last ~2 seconds.
        if let first = trail.first(where: { time - $0.time <= 2 }), time - first.time >= 1 {
            var d: Float = 0
            let window = trail.filter { $0.time >= first.time }
            for (a, b) in zip(window, window.dropFirst()) { d += hypot(b.x-a.x, b.z-a.z) }
            if d / Float(time - first.time) > Self.fastSpeed {
                return emit(.slowDown, "Slow down a little so the map stays smooth.", time)
            }
        }

        // Turning: compare headings of the last 1.5 m and the 1.5 m before it.
        if let turn = recentTurn() {
            if abs(turn) > .pi/4 && !inCorner {
                inCorner = true; straightSince = walked
                let side = turn > 0 ? "right" : "left"
                return emit(.corner, "Corner to the \(side). Slow down and sweep the phone across both walls of the corner.", time, force: true)
            }
            if abs(turn) < .pi/9 && inCorner {
                inCorner = false; corners += 1; cornerEndedAt = walked; straightSince = walked
                return emit(.cornerDone, "Corner captured. Nice.", time, force: true)
            }
        }

        // Moving but no new surfaces: the camera is likely pointed at the floor or ceiling.
        if let changed = meshChangedAt, time - changed >= 5, walked - meshChangedWalked >= 3 {
            if let tip = emit(.surfaces, "Point the camera at the walls ahead so the area is captured.", time) {
                meshChangedAt = time; meshChangedWalked = walked
                return tip
            }
        }

        if !inCorner && walked - straightSince >= 10,
           let tip = emit(.steady, "Looking good. Keep the phone at chest height, camera ahead.", time) {
            straightSince = walked
            return tip
        }
        return nil
    }

    private func recentTurn() -> Float? {
        guard trail.count >= 3, let end = trail.last else { return nil }
        var i = trail.count - 1, d: Float = 0
        while i > 0 && d < 1.5 { d += hypot(trail[i].x-trail[i-1].x, trail[i].z-trail[i-1].z); i -= 1 }
        guard d >= 1.2 else { return nil }
        let mid = trail[i]
        var j = i, e: Float = 0
        while j > 0 && e < 1.5 { e += hypot(trail[j].x-trail[j-1].x, trail[j].z-trail[j-1].z); j -= 1 }
        guard e >= 1.2 else { return nil }
        let start = trail[j]
        let a = atan2(mid.z-start.z, mid.x-start.x), b = atan2(end.z-mid.z, end.x-mid.x)
        return atan2(sin(b-a), cos(b-a))
    }

    private mutating func emit(_ kind: Kind, _ text: String, _ time: Double, force: Bool = false) -> Tip? {
        guard force || (time - lastTipTime >= Self.cooldown && lastKind != kind) || time - lastTipTime >= Self.cooldown * 3 else { return nil }
        lastTipTime = time; lastKind = kind
        let tip = Tip(kind: kind, text: text)
        current = tip
        return tip
    }
}
