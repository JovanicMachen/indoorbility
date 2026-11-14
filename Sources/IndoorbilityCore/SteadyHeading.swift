import Foundation

/// A sustained heading decision, independent of camera/GPS update frequency.
public struct SteadyHeading {
    public enum Cue: String { case straight, left, right, reverse }
    public private(set) var cue: Cue?
    private var candidate: Cue?
    private var since: Double?
    private var lastTime: Double?
    private var observations = 0
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func update(radians: Double, time: Double) -> Cue? {
        guard radians.isFinite, time.isFinite else { reset(); return nil }
        if let lastTime, time <= lastTime { return cue }
        if let lastTime, time-lastTime > 3 { reset() }
        lastTime = time
        let angle = atan2(sin(radians), cos(radians))
        let threshold = cue == .left || cue == .right ? 22.0 : 45.0
        let degrees = abs(angle) * 180 / .pi
        let desired: Cue = degrees >= 150 ? .reverse : degrees < threshold ? .straight : angle > 0 ? .right : .left
        if desired == cue { candidate = nil; since = nil; observations = 0; return cue }
        if candidate != desired { candidate = desired; since = time; observations = 1 }
        else { observations += 1 }
        if observations >= 3, time-(since ?? time) >= 0.35 {
            cue = desired; candidate = nil; since = nil; observations = 0
        }
        return cue
    }
}
