import XCTest
@testable import IndoorbilityCore

final class LiveGuidanceTests: XCTestCase {
    func testStationaryPhoneRotationsNeverChangeStraightRouteInstruction() throws {
        let points = (0...30).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
        let marks = [ScanLandmark(label: "Start", kind: "entrance", position: points[0]),
                     ScanLandmark(label: "End", kind: "room", position: points.last!)]
        let draft = ScanDraft(name: "Synthetic", usesLiDAR: true, hasWorldMap: true,
            samples: points.map { ScanSample(position: $0, segment: 0) }, landmarks: marks,
            meshVertexCount: 30, meshTriangleCount: 10)
        var follower = HallwayFollower(route: try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true))
        var time = 0.0
        for _ in 0...25 { time += 0.1; follower.update(position: points[0], heading: 0, time: time, trackingNormal: true) }
        try follower.confirmEntrance()
        var ids = Set<String>(), texts = Set<String>()
        for heading: Float in [0, .pi/2, -.pi/2, .pi, 0, -.pi/2, .pi/2] {
            for _ in 0..<10 {
                time += 0.1
                follower.update(position: points[0], heading: heading, time: time, trackingNormal: true)
                let message = LiveGuidance.message(follower)
                ids.insert(message.id); texts.insert(message.text)
            }
        }
        print("STATIONARY_ROTATION: distinct guidance IDs=\(ids.count), texts=\(texts.sorted())")
        XCTAssertEqual(ids.count, 1)
        XCTAssertEqual(follower.progress, 0)
    }
    func testPlannedTurnsAreIndependentOfAllPhoneHeadings() throws {
        let start = (0...10).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
        for sign: Float in [-1, 1] {
            let path = start + (1...10).map { SpatialPoint(x: 10, y: 0, z: sign*Float($0)) }
            let marks = [ScanLandmark(label: "Start", kind: "entrance", position: path[0]), ScanLandmark(label: "End", kind: "room", position: path.last!)]
            let draft = ScanDraft(name: "L route", usesLiDAR: true, hasWorldMap: true,
                samples: path.map { ScanSample(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
            let route = try HallwayRoute.make(draft: draft, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
            var sequences = [[String]]()
            for heading: Float in [0, .pi, .pi/2, -.pi/2] {
                var f = HallwayFollower(route: route)
                var time = 0.0
                for _ in 0...25 { time += 0.1; f.update(position: path[0], heading: heading, time: time, trackingNormal: true) }
                try f.confirmEntrance()
                var delivery = GuidanceDelivery(), texts = [String]()
                for (a,b) in zip(path, path.dropFirst()) {
                    for step in 1...10 {
                        time += 0.1; let t = Float(step)/10
                        f.update(position: SpatialPoint(x: a.x+(b.x-a.x)*t, y: 0, z: a.z+(b.z-a.z)*t), heading: heading, time: time, trackingNormal: true)
                        let message = LiveGuidance.message(f)
                        if delivery.consume(message, listening: false) { texts.append(message.text) }
                    }
                }
                XCTAssertEqual(texts.filter { $0 == "Turn \(sign < 0 ? "left" : "right") now." }.count, 1)
                sequences.append(texts)
            }
            XCTAssertTrue(sequences.dropFirst().allSatisfy { $0 == sequences[0] })
        }
    }
    func testGeometryUTurnIsNotAnArbitraryLeftOrRight() {
        let path = (0...10).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
            + (1...8).map { SpatialPoint(x: 10-Float($0), y: 0, z: 0) }
        let turns = LiveGuidance.measuredTurns(path)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.direction, "around")
    }
    func testNewDirectionsInterruptOldDirectionsButNotSafety() {
        let old = PendingSpeech("In 10 meters, turn left", priority: .direction, now: 0)
        let turn = PendingSpeech("Turn left now", priority: .direction, now: 2)
        let safety = PendingSpeech("Position uncertain", priority: .safety, now: 2)
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: old, incoming: turn))
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: PendingSpeech("Cloud response", priority: .routine, now: 1), incoming: turn))
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: old, incoming: safety))
        XCTAssertFalse(NavigationSpeechQueue.shouldInterrupt(active: safety, incoming: turn))
        XCTAssertFalse(NavigationSpeechQueue.shouldInterrupt(active: turn, incoming: turn))
    }
    func testMuteOverridesForcedSpeechAndCues() {
        XCTAssertFalse(GuidanceSoundPolicy.speechAllowed(muted: true, enabled: true, forced: true, voiceOver: true, active: true, suspended: false))
        XCTAssertFalse(GuidanceSoundPolicy.cueAllowed(muted: true, enabled: true, suspended: false))
        XCTAssertTrue(GuidanceSoundPolicy.speechAllowed(muted: false, enabled: true, forced: false, voiceOver: false, active: true, suspended: false))
        XCTAssertFalse(GuidanceSoundPolicy.speechAllowed(muted: false, enabled: true, forced: true, voiceOver: false, active: false, suspended: false))
        XCTAssertFalse(GuidanceSoundPolicy.cueAllowed(muted: false, enabled: false, suspended: false))
    }
    func testRemindersRequireReliablePositionAndDoNotInterruptListening() {
        var delivery = GuidanceDelivery()
        let message = GuidanceMessage(id: "straight", text: "Continue straight.", cue: nil)
        XCTAssertTrue(delivery.consume(message, listening: false, now: 10, repeatReliable: true))
        XCTAssertFalse(delivery.consume(message, listening: false, now: 21, repeatReliable: true))
        XCTAssertFalse(delivery.consume(message, listening: true, now: 22, repeatReliable: true))
        XCTAssertFalse(delivery.consume(message, listening: false, now: 22, repeatReliable: false))
        XCTAssertTrue(delivery.consume(message, listening: false, now: 23, repeatReliable: true))
        XCTAssertFalse(delivery.consume(message, listening: false, now: 24, repeatReliable: true))
        let turn = GuidanceMessage(id: "turn", text: "Turn left now.", cue: .turn)
        XCTAssertTrue(delivery.consume(turn, listening: false, now: 24, repeatReliable: true))
    }
    func testDistanceAndDelivery() {
        XCTAssertEqual(LiveGuidance.distance(100, feet: false), "100 meters")
        XCTAssertEqual(LiveGuidance.distance(1, feet: true), "3 feet")
        XCTAssertEqual(LiveGuidance.distance(.nan, feet: false), "0 meters")
        var delivery = GuidanceDelivery()
        let m = GuidanceMessage(id: "turn", text: "Turn left now.", cue: .turn)
        XCTAssertFalse(delivery.consume(m, listening: true))
        XCTAssertTrue(delivery.consume(m, listening: false))
        XCTAssertFalse(delivery.consume(m, listening: false))
        delivery.reset()
        XCTAssertTrue(delivery.consume(m, listening: false))
    }
    func testMeasuredTurnsLossAndArrivalGate() throws {
        let path = (0...100).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
            + (1...30).map { SpatialPoint(x: 100, y: 0, z: -Float($0)) }
            + (1...20).map { SpatialPoint(x: 100+Float($0), y: 0, z: -30) }
        let marks = [ScanLandmark(label: "Entrance", kind: "entrance", position: path[0]), ScanLandmark(label: "Room", kind: "room", position: path.last!)]
        let d = ScanDraft(name: "Test", usesLiDAR: true, hasWorldMap: true, samples: path.map { ScanSample(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        var f = HallwayFollower(route: try HallwayRoute.make(draft: d, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true))
        var time = 0.0
        for _ in 0...25 { time += 0.1; f.update(position: path[0], heading: 0, time: time, trackingNormal: true) }
        try f.confirmEntrance()
        XCTAssertEqual(LiveGuidance.message(f).text, "Continue straight for 100 meters.")
        var delivery = GuidanceDelivery(); var spoken = [String]()
        for i in 1..<path.count {
            let a = path[i-1], b = path[i]
            for step in 1...10 {
                time += 0.1; let t = Float(step)/10
                f.update(position: SpatialPoint(x: a.x+(b.x-a.x)*t, y: 0, z: a.z+(b.z-a.z)*t), heading: atan2(b.z-a.z,b.x-a.x), time: time, trackingNormal: true)
                let message = LiveGuidance.message(f)
                if delivery.consume(message, listening: false) { spoken.append(message.text) }
            }
        }
        XCTAssertTrue(spoken.contains("Continue straight. In 20 meters, turn left."))
        XCTAssertEqual(spoken.filter { $0 == "Turn left now." }.count, 1)
        XCTAssertEqual(spoken.filter { $0 == "Turn right now." }.count, 1)
        XCTAssertThrowsError(try f.confirmArrival())
        for _ in 0...25 { time += 0.1; f.update(position: path.last!, heading: 0, time: time, trackingNormal: true) }
        try f.confirmArrival()
        XCTAssertEqual(LiveGuidance.message(f).cue, .arrived)
        f.invalidate()
        XCTAssertEqual(LiveGuidance.message(f).cue, .attention)
        XCTAssertFalse(LiveGuidance.message(f).text.contains("Turn left"))
    }
}
