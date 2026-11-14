import Foundation

public enum GuidanceCue: String, CaseIterable, Sendable { case started, approach, turn, changed, attention, arrived }
public struct GuidanceMessage: Equatable {
    public let id: String
    public let text: String
    public let cue: GuidanceCue?
    public var primary: String? = nil
    public var secondary: String? = nil
}

/// Immutable directions from the recording, independent of any live position.
/// A preview never advances the follower, speaks a live turn, or asserts arrival.
public struct RecordedRoutePreview {
    public let firstLegDistance: Float
    public let firstTurn: String?
    public let destination: String
    public var symbol: String {
        if let firstTurn, firstLegDistance <= 1.5 {
            return LiveGuidance.symbol(for: "Turn " + firstTurn, reliable: true)
        }
        return "arrow.up"
    }
    public func instruction(feet: Bool) -> String {
        if let firstTurn, firstLegDistance <= 1.5 { return "At the recorded start, turn " + firstTurn }
        let ahead = "Straight for " + LiveGuidance.distance(firstLegDistance, feet: feet)
        if let firstTurn { return ahead + ", then turn " + firstTurn }
        return ahead + " to " + destination
    }
    public func narration(feet: Bool) -> String {
        "Route preview, from the recorded start. " + instruction(feet: feet) + ". Your live position is not matched."
    }
}
/// Presentation only: the verified follower remains authoritative for progress and arrival.
public enum LiveGuidance {
    /// Shared outdoor/indoor artwork. Callers supply the current maneuver,
    /// not a camera bearing or a future turn embedded in a longer briefing.
    public static func symbol(for instruction: String, reliable: Bool) -> String {
        guard reliable else { return "pause.fill" }
        let text = instruction.lowercased()
        if text.contains("arrived") || text.hasPrefix("arrival confirmed") { return "checkmark.circle.fill" }
        if text.hasPrefix("check") || text.hasPrefix("stop") || text.contains("pause") || text.contains("uncertain") || text.contains("moving away") { return "pause.fill" }
        if text.contains("stairs") || text.contains("level change") { return "stairs" }
        if text.contains("turn around") || text.contains("u-turn") { return "arrow.uturn.down" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
    public static func distance(_ metres: Float, feet: Bool) -> String {
        guard metres.isFinite, metres >= 0 else { return "distance unavailable" }
        let value = metres * (feet ? 3.28084 : 1)
        guard value.isFinite, value < Float(Int.max) else { return "distance unavailable" }
        if value > 0 && value < 0.5 { return feet ? "less than 1 foot" : "less than 1 meter" }
        let rounded = Int(value.rounded())
        let unit = feet ? (rounded == 1 ? "foot" : "feet") : (rounded == 1 ? "meter" : "meters")
        return "\(rounded) \(unit)"
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
            // At the recording edges a centimetre-scale start wobble otherwise
            // becomes a full left/right turn against a long outgoing baseline.
            // Require measured support on both sides; genuine early turns with
            // short, metre-scale legs are still included.
            guard path[a].horizontalDistance(to: path[i]) >= 0.75,
                  path[b].horizontalDistance(to: path[i]) >= 0.75 else { continue }
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
                    primary: "Continue straight for " + distance(remaining, feet: feet))
            }
            return GuidanceMessage(id: key+"-straight", text: "Continue straight for \(distance(remaining, feet: feet)).", cue: .started, primary: "Continue straight for " + distance(remaining, feet: feet))
        }
        return GuidanceMessage(id: "\(follower.route.room.id)-final", text: "Continue straight. \(distance(follower.remaining, feet: feet)) to \(follower.route.room.label).", cue: nil, primary: "Continue straight for " + distance(follower.remaining, feet: feet))
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
    public static func journeyLoopAllowed(travelling: Bool, muted: Bool, enabled: Bool, suspended: Bool, active: Bool) -> Bool {
        travelling && !muted && enabled && !suspended && active
    }
    public static func speechAllowed(muted: Bool, enabled: Bool, forced: Bool, voiceOver: Bool, active: Bool, suspended: Bool) -> Bool {
        !muted && active && !suspended && (enabled || forced || voiceOver)
    }
    public static func cueAllowed(muted: Bool, enabled: Bool, suspended: Bool) -> Bool { !muted && enabled && !suspended }
}
