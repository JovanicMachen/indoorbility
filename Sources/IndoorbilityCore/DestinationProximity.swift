import Foundation

/// A prompt trigger, never evidence of being inside or aligned to an indoor map.
public enum DestinationProximity {
    public static func shouldOfferIndoorChoice(distance: Double, accuracy: Double, age: Double) -> Bool {
        distance.isFinite && accuracy.isFinite && age.isFinite &&
        distance >= 0 && distance <= 100 && accuracy >= 0 && accuracy <= 30 && age >= 0 && age <= 10
    }
}
