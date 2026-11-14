import Foundation

/// A mapper's recorded field review, not a sensor-accuracy certification.
/// Store the whole reviewed route so any edit invalidates the review.
public struct VolunteerReview: Codable, Equatable {
    public let route: HallwayRoute
    public let reviewer: String
    public let floorLabel: String
    public let measuredLength: Float
    public let endpointError: Float
    public let accessConfirmed: Bool
    public let returnTestPassed: Bool
    public let reviewedAt: Date

    public init(route: HallwayRoute, reviewer: String, floorLabel: String, measuredLength: Float,
                endpointError: Float, accessConfirmed: Bool, returnTestPassed: Bool) {
        self.route = route; self.reviewer = reviewer; self.floorLabel = floorLabel
        self.measuredLength = measuredLength; self.endpointError = endpointError
        self.accessConfirmed = accessConfirmed; self.returnTestPassed = returnTestPassed
        reviewedAt = Date()
    }
    public func validate(for current: HallwayRoute) throws {
        guard route == current else { throw MapError.invalid("This route changed. Repeat its field review.") }
        guard !reviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !floorLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              accessConfirmed, returnTestPassed else {
            throw MapError.invalid("Confirm the floor, reviewer, permitted access and any recorded stairs and return-walk test.")
        }
        guard measuredLength.isFinite, measuredLength >= 2,
              endpointError.isFinite, endpointError >= 0, endpointError <= 0.5,
              abs(measuredLength - current.distance) <= max(0.5, measuredLength * 0.05) else {
            throw MapError.invalid("Measurements do not agree closely enough. Recheck the path and landmarks, then rescan if needed.")
        }
    }
}

/// Publishing a structurally valid recording is distinct from an independent field review.
public struct RoutePublication: Codable, Equatable {
    public let route: HallwayRoute
    public let publishedAt: Date
    public init(route: HallwayRoute, draft: ScanDraft) throws {
        try route.validate(for: draft)
        self.route = route
        publishedAt = Date()
    }
    public func validate(for current: HallwayRoute, draft: ScanDraft) throws {
        guard route == current else { throw MapError.invalid("Route changed. Publish it again.") }
        try current.validate(for: draft)
    }
}
