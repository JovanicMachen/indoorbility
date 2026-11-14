import Foundation

public enum GuidanceCue: String, CaseIterable { case started, approach, turn, changed, attention, arrived }
public struct GuidanceMessage: Equatable {
    public let id: String
    public let text: String
    public let cue: GuidanceCue?
    public var primary: String? = nil
    public var secondary: String? = nil
}
/// Presentation only: the verified follower remains authoritative for progress and arrival.
public enum LiveGuidance {
    public static func distance(_ metres: Float, feet: Bool) -> String {
        let value = max(0, metres.isFinite ? metres : 0) * (feet ? 3.28084 : 1)
        return "\(Int(value.rounded())) \(feet ? "feet" : "meters")"
    }
    public struct MeasuredTurn {
        public let index: Int
        public let along: Float
        public let direction: String
    }
    public static func measuredTurns(_ path: [SpatialPoint]) -> [MeasuredTurn] {
        guard path.count >= 3 else { return [] }
        var turns: [MeasuredTurn] = []
        var bend: [(turn: MeasuredTurn, angle: Float)] = []
        func finishBend() {
            guard let peak = bend.map(\.angle).max() else { return }
            // Choose the middle of a curvature plateau, not every scan sample on a curve.
            let strongest = bend.filter { $0.angle >= peak - 0.001 }
            turns.append(strongest[strongest.count/2].turn)
            bend.removeAll()
        }
        var along: Float = 0
        for i in 1..<(path.count - 1) {
            along += path[i-1].distance(to: path[i])
            var a = i-1; var b = i+1
            while a > 0 && path[a].horizontalDistance(to: path[i]) < 2 { a -= 1 }
            while b < path.count-1 && path[b].horizontalDistance(to: path[i]) < 2 { b += 1 }
            let incoming = atan2(path[i].z-path[a].z, path[i].x-path[a].x)
            let outgoing = atan2(path[b].z-path[i].z, path[b].x-path[i].x)
            let delta = atan2(sin(outgoing-incoming), cos(outgoing-incoming))
            // Compare metre-scale headings. A rounded corner need not contain any
            // single sample with a 45-degree kink; that requirement missed real turns.
            guard abs(delta) > .pi/4 else { continue }
            let turn = MeasuredTurn(index: i, along: along, direction: abs(delta) >= .pi*5/6 ? "around" : delta < 0 ? "left" : "right")
            if let last = bend.last, turn.direction != last.turn.direction || along-last.turn.along > 2 {
                finishBend()
            }
            bend.append((turn, abs(delta)))
        }
        finishBend()
        return turns
    }
    public static func message(_ follower: HallwayFollower, feet: Bool = false) -> GuidanceMessage {
        guard follower.state == .guiding, follower.stable else {
            return GuidanceMessage(id: "state-\(follower.state.rawValue)-\(follower.instruction)", text: follower.instruction,
                cue: follower.state == .arrived ? .arrived : [.trackingLost, .offRoute, .blocked].contains(follower.state) ? .attention : nil)
        }
        // Preserve the follower's heading/off-route warning instead of issuing an incompatible turn.
        if follower.instruction.hasPrefix("Moving away") || follower.instruction.hasPrefix("Turn around") || follower.instruction.hasPrefix("You may") || follower.instruction.hasPrefix("Check your heading") {
            return GuidanceMessage(id: follower.instruction, text: follower.instruction, cue: .attention)
        }
        if follower.instruction.hasPrefix("Stairs") || follower.instruction.hasPrefix("Level change") {
            return GuidanceMessage(id: follower.instruction, text: follower.instruction, cue: .attention)
        }
        if let turn = follower.nextMeasuredTurn {
            let leftRight = turn.direction
            let remaining = max(0, turn.along-follower.progress)
            let key = "\(follower.route.room.id)-\(turn.index)"
            if remaining <= 1.5 { return GuidanceMessage(id: key+"-now", text: "Turn \(leftRight) now.", cue: .turn) }
            if remaining <= 20 {
                let band = remaining <= 5 ? 5 : remaining <= 10 ? 10 : 20
                return GuidanceMessage(id: key+"-approach-\(band)", text: "Continue straight. In \(distance(remaining, feet: feet)), turn \(leftRight).", cue: .approach,
                    primary: "Continue straight", secondary: "Next turn in " + distance(remaining, feet: feet))
            }
            return GuidanceMessage(id: key+"-straight", text: "Continue straight for \(distance(remaining, feet: feet)).", cue: .started, primary: "Continue straight", secondary: "Next turn in " + distance(remaining, feet: feet))
        }
        return GuidanceMessage(id: "\(follower.route.room.id)-final", text: "Continue straight. \(distance(follower.remaining, feet: feet)) to \(follower.route.room.label).", cue: nil, primary: "Continue straight", secondary: distance(follower.remaining, feet: feet) + " remaining")
    }
}

public struct GuidanceDelivery {
    public private(set) var lastID: String?
    private var lastDelivery: TimeInterval?
    private var deliveredTurns: Set<String> = []
    public init() {}
    public mutating func reset() { lastID = nil; lastDelivery = nil; deliveredTurns = [] }
    public mutating func consume(_ message: GuidanceMessage, listening: Bool, now: TimeInterval = 0, repeatReliable: Bool = false) -> Bool {
        if message.cue == .turn && deliveredTurns.contains(message.id) { return false }
        let reminder = repeatReliable && lastDelivery.map { now - $0 >= 12 } == true
        guard !listening, message.id != lastID || reminder else { return false }
        if message.cue == .turn { deliveredTurns.insert(message.id) }
        lastID = message.id; lastDelivery = now; return true
    }
}

public enum GuidanceSoundPolicy {
    public static func speechAllowed(muted: Bool, enabled: Bool, forced: Bool, voiceOver: Bool, active: Bool, suspended: Bool) -> Bool {
        !muted && active && !suspended && (enabled || forced || voiceOver)
    }
    public static func cueAllowed(muted: Bool, enabled: Bool, suspended: Bool) -> Bool { !muted && enabled && !suspended }
}
