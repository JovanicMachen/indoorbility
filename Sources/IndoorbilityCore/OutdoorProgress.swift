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
    public private(set) var acceptedTimestamp: Double?
    public let legs: [Leg]
    public private(set) var wrongWay = false
    public private(set) var alignedWithPath = false
    private var headingDecision = SteadyHeading()
    private var furthestAlong = 0.0
    private var retreatFixes = 0
    private var retreatLow: Double?
    private var offRouteFixes = 0
    private var goodFixes = 0
    private var endFixes = 0
    private var lastTimestamp: Double?
    private var everGuided = false
    private var alongRoute = 0.0
    private let samples: [Point]
    private let sampleAlong: [Double]
    private let totalLength: Double
    private let legEnd: [Double]
    private let turns: [(along: Double, direction: String, instruction: String)]
    private var turnIndex = 0
    private var turnExitFixes = 0
    private var lastAcceptedPoint: Point?
    private var lastAcceptedAccuracy = 0.0
    private var lastAcceptedTime: Double?
    public init(legs: [Leg]) {
        let legs = legs.filter { $0.points.count >= 2 }
        self.legs = legs
        var points: [Point] = []
        var along: [Double] = []
        var ends: [Double] = []
        var travelled = 0.0
        for leg in legs {
            for point in leg.points {
                if let last = points.last {
                    let step = last.distance(point)
                    guard step > 0 else { continue }
                    travelled += step
                }
                points.append(point); along.append(travelled)
            }
            ends.append(travelled)
        }
        samples = points; sampleAlong = along; totalLength = travelled; legEnd = ends
        turns = legs.enumerated().compactMap { index, leg in
            let text = leg.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = text.lowercased()
            // Arrival-side labels describe the destination, not a junction.
            guard !value.contains("destination"), !value.contains("arriv"),
                  !value.contains("will be on") else { return nil }
            let direction: String
            if value.contains("u-turn") || value.contains("turn around") { direction = "around" }
            else if value.contains("left") { direction = "left" }
            else if value.contains("right") { direction = "right" }
            else { return nil }
            return (index == 0 ? 0 : ends[index - 1], direction, text)
        }
        remaining = ends.first ?? 0
    }
    public var remainingRouteDistance: Double { max(0, totalLength - alongRoute) }
    public var instruction: String { legs.indices.contains(index) ? legs[index].instruction : "Route unavailable" }
    public var travelInstruction: String {
        guard let turn = nextTurn else { return "Continue straight" }
        guard turn.along - alongRoute <= 12 else { return "Continue straight" }
        return turn.instruction
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
    public var nextInstruction: String? {
        guard let current = nextTurn else { return nil }
        if current.along - alongRoute > 12 { return current.instruction }
        guard turnIndex + 1 < turns.count else { return nil }
        return turns[turnIndex + 1].instruction
    }
    public func shouldReplaceRoute() -> Bool { status == .offRoute }
    public mutating func pause() { headingDecision.reset(); alignedWithPath = false; status = .locating; goodFixes = 0; endFixes = 0; wrongWay = false; retreatFixes = 0; retreatLow = nil; furthestAlong = 0 }
    public mutating func update(_ point: Point, accuracy: Double, timestamp: Double, now: Double, course: Double? = nil) {
        guard point.x.isFinite, point.y.isFinite, accuracy.isFinite, accuracy >= 0, accuracy <= 30,
              timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp <= 10,
              samples.count >= 2, totalLength > 0 else {
            pause(); return
        }
        // Broad GPS uncertainty cannot safely distinguish nearby paths or turns.
        guard accuracy <= 15 else { pause(); return }
        let previousTime = lastTimestamp
        guard previousTime.map({ timestamp > $0 }) ?? true else { return }
        lastTimestamp = timestamp
        let wasGuiding = status == .guiding
        // Real GPS wanders 10–30 m near buildings. A tight corridor turned that drift into
        // "off route" → reroute from a bad fix → new turns, which walked people in circles.
        let corridor = max(12, min(25, accuracy * 1.5))
        // The walker starts at the route origin; never snap a first fix onto a far part of
        // a route that doubles back near itself.
        let elapsed = lastAcceptedTime.map { min(5, max(0, timestamp - $0)) } ?? 0
        let windowMin = everGuided ? max(0, alongRoute - max(12, accuracy * 2)) : 0
        let windowMax = everGuided ? min(totalLength, alongRoute + max(15, elapsed * 2.5 + accuracy * 2)) : min(totalLength, 80)
        var along = 0.0, closest = Double.infinity
        var tangent: Point?
        var candidates: [(distance: Double, along: Double, bearing: Double)] = []
        for i in 1..<samples.count {
            let a = samples[i-1], b = samples[i]
            let length = a.distance(b)
            guard length > 0 else { continue }
            let start = sampleAlong[i-1]
            let end = sampleAlong[i]
            let rawT = max(0, min(1, ((point.x-a.x)*(b.x-a.x)+(point.y-a.y)*(b.y-a.y))/(length*length)))
            let rawDistance = point.distance(Point(a.x+rawT*(b.x-a.x), a.y+rawT*(b.y-a.y)))
            candidates.append((rawDistance, start + rawT * length, atan2(b.x-a.x, -(b.y-a.y))))
            if end < windowMin || start > windowMax { continue }
            let lower = max(0, (windowMin - start) / length)
            let upper = min(1, (windowMax - start) / length)
            guard lower <= upper else { continue }
            let t = max(lower, min(upper, ((point.x-a.x)*(b.x-a.x)+(point.y-a.y)*(b.y-a.y))/(length*length)))
            let d = point.distance(Point(a.x+t*(b.x-a.x), a.y+t*(b.y-a.y)))
            if d < closest {
                closest = d
                along = start + t * length
                tangent = Point((b.x-a.x)/length, (b.y-a.y)/length)
            }
        }
        guard closest <= corridor else {
            offRouteFixes += 1
            if status != .guiding || offRouteFixes >= 6 { status = .offRoute; goodFixes = 0; endFixes = 0; wrongWay = false }
            return
        }
        // If two separated parts of the route fit within GPS uncertainty,
        // the phone cannot tell which path the user is on.
        let reliableCourse = course.flatMap { $0.isFinite && (0..<360).contains($0) && accuracy <= 12 ? $0 * .pi / 180 : nil }
        func courseCompatible(_ bearing: Double) -> Bool {
            guard let reliableCourse else { return true }
            return abs(atan2(sin(bearing - reliableCourse), cos(bearing - reliableCourse))) < .pi / 3
        }
        let bestBearing = tangent.map { atan2($0.x, -$0.y) }
        if candidates.contains(where: { candidate in
            abs(candidate.along - along) > max(10, accuracy * 2) && candidate.distance <= closest + max(3, accuracy)
                && !(bestBearing.map(courseCompatible) == true && !courseCompatible(candidate.bearing))
        }) {
            status = .locating; goodFixes = 0; alignedWithPath = false; return
        }
        if let previous = lastAcceptedPoint, let previousTime = lastAcceptedTime {
            let maxMovement = max(12, (timestamp - previousTime) * 3 + accuracy + lastAcceptedAccuracy)
            if point.distance(previous) > maxMovement {
                status = .locating; goodFixes = 0; alignedWithPath = false; return
            }
        }
        lastAcceptedPoint = point; lastAcceptedTime = timestamp; lastAcceptedAccuracy = accuracy
        alignedWithPath = false
        if let course, course.isFinite, (0..<360).contains(course), let tangent, accuracy <= 12 {
            let radians = course * .pi / 180
            let routeBearing = atan2(tangent.x, -tangent.y)
            alignedWithPath = headingDecision.update(radians: routeBearing-radians, time: timestamp) == .straight
        } else { headingDecision.reset() }
        offRouteFixes = 0
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
        // Use the back edge of the uncertainty interval so sideways GPS
        // drift cannot claim that the walker has crossed a junction.
        let supportedAlong = max(0, along - accuracy)
        alongRoute = everGuided && !wrongWay ? max(alongRoute, supportedAlong) : supportedAlong
        while index+1 < legEnd.count, legEnd[index] + max(3, accuracy) < alongRoute { index += 1 }
        if let turn = nextTurn, along - turn.along > max(4, accuracy), accuracy <= 12 {
            turnExitFixes += 1
            if turnExitFixes >= 2 || (!wasGuiding && goodFixes >= 3) { turnIndex += 1; turnExitFixes = 0 }
        } else { turnExitFixes = 0 }
        let currentEnd = legEnd.indices.contains(index) ? legEnd[index] : totalLength
        let currentStart = index == 0 ? 0 : legEnd[index-1]
        travelledOnLeg = max(0, alongRoute - currentStart)
        remaining = max(0, currentEnd - alongRoute)
        status = .guiding
        acceptedTimestamp = timestamp
        if wrongWay { endFixes = 0; return }
        if accuracy <= 12 && remainingRouteDistance <= 8 { endFixes += 1 } else { endFixes = 0 }
        if endFixes >= 3 { status = .nearDestination }
    }

    private var nextTurn: (along: Double, direction: String, instruction: String)? {
        turns.indices.contains(turnIndex) ? turns[turnIndex] : nil
    }
}
