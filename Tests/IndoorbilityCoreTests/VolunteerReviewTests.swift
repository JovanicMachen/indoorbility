import XCTest
@testable import IndoorbilityCore

final class VolunteerReviewTests: XCTestCase {
    private func route() throws -> HallwayRoute {
        func p(_ x: Float) -> SpatialPoint { SpatialPoint(x: x, y: 0, z: 0) }
        let draft = ScanDraft(name: "Test only", usesLiDAR: true, hasWorldMap: true,
            samples: (0...10).map { ScanSample(position: p(Float($0)), segment: 0) },
            landmarks: [ScanLandmark(label: "Start", kind: "entrance", position: p(0)), ScanLandmark(label: "Room", kind: "room", position: p(10))], meshVertexCount: 3, meshTriangleCount: 1)
        return try HallwayRoute.make(draft: draft, entranceID: draft.landmarks[0].id, roomID: draft.landmarks[1].id, reviewed: true)
    }
    private func review(_ r: HallwayRoute, length: Float = 10, error: Float = 0.2, access: Bool = true, tested: Bool = true, floor: String = "LL") -> VolunteerReview {
        VolunteerReview(route: r, reviewer: "AB", floorLabel: floor, measuredLength: length, endpointError: error, accessConfirmed: access, returnTestPassed: tested)
    }
    func testReviewRoundTripRemainsBoundToExactRoute() throws {
        let r = try route()
        let decoded = try JSONDecoder().decode(VolunteerReview.self, from: JSONEncoder().encode(review(r)))
        XCTAssertNoThrow(try decoded.validate(for: r))
        XCTAssertThrowsError(try decoded.validate(for: route()))
    }
    func testRejectBadMeasurements() throws {
        let r = try route()
        for length: Float in [0, -1, .nan, .infinity, 12] { XCTAssertThrowsError(try review(r, length: length).validate(for: r)) }
        for error: Float in [-1, .nan, .infinity, 0.51] { XCTAssertThrowsError(try review(r, error: error).validate(for: r)) }
    }
    func testIncompleteFieldChecksCannotReleaseRoute() throws {
        let r = try route()
        XCTAssertThrowsError(try review(r, access: false).validate(for: r))
        XCTAssertThrowsError(try review(r, tested: false).validate(for: r))
        XCTAssertThrowsError(try review(r, floor: " ").validate(for: r))
    }
}
