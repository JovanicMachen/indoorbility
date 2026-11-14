import XCTest
@testable import IndoorbilityCore

final class FriendCenterTests: XCTestCase {
    func testPublishedIdentityDoesNotCreateRoute() {
        XCTAssertEqual(FriendCenter.levels, ["LL", "L", "1", "2", "3"])
        XCTAssertTrue(FriendCenter.rooms.allSatisfy { $0.level == "LL" })
        XCTAssertFalse(FriendCenter.indoorRoutingAvailable)
    }
    func testExactRoomSearchAndUnknownRoom() {
        XCTAssertEqual(FriendCenter.search("Take me to Friend Center 006").map(\.id), ["006"])
        XCTAssertEqual(FriendCenter.search("Actually 008 instead").map(\.id), ["008"])
        XCTAssertTrue(FriendCenter.search("Room 1006").isEmpty)
        XCTAssertTrue(FriendCenter.search("Room 105").isEmpty)
        XCTAssertTrue(FriendCenter.search("Frist 006").isEmpty)
        XCTAssertTrue(FriendCenter.search("").isEmpty)
    }
    func testOCRDoesNotMatchPartialNumber() {
        XCTAssertEqual(FriendCenter.recognizedRooms(in: "CLASSROOM\n006").map(\.id), ["006"])
        XCTAssertTrue(FriendCenter.recognizedRooms(in: "1006 A006 006A").isEmpty)
    }
}
