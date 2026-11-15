import XCTest
@testable import IndoorbilityCore

final class TraceGapTests: XCTestCase {
    private func draft(_ samples: [ScanSample]) -> ScanDraft {
        ScanDraft(name: "Hallway", usesLiDAR: true, hasWorldMap: true, samples: samples,
                  landmarks: [ScanLandmark(label: "A", kind: "entrance", position: samples.first!.position),
                              ScanLandmark(label: "B", kind: "room", position: samples.last!.position)],
                  meshVertexCount: 30, meshTriangleCount: 10)
    }
    func testShortDropoutsAreBridgedIntoOneContinuousRoute() throws {
        // Walk 12 m with two brief tracking dropouts (1 m and 2.5 m unrecorded).
        var samples: [ScanSample] = []
        for i in 0...8 { samples.append(ScanSample(position: SpatialPoint(x: Float(i)*0.5, y: 0, z: 0), segment: 0)) }      // 0…4 m
        for i in 0...8 { samples.append(ScanSample(position: SpatialPoint(x: 5+Float(i)*0.5, y: 0.05, z: 0), segment: 1)) }  // 5…9 m
        for i in 0...1 { samples.append(ScanSample(position: SpatialPoint(x: 11.5+Float(i)*0.5, y: 0, z: 0), segment: 2)) } // 11.5…12 m
        let d = draft(samples)
        let route = try HallwayRoute.make(draft: d, entranceID: d.landmarks[0].id, roomID: d.landmarks[1].id, reviewed: true)
        XCTAssertEqual(route.distance, 12, accuracy: 0.1)
        XCTAssertTrue(zip(route.path, route.path.dropFirst()).allSatisfy { $0.distance(to: $1) <= 0.6 })
        // Reverse direction works too.
        let back = try HallwayRoute.make(draft: d, entranceID: d.landmarks[1].id, roomID: d.landmarks[0].id, reviewed: true)
        XCTAssertEqual(back.distance, 12, accuracy: 0.1)
    }
    func testRealJumpsAreRejectedWithAnActionableMessage() {
        let far = [ScanSample(position: SpatialPoint(x: 0, y: 0, z: 0), segment: 0), ScanSample(position: SpatialPoint(x: 1, y: 0, z: 0), segment: 0),
                   ScanSample(position: SpatialPoint(x: 6, y: 0, z: 0), segment: 1), ScanSample(position: SpatialPoint(x: 7, y: 0, z: 0), segment: 1)]
        XCTAssertThrowsError(try TraceGaps.bridge(far)) { error in
            XCTAssertTrue("\(error)".contains("16 ft"), "\(error)")
            XCTAssertTrue("\(error)".contains("Record this route again"))
        }
        let floorJump = [ScanSample(position: SpatialPoint(x: 0, y: 0, z: 0), segment: 0),
                         ScanSample(position: SpatialPoint(x: 1, y: 1.2, z: 0), segment: 1)]
        XCTAssertThrowsError(try TraceGaps.bridge(floorJump))
    }
    func testContinuousTraceIsUnchanged() throws {
        let samples = (0...4).map { ScanSample(position: SpatialPoint(x: Float($0), y: 0, z: 0), segment: 3) }
        XCTAssertEqual(try TraceGaps.bridge(samples), samples.map(\.position))
    }
}
