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
        for i in 1...3 { p.update(.init(40,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .guiding); XCTAssertEqual(p.remaining, 60, accuracy: 0.01)
        for i in 4...6 { p.update(.init(99,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.index, 1); XCTAssertEqual(p.instruction, "Turn left")
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
        for i in 1...5 { p.update(.init(99,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .nearDestination)
    }
    func testBriefNoiseDoesNotPauseOrAdvance() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(40,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        p.update(.init(99,0), accuracy: 45, timestamp: 4, now: 4)
        XCTAssertEqual(p.status, .guiding); XCTAssertEqual(p.remaining, 60)
        p.update(.init(99,0), accuracy: 45, timestamp: 12, now: 12)
        XCTAssertEqual(p.status, .locating)
    }
    func testModerateAccuracyCannotClaimCheckpoint() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...8 { p.update(.init(99,0), accuracy: 18, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .guiding)
    }
    func testWrongWayNeedsSustainedRetreatAndClearsOnRecovery() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)])])
        for i in 1...3 { p.update(.init(60,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        p.update(.init(44,0), accuracy: 5, timestamp: 4, now: 4)
        XCTAssertFalse(p.wrongWay)
        p.update(.init(43,0), accuracy: 5, timestamp: 5, now: 5)
        p.update(.init(42,0), accuracy: 5, timestamp: 6, now: 6)
        XCTAssertTrue(p.wrongWay)
        p.update(.init(49,0), accuracy: 5, timestamp: 7, now: 7)
        XCTAssertFalse(p.wrongWay)
    }
    func testLegTransitionKeepsGuidanceActive() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)]), .init(instruction: "Left", points: [.init(100,0), .init(100,100)])])
        for i in 1...5 { p.update(.init(99,0), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.index, 1); XCTAssertEqual(p.status, .guiding); XCTAssertEqual(p.remaining, 100)
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
            .init(instruction: "Turn right", points: [.init(0,0), .init(20,2)]),
            .init(instruction: "Turn left", points: [.init(20,2), .init(40,-2)]),
            .init(instruction: "Continue", points: [.init(40,-2), .init(140,0)]),
            .init(instruction: "Turn left", points: [.init(140,0), .init(140,80)])
        ])
        var t = 1.0
        for x in stride(from: 20.0, through: 80.0, by: 4) {
            p.update(.init(x, sin(x)*12), accuracy: 8, timestamp: t, now: t)
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
        XCTAssertEqual(progress.remaining, 58, accuracy: 0.01)
        XCTAssertEqual(progress.legs.count, 1)
    }

    func testJitterAroundTurnNeverFlipsInstructionBackwards() {
        // Straight 60 m then a right turn. GPS jitters ±6 m along the street near the corner.
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(60,0)]),
                                       .init(instruction: "Turn right onto Main St", points: [.init(60,0), .init(60,60)])])
        var t = 1.0
        for x in stride(from: 0.0, through: 50.0, by: 2) { p.update(.init(x, 0), accuracy: 6, timestamp: t, now: t); t += 1 }
        XCTAssertEqual(p.travelInstruction, "Turn right onto Main St")
        let along = p.remainingRouteDistance
        for jitter in [-6.0, 4.0, -5.0, 2.0, -6.0] {
            p.update(.init(50 + jitter, 0), accuracy: 6, timestamp: t, now: t); t += 1
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
        XCTAssertEqual(p.status, .guiding)
        XCTAssertEqual(p.index, 0)
        XCTAssertGreaterThan(p.remainingRouteDistance, 190)
    }
}
