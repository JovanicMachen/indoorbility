import XCTest
@testable import IndoorbilityCore

final class StartHereTests: XCTestCase {
    func testStartingHereFollowsTheRouteFromAnyLiveFrame() throws {
        // L route: 10 m east, then 10 m south (+z), recorded in its own frame.
        let path = (0...10).map { SpatialPoint(x: Float($0), y: 0, z: 0) } + (1...10).map { SpatialPoint(x: 10, y: 0, z: Float($0)) }
        let marks = [ScanLandmark(label: "Lobby", kind: "entrance", position: path[0]), ScanLandmark(label: "Lounge", kind: "room", position: path.last!)]
        let draft = ScanDraft(name: "Synthetic", usesLiDAR: true, hasWorldMap: true, samples: path.map { ScanSample(position: $0, segment: 0) },
                              landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        let route = try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
        // The live AR session has an unrelated origin and orientation.
        let liveStart = SpatialPoint(x: 5, y: -1.2, z: -7), liveHeading: Float = 2.0
        var f = HallwayFollower(route: route), time = 0.0
        for _ in 0...25 { time += 0.1; f.update(position: liveStart, heading: liveHeading, time: time, trackingNormal: true) }
        let alignment = try ScanAlignment.startingHere(livePosition: liveStart, liveHeading: liveHeading, path: route.path)
        try f.recover(using: alignment, livePosition: liveStart)
        XCTAssertEqual(f.state, .guiding)
        XCTAssertEqual(f.progress, 0, accuracy: 0.05)
        // Walk the live equivalent of the route: forward 10 m, then turn right 10 m.
        let fwd = (cos(liveHeading), sin(liveHeading)), right = (-sin(liveHeading), cos(liveHeading))
        func live(_ a: Float, _ b: Float) -> SpatialPoint {
            SpatialPoint(x: liveStart.x + fwd.0*a + right.0*b, y: liveStart.y, z: liveStart.z + fwd.1*a + right.1*b)
        }
        var arrows: [IndoorDirection.Arrow] = []
        for i in 1...100 { time += 0.1; f.update(position: live(Float(i)/10, 0), heading: liveHeading, time: time, trackingNormal: true)
            if let d = IndoorDirection.live(f), arrows.last != d.arrow { arrows.append(d.arrow) } }
        for i in 1...100 { time += 0.1; f.update(position: live(10, Float(i)/10), heading: liveHeading + .pi/2, time: time, trackingNormal: true)
            if let d = IndoorDirection.live(f), arrows.last != d.arrow { arrows.append(d.arrow) } }
        for _ in 0...20 { time += 0.1; f.update(position: live(10, 10), heading: liveHeading + .pi/2, time: time, trackingNormal: true) }
        XCTAssertTrue(arrows.contains(.right), "\(arrows)")
        XCTAssertFalse(arrows.contains(.left))
        XCTAssertEqual(f.state, .nearRoom)
        try f.finishRecordedRoute(positionVerified: true)
        XCTAssertEqual(f.state, .arrived)
    }
    func testStartingHereKeepsGuidingAfterDriftingOffAndBack() throws {
        let path = (0...20).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
        let marks = [ScanLandmark(label: "Lobby", kind: "entrance", position: path[0]), ScanLandmark(label: "Couch", kind: "room", position: path.last!)]
        let draft = ScanDraft(name: "Synthetic", usesLiDAR: true, hasWorldMap: true, samples: path.map { ScanSample(position: $0, segment: 0) },
                              landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        let route = try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
        var f = HallwayFollower(route: route), time = 0.0
        for _ in 0...25 { time += 0.1; f.update(position: path[0], heading: 0, time: time, trackingNormal: true) }
        f.followFromStart(using: try ScanAlignment.startingHere(livePosition: path[0], liveHeading: 0, path: route.path))
        XCTAssertTrue(f.forgiving)
        func walk(_ to: SpatialPoint, from: SpatialPoint) {
            for i in 1...30 { time += 0.1; let t = Float(i)/30
                f.update(position: SpatialPoint(x: from.x+(to.x-from.x)*t, y: 0, z: from.z+(to.z-from.z)*t), heading: 0, time: time, trackingNormal: true) }
        }
        walk(SpatialPoint(x: 8, y: 0, z: 0), from: path[0])
        XCTAssertEqual(f.state, .guiding)
        // Step 3 m to the side, around an obstacle: told where the path is, not stopped.
        walk(SpatialPoint(x: 9, y: 0, z: 3), from: SpatialPoint(x: 8, y: 0, z: 0))
        for _ in 0...15 { time += 0.1; f.update(position: SpatialPoint(x: 9, y: 0, z: 3), heading: 0, time: time, trackingNormal: true) }
        XCTAssertEqual(f.state, .offRoute)
        XCTAssertNotNil(IndoorDirection.live(f))
        // Back on the path further along: guidance resumes on its own.
        walk(SpatialPoint(x: 12, y: 0, z: 0), from: SpatialPoint(x: 9, y: 0, z: 3))
        for _ in 0...10 { time += 0.1; f.update(position: SpatialPoint(x: 12, y: 0, z: 0), heading: 0, time: time, trackingNormal: true) }
        XCTAssertEqual(f.state, .guiding)
        XCTAssertEqual(f.remaining, 8, accuracy: 0.5)
        walk(path.last!, from: SpatialPoint(x: 12, y: 0, z: 0))
        for _ in 0...20 { time += 0.1; f.update(position: path.last!, heading: 0, time: time, trackingNormal: true) }
        XCTAssertEqual(f.state, .arrived)
    }
    func testInvalidStartIsRejected() {
        XCTAssertThrowsError(try ScanAlignment.startingHere(livePosition: SpatialPoint(x: .nan, y: 0, z: 0), liveHeading: 0, path: [SpatialPoint(x: 0, y: 0, z: 0)]))
        XCTAssertThrowsError(try ScanAlignment.startingHere(livePosition: SpatialPoint(x: 0, y: 0, z: 0), liveHeading: 0, path: [SpatialPoint(x: 0, y: 0, z: 0), SpatialPoint(x: 0.2, y: 0, z: 0)]))
    }
}
