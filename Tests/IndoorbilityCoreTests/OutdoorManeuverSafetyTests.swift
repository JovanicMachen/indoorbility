import XCTest
@testable import IndoorbilityCore

/// Synthetic fixtures validate route decisions, not real-world GPS accuracy.
final class OutdoorManeuverSafetyTests: XCTestCase {
    private typealias P = OutdoorProgress.Point
    func testProviderTurnNearStartRemainsUntilMeasuredExit() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [P(0,0), P(8,0)]),
            .init(instruction: "Turn left onto Oak Walk", points: [P(8,0), P(8,30)])])
        var time = 0.0
        func update(_ x: Double, _ y: Double) { time += 1; p.update(P(x,y), accuracy: 1, timestamp: time, now: time) }
        for _ in 0..<3 { update(0,0) }
        XCTAssertEqual(p.travelInstruction, "Turn left onto Oak Walk")
        for x in [2.0, 4, 6, 7, 8] { update(x,0) }
        for _ in 0..<3 { update(8,0) }
        XCTAssertEqual(p.travelInstruction, "Turn left onto Oak Walk")
        for y in [2.0, 4, 6, 7] { update(8,y) }
        XCTAssertEqual(p.travelInstruction, "Continue straight")
    }
    func testProviderRightTurnAdvancesOnlyAfterTheCorner() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [P(0,0),P(10,0)]),
            .init(instruction: "Turn right onto Main Street", points: [P(10,0),P(10,-30)])])
        var time = 0.0
        func update(_ x: Double, _ y: Double) { time += 1; p.update(P(x,y), accuracy: 1, timestamp: time, now: time) }
        for _ in 0..<3 { update(0,0) }
        for x in [2.0,4,6,8,10] { update(x,0) }
        XCTAssertEqual(p.travelInstruction, "Turn right onto Main Street")
        for y in [-2.0,-4,-6,-7] { update(10,y) }
        XCTAssertEqual(p.travelInstruction, "Continue straight")
    }
    func testStraightRouteDoesNotInventTurnsFromWobble() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [P(0,0), P(10,1), P(20,-1), P(30,0)])])
        for i in 0..<20 { let t = Double(i+1); p.update(P(Double(i),0), accuracy: 2, timestamp: t, now: t); if p.status == .guiding { XCTAssertEqual(p.travelInstruction, "Continue straight") } }
    }
    func testAmbiguousParallelPathPauses() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [P(0,0),P(40,0)]),
            .init(instruction: "Turn left", points: [P(40,0),P(40,6)]),
            .init(instruction: "Turn left", points: [P(40,6),P(0,6)])])
        for i in 1...4 { p.update(P(2,3), accuracy: 5, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.status, .locating)
        XCTAssertGreaterThan(p.remainingRouteDistance, 80)
    }
    func testBadFixAndStationaryDriftCannotCompleteTurn() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [P(0,0),P(12,0)]),
            .init(instruction: "Turn right onto Elm Walk", points: [P(12,0),P(12,30)])])
        var t = 0.0
        func update(_ x: Double, _ y: Double, _ accuracy: Double) { t += 1; p.update(P(x,y), accuracy: accuracy, timestamp: t, now: t) }
        for _ in 0..<3 { update(0,0,2) }
        for x in [2.0,4,6,8,10,12] { update(x,0,2) }
        update(12,12,30)
        XCTAssertEqual(p.status, .locating)
        for y in [1.0,-1,1,-1,1] { update(12,y,2) }
        XCTAssertEqual(p.travelInstruction, "Turn right onto Elm Walk")
    }
    func testArrivalSideIsNotAnInventedTurn() {
        var p = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [P(0,0),P(10,0)]),
            .init(instruction: "Your destination is on the left", points: [P(10,0),P(20,0)])])
        for i in 1...3 { p.update(P(0,0), accuracy: 1, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(p.travelInstruction, "Continue straight")
        XCTAssertNil(p.nextInstruction)
    }
    func testGpsJumpDoesNotAdvance() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [P(0,0),P(100,0)])])
        for i in 1...3 { p.update(P(0,0), accuracy: 2, timestamp: Double(i), now: Double(i)) }
        p.update(P(70,0), accuracy: 2, timestamp: 4, now: 4)
        XCTAssertNotEqual(p.status, .nearDestination)
        XCTAssertGreaterThan(p.remainingRouteDistance, 90)
    }
}
