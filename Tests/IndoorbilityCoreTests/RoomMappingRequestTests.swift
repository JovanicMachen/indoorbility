import XCTest
@testable import IndoorbilityCore

final class RoomMappingRequestTests: XCTestCase {
    func testAttachedBuildingAndRoom() {
        XCTAssertEqual(RoomMappingRequest.attached("Earl Hall 112"), RoomMappingRequest(building: "Earl Hall", room: "112"))
        XCTAssertEqual(RoomMappingRequest.attached("take me to Engineering building room 156"), RoomMappingRequest(building: "Engineering building", room: "156"))
        XCTAssertEqual(RoomMappingRequest.attached("Science Library room one hundred twelve")?.room, "112")
        XCTAssertEqual(RoomMappingRequest.resolve("Earl Hall 112", selectedBuilding: FriendCenter.name)?.building, "Earl Hall")
        XCTAssertNil(RoomMappingRequest.attached("112 Main Street"))
        XCTAssertNil(RoomMappingRequest.attached("Earl Hall 112 or 156"))
        XCTAssertNil(RoomMappingRequest.attached("Earl Hall room"))
        XCTAssertNil(RoomMappingRequest.attached("Earl Hall 112")?.verifiedFloor)
    }
    func testAnyRoomUsesSelectedBuilding() {
        XCTAssertEqual(RoomMappingRequest.resolve("112", selectedBuilding: FriendCenter.name)?.room, "112")
        XCTAssertEqual(RoomMappingRequest.resolve("take me to room 156", selectedBuilding: "Library")?.building, "Library")
        XCTAssertEqual(RoomMappingRequest.resolve("one hundred twelve", selectedBuilding: "Library")?.room, "112")
        XCTAssertNil(RoomMappingRequest.resolve("156", selectedBuilding: nil))
        XCTAssertNil(RoomMappingRequest.resolve("Frist 112", selectedBuilding: FriendCenter.name))
        XCTAssertNil(RoomMappingRequest.resolve("112 or 156", selectedBuilding: FriendCenter.name))
        XCTAssertNil(RoomMappingRequest.resolve("112", selectedBuilding: FriendCenter.name)?.verifiedFloor)
    }
    func testUnknownRoomKeepsBuildingButDoesNotInventFloor() {
        let request = RoomMappingRequest.friend("Friend Center 005")
        XCTAssertEqual(request?.building, FriendCenter.name)
        XCTAssertEqual(request?.room, "005")
        XCTAssertNil(request?.verifiedFloor)
    }
    func testCasualWalkingRequest() {
        XCTAssertEqual(RoomMappingRequest.friend("Walk me to 005 Friend Center")?.room, "005")
        XCTAssertEqual(RoomMappingRequest.resolve("guide me to room six please", selectedBuilding: "Library")?.room, "6")
        XCTAssertNil(RoomMappingRequest.friend("Walk me to 005 Friend Circle"))
    }
    func testSpokenAliasAndDigits() {
        XCTAssertEqual(RoomMappingRequest.friend("frend center zero zero five")?.room, "005")
        XCTAssertEqual(RoomMappingRequest.friend("Friend Center 006")?.verifiedFloor, "LL")
    }
    func testOtherBuildingAndMissingRoomAreNotAssumed() {
        XCTAssertNil(RoomMappingRequest.friend("Frist 005"))
        XCTAssertNil(RoomMappingRequest.friend("Friend Center"))
        XCTAssertNil(RoomMappingRequest.friend("005"))
    }
}
