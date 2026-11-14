import XCTest
@testable import IndoorbilityCore
final class OutdoorProgressTests: XCTestCase {
    func testCourseFluctuationsDoNotRepeatCompletedTurn() {
        var p = OutdoorProgress(legs: [.init(instruction: "Turn left", points: [.init(0,0), .init(100,0)])])
        for i in 1...30 {
            p.update(.init(8,0), accuracy: 5, timestamp: Double(i), now: Double(i), course: i % 2 == 0 ? 90 : 270)
            if i >= 3 { XCTAssertEqual(p.travelInstruction, "Continue straight") }
        }
        XCTAssertFalse(p.wrongWay)
        XCTAssertEqual(p.index, 0)
    }
    func testProgressAndNextLegRequireRepeatedFixes() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)]), .init(instruction: "Turn left", points: [.init(100,0), .init(100,100)])])
        var t = 0.0
        for _ in 1...3 { t += 1; p.update(.init(40,0), accuracy: 5, timestamp: t, now: t) }
        XCTAssertEqual(p.status, .guiding); XCTAssertEqual(p.remaining, 65, accuracy: 0.01)
        for x in stride(from: 44.0, through: 100.0, by: 4) { t += 1; p.update(.init(x,0), accuracy: 5, timestamp: t, now: t) }
        XCTAssertEqual(p.travelInstruction, "Turn left")
        for y in stride(from: 2.0, through: 14.0, by: 2) { t += 1; p.update(.init(100,y), accuracy: 5, timestamp: t, now: t) }
        XCTAssertEqual(p.index, 1)
    }
    func testBadTrackingAndOffRouteDoNotAdvance() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        p.update(.init(99,0), accuracy: 80, timestamp: 1, now: 1)
        XCTAssertEqual(p.status, .locating)
        p.update(.init(50,50), accuracy: 5, timestamp: 2, now: 2)
        XCTAssertEqual(p.status, .offRoute); XCTAssertEqual(p.index, 0)
        p.update(.init(99,0), accuracy: 5, timestamp: 3, now: 20)
        XCTAssertEqual(p.status, .locating)
    }
    func testFinalCheckpointDoesNotClaimArrival() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        var t = 0.0
        for _ in 0..<3 { t += 1; p.update(.init(0,0), accuracy: 2, timestamp: t, now: t) }
        for x in stride(from: 2.0, through: 100.0, by: 2) { t += 1; p.update(.init(x,0), accuracy: 2, timestamp: t, now: t) }
        for _ in 0..<3 { t += 1; p.update(.init(100,0), accuracy: 2, timestamp: t, now: t) }
        XCTAssertEqual(p.status, .nearDestination) // User still confirms the entrance.
    }
    func testBriefNoiseDoesNotPauseOrAdvance() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(40,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        p.update(.init(99,0), accuracy: 45, timestamp: 4, now: 4)
        XCTAssertEqual(p.status, .locating); XCTAssertEqual(p.remaining, 65)
        p.update(.init(99,0), accuracy: 45, timestamp: 12, now: 12)
        XCTAssertEqual(p.status, .locating)
    }
    func testModerateAccuracyCannotClaimCheckpoint() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...8 { p.update(.init(99,0), accuracy: 18, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .locating)
    }
    func testWrongWayNeedsSustainedRetreatAndClearsOnRecovery() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        var t = 0.0
        for _ in 1...3 { t += 1; p.update(.init(60,0), accuracy: 3, timestamp: t, now: t) }
        for x in stride(from: 58.0, through: 42.0, by: -2) { t += 1; p.update(.init(x,0), accuracy: 3, timestamp: t, now: t) }
        XCTAssertTrue(p.wrongWay)
        for x in stride(from: 44.0, through: 54.0, by: 2) { t += 1; p.update(.init(x,0), accuracy: 3, timestamp: t, now: t) }
        XCTAssertFalse(p.wrongWay)
    }
    func testLegTransitionKeepsGuidanceActive() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(25,0)]), .init(instruction: "Turn left", points: [.init(25,0), .init(25,40)])])
        var t = 0.0
        for _ in 0..<3 { t += 1; p.update(.init(0,0), accuracy: 2, timestamp: t, now: t) }
        for x in stride(from: 2.0, through: 24.0, by: 2) { t += 1; p.update(.init(x,0), accuracy: 2, timestamp: t, now: t) }
        XCTAssertEqual(p.travelInstruction, "Turn left")
        for y in stride(from: 2.0, through: 12.0, by: 2) { t += 1; p.update(.init(25,y), accuracy: 2, timestamp: t, now: t) }
        XCTAssertEqual(p.index, 1); XCTAssertEqual(p.status, .guiding)
    }
    func testSingleLateralJumpDoesNotTriggerRerouting() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(40,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        p.update(.init(40,40), accuracy: 5, timestamp: 4, now: 4)
        XCTAssertEqual(p.status, .guiding)
        p.update(.init(41,0), accuracy: 5, timestamp: 5, now: 5)
        XCTAssertEqual(p.status, .guiding)
        for i in 6...11 { p.update(.init(42,40), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .offRoute)
    }
    func testCampusGPSJitterDoesNotFlipTurnsOrReplaceRoute() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [.init(0,0), .init(20,2)]),
            .init(instruction: "Continue", points: [.init(20,2), .init(40,-2)]),
            .init(instruction: "Continue", points: [.init(40,-2), .init(140,0)]),
            .init(instruction: "Turn left", points: [.init(140,0), .init(140,80)])
        ])
        var t = 1.0
        for x in stride(from: 20.0, through: 80.0, by: 4) {
            p.update(.init(x, sin(x)*3), accuracy: 8, timestamp: t, now: t)
            t += 1
            if p.status == .guiding {
                XCTAssertEqual(p.travelInstruction, "Continue straight")
                XCTAssertFalse(p.shouldReplaceRoute())
            }
        }
        XCTAssertEqual(p.status, .guiding)
        XCTAssertEqual(p.travelInstruction, "Continue straight")
        XCTAssertFalse(p.shouldReplaceRoute())
    }
    func testCommittedRouteStaysUntilSustainedOffRoute() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(20,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertFalse(p.shouldReplaceRoute())
        p.update(.init(20,40), accuracy: 5, timestamp: 4, now: 4)
        XCTAssertFalse(p.shouldReplaceRoute())
        for i in 5...10 { p.update(.init(20,40), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertTrue(p.shouldReplaceRoute())
    }
    func testGPSLossRecoversOnSameLoadedRouteWithoutFalseArrival() {
        var progress = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for t in 1...3 { progress.update(.init(40,0), accuracy: 5, timestamp: Double(t), now: Double(t)) }
        XCTAssertEqual(progress.status, .guiding)
        progress.update(.init(99,0), accuracy: 5, timestamp: 3, now: 20)
        XCTAssertEqual(progress.status, .locating)
        XCTAssertEqual(progress.index, 0)
        for t in 21...23 { progress.update(.init(42,0), accuracy: 5, timestamp: Double(t), now: Double(t)) }
        XCTAssertEqual(progress.status, .guiding)
        XCTAssertEqual(progress.remaining, 63, accuracy: 0.01)
        XCTAssertEqual(progress.legs.count, 1)
    }

    func testJitterAroundTurnNeverFlipsInstructionBackwards() {
        // Straight 60 m then a right turn. GPS jitters ±6 m along the street near the corner.
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(60,0)]),
                                       .init(instruction: "Turn right onto Main St", points: [.init(60,0), .init(60,60)])])
        var t = 1.0
        for x in stride(from: 0.0, through: 56.0, by: 2) { p.update(.init(x, 0), accuracy: 6, timestamp: t, now: t); t += 1 }
        XCTAssertEqual(p.travelInstruction, "Turn right onto Main St")
        let along = p.remainingRouteDistance
        for jitter in [-6.0, 4.0, -5.0, 2.0, -6.0] {
            p.update(.init(56 + jitter, 0), accuracy: 6, timestamp: t, now: t); t += 1
            XCTAssertEqual(p.travelInstruction, "Turn right onto Main St")
            XCTAssertLessThanOrEqual(p.remainingRouteDistance, along)
        }
    }
    func testFirstFixDoesNotSnapToFarSideOfLoopingRoute() {
        // Route goes 100 m east, then comes back west 8 m north of the start.
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)]),
                                       .init(instruction: "Turn left", points: [.init(100,0), .init(100,8)]),
                                       .init(instruction: "Turn left", points: [.init(100,8), .init(0,8)])])
        for i in 1...3 { p.update(.init(2, 7), accuracy: 8, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .locating) // GPS cannot distinguish the parallel corridors.
        XCTAssertEqual(p.index, 0)
        XCTAssertGreaterThan(p.remainingRouteDistance, 190)
    }
}
