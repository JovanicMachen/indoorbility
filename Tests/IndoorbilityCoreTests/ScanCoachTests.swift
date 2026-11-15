import XCTest
@testable import IndoorbilityCore

final class ScanCoachTests: XCTestCase {
    func testCornerIsCoachedThenConfirmed() {
        var coach = ScanCoach(), time = 0.0, mesh = 0, tips: [ScanCoach.Kind] = []
        func walk(_ x: Float, _ z: Float) {
            time += 0.1; mesh += 1
            if let tip = coach.update(x: x, z: z, time: time, meshCount: mesh) { tips.append(tip.kind) }
        }
        for i in 0...60 { walk(Float(i)*0.08, 0) }          // 4.8 m east at 0.8 m/s
        for i in 1...60 { walk(4.8, -Float(i)*0.08) }       // turn left, 4.8 m north
        XCTAssertEqual(tips.filter { $0 == .corner }.count, 1)
        XCTAssertEqual(tips.filter { $0 == .cornerDone }.count, 1)
        XCTAssertLessThan(tips.firstIndex(of: .corner)!, tips.firstIndex(of: .cornerDone)!)
        XCTAssertEqual(coach.corners, 1)
        XCTAssertFalse(tips.contains(.slowDown))
    }
    func testFastWalkingAndMissingSurfacesAndEndStop() {
        var coach = ScanCoach(), time = 0.0, tips: [ScanCoach.Tip] = []
        for i in 0...40 {
            time += 0.1
            if let tip = coach.update(x: Float(i)*0.2, z: 0, time: time, meshCount: i) { tips.append(tip) }
        }
        XCTAssertTrue(tips.contains { $0.kind == .slowDown })
        // Walking slowly with no new surfaces.
        for i in 0...80 {
            time += 0.1
            if let tip = coach.update(x: 8+Float(i)*0.07, z: 0, time: time, meshCount: 41) { tips.append(tip) }
        }
        XCTAssertTrue(tips.contains { $0.kind == .surfaces })
        // Standing still at the destination.
        for _ in 0...80 {
            time += 0.1
            if let tip = coach.update(x: 13.6, z: 0, time: time, meshCount: 41) { tips.append(tip) }
        }
        XCTAssertEqual(tips.last?.kind, .endStop)
        XCTAssertTrue(tips.last!.text.contains("Stop here"))
    }
    func testInvalidInputIsIgnored() {
        var coach = ScanCoach()
        XCTAssertNil(coach.update(x: .nan, z: 0, time: 0, meshCount: 0))
        XCTAssertNil(coach.current)
    }
}
