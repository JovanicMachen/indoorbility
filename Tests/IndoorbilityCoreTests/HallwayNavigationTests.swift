import XCTest
@testable import IndoorbilityCore

final class HallwayNavigationTests: XCTestCase {
    func p(_ x: Float, _ z: Float = 0) -> SpatialPoint { SpatialPoint(x: x, y: 0, z: z) }
    func draft(gap: Bool = false) -> ScanDraft {
        ScanDraft(name: "Hallway", usesLiDAR: true, hasWorldMap: true,
                  // gap: tracking dropped and the position jumped 4 m (a real jump, not a short dropout).
                  samples: (0...20).map { ScanSample(position: p(Float($0)/2 + (gap && $0 > 10 ? 4 : 0)), segment: gap && $0 > 10 ? 1 : 0) },
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
    func testMatchedMapStartsAtMeasuredPositionWithoutManualEndpoints() throws {
        var f = HallwayFollower(route: try route())
        for i in 0...25 { f.update(position: p(4), heading: Float(i), time: Double(i)/10, trackingNormal: true) }
        XCTAssertThrowsError(try f.startInRelocalizedMap(livePosition: p(4), relocalized: false))
        try f.startInRelocalizedMap(livePosition: p(4), relocalized: true)
        XCTAssertEqual(f.progress, 4, accuracy: 0.01)
        XCTAssertEqual(f.remaining, 6, accuracy: 0.01)
        XCTAssertEqual(f.state, .guiding)
        XCTAssertFalse(f.localized) // Preserve segment guidance and room evidence checks.
    }
    func testMatchedPositionNearTheMiddleOfPathDoesNotRequireExactStartOrCenterline() throws {
        var follower = HallwayFollower(route: try route())
        let measured = p(4, 0.8)
        for i in 0...25 {
            follower.update(position: measured, heading: Float(i), time: Double(i)/10, trackingNormal: true)
        }
        XCTAssertThrowsError(try follower.startInRelocalizedMap(livePosition: measured, relocalized: false))
        try follower.startInRelocalizedMap(livePosition: measured, relocalized: true)
        XCTAssertEqual(follower.state, .guiding)
        XCTAssertEqual(follower.progress, 4, accuracy: 0.01)
        XCTAssertEqual(follower.remaining, 6, accuracy: 0.01)
        XCTAssertEqual(follower.route.entrance.position, p(0))
        XCTAssertEqual(follower.route.room.position, p(10))
    }
    func testMatchingAndPoseStabilityCanSettleTogetherWithoutSkippingEitherCheck() throws {
        func startup(serialWindows: Bool, jumpAt: Int? = nil) throws -> Double {
            var follower = HallwayFollower(route: try route())
            var matching = SavedRouteRelocalization()
            for i in 0...160 {
                let time = Double(i) * 0.05
                let position = p(jumpAt.map { i >= $0 ? 4.8 : 4 } ?? 4)
                follower.update(position: position, heading: Float(i), time: time, trackingNormal: true)
                let matched = matching.update(mapMatched: true,
                    trackingStable: serialWindows ? follower.stable : true, position: position, time: time)
                if matched && follower.stable && follower.state == .ready {
                    try follower.startInRelocalizedMap(livePosition: position, relocalized: true)
                    XCTAssertEqual(follower.state, .guiding)
                    XCTAssertEqual(follower.progress, position.x, accuracy: 0.01)
                    return time
                }
                XCTAssertNotEqual(follower.state, .guiding)
            }
            XCTFail("Valid measured positions did not settle")
            return .infinity
        }
        let previous = try startup(serialWindows: true)
        let parallel = try startup(serialWindows: false)
        print("SYNTHETIC_MATCH_SETTLING: serial=\(previous)s; concurrent=\(parallel)s; sensor relocalization time excluded")
        XCTAssertEqual(previous, 4, accuracy: 0.1)
        XCTAssertEqual(parallel, 2, accuracy: 0.1)
        // An impossible one-frame jump restarts both evidence windows.
        XCTAssertGreaterThanOrEqual(try startup(serialWindows: false, jumpAt: 30), 3.5)
    }
    func testRecordedWalkFinishesAtItsMeasuredEndpointWithoutRoomSignClaim() throws {
        var f = try ready()
        XCTAssertThrowsError(try f.finishRecordedRoute(positionVerified: true))
        try f.startInRelocalizedMap(livePosition: p(10), relocalized: true)
        for i in 26...49 { f.update(position: p(10), heading: Float(i), time: Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .nearRoom)
        XCTAssertThrowsError(try f.finishRecordedRoute(positionVerified: false))
        try f.finishRecordedRoute(positionVerified: true)
        XCTAssertEqual(f.state, .arrived)
        XCTAssertEqual(f.remaining, 0)
        XCTAssertEqual(f.instruction, "You’ve arrived at Room 12.")
        XCTAssertFalse(f.instruction.contains("Arrival confirmed"))
    }
    func testMatchedMapResumesSameRouteAfterTrackingInterruption() throws {
        var f = try ready()
        try f.startInRelocalizedMap(livePosition: p(4), relocalized: true)
        let routeID = f.route.id, roomID = f.route.room.id
        f.update(position: nil, heading: nil, time: 2.6, trackingNormal: false)
        XCTAssertNil(f.position)
        XCTAssertEqual(f.state, .trackingLost)
        for i in 27...49 { f.update(position: p(4.2), heading: Float(i), time: Double(i)/10, trackingNormal: true) }
        try f.resumeInRelocalizedMap(livePosition: p(4.2), relocalized: true)
        XCTAssertEqual(f.route.id, routeID)
        XCTAssertEqual(f.route.room.id, roomID)
        XCTAssertEqual(f.progress, 4.2, accuracy: 0.01)
        XCTAssertEqual(f.remaining, 5.8, accuracy: 0.01)
        for i in 50...65 { f.update(position: p(4.2), heading: Float(i), time: Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.instruction, "Continue straight.")
        XCTAssertEqual(f.state, .guiding)
    }
    func testMatchedMapResumeCannotJumpToDistantPartOfRoute() throws {
        var f = try ready()
        try f.startInRelocalizedMap(livePosition: p(4), relocalized: true)
        XCTAssertThrowsError(try f.resumeInRelocalizedMap(livePosition: p(8), relocalized: true))
        XCTAssertThrowsError(try f.resumeInRelocalizedMap(livePosition: p(4), relocalized: false))
        XCTAssertThrowsError(try f.resumeInRelocalizedMap(livePosition: SpatialPoint(x: 4, y: 3, z: 0), relocalized: true))
        XCTAssertEqual(f.progress, 4, accuracy: 0.01)
        f.invalidate()
        XCTAssertThrowsError(try f.resumeInRelocalizedMap(livePosition: p(4), relocalized: true))
    }
    func testMatchedMapResumeRejectsOverlappingSegmentsAndManualFrame() throws {
        let path = [p(0), p(5), p(10), p(5), p(0), p(0, 2)]
        let a = ScanLandmark(label: "Start", kind: "entrance", position: path.first!)
        let b = ScanLandmark(label: "End", kind: "room", position: path.last!)
        let route = HallwayRoute(id: UUID(), scanID: UUID(), entrance: a, room: b, path: path, confirmedAt: Date())
        var f = HallwayFollower(route: route)
        for i in 0...25 { f.update(position: p(0, 1), heading: 0, time: Double(i)/10, trackingNormal: true) }
        try f.startInRelocalizedMap(livePosition: p(0, 1), relocalized: true)
        XCTAssertThrowsError(try f.resumeInRelocalizedMap(livePosition: p(0, 0.2), relocalized: true))
        var manual = try ready()
        try manual.recover(using: ScanAlignment(yaw: 0, translation: p(1)), livePosition: p(3))
        XCTAssertThrowsError(try manual.resumeInRelocalizedMap(livePosition: p(4), relocalized: true))
    }
    func testAutomaticMapStartRejectsWrongFloorAndUnstableTracking() throws {
        var f = try ready()
        XCTAssertThrowsError(try f.startInRelocalizedMap(livePosition: SpatialPoint(x: 4, y: 3, z: 0), relocalized: true))
        f.invalidate()
        XCTAssertThrowsError(try f.startInRelocalizedMap(livePosition: p(4), relocalized: true))
    }
    func testAutomaticMapStartRejectsOverlappingRouteSegments() throws {
        let a = ScanLandmark(label: "Start", kind: "entrance", position: p(0))
        let b = ScanLandmark(label: "End", kind: "room", position: p(0, 2))
        let path = [p(0), p(5), p(10), p(5), p(0), p(0, 2)]
        let route = HallwayRoute(id: UUID(), scanID: UUID(), entrance: a, room: b, path: path, confirmedAt: Date())
        var f = HallwayFollower(route: route)
        for i in 0...25 { f.update(position: p(5), heading: 0, time: Double(i)/10, trackingNormal: true) }
        XCTAssertThrowsError(try f.startInRelocalizedMap(livePosition: p(5), relocalized: true))
        XCTAssertNotEqual(f.state, .guiding)
    }
    func testSavedMapRecoveryRequiresMatchingLandmarkAndStableTracking() throws {
        var f = try ready()
        XCTAssertThrowsError(try f.recoverInSavedMap(livePosition: p(5), landmark: p(5), relocalized: false))
        XCTAssertThrowsError(try f.recoverInSavedMap(livePosition: p(5), landmark: p(9), relocalized: true))
        XCTAssertThrowsError(try f.recoverInSavedMap(livePosition: SpatialPoint(x: 5, y: 3, z: 0), landmark: p(5), relocalized: true))
        try f.recoverInSavedMap(livePosition: p(5), landmark: p(5), relocalized: true)
        XCTAssertEqual(f.progress, 5, accuracy: 0.01)
        XCTAssertEqual(f.state, .guiding)
        f.invalidate()
        XCTAssertThrowsError(try f.recoverInSavedMap(livePosition: p(5), landmark: p(5), relocalized: true))
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
    func testBackwardWalkingPausesWithoutInventingTurns() throws {
        var f = try ready()
        for i in 1...40 { f.update(position: p(Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        var texts = [String]()
        for i in 1...25 {
            f.update(position: p(4-Float(i)/10), heading: 0, time: 6.5+Double(i)/10, trackingNormal: true)
            texts.append(LiveGuidance.message(f).text)
        }
        XCTAssertEqual(f.state, .trackingLost)
        XCTAssertTrue(texts.contains(where: { $0.hasPrefix("Moving away") }))
        XCTAssertFalse(texts.contains(where: { $0.contains("left") || $0.contains("right") }))
        XCTAssertLessThanOrEqual(f.progress, 4.01)
    }
    func testVerticalCameraDoesNotInvalidateReliablePosition() throws {
        var f = try ready()
        for i in 1...10 { f.update(position: p(Float(i)/10), heading: nil, time: 2.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .guiding)
        XCTAssertNil(f.cameraHeading)
        XCTAssertEqual(f.progress, 1, accuracy: 0.01)
        f.update(position: p(1), heading: nil, time: 3.6, trackingNormal: false)
        XCTAssertEqual(f.state, .trackingLost)
    }
    func testCrossingRouteKeepsSequenceAndRejectsAmbiguousRecovery() throws {
        let path = (-5...5).map { p(Float($0)) }
            + (1...5).map { p(5, Float($0)) }
            + (1...5).map { p(5-Float($0), 5) }
            + (1...10).map { p(0, 5-Float($0)) }
        let marks = [ScanLandmark(label: "Entrance", kind: "entrance", position: path[0]), ScanLandmark(label: "Destination", kind: "room", position: path.last!)]
        let d = ScanDraft(name: "Synthetic crossing", usesLiDAR: true, hasWorldMap: true, samples: path.map { ScanSample(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        let route = try HallwayRoute.make(draft: d, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
        var follower = HallwayFollower(route: route)
        for i in 0...25 { follower.update(position: path[0], heading: 0, time: Double(i)/10, trackingNormal: true) }
        try follower.confirmEntrance()
        XCTAssertThrowsError(try follower.recover(using: .identity, livePosition: p(0, 0)))
        XCTAssertEqual(follower.progress, 0)
        XCTAssertEqual(follower.route.id, route.id)
        for i in 1..<path.count {
            follower.update(position: path[i], heading: i % 2 == 0 ? .pi : -.pi/2, time: 2.5+Double(i)*0.5, trackingNormal: true)
            XCTAssertEqual(follower.progress, Float(i), accuracy: 0.01)
            XCTAssertEqual(follower.state, .guiding)
        }
        follower.invalidate()
        XCTAssertEqual(follower.route, route)
        XCTAssertEqual(follower.route.room.id, marks[1].id)
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
    func testProgressAutomaticallyAdvancesAndEndStopNeedsOnlyAShortDwell() throws {
        var f = try ready()
        for i in 1...80 { f.update(position: p(Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.progress, 8, accuracy: 0.01)
        XCTAssertEqual(f.state, .guiding) // 2 m from the end stop: not there yet.
        XCTAssertThrowsError(try f.confirmArrival())
        // Within about 5 ft of the recorded end stop for one second is enough.
        for i in 81...90 { f.update(position: p(Float(i)/10), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        for i in 1...12 { f.update(position: p(9), heading: 0, time: 11.5+Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(f.state, .nearRoom)
        XCTAssertFalse(f.instruction.contains("label"))
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
    func testHeadingDoesNotChangePlannedInstructionOrProgress() throws {
        var f = try ready()
        for i in 26...30 { f.update(position: p(0), heading: .pi, time: Double(i)/10, trackingNormal: true) }
        XCTAssertTrue(f.instruction.hasPrefix("Continue straight"))
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

final class HallwayGPSModeTests: XCTestCase {
    /// L-shaped hallway: 6 m along +x, then 6 m along +z.
    private func follower() throws -> HallwayFollower {
        let pts = (0...12).map { i -> SpatialPoint in i <= 6 ? SpatialPoint(x: Float(i), y: 0, z: 0) : SpatialPoint(x: 6, y: 0, z: Float(i-6)) }
        let entrance = ScanLandmark(label: "Front door", kind: "entrance", position: pts.first!)
        let room = ScanLandmark(label: "Room 105", kind: "room", position: pts.last!)
        let route = HallwayRoute(id: UUID(), scanID: UUID(), entrance: entrance, room: room, path: pts, confirmedAt: Date())
        var f = HallwayFollower(route: route); f.setLocalized(); return f
    }
    private func walk(_ f: inout HallwayFollower, _ p: SpatialPoint, heading: Float = 0, from t: inout Double, frames: Int = 12) {
        for _ in 0..<frames { f.update(position: p, heading: heading, time: t, trackingNormal: true); t += 0.1 }
    }
    func testStartsAnywhereOnPathWithoutEntranceConfirmation() throws {
        var f = try follower(); var t = 0.0
        walk(&f, SpatialPoint(x: 3, y: 0, z: 0.4), from: &t)
        XCTAssertEqual(f.state, .guiding)
        XCTAssertEqual(f.progress, 3, accuracy: 0.2)
    }
    func testPoseCorrectionAndTrackingLossRecoverAutomatically() throws {
        var f = try follower(); var t = 0.0
        walk(&f, SpatialPoint(x: 2, y: 0, z: 0), from: &t)
        XCTAssertEqual(f.state, .guiding)
        // ARKit snaps 1 m forward when it refines the match.
        walk(&f, SpatialPoint(x: 3, y: 0, z: 0), from: &t)
        XCTAssertEqual(f.state, .guiding)
        // Tracking lost for 3 s, then resumes further along.
        for _ in 0..<30 { f.update(position: nil, heading: nil, time: t, trackingNormal: false); t += 0.1 }
        XCTAssertEqual(f.state, .trackingLost)
        walk(&f, SpatialPoint(x: 6, y: 0, z: 2), heading: .pi/2, from: &t)
        XCTAssertEqual(f.state, .guiding)
        XCTAssertEqual(f.progress, 8, accuracy: 0.3)
    }
    func testOffPathTellsWhichWayAndResumes() throws {
        var f = try follower(); var t = 0.0
        walk(&f, SpatialPoint(x: 2, y: 0, z: 0), from: &t)
        // Step 3 m to the side, facing +x; the path (z = 0) is then anticlockwise = left.
        walk(&f, SpatialPoint(x: 2, y: 0, z: 3), heading: 0, from: &t, frames: 15)
        XCTAssertEqual(f.state, .offRoute)
        XCTAssertTrue(f.instruction.contains("to your left"), f.instruction)
        walk(&f, SpatialPoint(x: 2.5, y: 0, z: 0.3), from: &t)
        XCTAssertEqual(f.state, .guiding)
    }
    func testWalkingBackwardsDoesNotStopGuidance() throws {
        var f = try follower(); var t = 0.0
        walk(&f, SpatialPoint(x: 4, y: 0, z: 0), from: &t)
        walk(&f, SpatialPoint(x: 3, y: 0, z: 0), heading: .pi, from: &t, frames: 20)
        XCTAssertEqual(f.state, .guiding)
        XCTAssertEqual(f.instruction, "Turn around.")
        XCTAssertEqual(f.progress, 3, accuracy: 0.2)
    }
    func testArrivesAutomatically() throws {
        var f = try follower(); var t = 0.0
        walk(&f, SpatialPoint(x: 6, y: 0, z: 4), heading: .pi/2, from: &t)
        walk(&f, SpatialPoint(x: 6, y: 0, z: 5.6), heading: .pi/2, from: &t, frames: 15)
        XCTAssertEqual(f.state, .arrived)
        XCTAssertEqual(LiveGuidance.message(f).cue, .arrived)
    }
}
