import XCTest
@testable import IndoorbilityCore

final class IndoorDirectionTests: XCTestCase {
    private func lRoute(sign: Float) throws -> (HallwayRoute, [SpatialPoint]) {
        let path = (0...10).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
            + (1...10).map { SpatialPoint(x: 10, y: 0, z: sign*Float($0)) }
        let marks = [ScanLandmark(label: "Start", kind: "entrance", position: path[0]),
                     ScanLandmark(label: "End", kind: "room", position: path.last!)]
        let draft = ScanDraft(name: "Synthetic L", usesLiDAR: true, hasWorldMap: true,
            samples: path.map { ScanSample(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        return (try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true), path)
    }

    func testWalkingAnLRouteShowsStraightDistanceThenTurnArrowThenArrival() throws {
        for sign: Float in [-1, 1] {
            let side = sign < 0 ? "left" : "right"
            let (route, path) = try lRoute(sign: sign)
            var f = HallwayFollower(route: route), time = 0.0
            XCTAssertNil(IndoorDirection.live(f)) // Nothing drawn before a position.
            for _ in 0...25 { time += 0.1; f.update(position: path[0], heading: 0, time: time, trackingNormal: true) }
            try f.confirmEntrance()
            time += 0.1; f.update(position: path[0], heading: 0, time: time, trackingNormal: true)
            let first = try XCTUnwrap(IndoorDirection.live(f))
            XCTAssertEqual(first.arrow, .straight)
            XCTAssertEqual(first.detail, "then turn " + side)
            XCTAssertEqual(try XCTUnwrap(first.distance), 10, accuracy: 1)
            XCTAssertEqual(IndoorDirection.distanceParts(try XCTUnwrap(first.distance), feet: true).unit, "ft")
            XCTAssertTrue(first.spoken(feet: true).contains("feet"))

            var arrows: [IndoorDirection.Arrow] = []
            let heading: Float = 0
            for (a, b) in zip(path, path.dropFirst()) {
                for step in 1...10 {
                    time += 0.1; let t = Float(step)/10
                    let facing = b.z == a.z ? heading : (sign < 0 ? -.pi/2 : .pi/2)
                    f.update(position: SpatialPoint(x: a.x+(b.x-a.x)*t, y: 0, z: a.z+(b.z-a.z)*t), heading: facing, time: time, trackingNormal: true)
                    if let d = IndoorDirection.live(f), arrows.last != d.arrow { arrows.append(d.arrow) }
                }
            }
            for _ in 0..<20 { time += 0.1; f.update(position: path.last!, heading: 0, time: time, trackingNormal: true) }
            if let d = IndoorDirection.live(f), arrows.last != d.arrow { arrows.append(d.arrow) }
            XCTAssertEqual(arrows.first, .straight)
            XCTAssertTrue(arrows.contains(sign < 0 ? .left : .right), "\(arrows)")
            XCTAssertFalse(arrows.contains(sign < 0 ? .right : .left))
            XCTAssertFalse(arrows.contains(.back))
        }
    }

    func testOffPathPointsTowardThePath() throws {
        let (route, path) = try lRoute(sign: 1)
        var f = HallwayFollower(route: route), time = 0.0
        f.setLocalized() // Saved-map mode: the follower reports which side the path is on.
        for _ in 0...25 { time += 0.1; f.update(position: path[0], heading: 0, time: time, trackingNormal: true) }
        // Facing +x, standing 3 m to the +z side: the path is on the left.
        for step in 1...30 { time += 0.1; f.update(position: SpatialPoint(x: Float(step)/10, y: 0, z: 0), heading: 0, time: time, trackingNormal: true) }
        for step in 1...30 { time += 0.1; f.update(position: SpatialPoint(x: 3, y: 0, z: Float(step)/10), heading: 0, time: time, trackingNormal: true) }
        for _ in 0..<15 { time += 0.1; f.update(position: SpatialPoint(x: 3, y: 0, z: 3), heading: 0, time: time, trackingNormal: true) }
        XCTAssertEqual(f.state, .offRoute)
        let d = try XCTUnwrap(IndoorDirection.live(f))
        XCTAssertEqual(d.arrow, .left)
        XCTAssertNil(d.distance)
        // Manual-alignment mode gives no side, so no arrow is guessed.
        var manual = HallwayFollower(route: route); time = 0
        for _ in 0...25 { time += 0.1; manual.update(position: path[0], heading: 0, time: time, trackingNormal: true) }
        try manual.confirmEntrance()
        for step in 1...30 { time += 0.1; manual.update(position: SpatialPoint(x: Float(step)/10, y: 0, z: 0), heading: 0, time: time, trackingNormal: true) }
        for step in 1...30 { time += 0.1; manual.update(position: SpatialPoint(x: 3, y: 0, z: Float(step)/10), heading: 0, time: time, trackingNormal: true) }
        for _ in 0..<20 { time += 0.1; manual.update(position: SpatialPoint(x: 3, y: 0, z: 3), heading: 0, time: time, trackingNormal: true) }
        XCTAssertEqual(manual.state, .offRoute)
        XCTAssertNil(IndoorDirection.live(manual))
    }

    func testPreviewDirectionsComeFromTheRecordedStart() {
        let straight = IndoorDirection.preview(RecordedRoutePreview(firstLegDistance: 9.144, firstTurn: "left", destination: "Room 006"))
        XCTAssertEqual(straight.arrow, .straight)
        XCTAssertEqual(straight.detail, "then turn left")
        XCTAssertEqual(IndoorDirection.distanceParts(9.144, feet: true).value, "30")
        let turn = IndoorDirection.preview(RecordedRoutePreview(firstLegDistance: 0.5, firstTurn: "right", destination: "Room 006"))
        XCTAssertEqual(turn.arrow, .right)
        XCTAssertNil(turn.distance)
        let noTurn = IndoorDirection.preview(RecordedRoutePreview(firstLegDistance: 12, firstTurn: nil, destination: "Room 006"))
        XCTAssertEqual(noTurn.detail, "to Room 006")
        XCTAssertEqual(IndoorDirection.distanceParts(0.1, feet: true).value, "<1")
        XCTAssertEqual(IndoorDirection.distanceParts(.nan, feet: false).value, "–")
    }

    func testTravelLoopHasOneSecondGapLouderVolumeAndSoftStop() {
        XCTAssertEqual(TravelLoopTiming.gapSeconds, 1.0)
        XCTAssertGreaterThan(TravelLoopTiming.normalVolume, 0.28)
        XCTAssertGreaterThan(TravelLoopTiming.duckedVolume, 0.04)
        XCTAssertLessThan(TravelLoopTiming.duckedVolume, TravelLoopTiming.normalVolume)
        XCTAssertEqual(TravelLoopTiming.gain(peak: 0.3), 3, accuracy: 0.001)
        XCTAssertEqual(TravelLoopTiming.gain(peak: 0.95), 1)
        XCTAssertEqual(TravelLoopTiming.gain(peak: 0.01), 4)
        XCTAssertEqual(TravelLoopTiming.gain(peak: 0), 1)
        XCTAssertEqual(TravelLoopTiming.softStopDelay(currentTime: 0.2, clipDuration: 0.57), 0.37, accuracy: 0.0001)
        XCTAssertEqual(TravelLoopTiming.softStopDelay(currentTime: 1.2, clipDuration: 0.57), 0) // in the silent gap
        XCTAssertEqual(TravelLoopTiming.softStopDelay(currentTime: .nan, clipDuration: 0.57), 0)
    }
}
