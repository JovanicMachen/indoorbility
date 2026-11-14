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
    private var everGuided = false
    private var alongRoute = 0.0
    private let samples: [Point]
    private let sampleAlong: [Double]
    private let sampleLeg: [Int]
    private let totalLength: Double
    private let legEnd: [Double]
    private let turns: [(along: Double, direction: String)]
    public init(legs: [Leg]) {
        let legs = legs.filter { $0.points.count >= 2 }
        self.legs = legs
        var points: [Point] = []
        var along: [Double] = []
        var owner: [Int] = []
        var ends: [Double] = []
        var travelled = 0.0
        for (legIndex, leg) in legs.enumerated() {
            for point in leg.points {
                if let last = points.last {
                    let step = last.distance(point)
                    guard step > 0 else { continue }
                    travelled += step
                }
                points.append(point); along.append(travelled); owner.append(legIndex)
            }
            ends.append(travelled)
        }
        samples = points; sampleAlong = along; sampleLeg = owner; totalLength = travelled; legEnd = ends
        turns = Self.measuredTurns(points: points, along: along)
        remaining = ends.first ?? 0
    }
    public var remainingRouteDistance: Double { max(0, totalLength - alongRoute) }
    public var instruction: String { legs.indices.contains(index) ? legs[index].instruction : "Route unavailable" }
    public var travelInstruction: String {
        // Geometry decides the maneuver. MapKit step text is a label for a real bend,
        // not permission to repeat GPS-snap turns every time the fix jitters.
        guard let turn = nextTurn else { return "Continue straight" }
        let distance = turn.along - alongRoute
        guard distance <= 12 else { return "Continue straight" }
        if turn.direction == "around" { return "Turn around" }
        let labeled = nextLabeledTurn
        let text = labeled?.lowercased() ?? ""
        if turn.direction == "left", text.contains("left") { return labeled! }
        if turn.direction == "right", text.contains("right") { return labeled! }
        return "Turn \(turn.direction)"
    }
    public func upcomingDetail(feet: Bool = false) -> String {
        let remainingToTurn = nextTurn.map { max(0, $0.along - alongRoute) } ?? remainingRouteDistance
        let metres = Float((remainingToTurn / 5).rounded() * 5)
        let distance = LiveGuidance.distance(max(5, metres), feet: feet)
        guard nextTurn != nil else { return "Destination in about " + distance }
        return "Next turn in about " + distance
    }
    public var announcementBand: Int {
        let distance = nextTurn.map { $0.along - alongRoute } ?? remainingRouteDistance
        return distance <= 5 ? 5 : distance <= 10 ? 10 : distance <= 20 ? 20 : 100
    }
    public var nextInstruction: String? { nextLabeledTurn }
    public func shouldReplaceRoute() -> Bool { status == .offRoute }
    public mutating func pause() { headingDecision.reset(); alignedWithPath = false; status = .locating; goodFixes = 0; endFixes = 0; wrongWay = false; retreatFixes = 0; retreatLow = nil; furthestAlong = 0; lastReliable = nil }
    public mutating func update(_ point: Point, accuracy: Double, timestamp: Double, now: Double, course: Double? = nil) {
        guard point.x.isFinite, point.y.isFinite, accuracy.isFinite, accuracy >= 0, accuracy <= 30,
              timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp <= 10,
              samples.count >= 2, totalLength > 0 else {
            // Brief GPS noise (common between buildings) must not reset a stable route or advance a turn.
            if status == .guiding, accuracy.isFinite, accuracy > 30, accuracy <= 60,
               let lastReliable, now.isFinite, now >= lastReliable, now-lastReliable <= 8 { return }
            pause(); return
        }
        let previousTime = lastTimestamp
        guard previousTime.map({ timestamp > $0 }) ?? true else { return }
        lastTimestamp = timestamp
        let wasGuiding = status == .guiding
        // Real GPS wanders 10–30 m near buildings. A tight corridor turned that drift into
        // "off route" → reroute from a bad fix → new turns, which walked people in circles.
        let corridor = wasGuiding ? max(30, accuracy * 2.5) : max(20, accuracy * 2)
        // The walker starts at the route origin; never snap a first fix onto a far part of
        // a route that doubles back near itself.
        let windowMin = wasGuiding ? max(0, alongRoute - 30) : 0
        let windowMax = wasGuiding ? min(totalLength, alongRoute + 45) : everGuided ? totalLength : min(totalLength, 80)
        var along = 0.0, closest = Double.infinity
        var tangent: Point?
        var leg = index
        for i in 1..<samples.count {
            let a = samples[i-1], b = samples[i]
            let length = a.distance(b)
            guard length > 0 else { continue }
            let start = sampleAlong[i-1]
            let end = sampleAlong[i]
            if end < windowMin || start > windowMax { continue }
            let t = max(0, min(1, ((point.x-a.x)*(b.x-a.x)+(point.y-a.y)*(b.y-a.y))/(length*length)))
            let d = point.distance(Point(a.x+t*(b.x-a.x), a.y+t*(b.y-a.y)))
            if d < closest {
                closest = d
                along = start + t * length
                tangent = Point((b.x-a.x)/length, (b.y-a.y)/length)
                leg = sampleLeg[i-1]
            }
        }
        guard closest <= corridor else {
            offRouteFixes += 1
            if status != .guiding || offRouteFixes >= 6 { status = .offRoute; goodFixes = 0; endFixes = 0; wrongWay = false }
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
        if wasGuiding, let previousTime, closest > max(8, accuracy) {
            let cap = max(20, (timestamp - previousTime) * 6 + accuracy)
            if along > alongRoute + cap { along = alongRoute + cap }
        }
        everGuided = true
        if accuracy <= 12 {
            // Wrong-way detection uses the raw projection, not the smoothed progress.
            if furthestAlong-along > max(12, accuracy*2) { retreatFixes += 1 } else { retreatFixes = 0 }
            if retreatFixes >= 3 { wrongWay = true; retreatLow = min(retreatLow ?? along, along) }
            if let low = retreatLow, along-low >= max(6, accuracy) {
                wrongWay = false; retreatFixes = 0; retreatLow = nil; furthestAlong = along
            }
            if retreatFixes == 0 { wrongWay = false; retreatLow = nil }
            furthestAlong = max(furthestAlong, along)
        } else { wrongWay = false; retreatFixes = 0; retreatLow = nil }
        // Progress only moves forward while guiding, so GPS jitter cannot flip the
        // next instruction between "turn right", "straight" and "turn left".
        alongRoute = wasGuiding && !wrongWay ? max(alongRoute, along) : along
        index = min(max(leg, wasGuiding && !wrongWay ? index : 0), max(0, legs.count-1))
        while index+1 < legEnd.count, legEnd[index] < alongRoute - 0.01 { index += 1 }
        let currentEnd = legEnd.indices.contains(index) ? legEnd[index] : totalLength
        let currentStart = index == 0 ? 0 : legEnd[index-1]
        travelledOnLeg = max(0, alongRoute - currentStart)
        remaining = max(0, currentEnd - alongRoute)
        status = .guiding
        if wrongWay { endFixes = 0; return }
        if accuracy <= 12 && remaining <= 8 { endFixes += 1 } else { endFixes = 0 }
        guard endFixes >= 3 else { return }
        if index+1 < legs.count {
            index += 1; headingDecision.reset(); alignedWithPath = false; endFixes = 0; goodFixes = 3
            retreatFixes = 0; wrongWay = false
            let nextEnd = legEnd[index]
            let nextStart = legEnd[index-1]
            // Switch the active step label only; never teleport progress onto the corner,
            // which used to drop the "turn" cue several metres before the actual turn.
            travelledOnLeg = max(0, alongRoute - nextStart)
            remaining = max(0, min(nextEnd - nextStart, nextEnd - alongRoute))
            furthestAlong = max(furthestAlong, alongRoute)
            status = .guiding
        }
        else { status = .nearDestination } // User still confirms arrival and entrance.
    }

    private var nextTurn: (along: Double, direction: String)? {
        turns.first { $0.along > alongRoute + 2 }
    }
    private var nextLabeledTurn: String? {
        guard let turn = nextTurn else { return nil }
        for i in 0..<legs.count {
            let start = i == 0 ? 0.0 : legEnd[i-1]
            if abs(start - turn.along) <= 15, !legs[i].instruction.isEmpty { return legs[i].instruction }
        }
        return nil
    }
    private static func measuredTurns(points: [Point], along: [Double]) -> [(along: Double, direction: String)] {
        guard points.count >= 3 else { return [] }
        var turns: [(along: Double, direction: String, angle: Double)] = []
        var bend: [(along: Double, direction: String, angle: Double)] = []
        func finishBend() {
            guard let peak = bend.map(\.angle).max() else { return }
            let strongest = bend.filter { $0.angle >= peak - 0.001 }
            turns.append(strongest[strongest.count/2])
            bend.removeAll()
        }
        for i in 1..<(points.count - 1) {
            var a = i-1, b = i+1
            while a > 0 && points[a].distance(points[i]) < 8 { a -= 1 }
            while b < points.count-1 && points[b].distance(points[i]) < 8 { b += 1 }
            let incoming = atan2(points[i].x-points[a].x, -(points[i].y-points[a].y))
            let outgoing = atan2(points[b].x-points[i].x, -(points[b].y-points[i].y))
            let delta = atan2(sin(outgoing-incoming), cos(outgoing-incoming))
            guard abs(delta) > .pi/4 else { continue }
            let direction = abs(delta) >= .pi*5/6 ? "around" : delta < 0 ? "left" : "right"
            let sample = (along: along[i], direction: direction, angle: abs(delta))
            if let last = bend.last, sample.direction != last.direction || sample.along-last.along > 12 {
                finishBend()
            }
            bend.append(sample)
        }
        finishBend()
        // The first ~15 m of an Apple walking route is often a GPS-to-road hook, not a real corner.
        return turns.filter { $0.along >= 15 }.map { ($0.along, $0.direction) }
    }
}
