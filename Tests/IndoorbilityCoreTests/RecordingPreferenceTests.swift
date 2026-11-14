import XCTest
@testable import IndoorbilityCore

final class RecordingPreferenceTests: XCTestCase {
    private func evidence(reviewed: Bool = true, visits: Int = 0, error: Float? = 0.2, date: Date? = nil) -> RecordingEvidence {
        RecordingEvidence(id: UUID(), fieldReviewed: reviewed, successfulVisits: visits, measuredError: error, reviewedAt: date)
    }
    func testReviewBeatsUnreviewedVisitHistory() {
        XCTAssertTrue(RecordingEvidence.preferred(evidence(), over: evidence(reviewed: false, visits: 50)))
    }
    func testVisitsThenMeasuredErrorThenRecency() {
        XCTAssertTrue(RecordingEvidence.preferred(evidence(visits: 3), over: evidence(visits: 2, error: 0.1)))
        XCTAssertTrue(RecordingEvidence.preferred(evidence(error: 0.1), over: evidence(error: 0.3)))
        XCTAssertTrue(RecordingEvidence.preferred(evidence(date: Date(timeIntervalSince1970: 10)), over: evidence(date: Date(timeIntervalSince1970: 1))))
    }
    func testInvalidEvidenceCannotImproveRanking() {
        let invalid = evidence(visits: -3, error: .nan)
        XCTAssertEqual(invalid.successfulVisits, 0)
        XCTAssertNil(invalid.measuredError)
        XCTAssertTrue(RecordingEvidence.preferred(evidence(), over: invalid))
        XCTAssertFalse(RecordingEvidence.preferred(invalid, over: invalid))
    }
    func testOldDestinationCatalogStillDecodes() throws {
        let id = UUID().uuidString
        let data = Data("{\"id\":\"\(id)\",\"routeID\":\"\(id)\",\"scanID\":\"\(id)\",\"room\":\"Room 006\",\"building\":\"Friend Center\"}".utf8)
        let item = try JSONDecoder().decode(JourneyDestination.self, from: data)
        XCTAssertNil(item.successfulVisits)
        XCTAssertEqual(item.room, "Room 006")
    }
}
