import XCTest
@testable import IndoorbilityCore

final class NavigationExperienceTests: XCTestCase {
    private func destination(_ room: String, building: String) -> JourneyDestination {
        let a = ScanLandmark(label: "North entrance", kind: "entrance", position: SpatialPoint(x: 0, y: 0, z: 0))
        let b = ScanLandmark(label: room, kind: "room", position: SpatialPoint(x: 4, y: 0, z: 0))
        return JourneyDestination(route: HallwayRoute(id: UUID(), scanID: UUID(), entrance: a, room: b, path: [a.position, b.position], confirmedAt: Date()), building: building)
    }
    func testTypedAndSpokenSearchUseSameBuildingQualifiedMatches() {
        let a = destination("Room 105", building: "Friend Center"), b = destination("Room 105", building: "Other Hall")
        XCTAssertEqual(DestinationSearch.matches("Room 105 Friend Center", in: [a,b]), [a])
        XCTAssertEqual(DestinationSearch.matches("Take me to Room 105 in Friend Center please", in: [a,b]), [a])
        XCTAssertEqual(DestinationSearch.matches("Room 105", in: [a,b]).count, 2)
    }
    func testPartialNamesDoNotPrefixMatchRoomNumbers() {
        let a = destination("Room 105", building: "Friend Center"), b = destination("Room 1050", building: "Friend Center")
        XCTAssertEqual(DestinationSearch.matches("105 Fri", in: [a,b]), [a])
        XCTAssertTrue(DestinationSearch.matches("999", in: [a,b]).isEmpty)
        XCTAssertTrue(DestinationSearch.matches("", in: [a,b]).isEmpty)
    }
    func testConfirmationExpiresAndCannotRepeat() {
        var confirmation = DestinationConfirmation(); let id = UUID()
        confirmation.propose(id, now: 1)
        XCTAssertEqual(confirmation.accept(id, now: 2), id)
        XCTAssertNil(confirmation.accept(id, now: 3))
        confirmation.propose(id, now: 4)
        XCTAssertNil(confirmation.accept(id, now: 35))
    }
    func testReplacedConfirmationCannotStartOldDestination() {
        var confirmation = DestinationConfirmation(); let old = UUID(), new = UUID()
        confirmation.propose(old, now: 1); confirmation.propose(new, now: 2)
        XCTAssertFalse(confirmation.isCurrent(old, now: 3))
        XCTAssertEqual(confirmation.accept(new, now: 3), new)
    }
    func testDeclineAndNanNeverAccept() {
        var confirmation = DestinationConfirmation(); let id = UUID()
        confirmation.propose(id, now: 1); confirmation.cancel()
        XCTAssertNil(confirmation.accept(id, now: 2))
        confirmation.propose(id, now: 1)
        XCTAssertNil(confirmation.accept(id, now: .nan))
    }
    func testDepthRequiresFreshStableConfidentUprightEvidence() {
        var filter = SceneAwarenessFilter()
        for t in [1.0, 1.1] { XCTAssertNil(filter.update(distance: 1, coverage: 0.9, timestamp: t, now: t, tracking: true, upright: true)) }
        XCTAssertEqual(filter.update(distance: 1.1, coverage: 0.9, timestamp: 1.2, now: 1.2, tracking: true, upright: true), 1.1)
        XCTAssertNil(filter.update(distance: 1, coverage: 0.9, timestamp: 1.3, now: 1.3, tracking: true, upright: true))
        XCTAssertNil(filter.update(distance: 1, coverage: 0.9, timestamp: 2, now: 3, tracking: true, upright: true))
    }
    func testDepthRejectsLossLowConfidenceTiltNilAndDuplicateFrames() {
        var filter = SceneAwarenessFilter()
        for _ in 0..<5 { XCTAssertNil(filter.update(distance: 1, coverage: 1, timestamp: 1, now: 1, tracking: true, upright: true)) }
        XCTAssertNil(filter.update(distance: 1, coverage: 0.2, timestamp: 2, now: 2, tracking: true, upright: true))
        XCTAssertNil(filter.update(distance: 1, coverage: 1, timestamp: 3, now: 3, tracking: false, upright: true))
        XCTAssertNil(filter.update(distance: 1, coverage: 1, timestamp: 4, now: 4, tracking: true, upright: false))
        XCTAssertNil(filter.update(distance: nil, coverage: 1, timestamp: 5, now: 5, tracking: true, upright: true))
    }
    func testCameraDescriptionRejectsMovedTurnedOrStaleCapture() {
        XCTAssertTrue(SceneObservationValidity.isFresh(capturedAt: 1, now: 1.5, movement: 0.1, forwardAgreement: 1))
        XCTAssertFalse(SceneObservationValidity.isFresh(capturedAt: 1, now: 3, movement: 0, forwardAgreement: 1))
        XCTAssertFalse(SceneObservationValidity.isFresh(capturedAt: 1, now: 1.5, movement: 0.5, forwardAgreement: 1))
        XCTAssertFalse(SceneObservationValidity.isFresh(capturedAt: 1, now: 1.5, movement: 0, forwardAgreement: 0.5))
    }
    func testExplicitWrongBuildingCannotResolveAgainstCurrentMap() {
        XCTAssertFalse(BuildingQualifier.matches("Room 105 in Other Hall", building: "Friend Center"))
        XCTAssertTrue(BuildingQualifier.matches("Room 105 in Friend Center, avoid stairs please", building: "Friend Center"))
        XCTAssertTrue(BuildingQualifier.matches("Room 105 instead", building: "Friend Center"))
    }
    func testFloorIsExplicitNotDerivedFromRoom() throws {
        let value = VerifiedRoomMetadata(buildingID: UUID(), roomID: UUID(), floorLabel: "Mezzanine")
        XCTAssertEqual(value.floorLabel, "Mezzanine"); XCTAssertEqual(value.source, "manually-confirmed")
        XCTAssertEqual(try JSONDecoder().decode(VerifiedRoomMetadata.self, from: JSONEncoder().encode(value)), value)
    }
}
