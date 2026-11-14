import Foundation

/// Evidence ordering only: never establishes pose, access or a safe path.
public struct RecordingEvidence: Equatable {
    public let id: UUID
    public let fieldReviewed: Bool
    public let successfulVisits: Int
    public let measuredError: Float?
    public let reviewedAt: Date?
    public init(id: UUID, fieldReviewed: Bool, successfulVisits: Int, measuredError: Float?, reviewedAt: Date?) {
        self.id = id; self.fieldReviewed = fieldReviewed; self.successfulVisits = max(0, successfulVisits)
        self.measuredError = measuredError.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.reviewedAt = reviewedAt
    }
    public static func preferred(_ a: Self, over b: Self) -> Bool {
        if a.fieldReviewed != b.fieldReviewed { return a.fieldReviewed }
        if a.successfulVisits != b.successfulVisits { return a.successfulVisits > b.successfulVisits }
        if a.measuredError != b.measuredError { return (a.measuredError ?? .infinity) < (b.measuredError ?? .infinity) }
        if a.reviewedAt != b.reviewedAt { return (a.reviewedAt ?? .distantPast) > (b.reviewedAt ?? .distantPast) }
        return a.id.uuidString < b.id.uuidString
    }
}
