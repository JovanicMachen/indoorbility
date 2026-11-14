import XCTest
@testable import IndoorbilityCore

final class HallwayNavigationTests: XCTestCase {
    func p(_ x: Float, _ z: Float = 0) -> SpatialPoint { SpatialPoint(x: x, y: 0, z: z) }
    func draft(gap: Bool = false) -> ScanDraft {
        ScanDraft(name: "Hallway", usesLiDAR: true, hasWorldMap: true,
                  samples: (0...20).map { ScanSample(position: p(Float($0)/2), segment: gap && $0 > 10 ? 1 : 0) },
                  landmarks: [ScanLandmark(label: "Entrance", kind: "entrance", position: p(0)), ScanLandmark(label: "Room 12", kind: "room", position: p(10))],
                  meshVertexCount: 30, meshTriangleCount: 10)
    }
    func route() throws -> HallwayRoute {
        let d = draft()
        return try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true)
    }
    func ready() throws -> HallwayFollower {
        var f = HallwayFollower(route: try route())
        for i in 0...25 { f.update(position: p(0), heading: 0, time: Double(i)/10, trackingNormal: true) }
        try f.confirmEntrance()
        return f
    }
    func testLiveDestinationChangeRetainsMeasuredPositionAndAlignment() throws {
        let original = draft()
        let middle = ScanLandmark(label: "Room 105", kind: "room", position: p(6))
        let d = ScanDraft(name: original.name, usesLiDAR: true, hasWorldMap: true,
            samples: original.samples, landmarks: original.landmarks + [middle], meshVertexCount: 30, meshTriangleCount: 10)
        let route = try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true)
        var f = HallwayFollower(route: route)
        for i in 0...25 { f.update(position: p(0), heading: 0, time: Double(i)/10, trackingNormal: true) }
        try f.confirmEntrance()
        for i in 26...65 { f.update(position: p(Float(i-25)/10), heading: 0, time: Double(i)/10, trackingNormal: true) }
        let changed = try f.changingDestination(to: middle, on: route, draft: d)
        XCTAssertEqual(changed.position, f.position)
        XCTAssertEqual(changed.alignment, f.alignment)
        XCTAssertEqual(changed.remaining, 2, accuracy: 0.01)
        XCTAssertEqual(changed.state, .guiding)
        for i in 66...105 { f.update(position: p(Float(i-25)/10), heading: 0, time: Double(i)/10, trackingNormal: true) }
        let reverse = try f.changingDestination(to: middle, on: route, draft: d)
        XCTAssertEqual(reverse.remaining, 2, accuracy: 0.01)
        XCTAssertEqual(reverse.route.path.first, route.room.position)
        XCTAssertEqual(reverse.position, f.position)
        let unmapped = ScanLandmark(label: "Room 999", kind: "room", position: p(6, 3))
        XCTAssertThrowsError(try f.changingDestination(to: unmapped, on: route, draft: d))

        XCTAssertThrowsError(try { var lost = f; lost.invalidate(); return try lost.changingDestination(to: middle, on: route, draft: d) }())
        XCTAssertThrowsError(try { var arrived = changed; try arrived.confirmArrival() }())
    }
    func testLiveDestinationResolutionRejectsUnknownAmbiguousAndPartialLabels() throws {
        let room = ScanLandmark(label: "Room 105", kind: "room", position: p(6))
        XCTAssertEqual(try LiveHallwayCommand.destination(in: "Actually take me to Room 105 instead", landmarks: [room]).id, room.id)
        XCTAssertThrowsError(try LiveHallwayCommand.destination(in: "Room 1050", landmarks: [room]))
        XCTAssertThrowsError(try LiveHallwayCommand.destination(in: "Room 999", landmarks: [room]))
        XCTAssertThrowsError(try LiveHallwayCommand.destination(in: "Room 105", landmarks: [room, room]))
    }
    func testMeasuredGraphAndClosure() throws {
        let r = try route()
        XCTAssertEqual(r.distance, 10, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(Router.plan(in: r.building, from: "entrance", to: "room")).cost, 10, accuracy: 0.001)
        XCTAssertNil(try Router.plan(in: r.building, from: "entrance", to: "room", excluding: ["hallway"]))
        let d = draft()
        let reverse = try HallwayRoute.make(draft: d, entranceID: d.landmarks[1].id, roomID: d.landmarks[0].id, reviewed: true)
        XCTAssertEqual(reverse.path.first, p(10)); XCTAssertEqual(reverse.path.last, p(0))
    }
    func testUnreviewedAndInterruptedTraceRejected() throws {
        for gap in [false, true] {
            let d = draft(gap: gap)
            XCTAssertThrowsError(try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: gap))
        }
    }
    func testSparsePathsRejectedAndElevationUncertaintyPreserved() throws {
        let d = draft()
        let sparse = ScanDraft(name: "Sparse", usesLiDAR: true, hasWorldMap: true,
            samples: [ScanSample(position: p(0), segment: 0), ScanSample(position: p(10), segment: 0)],
            landmarks: d.landmarks, meshVertexCount: 3, meshTriangleCount: 1)
        XCTAssertThrowsError(try HallwayRoute.make(draft: sparse, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true))
        let elevated = ScanDraft(name: "Elevation uncertainty", usesLiDAR: true, hasWorldMap: true,
            samples: (0...20).map { ScanSample(position: SpatialPoint(x: Float($0)/2, y: $0 == 10 ? 1 : 0, z: 0), segment: 0) },
            landmarks: d.landmarks, meshVertexCount: 3, meshTriangleCount: 1)
        let saved = try HallwayRoute.make(draft: elevated, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true)
        XCTAssertTrue(saved.hasLevelChange)
        XCTAssertNil(saved.stairFloors) // A height excursion cannot identify stairs or floor numbers.
        XCTAssertNil(try Router.plan(in: saved.building, from: "entrance", to: "room", avoidStairs: true))
    }
    func testReviewedReplacementKeepsReportIdentity() throws {
        let d = draft(), id = UUID()
        let r = try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true, id: id)
        XCTAssertEqual(r.id, id)
        var session = try NavigationSession(building: r.building)
        try session.confirmReport(BarrierReport(targetEdgeID: "hallway"))
        let replacement = try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true, id: id)
        let restored = try NavigationSession(building: replacement.building, saved: session.saved)
        XCTAssertTrue(restored.saved.blockedEdges.contains("hallway"))
    }

    func testRigidAlignmentAndHeading() throws {
        let a = try ScanAlignment.fit(liveA: p(0), liveB: p(4), savedA: p(3, 2), savedB: p(3, 6))
        XCTAssertEqual(a.apply(p(2)).x, 3, accuracy: 0.001)
        XCTAssertEqual(a.apply(p(2)).z, 4, accuracy: 0.001)
        XCTAssertEqual(a.heading(0), .pi/2, accuracy: 0.001)
        XCTAssertEqual(a.apply(p(1)).distance(to: a.apply(p(4))), 3, accuracy: 0.001)
    }
    func testAlignmentRejectsScaleAndShortBaseline() {
        XCTAssertThrowsError(try ScanAlignment.fit(liveA: p(0), liveB: p(1), savedA: p(0), savedB: p(1)))
        XCTAssertThrowsError(try ScanAlignment.fit(liveA: p(0), liveB: p(4), savedA: p(0), savedB: p(6)))
    }
    func testProgressAutomaticallyAdvancesButArrivalNeedsDwellAndConfirmation() throws {
        var f = try ready()
        for i in 1...100 { f.update(position: p(Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.progress, 10, accuracy: 0.01)
        XCTAssertNotEqual(f.state, .arrived)
        XCTAssertThrowsError(try f.confirmArrival())
        for i in 1...25 { f.update(position: p(10), heading: 0, time: 12.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .nearRoom)
        try f.confirmArrival(); XCTAssertEqual(f.state, .arrived)
    }
    func testLossFreezesProgressAndReacquiringDoesNotResume() throws {
        var f = try ready()
        for i in 1...30 { f.update(position: p(Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        let progress = f.progress
        f.update(position: nil, heading: nil, time: 5.6, trackingNormal: false)
        XCTAssertEqual(f.state, .trackingLost); XCTAssertFalse(f.stable)
        for i in 0...25 { f.update(position: p(4), heading: 0, time: 5.7+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .ready); XCTAssertEqual(f.progress, progress)
        XCTAssertThrowsError(try f.confirmEntrance()); XCTAssertThrowsError(try f.confirmArrival())
        try f.recover(using: .identity, livePosition: p(4))
        XCTAssertEqual(f.state, .guiding); XCTAssertEqual(f.progress, 4, accuracy: 0.001)
    }
    func testOffRouteRequiresRecovery() throws {
        var f = try ready()
        for i in 1...30 { f.update(position: p(0, Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        for i in 1...20 { f.update(position: p(0, 3), heading: 0, time: 5.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .offRoute); XCTAssertEqual(f.progress, 0)
        XCTAssertThrowsError(try f.recover(using: .identity, livePosition: p(0, 3)))
    }
    func testPoseJumpAndMissingFramesInvalidate() throws {
        var f = try ready()
        f.update(position: p(8), heading: 0, time: 2.6, trackingNormal: true)
        XCTAssertEqual(f.state, .trackingLost); XCTAssertEqual(f.progress, 0)
        f = try ready()
        f.update(position: p(0), heading: 0, time: 4, trackingNormal: true)
        XCTAssertFalse(f.stable); XCTAssertThrowsError(try f.confirmEntrance())
    }
    func testHeadingChangesInstructionWithoutSkippingProgress() throws {
        var f = try ready()
        for i in 26...30 { f.update(position: p(0), heading: .pi, time: Double(i)/10, trackingNormal: true) }
        XCTAssertTrue(f.instruction.hasPrefix("Turn around"))
        XCTAssertEqual(f.progress, 0)
        for i in 31...35 { f.update(position: p(0), heading: 0, time: Double(i)/10, trackingNormal: true) }
        XCTAssertTrue(f.instruction.hasPrefix("Continue straight"))
    }
    func testRecoveryTransformsLiveSessionIntoSavedRoute() throws {
        var f = try ready()
        // Live +Z becomes saved +X, with a 2 m saved-space offset.
        let transform = try ScanAlignment.fit(liveA: p(0), liveB: p(0, 4), savedA: p(2), savedB: p(6))
        try f.recover(using: transform, livePosition: p(0, 4))
        XCTAssertEqual(f.progress, 6, accuracy: 0.001)
        for i in 26...30 { f.update(position: p(0, 4.1), heading: .pi/2, time: Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.progress, 6.1, accuracy: 0.001)
        XCTAssertTrue(f.instruction.hasPrefix("Continue straight"))
    }

    func testClosureImmediatelyStopsGuidance() throws {
        var f = try ready()
        f.update(position: p(0), heading: 0, time: 2.6, trackingNormal: true, routeAvailable: false)
        XCTAssertEqual(f.state, .blocked); XCTAssertFalse(f.stable)
        XCTAssertThrowsError(try f.confirmArrival())
    }
    func testLossAtRoomRevokesArrivalConfirmation() throws {
        var f = try ready()
        try f.recover(using: .identity, livePosition: p(10))
        for i in 0...25 { f.update(position: p(10), heading: 0, time: 3+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .nearRoom)
        f.invalidate(); XCTAssertThrowsError(try f.confirmArrival())
    }
}
