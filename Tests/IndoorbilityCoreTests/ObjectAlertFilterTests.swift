import XCTest
@testable import IndoorbilityCore
final class ObjectAlertFilterTests: XCTestCase {
    func testRequiresRepeatedEvidenceAndCooldown() {
        var f = ObjectAlertFilter()
        XCTAssertFalse(f.update(kind: "person", capturedAt: 1, now: 1, reliable: true))
        XCTAssertTrue(f.update(kind: "person", capturedAt: 2, now: 2, reliable: true))
        XCTAssertFalse(f.update(kind: "person", capturedAt: 3, now: 3, reliable: true))
        XCTAssertFalse(f.update(kind: "table", capturedAt: 10, now: 10, reliable: true))
        XCTAssertTrue(f.update(kind: "table", capturedAt: 11, now: 11, reliable: true))
    }
    func testADifferentObjectIsAnnouncedSoonerThanARepeat() {
        var f = ObjectAlertFilter()
        _ = f.update(kind: "chair", capturedAt: 1, now: 1, reliable: true)
        XCTAssertTrue(f.update(kind: "chair", capturedAt: 2, now: 2, reliable: true))
        _ = f.update(kind: "table", capturedAt: 3, now: 3, reliable: true)
        XCTAssertFalse(f.update(kind: "table", capturedAt: 4, now: 4, reliable: true)) // 2 s: too soon
        XCTAssertTrue(f.update(kind: "table", capturedAt: 5, now: 5, reliable: true))  // 3 s: new object
        XCTAssertFalse(f.update(kind: "table", capturedAt: 6, now: 6, reliable: true)) // same object again
    }
    func testStaleUnreliableMissingOrDuplicateEvidenceCannotAlert() {
        var f = ObjectAlertFilter()
        XCTAssertFalse(f.update(kind: "person", capturedAt: 1, now: 3, reliable: true))
        XCTAssertFalse(f.update(kind: "person", capturedAt: 3, now: 3, reliable: false))
        XCTAssertFalse(f.update(kind: "person", capturedAt: 4, now: 4, reliable: true))
        XCTAssertFalse(f.update(kind: "person", capturedAt: 4, now: 4, reliable: true))
        XCTAssertFalse(f.update(kind: nil, capturedAt: 5, now: 5, reliable: true))
        XCTAssertFalse(f.update(kind: "person", capturedAt: 6, now: 6, reliable: true))
        XCTAssertFalse(f.update(kind: "table", capturedAt: 7, now: 7, reliable: true))
    }
}
