import XCTest
@testable import IndoorbilityCore

final class SpokenPlaceTests: XCTestCase {
    private func destination(_ room: String, building: String) -> JourneyDestination {
        let a = ScanLandmark(label: "Front door", kind: "entrance", position: SpatialPoint(x: 0, y: 0, z: 0))
        let b = ScanLandmark(label: room, kind: "room", position: SpatialPoint(x: 4, y: 0, z: 0))
        return JourneyDestination(route: HallwayRoute(id: UUID(), scanID: UUID(), entrance: a, room: b, path: [a.position, b.position], confirmedAt: Date()), building: building)
    }
    func testMisheardNameFindsTheKnownPlace() {
        let armstrong = destination("Louis Armstrong Lounge", building: "Student Center")
        let library = destination("Main Library", building: "Firestone")
        XCTAssertEqual(DestinationSearch.matches("I want to go to louis rm strng lounge", in: [armstrong, library]), [armstrong])
        XCTAssertEqual(DestinationSearch.matches("take me to louie armstrong", in: [armstrong, library]), [armstrong])
        XCTAssertEqual(SpokenPlaceMatch.correct("louis rm strng", names: ["Louis Armstrong", "Lewis Library"]), "Louis Armstrong")
    }
    func testRoomNumbersNeverFuzzyMatch() {
        let a = destination("Room 105", building: "Friend Center")
        XCTAssertTrue(DestinationSearch.matches("Room 106 Friend Center", in: [a]).isEmpty)
    }
    func testUnclearOrShortSpeechIsNotGuessed() {
        let a = destination("Lab", building: "Frick"), b = destination("Lobby", building: "Frick")
        XCTAssertTrue(DestinationSearch.matches("lib", in: [a, b]).isEmpty)
        XCTAssertNil(SpokenPlaceMatch.correct("something unrelated", names: ["Louis Armstrong"]))
        // Two equally close names: ask instead of picking one.
        XCTAssertNil(SpokenPlaceMatch.correct("jonson hall", names: ["Johnson Hall", "Jonsen Hall"]))
    }
    func testNearestRecordedStartIsPreferred() {
        XCTAssertEqual(RouteChoice.ranked([120, 15, nil], fixAccuracy: 8), [1, 0, 2])
        // Within GPS error the saved order (reviews, visits) is kept.
        XCTAssertEqual(RouteChoice.ranked([20, 18], fixAccuracy: 10), [0, 1])
        // No trustworthy fix: keep the saved order.
        XCTAssertEqual(RouteChoice.ranked([120, 15], fixAccuracy: nil), [0, 1])
        XCTAssertEqual(RouteChoice.ranked([120, 15], fixAccuracy: 200), [0, 1])
    }
}
