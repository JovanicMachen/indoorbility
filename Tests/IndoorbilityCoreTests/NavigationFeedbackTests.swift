import XCTest
@testable import IndoorbilityCore
final class NavigationFeedbackTests: XCTestCase {
    func testSafetyFirstThenFreshDirection() {
        var queue = NavigationSpeechQueue()
        queue.push(PendingSpeech("Turn left", priority: .direction, now: 1))
        queue.push(PendingSpeech("Possible drop", priority: .safety, now: 2))
        XCTAssertEqual(queue.next(now: 3)?.text, "Possible drop")
        XCTAssertEqual(queue.next(now: 4)?.text, "Turn left")
        XCTAssertNil(queue.next(now: 5))
    }
    func testInterruptedTurnCannotReplaceNewerTurn() {
        var queue = NavigationSpeechQueue()
        queue.push(PendingSpeech("New turn", priority: .direction, now: 2))
        queue.resumeInterrupted(PendingSpeech("Old turn", priority: .direction, now: 1))
        XCTAssertEqual(queue.next(now: 3)?.text, "New turn")
        XCTAssertNil(queue.next(now: 3))
    }
    func testExpiryReplacementAndReset() {
        var queue = NavigationSpeechQueue()
        queue.push(PendingSpeech("Old turn", priority: .direction, now: 1))
        queue.push(PendingSpeech("New turn", priority: .direction, now: 2))
        XCTAssertEqual(queue.next(now: 3)?.text, "New turn")
        XCTAssertNil(queue.next(now: 3))
        queue.push(PendingSpeech("Warning", priority: .safety, now: 3))
        XCTAssertNil(queue.next(now: 10))
        queue.push(PendingSpeech("Turn", priority: .direction, now: 10))
        queue.clear(); XCTAssertNil(queue.next(now: 11))
    }
    func testPostureDwellRecoveryAndRepeat() {
        var coach = PhoneCoach()
        XCTAssertNil(coach.update(pitch: -40, roll: 0, now: 1))
        XCTAssertNil(coach.update(pitch: -40, roll: 0, now: 1.5))
        XCTAssertNotNil(coach.update(pitch: -40, roll: 0, now: 2))
        XCTAssertNil(coach.update(pitch: -25, roll: 0, now: 3))
        XCTAssertNotNil(coach.issue)
        XCTAssertNil(coach.update(pitch: 0, roll: 0, now: 4))
        XCTAssertEqual(coach.update(pitch: 0, roll: 0, now: 5), "Phone position is better.")
        XCTAssertNil(coach.issue)
    }
    func testMissingFloorAndSparseDepthNeverMeanClear() {
        XCTAssertEqual(FloorAssessment.evaluate(floor: nil, samples: []), .unknown)
        XCTAssertEqual(FloorAssessment.evaluate(floor: 0, samples: []), .unknown)
        XCTAssertEqual(FloorAssessment.evaluate(floor: 0, samples: [.init(ahead: 1, height: -1)]), .unknown)
        let observed = [Float(0.5), 0.75, 1, 1.25].map { FloorDepthSample(ahead: $0, height: 0) }
        XCTAssertEqual(FloorAssessment.evaluate(floor: 0, samples: observed), .observed)
        let drops = (0..<8).map { FloorDepthSample(ahead: 0.6 + Float($0)*0.1, height: -0.3) }
        XCTAssertEqual(FloorAssessment.evaluate(floor: 0, samples: drops), .possibleDrop)
        XCTAssertEqual(FloorAssessment.evaluate(floor: nil, samples: drops), .unknown)
    }
}
