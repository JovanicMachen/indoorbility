import XCTest
@testable import IndoorbilityCore

final class OutdoorTraceTests: XCTestCase {
    func testJitterAndUncertainGaps() {
        var trace = OutdoorTrace()
        trace.update(.init(0,0), accuracy: 4, timestamp: 1, now: 1)
        trace.update(.init(1,0), accuracy: 4, timestamp: 2, now: 2)
        XCTAssertEqual(trace.segments[0].count, 1)
        trace.update(.init(3,0), accuracy: 4, timestamp: 3, now: 3)
        XCTAssertEqual(trace.segments[0].count, 2)
        trace.update(.init(20,0), accuracy: 50, timestamp: 4, now: 4)
        trace.update(.init(6,0), accuracy: 4, timestamp: 5, now: 5)
        XCTAssertEqual(trace.segments.count, 2)
    }
    func testJumpAndBackgroundDoNotConnect() {
        var trace = OutdoorTrace()
        trace.update(.init(0,0), accuracy: 4, timestamp: 1, now: 1)
        trace.update(.init(200,0), accuracy: 4, timestamp: 2, now: 2)
        XCTAssertEqual(trace.segments.count, 2)
        trace.interrupt()
        trace.update(.init(202,0), accuracy: 4, timestamp: 3, now: 3)
        XCTAssertEqual(trace.segments.count, 3)
    }
    func testLongWalkIsBounded() {
        var trace = OutdoorTrace()
        for i in 1...1000 { trace.update(.init(Double(i)*3,0), accuracy: 3, timestamp: Double(i), now: Double(i)) }
        XCTAssertEqual(trace.segments.reduce(0) { $0 + $1.count }, 600)
    }
}
