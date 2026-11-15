import XCTest
@testable import IndoorbilityCore

final class CalmSpeechTests: XCTestCase {
    func testTurnQueuesWithoutCuttingOffCurrentSentenceAndNewestQueuedTurnWins() {
        let active = PendingSpeech("Continue straight", priority: .direction, now: 0)
        let upcoming = PendingSpeech("In 10 meters, turn left", priority: .direction, now: 1)
        let atCorner = PendingSpeech("Turn left now", priority: .direction, now: 2)
        var queue = NavigationSpeechQueue()
        XCTAssertFalse(NavigationSpeechQueue.shouldInterrupt(active: active, incoming: upcoming))
        queue.push(upcoming); queue.push(atCorner)
        XCTAssertEqual(queue.next(now: 3)?.text, "Turn left now")
        XCTAssertNil(queue.next(now: 3))
    }

    func testTrackingLossImmediatelyInterruptsAndInvalidatesWaitingTurns() {
        let active = PendingSpeech("Walk straight", priority: .direction, now: 0)
        let warning = PendingSpeech("Position uncertain. Stop and check your surroundings.", priority: .safety, now: 1)
        var queue = NavigationSpeechQueue()
        queue.push(PendingSpeech("Turn right now", priority: .direction, now: 0))
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: active, incoming: warning))
        queue.push(warning)
        XCTAssertEqual(queue.next(now: 2)?.text, warning.text)
        XCTAssertNil(queue.next(now: 2))
    }

    func testMovedPastTurnOrChangedDestinationDropsQueuedSpeech() {
        var queue = NavigationSpeechQueue()
        let old = PendingSpeech("Turn left to Room 005", priority: .direction, now: 0)
        let current = PendingSpeech("Turn right to Room 006", priority: .direction, now: 1)
        queue.push(old)
        XCTAssertNil(queue.next(now: 1, isRelevant: { $0.id == current.id }))
        queue.push(current)
        XCTAssertEqual(queue.next(now: 2, isRelevant: { $0.id == current.id })?.text, current.text)
        queue.push(current)
        XCTAssertNil(queue.next(now: 7))
    }

    func testDeduplicationAndAmbientChatterDoNotSwallowExplicitRepeat() {
        var gate = SpeechAdmission()
        let turn = PendingSpeech("Turn left", priority: .direction, now: 0)
        gate.didStart(turn, now: 0)
        XCTAssertFalse(gate.allows(turn, active: nil, now: 2))
        XCTAssertFalse(gate.allows(PendingSpeech("Checking that.", priority: .ambient, now: 2), active: turn, now: 2))
        XCTAssertTrue(gate.allows(PendingSpeech("Sign review cancelled.", priority: .routine, now: 2), active: turn, now: 2))
        let repeatLine = PendingSpeech("Turn left", priority: .direction, now: 2, userRequested: true)
        XCTAssertTrue(gate.allows(repeatLine, active: turn, now: 2))
        let response = PendingSpeech("Room 005 found. Confirm this destination.", priority: .routine, now: 2, userRequested: true)
        XCTAssertTrue(gate.allows(response, active: turn, now: 2))
        let warning = PendingSpeech("Stop. Position uncertain.", priority: .safety, now: 2)
        XCTAssertTrue(gate.allows(warning, active: turn, now: 2))
        gate.didStart(warning, now: 2)
        XCTAssertFalse(gate.allows(warning, active: nil, now: 3))
        XCTAssertTrue(gate.allows(warning, active: nil, now: 5))
        gate.reset()
        XCTAssertTrue(gate.allows(turn, active: nil, now: 2))
    }

    func testDefaultStraightGuidanceDoesNotNagAfterTwelveSeconds() {
        var delivery = GuidanceDelivery()
        let straight = GuidanceMessage(id: "straight", text: "Continue straight.", cue: nil)
        XCTAssertTrue(delivery.consume(straight, listening: false, now: 0))
        for second in 1...120 { XCTAssertFalse(delivery.consume(straight, listening: false, now: Double(second))) }
        // Reminders are explicitly opt-in, and cannot interrupt listening.
        XCTAssertFalse(delivery.consume(straight, listening: true, now: 121, repeatReliable: true))
        XCTAssertTrue(delivery.consume(straight, listening: false, now: 122, repeatReliable: true))
    }

    func testTwoDifferentCornersWithTheSameWordsAreBothAnnounced() {
        var gate = SpeechAdmission()
        let first = PendingSpeech("Turn left now.", priority: .direction, now: 0, deduplicationKey: "corner-1")
        let second = PendingSpeech("Turn left now.", priority: .direction, now: 3, deduplicationKey: "corner-2")
        gate.didStart(first, now: 0)
        XCTAssertFalse(gate.allows(first, active: nil, now: 3))
        gate.forget(first.deduplicationKey) // Interrupted before it could finish.
        XCTAssertTrue(gate.allows(first, active: nil, now: 3))
        XCTAssertTrue(gate.allows(second, active: first, now: 3))
        XCTAssertTrue(gate.allows(second, active: nil, now: 3))
    }

    func testLostCurrentTurnRetriesWithoutReplayingAnObsoleteTurnOrNaggingEveryFrame() {
        var delivery = GuidanceDelivery()
        let turn = GuidanceMessage(id: "corner-1", text: "Turn left now.", cue: .turn)
        let next = GuidanceMessage(id: "straight-2", text: "Continue straight.", cue: nil)
        XCTAssertTrue(delivery.consume(turn, listening: false, now: 0))
        delivery.rearm(turn.id, now: 1)
        for i in 0..<15 { XCTAssertFalse(delivery.consume(turn, listening: false, now: 1+Double(i)*0.1)) }
        XCTAssertTrue(delivery.consume(turn, listening: false, now: 2.5))
        XCTAssertTrue(delivery.consume(next, listening: false, now: 3))
        delivery.rearm(turn.id, now: 3)
        XCTAssertFalse(delivery.consume(next, listening: false, now: 5))
        XCTAssertFalse(delivery.consume(turn, listening: false, now: 5))
    }

    func testInternalAgentLookupsAreSilentButErrorsAndCompletedActionsAreNot() {
        for tool: AgentTool in [.getNavigationState, .getAccessibilityPreferences, .getKnownClosures,
                               .getNearbyMappedDestinations, .resolveDestination, .calculateAccessibleRoute] {
            XCTAssertFalse(AgentSpeechPolicy.presentImmediately(tool: tool, status: .success))
            XCTAssertTrue(AgentSpeechPolicy.presentImmediately(tool: tool, status: .error))
        }
        for tool: AgentTool in [.changeDestination, .replanRoute, .describeCurrentView, .repeatInstruction, .addShoppingItem] {
            XCTAssertTrue(AgentSpeechPolicy.presentImmediately(tool: tool, status: .success))
        }
        for command in ["Stop!", "pause guidance", "Repeat directions.", "say that again", "where am I?"] {
            XCTAssertTrue(AgentSpeechPolicy.isImmediateLocalCommand(command, hasDestination: true))
        }
        for command in ["don't stop", "take me to the bus stop", "repeat the name of Room 005", "go to Room 005"] {
            XCTAssertFalse(AgentSpeechPolicy.isImmediateLocalCommand(command, hasDestination: true))
        }
        XCTAssertFalse(AgentSpeechPolicy.isImmediateLocalCommand("repeat", hasDestination: false))
    }
}
