import XCTest
@testable import IndoorbilityCore

final class AudioConcurrencyTests: XCTestCase {
    func testStopDuringSlowActivationRejectsPendingPlayback() async throws {
        let gate = AudioRequestGate(), token = gate.renew()
        let entered = expectation(description: "Slow activation started")
        let (release, continuation) = AsyncStream<Void>.makeStream()
        let playback = Task.detached { () -> Bool in
            guard gate.contains(token) else { return false }
            entered.fulfill()
            for await _ in release { break }
            // Same cancellation recheck as the platform audio worker, after I/O.
            return gate.contains(token)
        }
        await fulfillment(of: [entered], timeout: 3)
        gate.renew() // Stop/Mute while activation is in progress.
        continuation.yield(()); continuation.finish()
        let played = await playback.value
        XCTAssertFalse(played)
    }
    func testAnOldQueuedStopCannotCancelANewerCue() {
        let gate = AudioRequestGate()
        let oldStop = gate.renew(), newCue = gate.renew()
        XCTAssertFalse(gate.contains(oldStop))
        XCTAssertTrue(gate.contains(newCue))
        gate.renew()
        XCTAssertFalse(gate.contains(newCue))
    }
    func testFloorExtentUsesItsMeasuredYawAndRejectsInvalidGeometry() {
        XCTAssertTrue(FloorPlaneBounds.contains(x: 1.5, z: 0, width: 4, height: 1, yaw: 0))
        XCTAssertFalse(FloorPlaneBounds.contains(x: 0, z: 1.5, width: 4, height: 1, yaw: 0))
        XCTAssertTrue(FloorPlaneBounds.contains(x: 0, z: 1.5, width: 4, height: 1, yaw: .pi/2))
        XCTAssertFalse(FloorPlaneBounds.contains(x: 1.5, z: 0, width: 4, height: 1, yaw: .pi/2))
        let offset = Float(1.5 / sqrt(2.0))
        XCTAssertTrue(FloorPlaneBounds.contains(x: offset, z: -offset, width: 4, height: 1, yaw: .pi/4))
        XCTAssertFalse(FloorPlaneBounds.contains(x: offset, z: offset, width: 4, height: 1, yaw: .pi/4))
        XCTAssertFalse(FloorPlaneBounds.contains(x: .nan, z: 0, width: 4, height: 1, yaw: 0))
        XCTAssertFalse(FloorPlaneBounds.contains(x: 0, z: 0, width: 0, height: 1, yaw: 0))
    }
}
