import XCTest
@testable import IndoorbilityCore

/// Synthetic walks exercise decisions, not physical sensor accuracy.
final class WalkingJourneyTests: XCTestCase {
    private func draft(_ points: [SpatialPoint]) -> ScanDraft {
        ScanDraft(name: "Synthetic walking fixture", usesLiDAR: true, hasWorldMap: true,
            samples: points.map { ScanSample(position: $0, segment: 0) },
            landmarks: [ScanLandmark(label: "Lobby sign", kind: "entrance", position: points.first!),
                        ScanLandmark(label: "Library door", kind: "room", position: points.last!)],
            meshVertexCount: 30, meshTriangleCount: 10)
    }
    func testRoundedCornerIsAnnounced() throws {
        let approach = (0..<20).map { SpatialPoint(x: Float($0)*0.5, y: 0, z: 0) }
        let curve = (0...20).map { i -> SpatialPoint in
            let angle = Float(i)/20 * .pi/2
            return SpatialPoint(x: 10+2*sin(angle), y: 0, z: -2+2*cos(angle))
        }
        let exit = (1...20).map { SpatialPoint(x: 12, y: 0, z: -2-Float($0)*0.5) }
        let turns = LiveGuidance.measuredTurns(approach+curve+exit)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.direction, "left")
        let points = approach+curve+exit
        let d = draft(points)
        var follower = HallwayFollower(route: try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true))
        var time = 0.0
        for _ in 0...25 { time += 0.1; follower.update(position: points[0], heading: 0, time: time, trackingNormal: true) }
        try follower.confirmEntrance()
        var delivery = GuidanceDelivery()
        var turnCount = 0
        for (a, b) in zip(points, points.dropFirst()) {
            time += Double(a.distance(to: b))/1.4
            follower.update(position: b, heading: atan2(b.z-a.z, b.x-a.x), time: time, trackingNormal: true)
            XCTAssertEqual(follower.state, .guiding)
            let cue = LiveGuidance.message(follower)
            if delivery.consume(cue, listening: false, now: time), cue.cue == .turn { turnCount += 1 }
        }
        XCTAssertEqual(turnCount, 1)
    }
    func testNormalWalkingSpeedsForwardAndReverseNeedArrivalConfirmation() throws {
        let points = (0...40).map { SpatialPoint(x: Float($0)*0.5, y: 0, z: 0) }
        let d = draft(points)
        for speed: Float in [0.8, 1.4, 1.8] {
            for reverse in [false, true] {
                let route = try HallwayRoute.make(draft: d, entranceID: d.landmarks[reverse ? 1 : 0].id,
                    roomID: d.landmarks[reverse ? 0 : 1].id, reviewed: true)
                var follower = HallwayFollower(route: route)
                var time = 0.0
                let heading: Float = reverse ? .pi : 0
                for _ in 0...25 { time += 0.1; follower.update(position: route.path.first!, heading: heading, time: time, trackingNormal: true) }
                try follower.confirmEntrance()
                let steps = Int(ceil(20/(speed*0.1)))
                for i in 1...steps {
                    let distance = min(20, Float(i)*speed*0.1)
                    time += 0.1
                    // A natural sideways offset must not force touching each breadcrumb.
                    let point = SpatialPoint(x: reverse ? 20-distance : distance, y: 0, z: 0.3*sin(distance))
                    follower.update(position: point, heading: heading+0.08*sin(distance), time: time, trackingNormal: true)
                    XCTAssertEqual(follower.state, .guiding)
                    XCTAssertEqual(follower.progress, distance, accuracy: 0.03)
                }
                XCTAssertThrowsError(try follower.confirmArrival())
                for _ in 0...25 { time += 0.1; follower.update(position: route.path.last!, heading: heading, time: time, trackingNormal: true) }
                XCTAssertEqual(follower.state, .nearRoom)
                try follower.confirmArrival()
                XCTAssertEqual(follower.state, .arrived)
            }
        }
    }
    func testSmallTraceWobbleDoesNotInventTurns() {
        let points = (0...160).map { SpatialPoint(x: Float($0)*0.25, y: 0, z: 0.08*sin(Float($0)*1.7)) }
        XCTAssertTrue(LiveGuidance.measuredTurns(points).isEmpty)
    }
    func testNearbyReturnCorridorDoesNotSkipToDestination() throws {
        let outward = (0...40).map { SpatialPoint(x: Float($0)*0.5, y: 0, z: 0) }
        let across = [SpatialPoint(x: 20, y: 0, z: 0.5), SpatialPoint(x: 20, y: 0, z: 1)]
        let back = (1...36).map { SpatialPoint(x: 20-Float($0)*0.5, y: 0, z: 1) }
        let d = draft(outward+across+back)
        var f = HallwayFollower(route: try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true))
        for i in 0...25 { f.update(position: outward[0], heading: 0, time: Double(i)/10, trackingNormal: true) }
        try f.confirmEntrance()
        for i in 1...100 {
            f.update(position: .init(x: Float(i)*0.14, y: 0, z: 0.2), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true)
            XCTAssertEqual(f.progress, Float(i)*0.14, accuracy: 0.03)
            XCTAssertEqual(f.state, .guiding)
            XCTAssertThrowsError(try f.confirmArrival())
        }
    }

    func testUnknownFloorChangeWarningIsNotReplacedByStraightInstruction() throws {
        let points = (0...20).map { SpatialPoint(x: Float($0)*0.5, y: Float($0)*0.15, z: 0) }
        let d = draft(points)
        var follower = HallwayFollower(route: try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true))
        for i in 0...25 { follower.update(position: points[0], heading: 0, time: Double(i)/10, trackingNormal: true) }
        try follower.confirmEntrance()
        follower.update(position: points[0], heading: 0, time: 2.6, trackingNormal: true)
        XCTAssertTrue(follower.instruction.hasPrefix("Level change"))
        XCTAssertEqual(LiveGuidance.message(follower).text, follower.instruction)
        XCTAssertEqual(LiveGuidance.message(follower).cue, .attention)
    }
}
