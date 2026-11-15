import XCTest
@testable import IndoorbilityCore

final class ObstacleNoticeTests: XCTestCase {
    func testAnnouncementsSayWhatWhereAndHowFar() {
        XCTAssertEqual(ObstacleNotice(kind: .chair, distance: 1.22, lateral: 0.05).text(feet: true),
                       "Chair ahead, about 4 feet. Watch out.")
        XCTAssertEqual(ObstacleNotice(kind: .table, distance: 1.5, lateral: -0.8).text(feet: true),
                       "Table on your left, about 5 feet.")
        XCTAssertEqual(ObstacleNotice(kind: .table, distance: 2, lateral: 0.9).text(feet: false),
                       "Table on your right, about 2 meters.")
        XCTAssertEqual(ObstacleNotice(kind: .chair, distance: 0.6, lateral: 0).text(feet: true),
                       "Chair right in front of you. Stop and go around it.")
        XCTAssertEqual(ObstacleNotice(kind: .person, distance: nil, lateral: nil).text(feet: true),
                       "Person in front of you. Watch out.")
        XCTAssertEqual(ObstacleNotice(kind: .person, distance: nil, lateral: -0.5).text(feet: true),
                       "Person on your left. Watch out.")
    }
    func testInvalidMeasurementsAreDropped() {
        let notice = ObstacleNotice(kind: .chair, distance: .nan, lateral: .infinity)
        XCTAssertNil(notice.distance); XCTAssertNil(notice.lateral)
        XCTAssertEqual(notice.text(feet: true), "Chair in front of you. Watch out.")
    }
}
