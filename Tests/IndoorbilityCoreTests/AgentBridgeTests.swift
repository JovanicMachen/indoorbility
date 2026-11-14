import XCTest
@testable import IndoorbilityCore

final class AgentBridgeTests: XCTestCase {
    func testStaleSessionAndRevisionRejected() throws {
        var ledger = AgentExecutionLedger(sessionId: "navigation")
        let call = AgentCall(callId: "one", tool: .changeDestination, expectedRevision: 0, sessionId: "navigation")
        XCTAssertNil(try ledger.validate(call))
        ledger.invalidate()
        XCTAssertThrowsError(try ledger.validate(call))
        XCTAssertThrowsError(try ledger.validate(AgentCall(callId: "two", tool: .changeDestination, expectedRevision: 1, sessionId: "other-session")))
    }
    func testIdempotencyReturnsActualResultAndRejectsChangedArguments() throws {
        var ledger = AgentExecutionLedger(sessionId: "navigation")
        let call = AgentCall(callId: "one", tool: .changeDestination, argument: "105", expectedRevision: 0, sessionId: "navigation")
        ledger.invalidate()
        let result = AgentToolResult(callId: "one", sessionRevision: 1, status: .success, userSafeExplanation: "Changed")
        ledger.record(call, result: result)
        XCTAssertEqual(try ledger.validate(call), result)
        XCTAssertThrowsError(try ledger.validate(AgentCall(callId: "one", tool: .changeDestination, argument: "106", expectedRevision: 0, sessionId: "navigation")))
    }
    func testUnknownToolsFailDecoding() {
        let json = #"{"callId":"x","tool":"inventSafeRoute","argument":"","expectedRevision":0,"sessionId":"s"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(AgentCall.self, from: Data(json.utf8)))
    }
    func testShoppingMemoryPersistsUnknownItemsWithoutLocations() throws {
        var memory = AgentTaskMemory()
        try memory.add("Bananas"); try memory.add("bananas")
        XCTAssertEqual(memory.items, ["bananas"])
        let restored = try JSONDecoder().decode(AgentTaskMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(restored, memory)
        XCTAssertThrowsError(try memory.add(""))
    }
}
