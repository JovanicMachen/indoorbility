import XCTest
@testable import IndoorbilityCore

final class GeneralAssistantTests: XCTestCase {
    func testGeneralQuestionsAndLiveRequestsUseDifferentPathsIncludingFollowups() throws {
        struct Example: Decodable { let text: String; let followsGeneral: Bool?; let general: Bool }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/general_assistant_cases.json")
        let examples = try JSONDecoder().decode([Example].self, from: Data(contentsOf: file))
        for example in examples {
            XCTAssertEqual(GeneralQuestionPolicy.isGeneral(example.text, followsGeneral: example.followsGeneral ?? false),
                           example.general, example.text)
        }
    }
    func testGeneralAnswerCannotBecomeARouteInstructionOrExecutedAction() throws {
        let valid = #"{"kind":"general","answer":"LiDAR measures distance using light.","responseCallId":null,"clarification":"none"}"#
        let answer = try JSONDecoder().decode(AgentFinalResponse.self, from: Data(valid.utf8))
        XCTAssertEqual(try answer.validatedGeneralAnswer(for: "What is LiDAR?", followsGeneral: false), "LiDAR measures distance using light.")
        XCTAssertThrowsError(try answer.validatedGeneralAnswer(for: "Take me to Room 005", followsGeneral: true))
        for text in ["Turn left now.", "Walk straight for 10 meters.", "You have arrived at Room 005.", "I changed your destination.", "I can see a chair."] {
            XCTAssertFalse(GeneralQuestionPolicy.acceptsAnswer(text), text)
        }
        let actionClaim = valid.replacingOccurrences(of: "null", with: #""fake-device-action""#)
        let invalid = try JSONDecoder().decode(AgentFinalResponse.self, from: Data(actionClaim.utf8))
        XCTAssertThrowsError(try invalid.validatedGeneralAnswer(for: "What is LiDAR?", followsGeneral: false))
        XCTAssertFalse(GeneralQuestionPolicy.acceptsAnswer(String(repeating: "a", count: 651)))
        XCTAssertFalse(GeneralQuestionPolicy.acceptsAnswer("  "))
    }
    func testLegacyNavigationReplyIsCompatibleButNotRenderedAsGeneralSpeech() throws {
        let data = Data(#"{"responseCallId":"actual-device-call","clarification":"none"}"#.utf8)
        let reply = try JSONDecoder().decode(AgentFinalResponse.self, from: data)
        XCTAssertEqual(reply.responseCallId, "actual-device-call")
        XCTAssertNil(reply.kind)
        XCTAssertThrowsError(try reply.validatedGeneralAnswer(for: "What is LiDAR?", followsGeneral: false))
    }
    func testConversationRetainsOnlyThreePairsAndDoesNotPersistNavigationEvidence() {
        var conversation = GeneralConversation()
        for i in 0..<5 { conversation.append(question: "Question \(i)", answer: "Answer \(i)") }
        XCTAssertEqual(conversation.messages.count, 6)
        XCTAssertEqual(conversation.messages.first?.content, "Question 2")
        XCTAssertEqual(conversation.messages.last?.content, "Answer 4")
        for (i, message) in conversation.messages.enumerated() { XCTAssertEqual(message.role, i % 2 == 0 ? .user : .assistant) }
        conversation.clear()
        XCTAssertTrue(conversation.messages.isEmpty)
    }
    func testGeneralAnswerYieldsToNavigationWithoutMakingOrdinaryTurnsInterruptEachOther() {
        let answer = PendingSpeech("AI answer. LiDAR uses light.", priority: .ambient, now: 0, userRequested: true)
        let turn = PendingSpeech("Turn left now.", priority: .direction, now: 1)
        let warning = PendingSpeech("Position uncertain.", priority: .safety, now: 1)
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: answer, incoming: turn))
        XCTAssertTrue(NavigationSpeechQueue.shouldInterrupt(active: answer, incoming: warning))
        XCTAssertFalse(NavigationSpeechQueue.shouldInterrupt(active: turn, incoming: PendingSpeech("Continue straight.", priority: .direction, now: 2)))
    }
}
