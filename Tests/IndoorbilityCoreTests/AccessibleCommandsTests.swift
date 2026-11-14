import XCTest
@testable import IndoorbilityCore

final class AccessibleCommandsTests: XCTestCase {
    func testWholeUtterancesRejectAmbiguousOrNegatedCommands() {
        XCTAssertEqual(AccessibleCommand.parse("YES!"), .yes)
        XCTAssertEqual(AccessibleCommand.parse("Pause guidance."), .pause)
        XCTAssertNil(AccessibleCommand.parse("yes no"))
        XCTAssertNil(AccessibleCommand.parse("do not allow stairs"))
        XCTAssertNil(AccessibleCommand.parse("yesterday"))
        XCTAssertNil(AccessibleCommand.parse("yes and turn narration off"))
        XCTAssertEqual(AccessibleCommand.parse("Go to Room 204", destinations: ["204": "Room 204"]), .destination("204"))
        XCTAssertNil(AccessibleCommand.parse("Go to Room 204", destinations: ["a": "Room 204", "b": "Room 204"]))
        XCTAssertNil(AccessibleCommand.parse("Go to Room", destinations: ["204": "Room 204"]))
    }
    func testConfirmationIsScopedExpiringAndSingleUse() {
        var pending = CommandConfirmation()
        XCTAssertNil(pending.answer(yes: true, at: 0))
        pending.propose(.narration(true), question: "Enable narration?", at: 0)
        XCTAssertNil(pending.answer(yes: false, at: 1))
        XCTAssertNil(pending.answer(yes: true, at: 2))
        pending.propose(.start, question: "Start?", at: 3)
        pending.propose(.pause, question: "Pause?", at: 4)
        XCTAssertEqual(pending.answer(yes: true, at: 5), .pause)
        XCTAssertNil(pending.answer(yes: true, at: 6))
        pending.propose(.avoidStairs(false), question: "Allow stairs?", at: 7)
        XCTAssertNil(pending.answer(yes: true, at: 37))
        pending.propose(.start, question: "Start?", at: 40)
        pending.clear()
        XCTAssertNil(pending.answer(yes: true, at: 41))
    }
    func testFaceGestureRequiresNeutralAndFiresOncePerHold() {
        var gate = FaceGestureGate()
        for tick in 0...15 { XCTAssertNil(gate.update(.yes, at: Double(tick) / 10, tracked: true)) }
        for tick in 16...23 { XCTAssertNil(gate.update(nil, at: Double(tick) / 10, tracked: true)) }
        var results: [FaceGestureGate.Gesture] = []
        for tick in 24...50 { if let result = gate.update(.yes, at: Double(tick) / 10, tracked: true) { results.append(result) } }
        XCTAssertEqual(results, [.yes])
        for tick in 51...65 { XCTAssertNil(gate.update(.no, at: Double(tick) / 10, tracked: true)) }
        for tick in 66...73 { XCTAssertNil(gate.update(nil, at: Double(tick) / 10, tracked: true)) }
        for tick in 74...90 { if let result = gate.update(.no, at: Double(tick) / 10, tracked: true) { results.append(result) } }
        XCTAssertEqual(results, [.yes, .no])
    }
    func testTrackingLossAndFrameGapsDisarmFaceCommands() {
        var gate = FaceGestureGate()
        for tick in 0...10 { _ = gate.update(nil, at: Double(tick) / 10, tracked: true) }
        _ = gate.update(.yes, at: 1.1, tracked: true)
        XCTAssertNil(gate.update(.yes, at: 1.2, tracked: false))
        for tick in 13...30 { XCTAssertNil(gate.update(.yes, at: Double(tick) / 10, tracked: true)) }
        for tick in 31...40 { _ = gate.update(nil, at: Double(tick) / 10, tracked: true) }
        _ = gate.update(.yes, at: 4.1, tracked: true)
        XCTAssertNil(gate.update(.yes, at: 5, tracked: true))
        for tick in 51...65 { XCTAssertNil(gate.update(.yes, at: Double(tick) / 10, tracked: true)) }
    }
}
