import Foundation

/// A prompt trigger, never evidence of being inside or aligned to an indoor map.
public enum DestinationProximity {
    /// Outdoor arrival requires completed route progress plus fresh proximity.
    /// This confirms only arrival at the outdoor destination, never an indoor pose.
    public static func canConfirmOutdoorArrival(routeComplete: Bool, distance: Double, accuracy: Double, age: Double) -> Bool {
        routeComplete && shouldOfferSavedIndoorRoute(distance: distance, accuracy: accuracy, age: age, remainingRouteDistance: 0)
    }
    /// Offers a saved map at its entrance; never confirms an indoor position.
    /// A loaded walking route must also be near its end, so a nearby entrance
    /// across a wall or on another loop does not prematurely interrupt the walk.
    public static func shouldOfferSavedIndoorRoute(distance: Double, accuracy: Double, age: Double,
                                                  remainingRouteDistance: Double?) -> Bool {
        guard distance.isFinite, accuracy.isFinite, age.isFinite,
              distance >= 0, accuracy >= 0, accuracy <= 12, age >= 0, age <= 5,
              distance + accuracy <= 30 else { return false }
        if let remainingRouteDistance {
            return remainingRouteDistance.isFinite && remainingRouteDistance >= 0 && remainingRouteDistance <= 40
        }
        return true
    }
    /// GPS can suggest outdoor directions, but cannot prove where someone is indoors.
    public static func shouldAskAboutOutdoorDirections(distance: Double, fixAccuracy: Double, pinAccuracy: Double, fixAge: Double) -> Bool {
        guard distance.isFinite, fixAccuracy.isFinite, pinAccuracy.isFinite, fixAge.isFinite,
              distance >= 0, fixAccuracy >= 0, fixAccuracy <= 30,
              pinAccuracy >= 0, pinAccuracy <= 35, fixAge >= 0, fixAge <= 10 else { return false }
        return distance - fixAccuracy - pinAccuracy > 60
    }
    public static func shouldOfferIndoorChoice(distance: Double, accuracy: Double, age: Double) -> Bool {
        distance.isFinite && accuracy.isFinite && age.isFinite &&
        distance >= 0 && distance <= 100 && accuracy >= 0 && accuracy <= 30 && age >= 0 && age <= 10
    }
}
