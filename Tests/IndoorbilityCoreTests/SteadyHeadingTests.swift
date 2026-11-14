import XCTest
@testable import IndoorbilityCore

final class SteadyHeadingTests: XCTestCase {
    func testWobbleAndSustainedTurn() {
        var h = SteadyHeading()
        for i in 0...4 { _ = h.update(radians: 0, time: Double(i)*0.1) }
        XCTAssertEqual(h.cue, .straight)
        _ = h.update(radians: 1, time: 0.5)
        _ = h.update(radians: -1, time: 0.6)
        _ = h.update(radians: 0, time: 0.7)
        XCTAssertEqual(h.cue, .straight)
        for i in 8...12 { _ = h.update(radians: 1, time: Double(i)*0.1) }
        XCTAssertEqual(h.cue, .right)
        for i in 13...18 { _ = h.update(radians: 30 * .pi/180, time: Double(i)*0.1) }
        XCTAssertEqual(h.cue, .right)
        for i in 19...24 { _ = h.update(radians: 10 * .pi/180, time: Double(i)*0.1) }
        XCTAssertEqual(h.cue, .straight)
    }
    func testFrameBurstCannotConfirmAndLostDataClears() {
        var h = SteadyHeading()
        for i in 0...100 { _ = h.update(radians: .pi, time: Double(i)/1000) }
        XCTAssertNil(h.cue)
        _ = h.update(radians: .pi, time: 0.5)
        XCTAssertEqual(h.cue, .reverse)
        XCTAssertNil(h.update(radians: .nan, time: 0.6))
        XCTAssertNil(h.cue)
    }
    func testCountdownUsesRouteDistanceAndDoesNotInventTurn() {
        var p = OutdoorProgress(legs: [.init(instruction: "Continue", points: [.init(0,0), .init(100,0)]),
                                      .init(instruction: "Turn left", points: [.init(100,0), .init(100,100)])])
        for i in 1...3 { p.update(.init(80,0), accuracy: 5, timestamp: Double(i), now: Double(i), course: 90) }
        XCTAssertEqual(p.travelInstruction, "Continue straight")
        XCTAssertEqual(p.upcomingDetail(), "Next turn in about 20 meters")
        XCTAssertEqual(p.announcementBand, 20)
    }
}
