import XCTest
@testable import IndoorbilityCore
final class OutdoorProgressTests: XCTestCase {
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
        p.update(.init(99,0), accuracy: 30, timestamp: 4, now: 4)
        XCTAssertEqual(p.status, .guiding); XCTAssertEqual(p.remaining, 60)
        p.update(.init(99,0), accuracy: 30, timestamp: 7, now: 7)
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
        for i in 6...8 { p.update(.init(42,40), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .offRoute)
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

}
