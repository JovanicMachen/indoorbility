import Foundation
import IndoorbilityCore

// Synthetic positions, real Swift route engine. This executable never claims to run ARKit.
func point(_ x: Float) -> SpatialPoint { SpatialPoint(x: x, y: 0, z: 0) }
let entrance = ScanLandmark(label: "East entrance", kind: "entrance", position: point(0))
let room105 = ScanLandmark(label: "Room 105", kind: "room", position: point(6))
let room106 = ScanLandmark(label: "Room 106", kind: "room", position: point(10))
let draft = ScanDraft(name: "Synthetic hallway fixture", usesLiDAR: true, hasWorldMap: true,
    samples: (0...20).map { ScanSample(position: point(Float($0)/2), segment: 0) },
    landmarks: [entrance, room105, room106], meshVertexCount: 3, meshTriangleCount: 1)
let reviewed = try HallwayRoute.make(draft: draft, entranceID: entrance.id, roomID: room106.id, reviewed: true)
let initial = try HallwayRoute.make(draft: draft, entranceID: entrance.id, roomID: room105.id, reviewed: true)
var follower = HallwayFollower(route: initial)
for i in 0...25 { follower.update(position: point(0), heading: 0, time: Double(i)/10, trackingNormal: true) }
try follower.confirmEntrance()
for i in 26...65 { follower.update(position: point(Float(i-25)/10), heading: 0, time: Double(i)/10, trackingNormal: true) }
var ledger = AgentExecutionLedger()
var resolved: UUID?
var calculated: UUID?
func context() -> [String: Any] {
    ["sessionId": ledger.sessionId, "sessionRevision": ledger.revision, "buildingId": draft.id.uuidString,
     "floor": 0, "tracking": "verified", "destinationId": follower.route.room.id.uuidString,
     "avoidStairs": true, "instruction": follower.instruction,
     "knownDestinations": draft.landmarks.map { ["id": $0.id.uuidString, "name": $0.label, "mapId": draft.id.uuidString] }, "knownClosures": [String]()]
}
func emit(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self)); fflush(stdout)
}
try emit(["context": context(), "mode": "synthetic-pose-real-swift-routing"])
while let line = readLine() {
    do {
        let call = try JSONDecoder().decode(AgentCall.self, from: Data(line.utf8))
        let result: AgentToolResult
        if let prior = try ledger.validate(call) { result = prior }
        else {
            var status = AgentToolResult.Status.success
            var data: [String: String] = [:]
            var message = ""
            switch call.tool {
            case .resolveDestination:
                let target = try LiveHallwayCommand.destination(in: call.argument, landmarks: draft.landmarks)
                resolved = target.id; data["destinationId"] = target.id.uuidString; message = "Destination resolved."
            case .calculateAccessibleRoute, .changeDestination:
                guard let id = UUID(uuidString: call.argument), id == resolved,
                      let target = draft.landmarks.first(where: { $0.id == id }) else { throw MapError.invalid("Resolve a known target first.") }
                let next = try follower.changingDestination(to: target, on: reviewed, draft: draft)
                if call.tool == .changeDestination {
                    guard calculated == id else { throw MapError.invalid("Calculate first.") }
                    follower = next; ledger.invalidate(); message = follower.instruction
                } else { calculated = id; message = "Route calculated from synthetic verified position." }
                data = ["remainingMetres": String(next.remaining), "destinationId": target.id.uuidString]
            case .describeCurrentView:
                status = .unavailable; message = "No camera exists in this command-line probe. A physical iPhone is required for OCR and depth observations."
            case .getNavigationState: message = follower.instruction
            case .getAccessibilityPreferences: data["avoidStairs"] = "true"; message = "Stairs excluded."
            default: throw MapError.invalid("Tool not available in this limited fixture.")
            }
            result = AgentToolResult(callId: call.callId, sessionRevision: ledger.revision, status: status, data: data, userSafeExplanation: message)
            ledger.record(call, result: result)
        }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result))
        try emit(["context": context(), "result": encoded, "destinationChanged": follower.route.room.id == room105.id,
                  "positionPreserved": follower.position == point(4), "destinationLabel": follower.route.room.label, "remaining": follower.remaining])
    } catch { try emit(["error": error.localizedDescription, "context": context()]) }
}
