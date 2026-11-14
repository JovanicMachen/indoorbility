import Foundation

public extension SpatialPoint {
    func horizontalDistance(to p: SpatialPoint) -> Float { hypot(x - p.x, z - p.z) }
}

/// Rigid, gravity-aligned transform from a live AR session into a saved scan. Never scales metres.
public struct ScanAlignment: Codable, Equatable {
    public let yaw: Float
    public let translation: SpatialPoint
    public static let identity = ScanAlignment(yaw: 0, translation: SpatialPoint(x: 0, y: 0, z: 0))
    public func apply(_ p: SpatialPoint) -> SpatialPoint {
        SpatialPoint(x: cos(yaw)*p.x - sin(yaw)*p.z + translation.x,
                     y: p.y + translation.y, z: sin(yaw)*p.x + cos(yaw)*p.z + translation.z)
    }
    public func heading(_ angle: Float) -> Float { atan2(sin(angle + yaw), cos(angle + yaw)) }
    public static func fit(liveA: SpatialPoint, liveB: SpatialPoint, savedA: SpatialPoint, savedB: SpatialPoint) throws -> Self {
        guard [liveA, liveB, savedA, savedB].allSatisfy(\.isFinite) else { throw MapError.invalid("Landmark positions must be finite.") }
        let liveDistance = liveA.horizontalDistance(to: liveB), savedDistance = savedA.horizontalDistance(to: savedB)
        guard min(liveDistance, savedDistance) >= 2,
              abs(liveDistance - savedDistance) <= min(0.6, savedDistance * 0.1),
              abs((liveB.y-liveA.y) - (savedB.y-savedA.y)) < 0.5 else {
            throw MapError.invalid("These landmarks do not agree. Use two distinct marks at least two metres apart, at the same phone height.")
        }
        let yaw = atan2(savedB.z-savedA.z, savedB.x-savedA.x) - atan2(liveB.z-liveA.z, liveB.x-liveA.x)
        let rotation = ScanAlignment(yaw: yaw, translation: SpatialPoint(x: 0, y: 0, z: 0))
        let a = rotation.apply(liveA), b = rotation.apply(liveB)
        return ScanAlignment(yaw: yaw, translation: SpatialPoint(x: ((savedA.x-a.x)+(savedB.x-b.x))/2,
            y: ((savedA.y-a.y)+(savedB.y-b.y))/2, z: ((savedA.z-a.z)+(savedB.z-b.z))/2))
    }
}

public struct HallwayRoute: Codable, Identifiable, Equatable {
    public let id: UUID
    public let scanID: UUID
    public let entrance: ScanLandmark
    public let room: ScanLandmark
    public let path: [SpatialPoint]
    public let confirmedAt: Date
    public struct StairFloors: Codable, Equatable {
        public let start: String
        public let end: String
        public init(start: String, end: String) { self.start = start; self.end = end }
    }
    public var stairFloors: StairFloors? = nil
    /// Elevation is measured in the scan frame; it does not identify a signed floor or stairs.
    public var hasLevelChange: Bool {
        stairFloors != nil || path.contains { abs($0.y - entrance.position.y) >= 0.6 }
    }
    public var distance: Float { zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
    public var building: Building {
        Building(schemaVersion: 1, buildingID: "scan-\(id.uuidString)", name: "\(entrance.label) to \(room.label)",
                 description: "Recorded route requiring field review", floors: stairFloors.map { [Floor(id: 0, label: $0.start), Floor(id: 1, label: $0.end)] } ?? (hasLevelChange ? [Floor(id: 0, label: "Start level"), Floor(id: 1, label: "Destination level")] : [Floor(id: 0, label: "Mapped floor")]),
                 nodes: [Checkpoint(id: "entrance", label: entrance.label, floor: 0, kind: "entrance", x: Double(entrance.position.x), y: Double(entrance.position.z)),
                         Checkpoint(id: "room", label: room.label, floor: hasLevelChange ? 1 : 0, kind: "room", x: Double(room.position.x), y: Double(room.position.z))],
                 edges: [Connection(id: "hallway", from: "entrance", to: "room", distance: Double(distance), kind: hasLevelChange ? .stairs : .hallway, verified: true, blocked: false)])
    }
    public func validate(for draft: ScanDraft) throws {
        try draft.validate()
        if let floors = stairFloors {
            guard !floors.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !floors.end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  floors.start != floors.end else { throw MapError.invalid("Confirm both signed floor labels for this stair route.") }
        }
        guard scanID == draft.id, draft.usesLiDAR, draft.hasWorldMap,
              draft.landmarks.contains(entrance), draft.landmarks.contains(room), entrance.id != room.id,
              path.count >= 2, path.allSatisfy(\.isFinite), path.first == entrance.position, path.last == room.position,
              distance >= 2, entrance.position.distance(to: room.position) >= 2,
              zip(path, path.dropFirst()).allSatisfy({ $0.distance(to: $1) > 0.01 && $0.distance(to: $1) <= 2 }) else {
            throw MapError.invalid("The trace needs distinct endpoints and continuous tracking.")
        }
        try building.validate()
    }
    public static func make(draft: ScanDraft, entranceID: UUID, roomID: UUID, reviewed: Bool, id: UUID = UUID(), stairFloors: StairFloors? = nil) throws -> Self {
        guard reviewed, let entrance = draft.landmarks.first(where: { $0.id == entranceID }),
              let room = draft.landmarks.first(where: { $0.id == roomID }), entranceID != roomID else {
            throw MapError.invalid("Select an entrance and room, then confirm you walked and reviewed the entire route, including any stairs.")
        }
        func nearest(_ p: SpatialPoint) -> Int? { draft.samples.indices.min { draft.samples[$0].position.distance(to: p) < draft.samples[$1].position.distance(to: p) } }
        guard let a = nearest(entrance.position), let b = nearest(room.position), a != b,
              draft.samples[a].position.distance(to: entrance.position) < 1,
              draft.samples[b].position.distance(to: room.position) < 1 else { throw MapError.invalid("Mark both endpoints while standing on the recorded path, at least two metres apart.") }
        let samples = Array(draft.samples[min(a,b)...max(a,b)])
        guard Set(samples.map(\.segment)).count == 1 else { throw MapError.invalid("Tracking was lost along this hallway. Rescan it continuously; gaps cannot become routes.") }
        let ordered = a < b ? samples.map(\.position) : samples.reversed().map(\.position)
        var path = [entrance.position]
        for p in ordered.dropFirst().dropLast() where p.distance(to: path.last!) > 0.15 { path.append(p) }
        if path.count > 1 && path.last!.distance(to: room.position) < 0.15 { path.removeLast() }
        path.append(room.position)
        let route = Self(id: id, scanID: draft.id, entrance: entrance, room: room, path: path, confirmedAt: Date(), stairFloors: stairFloors)
        try route.validate(for: draft)
        return route
    }
}

public struct HallwayFollower {
    public enum State: String { case locating, ready, guiding, offRoute, trackingLost, nearRoom, arrived, blocked }
    public private(set) var state: State = .locating
    public private(set) var progress: Float = 0
    public private(set) var remaining: Float
    public private(set) var position: SpatialPoint?
    public private(set) var instruction = "Find the mapped entrance."
    public private(set) var alignment = ScanAlignment.identity
    public private(set) var stable = false
    public let route: HallwayRoute
    public let building: Building
    /// Diagnostic headings in the saved map frame; neither selects a maneuver.
    public private(set) var cameraHeading: Float?
    public private(set) var movementHeading: Float?
    public var selectedSegment: Int { segmentIndex(at: progress) }
    /// GPS mode: the live AR session has relocalized into the saved map, so poses are
    /// already in map coordinates. The follower then places you anywhere on the path,
    /// starts and recovers by itself, and announces arrival — like a normal GPS.
    public private(set) var localized = false
    private var offPathSide: String?
    private var lostSince: TimeInterval?
    private var movementAnchor: SpatialPoint?
    private var retreatSince: TimeInterval?
    private var confirmed = false
    private var stableSince: TimeInterval?
    private var previousTime: TimeInterval?
    private var previousPose: SpatialPoint?
    private var offSince: TimeInterval?
    private var arrivalSince: TimeInterval?
    private var distances: [Float]
    private let totalDistance: Float
    private let includesLevelChange: Bool
    private let turns: [LiveGuidance.MeasuredTurn]
    public var nextMeasuredTurn: LiveGuidance.MeasuredTurn? {
        var low = 0, high = turns.count
        while low < high {
            let mid = (low+high)/2
            if turns[mid].along < progress-0.5 { low = mid+1 } else { high = mid }
        }
        return low < turns.count ? turns[low] : nil
    }
    private func segmentIndex(at along: Float) -> Int {
        var low = 1, high = distances.count-1
        while low < high {
            let mid = (low+high)/2
            if distances[mid] < along { low = mid+1 } else { high = mid }
        }
        return max(0, low-1)
    }
    public init(route: HallwayRoute) {
        self.route = route; building = route.building; totalDistance = route.distance; remaining = route.distance
        includesLevelChange = route.hasLevelChange
        turns = LiveGuidance.measuredTurns(route.path)
        var cumulative: [Float] = [0]
        for (a,b) in zip(route.path, route.path.dropFirst()) { cumulative.append(cumulative.last! + a.distance(to: b)) }
        distances = cumulative
    }
    public mutating func invalidate(_ message: String = "Position uncertain. Point at a known sign and confirm the landmark.") {
        cameraHeading = nil; movementHeading = nil; movementAnchor = nil; retreatSince = nil
        confirmed = false; stable = false; stableSince = nil; previousTime = nil; previousPose = nil
        position = nil; offSince = nil; arrivalSince = nil; state = .trackingLost; instruction = message
    }
    public mutating func confirmEntrance() throws {
        guard stable, let position, position.horizontalDistance(to: route.entrance.position) <= 1.2,
              abs(position.y-route.entrance.position.y) < 0.8 else { throw MapError.invalid("Wait for stable tracking at the marked entrance, or use landmark recovery.") }
        confirmed = true; progress = 0; remaining = totalDistance; state = .guiding; instruction = "Follow the reviewed hallway."
    }
    /// A relocalized world map provides the transform. A user-confirmed nearby
    /// landmark checks it; a room label alone never establishes a transform.
    public mutating func recoverInSavedMap(livePosition: SpatialPoint, landmark: SpatialPoint, relocalized: Bool) throws {
        guard relocalized, livePosition.isFinite, landmark.isFinite,
              livePosition.horizontalDistance(to: landmark) <= 1.2,
              abs(livePosition.y-landmark.y) < 0.8 else {
            throw MapError.invalid("Position does not match this landmark. Try another mark.")
        }
        try recover(using: .identity, livePosition: livePosition)
    }
    public mutating func recover(using alignment: ScanAlignment, livePosition: SpatialPoint) throws {
        guard stable else { throw MapError.invalid("Wait for stable camera tracking before confirming recovery.") }
        let p = alignment.apply(livePosition)
        let projection = project(p, minimum: 0, maximum: totalDistance)
        guard projection.distance < 1.2 else { throw MapError.invalid("The confirmed landmark is not on this hallway.") }
        // A crossing or nearby return corridor can fit the same landmark pose.
        // Reject ambiguous recovery instead of silently choosing the first segment.
        for i in 0..<(route.path.count-1) {
            let a = route.path[i], b = route.path[i+1], length = distances[i+1]-distances[i]
            let t = max(0, min(1, ((p.x-a.x)*(b.x-a.x)+(p.y-a.y)*(b.y-a.y)+(p.z-a.z)*(b.z-a.z))/(length*length)))
            let along = distances[i]+t*length
            let q = SpatialPoint(x: a.x+t*(b.x-a.x), y: a.y+t*(b.y-a.y), z: a.z+t*(b.z-a.z))
            if abs(along-projection.along) > 3 && p.distance(to: q) <= projection.distance+0.25 {
                throw MapError.invalid("This position matches more than one route segment. Confirm a different landmark away from the junction.")
            }
        }
        movementAnchor = nil; movementHeading = nil; cameraHeading = nil; retreatSince = nil
        self.alignment = alignment; position = p; progress = projection.along; remaining = max(0, totalDistance-progress)
        confirmed = true; state = .guiding; previousPose = nil; previousTime = nil; arrivalSince = nil; offSince = nil
    }
    /// Switch to GPS mode once the saved map is matched (alignment becomes identity).
    public mutating func setLocalized() {
        guard !localized else { return }
        localized = true; alignment = .identity; confirmed = false; stableSince = nil; lostSince = nil
        previousTime = nil; previousPose = nil; offSince = nil; retreatSince = nil; arrivalSince = nil
        if state != .arrived { state = .locating; instruction = "Map matched. Finding your place on the path." }
    }
    public mutating func update(position live: SpatialPoint?, heading: Float?, time: TimeInterval, trackingNormal: Bool, routeAvailable: Bool = true) {
        if localized { updateLocalized(position: live, heading: heading, time: time, trackingNormal: trackingNormal, routeAvailable: routeAvailable); return }
        guard routeAvailable else { invalidate("This hallway is reported closed. No alternative has been mapped."); state = .blocked; return }
        guard trackingNormal, let live, live.isFinite, heading.map({ $0.isFinite }) ?? true, time.isFinite else { invalidate(); return }
        if let prior = previousTime, time <= prior || time-prior > 0.8 { invalidate("Tracking was interrupted. Confirm a landmark to continue.") }
        if let prior = previousTime, let pose = previousPose, live.distance(to: pose) > max(0.6, Float(time-prior)*2.5) {
            invalidate("Position jumped. Confirm a landmark to continue."); return
        }
        previousTime = time; previousPose = live
        if stableSince == nil { stableSince = time }
        stable = time - (stableSince ?? time) >= 2
        guard stable else { position = nil; instruction = "Finding your position. Point at a known sign."; return }
        let p = alignment.apply(live); position = p
        cameraHeading = heading.map(alignment.heading)
        if let anchor = movementAnchor, p.horizontalDistance(to: anchor) >= 0.3 {
            movementHeading = atan2(p.z-anchor.z, p.x-anchor.x); movementAnchor = p
        } else if movementAnchor == nil { movementAnchor = p }
        guard confirmed else { if state != .offRoute { state = .ready }; instruction = "Confirm your location to begin."; return }
        if state == .arrived { return }
        let projection = project(p, minimum: max(0, progress-1.5), maximum: min(totalDistance, progress+2.5))
        let off = projection.distance > 1.5
        if off {
            arrivalSince = nil
            if offSince == nil { offSince = time }
            instruction = "You may be outside the mapped hallway. Pause and check your position."
            if time - (offSince ?? time) >= 1.5 { confirmed = false; state = .offRoute; instruction = "Off the mapped route. Return to a known landmark to recover." }
            return
        }
        offSince = nil
        // Sustained measured retreat is not a phone rotation. Require recovery instead
        // of advancing into a nearby return corridor or guessing which way to face.
        if projection.along < progress-0.8 {
            if retreatSince == nil { retreatSince = time }
            instruction = "Moving away from the destination. Pause and check the map."
            if time-(retreatSince ?? time) >= 1 { invalidate(instruction) }
            return
        }
        retreatSince = nil
        progress = max(progress, projection.along); remaining = max(0, totalDistance-progress)
        if remaining < 1 && p.distance(to: route.room.position) <= 0.8 {
            if arrivalSince == nil { arrivalSince = time }
            if time - (arrivalSince ?? time) >= 2 { state = .nearRoom; instruction = "At \(route.room.label). Check the room label to confirm arrival."; return }
        } else { arrivalSince = nil }
        state = .guiding
        let target = point(at: min(totalDistance, progress+3))
        if includesLevelChange && abs(target.y-p.y) > 0.45 {
            guard route.stairFloors != nil else {
                instruction = "Level change ahead. Check for stairs or a ramp."
                return
            }
            instruction = target.y > p.y ? "Stairs up ahead. Use the handrail." : "Stairs down ahead. Use the handrail."
            return
        }
        instruction = "Continue straight."

    }
    private mutating func updateLocalized(position live: SpatialPoint?, heading: Float?, time: TimeInterval, trackingNormal: Bool, routeAvailable: Bool) {
        guard routeAvailable else { invalidate("This hallway is reported closed. No alternative has been mapped."); state = .blocked; return }
        guard trackingNormal, let live, live.isFinite, heading.map({ $0.isFinite }) ?? true, time.isFinite else {
            // Ride through brief camera hiccups silently while guiding.
            if state == .guiding, time.isFinite {
                if lostSince == nil { lostSince = time }
                if time - (lostSince ?? time) < 2 { previousPose = nil; return }
            }
            // Wait for tracking to come back; no manual recovery needed in GPS mode.
            stable = false; stableSince = nil; previousTime = nil; previousPose = nil; position = nil
            offSince = nil; retreatSince = nil; arrivalSince = nil
            if state != .arrived { state = .trackingLost; instruction = "Finding your position. Look around slowly." }
            return
        }
        if let prior = previousTime, time <= prior { return }
        if let prior = previousTime, time-prior > 2 { stableSince = nil }
        lostSince = nil
        // ARKit snaps the pose when it refines the saved-map match. Treat that as a
        // correction: settle briefly and re-place on the path instead of giving up.
        if let prior = previousTime, let pose = previousPose, live.distance(to: pose) > max(0.6, Float(time-prior)*2.5) {
            if state != .guiding { stableSince = nil }
            confirmed = false // re-place on the whole path next
        }
        previousTime = time; previousPose = live
        if stableSince == nil { stableSince = time }
        stable = time - (stableSince ?? time) >= 0.5
        guard stable || state == .guiding else {
            if state != .arrived { instruction = "Finding your position. Look around slowly." }
            return
        }
        let p = alignment.apply(live); position = p
        cameraHeading = heading.map(alignment.heading)
        if let anchor = movementAnchor, p.horizontalDistance(to: anchor) >= 0.3 {
            movementHeading = atan2(p.z-anchor.z, p.x-anchor.x); movementAnchor = p
        } else if movementAnchor == nil { movementAnchor = p }
        if state == .arrived { return }
        // While a pose correction settles, keep following but don't commit to a far jump.
        if !stable { return }
        var projection = confirmed ? project(p, minimum: max(0, progress-4), maximum: min(totalDistance, progress+6))
                                   : project(p, minimum: 0, maximum: totalDistance)
        if confirmed && projection.distance > 1.0 {
            let global = project(p, minimum: 0, maximum: totalDistance)
            if global.distance + 0.5 < projection.distance { projection = global }
        }
        if projection.distance > 2.0 {
            arrivalSince = nil; retreatSince = nil
            if offSince == nil { offSince = time }
            if !confirmed || time - (offSince ?? time) >= 1.0 {
                confirmed = false; state = .offRoute
                let target = point(at: projection.along)
                let side = Self.side(of: target, from: p, heading: cameraHeading, previous: offPathSide)
                offPathSide = side
                instruction = "Off the path. The path is \(side)."
            }
            return
        }
        offSince = nil; offPathSide = nil
        if !confirmed { confirmed = true; retreatSince = nil }
        progress = projection.along; remaining = max(0, totalDistance-progress)
        if remaining < 1.5 && p.horizontalDistance(to: route.room.position) <= 1.5 {
            if arrivalSince == nil { arrivalSince = time }
            if time - (arrivalSince ?? time) >= 1 {
                state = .arrived; progress = totalDistance; remaining = 0
                instruction = "You have arrived at \(route.room.label)."; return
            }
        } else { arrivalSince = nil }
        state = .guiding
        // Facing back along the path for a moment → "Turn around".
        if let facing = cameraHeading, remaining > 1.5 {
            let ahead = point(at: min(totalDistance, progress+1.5))
            let pathHeading = atan2(ahead.z-p.z, ahead.x-p.x)
            let delta = abs(atan2(sin(pathHeading-facing), cos(pathHeading-facing)))
            if p.horizontalDistance(to: ahead) > 0.3, delta > 2.2 {
                if retreatSince == nil { retreatSince = time }
                if time - (retreatSince ?? time) >= 1.5 { instruction = "Turn around."; return }
            } else { retreatSince = nil }
        }
        let target = point(at: min(totalDistance, progress+3))
        if includesLevelChange && abs(target.y-p.y) > 0.45 {
            instruction = target.y > p.y ? "Stairs or ramp up ahead. Use the handrail." : "Stairs or ramp down ahead. Use the handrail."
            return
        }
        instruction = "Continue straight."
    }
    /// Plain-language side of a point relative to where the camera faces (x–z map plane,
    /// positive angle = clockwise from above = to the right).
    static func side(of target: SpatialPoint, from p: SpatialPoint, heading: Float?, previous: String?) -> String {
        guard let heading else { return previous ?? "nearby" }
        let bearing = atan2(target.z-p.z, target.x-p.x)
        let delta = atan2(sin(bearing-heading), cos(bearing-heading)) * 180 / .pi
        if abs(delta) < 35 { return "ahead of you" }
        if abs(delta) > 145 { return "behind you" }
        return delta > 0 ? "to your right" : "to your left"
    }
    public mutating func confirmArrival() throws {
        guard state == .nearRoom, stable, let p = position, p.distance(to: route.room.position) <= 0.8 else {
            throw MapError.invalid("Arrival needs stable tracking near the room and confirmation of its label.")
        }
        state = .arrived; instruction = "Arrival confirmed at \(route.room.label)."; progress = totalDistance; remaining = 0
    }
    private func point(at along: Float) -> SpatialPoint {
        let i = segmentIndex(at: along)
        if i < route.path.count-1 {
            let a = route.path[i], b = route.path[i+1], t = max(0,min(1,(along-distances[i])/(distances[i+1]-distances[i])))
            return SpatialPoint(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t, z: a.z+(b.z-a.z)*t)
        }
        return route.room.position
    }
    private func project(_ p: SpatialPoint, minimum: Float, maximum: Float) -> (along: Float, distance: Float) {
        var best: (Float,Float) = (progress,.infinity)
        for i in segmentIndex(at: minimum)...segmentIndex(at: maximum) {
            let a = route.path[i], b = route.path[i+1], length = distances[i+1]-distances[i]
            guard distances[i+1] >= minimum, distances[i] <= maximum else { continue }
            let raw = ((p.x-a.x)*(b.x-a.x)+(p.y-a.y)*(b.y-a.y)+(p.z-a.z)*(b.z-a.z))/(length*length)
            let t = max(max(0,(minimum-distances[i])/length), min(min(1,(maximum-distances[i])/length),raw))
            let q = SpatialPoint(x: a.x+t*(b.x-a.x), y: a.y+t*(b.y-a.y), z: a.z+t*(b.z-a.z))
            let distance = p.distance(to: q)
            if distance < best.1 { best = (distances[i]+t*length,distance) }
        }
        return best
    }
}

/// Resolves only explicitly requested labels; never supplies missing map geometry.
public enum LiveHallwayCommand {
    public static func destination(in text: String, landmarks: [ScanLandmark]) throws -> ScanLandmark {
        let normalized = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        guard !normalized.contains("don t"), !normalized.contains("do not"), !normalized.contains("cancel") else {
            throw MapError.invalid("Nothing changed.")
        }
        let matches = landmarks.filter { landmark in
            let label = landmark.label.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
            return !label.isEmpty && (" " + normalized + " ").contains(" " + label + " ")
        }
        guard matches.count == 1 else {
            throw MapError.invalid(matches.isEmpty ? "That destination is not known on this mapped hallway. Your route is unchanged." : "More than one landmark matches. Please use a unique room label. Your route is unchanged.")
        }
        return matches[0]
    }
}

public extension HallwayFollower {
    /// The reviewed geometry and coordinate frame stay fixed. Only the destination changes.
    func changingDestination(to target: ScanLandmark, on reviewed: HallwayRoute, draft: ScanDraft) throws -> HallwayFollower {
        guard stable, [.guiding, .nearRoom].contains(state), let position, reviewed.scanID == route.scanID,
              let index = reviewed.path.indices.min(by: { reviewed.path[$0].distance(to: target.position) < reviewed.path[$1].distance(to: target.position) }),
              reviewed.path[index].distance(to: target.position) < 0.25 else {
            throw MapError.invalid("A fresh, confirmed position and a landmark on this reviewed hallway are required.")
        }
        let currentIndex = reviewed.path.indices.min { reviewed.path[$0].distance(to: position) < reviewed.path[$1].distance(to: position) } ?? 0
        let backwards = currentIndex > index
        var path = backwards ? Array(reviewed.path[index...].reversed()) : Array(reviewed.path[...index])
        guard path.count >= 2 else { throw MapError.invalid("This destination needs a longer verified route.") }
        path[path.count-1] = target.position
        let replacement = HallwayRoute(id: reviewed.id, scanID: reviewed.scanID,
            entrance: backwards ? reviewed.room : reviewed.entrance, room: target, path: path, confirmedAt: reviewed.confirmedAt, stairFloors: backwards ? reviewed.stairFloors.map { .init(start: $0.end, end: $0.start) } : reviewed.stairFloors)
        try replacement.validate(for: draft)
        var result = HallwayFollower(route: replacement)
        result.localized = localized
        result.stable = stable; result.stableSince = stableSince
        result.alignment = alignment; result.position = position
        let projection = result.project(position, minimum: 0, maximum: replacement.distance)
        guard projection.distance < 1.2 else { throw MapError.invalid("Your position is outside the verified route. Confirm a landmark first.") }
        result.progress = projection.along; result.remaining = max(0, replacement.distance-projection.along)
        result.confirmed = true; result.state = .guiding
        result.previousTime = previousTime; result.previousPose = previousPose
        result.instruction = "Route changed to \(target.label). Follow the mapped hallway."
        return result
    }
}
