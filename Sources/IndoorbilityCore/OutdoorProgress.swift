import Foundation

/// Tracks supplied walking-route geometry; it does not align GPS to an AR camera.
public struct OutdoorProgress {
    public struct Point: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        func distance(_ p: Self) -> Double { hypot(x-p.x, y-p.y) }
    }
    public struct Leg {
        public let instruction: String
        public let points: [Point]
        public init(instruction: String, points: [Point]) { self.instruction = instruction; self.points = points }
    }
    public enum Status { case locating, guiding, offRoute, nearDestination }
    public private(set) var index = 0
    public private(set) var remaining = 0.0
    public private(set) var travelledOnLeg = 0.0
    public private(set) var status: Status = .locating
    public let legs: [Leg]
    public private(set) var wrongWay = false
    public private(set) var alignedWithPath = false
    private var headingDecision = SteadyHeading()
    private var furthestAlong = 0.0
    private var retreatFixes = 0
    private var retreatLow: Double?
    private var lastReliable: Double?
    private var offRouteFixes = 0
    private var goodFixes = 0
    private var endFixes = 0
    private var lastTimestamp: Double?
    public init(legs: [Leg]) { self.legs = legs.filter { $0.points.count >= 2 } }
    public var instruction: String { legs.indices.contains(index) ? legs[index].instruction : "Route unavailable" }
    public var travelInstruction: String {
        if !alignedWithPath && travelledOnLeg < 12 { return instruction }
        return alignedWithPath ? "Continue straight" : "Continue along this path"
    }
    public func upcomingDetail(feet: Bool = false) -> String {
        let metres = Float((remaining / 5).rounded() * 5)
        let distance = LiveGuidance.distance(max(5, metres), feet: feet)
        guard let next = nextInstruction else { return "Destination in about " + distance }
        let lower = next.lowercased()
        if lower.contains("left") || lower.contains("right") || lower.contains("turn") {
            return "Next turn in about " + distance
        }
        return "Next checkpoint in about " + distance
    }
    public var announcementBand: Int {
        remaining <= 5 ? 5 : remaining <= 10 ? 10 : remaining <= 20 ? 20 : 100
    }
    public var nextInstruction: String? { legs.indices.contains(index+1) ? legs[index+1].instruction : nil }
    public mutating func pause() { headingDecision.reset(); alignedWithPath = false; status = .locating; goodFixes = 0; endFixes = 0; wrongWay = false; retreatFixes = 0; retreatLow = nil; furthestAlong = 0; lastReliable = nil }
    public mutating func update(_ point: Point, accuracy: Double, timestamp: Double, now: Double, course: Double? = nil) {
        guard point.x.isFinite, point.y.isFinite, accuracy.isFinite, accuracy >= 0, accuracy <= 20,
              timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp <= 10,
              legs.indices.contains(index) else {
            // Brief GPS noise must not reset a stable route or advance a turn.
            if status == .guiding, accuracy.isFinite, accuracy > 20, accuracy <= 40,
               let lastReliable, now.isFinite, now >= lastReliable, now-lastReliable <= 3 { return }
            pause(); return
        }
        guard lastTimestamp.map({ timestamp > $0 }) ?? true else { return }
        lastTimestamp = timestamp
        let points = legs[index].points
        var total = 0.0, along = 0.0, closest = Double.infinity
        var tangent: Point?
        for i in 1..<points.count {
            let a = points[i-1], b = points[i]
            let length = a.distance(b)
            guard length > 0 else { continue }
            let t = max(0, min(1, ((point.x-a.x)*(b.x-a.x)+(point.y-a.y)*(b.y-a.y))/(length*length)))
            let d = point.distance(Point(a.x+t*(b.x-a.x), a.y+t*(b.y-a.y)))
            if d < closest { closest = d; along = total+t*length; tangent = Point((b.x-a.x)/length, (b.y-a.y)/length) }
            total += length
        }
        guard total > 0, closest <= max(15, accuracy*1.5) else {
            offRouteFixes += 1
            if status != .guiding || offRouteFixes >= 3 { status = .offRoute; goodFixes = 0; endFixes = 0; wrongWay = false }
            return
        }
        alignedWithPath = false
        if let course, course.isFinite, (0..<360).contains(course), let tangent, accuracy <= 12 {
            let radians = course * .pi / 180
            let routeBearing = atan2(tangent.x, -tangent.y)
            alignedWithPath = headingDecision.update(radians: routeBearing-radians, time: timestamp) == .straight
        } else { headingDecision.reset() }
        offRouteFixes = 0; lastReliable = timestamp
        goodFixes += 1
        guard goodFixes >= 3 else { status = .locating; return }
        travelledOnLeg = along; remaining = max(0, total-along); status = .guiding
        if accuracy <= 12 {
            if furthestAlong-along > max(12, accuracy*2) { retreatFixes += 1 } else { retreatFixes = 0 }
            if retreatFixes >= 3 { wrongWay = true; retreatLow = min(retreatLow ?? along, along) }
            if let low = retreatLow, along-low >= max(6, accuracy) {
                wrongWay = false; retreatFixes = 0; retreatLow = nil; furthestAlong = along
            }
            if retreatFixes == 0 { wrongWay = false; retreatLow = nil }
            furthestAlong = max(furthestAlong, along)
        } else { wrongWay = false; retreatFixes = 0; retreatLow = nil }
        if wrongWay { endFixes = 0; return }
        if accuracy <= 12 && remaining <= 8 && point.distance(points.last!) <= 8 { endFixes += 1 } else { endFixes = 0 }
        guard endFixes >= 3 else { return }
        if index+1 < legs.count { index += 1; headingDecision.reset(); alignedWithPath = false; travelledOnLeg = 0; endFixes = 0; goodFixes = 3; furthestAlong = 0; retreatFixes = 0; wrongWay = false; remaining = zip(legs[index].points, legs[index].points.dropFirst()).reduce(0) { $0 + $1.0.distance($1.1) }; status = .guiding }
        else { status = .nearDestination } // User still confirms arrival and entrance.
    }
}
