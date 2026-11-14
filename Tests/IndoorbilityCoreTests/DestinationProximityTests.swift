import XCTest
@testable import IndoorbilityCore

final class DestinationProximityTests: XCTestCase {
    func testOutdoorArrivalRequiresRouteCompletionAndReliableProximity() {
        XCTAssertTrue(DestinationProximity.canConfirmOutdoorArrival(routeComplete: true, distance: 5, accuracy: 8, age: 1))
        XCTAssertFalse(DestinationProximity.canConfirmOutdoorArrival(routeComplete: false, distance: 1, accuracy: 5, age: 1))
        XCTAssertFalse(DestinationProximity.canConfirmOutdoorArrival(routeComplete: true, distance: 80, accuracy: 5, age: 1))
        XCTAssertFalse(DestinationProximity.canConfirmOutdoorArrival(routeComplete: true, distance: 5, accuracy: 25, age: 1))
        XCTAssertFalse(DestinationProximity.canConfirmOutdoorArrival(routeComplete: true, distance: 5, accuracy: 8, age: 8))
    }
    func testSavedIndoorRouteIsOfferedNearEntranceWithOrWithoutOutdoorRoute() {
        XCTAssertTrue(DestinationProximity.shouldOfferSavedIndoorRoute(distance: 20, accuracy: 10, age: 2, remainingRouteDistance: 25))
        XCTAssertTrue(DestinationProximity.shouldOfferSavedIndoorRoute(distance: 10, accuracy: 5, age: 1, remainingRouteDistance: nil))
        XCTAssertTrue(DestinationProximity.shouldOfferSavedIndoorRoute(distance: 0, accuracy: 12, age: 5, remainingRouteDistance: 0))
    }
    func testSavedIndoorOfferDoesNotSkipLongRoutePastNearbyEntrance() {
        XCTAssertFalse(DestinationProximity.shouldOfferSavedIndoorRoute(distance: 10, accuracy: 5, age: 1, remainingRouteDistance: 100))
        for remaining in [Double.nan, .infinity, -1] {
            XCTAssertFalse(DestinationProximity.shouldOfferSavedIndoorRoute(distance: 10, accuracy: 5, age: 1, remainingRouteDistance: remaining))
        }
    }
    func testSavedIndoorOfferRejectsUncertainStaleOrInvalidProximity() {
        for sample in [(21.0, 10.0, 1.0), (1, 13, 1), (1, 5, 6),
                       (-1, 5, 1), (1, -1, 1), (1, 5, -1),
                       (.nan, 5, 1), (1, .infinity, 1), (1, 5, .nan)] {
            XCTAssertFalse(DestinationProximity.shouldOfferSavedIndoorRoute(distance: sample.0, accuracy: sample.1, age: sample.2, remainingRouteDistance: nil))
        }
    }
    func testFreshNearbyFixOffersChoice() {
        XCTAssertTrue(DestinationProximity.shouldOfferIndoorChoice(distance: 40, accuracy: 15, age: 2))
    }
    func testOutdoorStartSuggestionRequiresFreshAccurateEvidence() {
        XCTAssertTrue(DestinationProximity.shouldAskAboutOutdoorDirections(distance: 150, fixAccuracy: 10, pinAccuracy: 10, fixAge: 2))
        XCTAssertFalse(DestinationProximity.shouldAskAboutOutdoorDirections(distance: 2000, fixAccuracy: 10, pinAccuracy: 10, fixAge: 11))
        XCTAssertFalse(DestinationProximity.shouldAskAboutOutdoorDirections(distance: 150, fixAccuracy: 65, pinAccuracy: 10, fixAge: 2))
        XCTAssertFalse(DestinationProximity.shouldAskAboutOutdoorDirections(distance: 80, fixAccuracy: 20, pinAccuracy: 20, fixAge: 2))
        XCTAssertFalse(DestinationProximity.shouldAskAboutOutdoorDirections(distance: .nan, fixAccuracy: 10, pinAccuracy: 10, fixAge: 2))
    }
    func testFarStaleOrUncertainFixDoesNotOfferChoice() {
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 101, accuracy: 10, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: 80, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: 10, age: 11))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: .nan, accuracy: 10, age: 1))
        XCTAssertFalse(DestinationProximity.shouldOfferIndoorChoice(distance: 10, accuracy: -1, age: 1))
    }
}
