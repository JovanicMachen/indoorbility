import XCTest
@testable import IndoorbilityCore

final class DestinationProximityTests: XCTestCase {
    func testFreshNearbyFixOffersChoice() {
        XCTAssertTrue(DestinationProximity.shouldOfferIndoorChoice(distance: 40, accuracy: 15, age: 2))
    }
    func testFarStaleOrUncertainFixDoesNotOfferChoice() {
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 101, accuracy: 10, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: 80, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: 10, age: 11))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: .nan, accuracy: 10, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: -1, age: 1))
    }
}
