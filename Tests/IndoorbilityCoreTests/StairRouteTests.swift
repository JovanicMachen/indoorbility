import XCTest
@testable import IndoorbilityCore

final class StairRouteTests: XCTestCase {
    func testAutomaticPublicationPreservesEvidenceAndInvalidatesEdits() throws {
        let draft = makeDraft()
        let original = try route(draft)
        let publication = try RoutePublication(route: original, draft: draft)
        let restored = try JSONDecoder().decode(RoutePublication.self, from: JSONEncoder().encode(publication))
        try restored.validate(for: original, draft: draft)
        let changed = try route(draft)
        XCTAssertThrowsError(try restored.validate(for: changed, draft: draft))
        XCTAssertThrowsError(try restored.validate(for: original, draft: makeDraft(gap: true)))
        XCTAssertEqual(restored.route.path, original.path)
    }
    func makeDraft(gap: Bool = false) -> ScanDraft {
        let points = (0...20).map { SpatialPoint(x: Float($0)*0.5, y: -Float($0)*0.15, z: 0) }
        return ScanDraft(name: "Measured stairs", usesLiDAR: true, hasWorldMap: true,
            samples: points.enumerated().map { ScanSample(position: gap && $0.offset > 10 ? SpatialPoint(x: $0.element.x + 4, y: $0.element.y, z: $0.element.z) : $0.element, segment: gap && $0.offset > 10 ? 1 : 0) },
            landmarks: [ScanLandmark(label: "Start", kind: "entrance", position: points.first!),
                        ScanLandmark(label: "Room", kind: "room", position: points.last!)],
            meshVertexCount: 30, meshTriangleCount: 10)
    }
    func route(_ draft: ScanDraft) throws -> HallwayRoute {
        try HallwayRoute.make(draft: draft, entranceID: draft.landmarks[0].id, roomID: draft.landmarks[1].id,
                              reviewed: true, stairFloors: .init(start: "1", end: "0"))
    }
    func testStairRecordingRoundTripAndAccessibility() throws {
        let draft = makeDraft(), r = try route(draft)
        try r.validate(for: draft)
        XCTAssertEqual(try JSONDecoder().decode(HallwayRoute.self, from: JSONEncoder().encode(r)), r)
        XCTAssertEqual(r.building.floors.map(\.label), ["1", "0"])
        XCTAssertNil(try Router.plan(in: r.building, from: "entrance", to: "room", avoidStairs: true))
        XCTAssertNotNil(try Router.plan(in: r.building, from: "entrance", to: "room", avoidStairs: false))
        XCTAssertThrowsError(try route(makeDraft(gap: true)))
    }
    func testFollowerDescendsWithoutFalseOffRoute() throws {
        let draft = makeDraft()
        var follower = HallwayFollower(route: try route(draft))
        for i in 0...25 { follower.update(position: draft.samples[0].position, heading: 0, time: Double(i)/10, trackingNormal: true) }
        try follower.confirmEntrance()
        for i in 1...100 {
            let p = SpatialPoint(x: Float(i)*0.1, y: -Float(i)*0.03, z: 0)
            follower.update(position: p, heading: 0, time: 2.5+Double(i)/10, trackingNormal: true)
            XCTAssertNotEqual(follower.state, .offRoute)
        }
        for i in 126...150 { follower.update(position: draft.landmarks[1].position, heading: 0, time: Double(i)/10, trackingNormal: true) }
        XCTAssertEqual(follower.state, .nearRoom)
        try follower.confirmArrival()
        XCTAssertEqual(follower.state, .arrived)
    }
    func testUnlabelledLevelChangeSavesAndReloadsWithoutInventingFloors() throws {
        let draft = makeDraft()
        for endpoints in [(0, 1), (1, 0)] {
            let route = try HallwayRoute.make(draft: draft,
                entranceID: draft.landmarks[endpoints.0].id,
                roomID: draft.landmarks[endpoints.1].id, reviewed: true)
            let restored = try JSONDecoder().decode(HallwayRoute.self, from: JSONEncoder().encode(route))
            try restored.validate(for: draft)
            XCTAssertEqual(restored.path, route.path)
            XCTAssertTrue(restored.hasLevelChange)
            XCTAssertNil(restored.stairFloors)
            XCTAssertEqual(restored.building.floors.map(\.label), ["Start level", "Destination level"])
            XCTAssertNil(try Router.plan(in: restored.building, from: "entrance", to: "room", avoidStairs: true))
            XCTAssertNotNil(try Router.plan(in: restored.building, from: "entrance", to: "room", avoidStairs: false))
        }
        let interrupted = makeDraft(gap: true)
        XCTAssertThrowsError(try HallwayRoute.make(draft: interrupted,
            entranceID: interrupted.landmarks[0].id, roomID: interrupted.landmarks[1].id, reviewed: true))
    }
    func testUnlabelledElevationGuidanceDoesNotClaimDetectedStairs() throws {
        let draft = makeDraft()
        let route = try HallwayRoute.make(draft: draft, entranceID: draft.landmarks[0].id,
            roomID: draft.landmarks[1].id, reviewed: true)
        var follower = HallwayFollower(route: route)
        for i in 0...25 {
            follower.update(position: draft.samples[0].position, heading: 0, time: Double(i)/10, trackingNormal: true)
        }
        try follower.confirmEntrance()
        follower.update(position: draft.samples[0].position, heading: 0, time: 2.6, trackingNormal: true)
        XCTAssertEqual(follower.instruction, "Level change ahead. Check for stairs or a ramp.")
    }
    func testWrongFloorCannotArrive() throws {
        let draft = makeDraft()
        var follower = HallwayFollower(route: try route(draft))
        for i in 0...25 { follower.update(position: draft.samples[0].position, heading: 0, time: Double(i)/10, trackingNormal: true) }
        try follower.confirmEntrance()
        for i in 1...100 { follower.update(position: SpatialPoint(x: Float(i)*0.1, y: 0, z: 0), heading: 0, time: 2.5+Double(i)/10, trackingNormal: true) }
        XCTAssertNotEqual(follower.state, .nearRoom)
        XCTAssertThrowsError(try follower.confirmArrival())
    }
    func testOutdoorDoesNotRepeatCompletedTurnWhenCourseChanges() {
        var p = OutdoorProgress(legs: [.init(instruction: "Turn left", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(40,0), accuracy: 5, timestamp: Double(i), now: Double(i), course: 90) }
        XCTAssertEqual(p.travelInstruction, "Continue straight")
        p.update(.init(41,0), accuracy: 5, timestamp: 4, now: 4, course: 270)
        XCTAssertEqual(p.travelInstruction, "Continue straight") // A single noisy course does not flip the cue.
        for i in 5...6 { p.update(.init(41,0), accuracy: 5, timestamp: Double(i), now: Double(i), course: 270) }
        XCTAssertEqual(p.travelInstruction, "Continue straight") // Course cannot replace the planned maneuver.
    }
}
