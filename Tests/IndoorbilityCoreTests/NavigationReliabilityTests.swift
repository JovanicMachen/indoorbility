import XCTest
@testable import IndoorbilityCore

final class NavigationReliabilityTests: XCTestCase {
    func testLongRouteProcessingBenchmark() throws {
        let points = (0..<5000).map { SpatialPoint(x: Float($0)*0.2, y: 0, z: 0) }
        let marks = [ScanLandmark(label: "Entrance", kind: "entrance", position: points.first!),
                     ScanLandmark(label: "Room", kind: "room", position: points.last!)]
        let draft = ScanDraft(name: "Synthetic benchmark, not a building", usesLiDAR: true, hasWorldMap: true,
                              samples: points.map { .init(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        var follower = HallwayFollower(route: try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true))
        for i in 0...25 { follower.update(position: points[0], heading: 0, time: Double(i)/10, trackingNormal: true) }
        try follower.confirmEntrance()
        let started = ProcessInfo.processInfo.systemUptime
        for i in 1...1000 {
            follower.update(position: .init(x: Float(i)*0.014, y: 0, z: 0), heading: 0, time: 2.5+Double(i)*0.01, trackingNormal: true)
            _ = LiveGuidance.message(follower)
        }
        let ms = (ProcessInfo.processInfo.systemUptime-started)*1000
        print(String(format: "NAV_BENCH 5000 vertices, 1000 synthetic pose+guidance updates: %.3f ms total; %.5f ms/update", ms, ms/1000))
        XCTAssertEqual(follower.state, .guiding)
        XCTAssertEqual(follower.progress, 14, accuracy: 0.05)
    }
    func testRouteAvailabilityConstructionBenchmark() throws {
        let points = (0..<5000).map { SpatialPoint(x: Float($0)*0.2, y: 0, z: 0) }
        let marks = [ScanLandmark(label: "Start", kind: "entrance", position: points[0]), ScanLandmark(label: "End", kind: "room", position: points.last!)]
        let draft = ScanDraft(name: "Synthetic only", usesLiDAR: true, hasWorldMap: true, samples: points.map { .init(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        let route = try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
        var successful = 0
        var start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            if try Router.plan(in: route.building, from: "entrance", to: "room") != nil { successful += 1 }
        }
        let originalMS = (ProcessInfo.processInfo.systemUptime-start)*1000
        let building = HallwayFollower(route: route).building
        start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            if try Router.plan(in: building, from: "entrance", to: "room") != nil { successful += 1 }
        }
        let cachedMS = (ProcessInfo.processInfo.systemUptime-start)*1000
        print(String(format: "AVAILABILITY_BENCH 5000 vertices / 1000 checks: rebuilding %.3f ms; immutable graph %.3f ms", originalMS, cachedMS))
        XCTAssertEqual(successful, 2000)
        XCTAssertNil(try Router.plan(in: building, from: "entrance", to: "room", excluding: ["hallway"]))
    }
    func testLostPoseCannotResumeOrArriveWithoutConfirmation() throws {
        let fixture = HallwayNavigationTests()
        var follower = try fixture.ready()
        follower.update(position: nil, heading: nil, time: 2.6, trackingNormal: false)
        XCTAssertEqual(follower.state, .trackingLost)
        for i in 27...60 {
            follower.update(position: fixture.p(0), heading: 0, time: Double(i)/10, trackingNormal: true)
        }
        XCTAssertEqual(follower.state, .ready)
        XCTAssertThrowsError(try follower.confirmArrival())
        try follower.confirmEntrance()
        XCTAssertEqual(follower.state, .guiding)
        follower.update(position: fixture.p(10), heading: 0, time: 6.1, trackingNormal: true)
        XCTAssertEqual(follower.state, .trackingLost) // Impossible one-frame jump to destination.
        XCTAssertThrowsError(try follower.confirmArrival())
    }
    func testSurfaceAgreementResetsAcrossMissingEvidence() {
        var filter = SurfaceAgreementFilter()
        XCTAssertFalse(filter.update(.discrepancy, time: 0))
        XCTAssertFalse(filter.update(.discrepancy, time: 0.5))
        XCTAssertFalse(filter.update(.discrepancy, time: 4))
        XCTAssertFalse(filter.update(.consistent, time: 4.5))
        XCTAssertFalse(filter.update(.discrepancy, time: 5))
        XCTAssertFalse(filter.update(.discrepancy, time: 5.5))
        XCTAssertTrue(filter.update(.discrepancy, time: 6))
    }
    func testTimingWindowIsBounded() {
        var timing = TimingWindow()
        for i in 0..<1000 { timing.record(Double(i)) }
        XCTAssertEqual(timing.count, 300)
        XCTAssertEqual(timing.mean!, 849.5, accuracy: 0.01)
        timing.record(.nan)
        XCTAssertEqual(timing.count, 300)
    }
    func testSparseSurfaceEvidenceAndRepeatedDiscrepancy() {
        let wall = (0..<30).flatMap { x in (0..<30).map { y in SpatialPoint(x: Float(x)*0.25, y: Float(y)*0.25, z: 0) } }
        let reference = SurfaceReference(points: wall)
        let visible = (0..<96).map { i in SpatialPoint(x: Float(i%12)*0.25, y: Float(i/12)*0.25, z: 0) }
        XCTAssertEqual(reference.compare(points: visible), .consistent)
        let changed = visible.map { SpatialPoint(x: $0.x, y: $0.y, z: 0.7) }
        XCTAssertEqual(reference.compare(points: changed), .discrepancy)
        XCTAssertEqual(reference.compare(points: [.init(x: 100, y: 100, z: 100)]), .unknown)
        var filter = SurfaceAgreementFilter()
        XCTAssertFalse(filter.update(.discrepancy, time: 0))
        XCTAssertFalse(filter.update(.discrepancy, time: 0)) // duplicate frame
        XCTAssertFalse(filter.update(.discrepancy, time: 0.5))
        XCTAssertTrue(filter.update(.discrepancy, time: 1))
        XCTAssertFalse(filter.update(.unknown, time: 1.5))
    }
}
