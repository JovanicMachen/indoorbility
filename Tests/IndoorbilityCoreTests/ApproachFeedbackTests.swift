import XCTest
@testable import IndoorbilityCore
final class ApproachFeedbackTests: XCTestCase {
    func testNoiseDoesNotGlow() {
        var feedback = ApproachFeedback()
        for t in 1...20 {
            feedback.update(distance: t.isMultiple(of: 2) ? 100 : 103, accuracy: 5, timestamp: Double(t), now: Double(t))
            XCTAssertEqual(feedback.trend, .steady)
        }
    }
    func testCloserAndFartherNeedRepeatedEvidence() {
        var feedback = ApproachFeedback()
        feedback.update(distance: 100, accuracy: 2, timestamp: 1, now: 1)
        feedback.update(distance: 96, accuracy: 2, timestamp: 2, now: 2)
        XCTAssertEqual(feedback.trend, .steady)
        feedback.update(distance: 95, accuracy: 2, timestamp: 3, now: 3)
        XCTAssertEqual(feedback.trend, .closer)
        feedback.update(distance: 99, accuracy: 2, timestamp: 4, now: 4)
        feedback.update(distance: 100, accuracy: 2, timestamp: 5, now: 5)
        XCTAssertEqual(feedback.trend, .farther)
        feedback.update(distance: 100, accuracy: 2, timestamp: 11, now: 11)
        XCTAssertEqual(feedback.trend, .steady)
    }
    func testStaleOrInaccurateFixClearsGlow() {
        var feedback = ApproachFeedback()
        for t in 1...3 { feedback.update(distance: 100-Double(t)*5, accuracy: 2, timestamp: Double(t), now: Double(t)) }
        XCTAssertEqual(feedback.trend, .closer)
        feedback.update(distance: 80, accuracy: 2, timestamp: 3, now: 10)
        XCTAssertEqual(feedback.trend, .steady)
        feedback.update(distance: 80, accuracy: 30, timestamp: 11, now: 11)
        XCTAssertEqual(feedback.trend, .steady)
    }
    func testRemainingDistanceIncludesLaterLegs() {
        var progress = OutdoorProgress(legs: [
            .init(instruction: "Continue", points: [.init(0,0), .init(100,0)]),
            .init(instruction: "Left", points: [.init(100,0), .init(100,50)])])
        for t in 1...3 { progress.update(.init(40,0), accuracy: 5, timestamp: Double(t), now: Double(t)) }
        XCTAssertEqual(progress.remainingRouteDistance, 110, accuracy: 0.01)
    }
}
