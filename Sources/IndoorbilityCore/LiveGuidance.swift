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
    private var retryID: String?
    private var retryAfter: TimeInterval = 0
    public init() {}
    public mutating func reset() { lastID = nil; lastDelivery = nil; deliveredTurns = []; retryID = nil; retryAfter = 0 }
    /// Re-arm only the CURRENT instruction if speech was lost. A short gap
    /// prevents competing warnings and directions from retrying every frame.
    public mutating func rearm(_ id: String, now: TimeInterval) {
        guard lastID == id else { return }
        lastID = nil; deliveredTurns.remove(id); retryID = id; retryAfter = now+1.5
    }
    public mutating func consume(_ message: GuidanceMessage, listening: Bool, now: TimeInterval = 0, repeatReliable: Bool = false) -> Bool {
        guard message.id != retryID || now >= retryAfter else { return false }
        if message.cue == .turn && deliveredTurns.contains(message.id) { return false }
        let reminder = repeatReliable && lastDelivery.map { now - $0 >= 12 } == true
        guard !listening, message.id != lastID || reminder else { return false }
        if message.cue == .turn { deliveredTurns.insert(message.id) }
        lastID = message.id; lastDelivery = now; retryID = nil; return true
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

/// Travel-loop timing. The clip plays, then a fixed silence, then repeats.
/// A soft stop lets an audible clip finish; Stop/Mute remain immediate.
public enum TravelLoopTiming {
    public static let gapSeconds: Double = 1.0
    public static let normalVolume: Float = 0.8
    public static let duckedVolume: Float = 0.25
    /// Normalizes a quiet recording toward full scale without clipping or
    /// amplifying silence/noise without bound.
    public static func gain(peak: Float) -> Float {
        guard peak.isFinite, peak > 0.001 else { return 1 }
        return min(4, max(1, 0.9/peak))
    }
    /// Seconds to wait before pausing so an audible clip is not cut off.
    /// Zero while the player is already inside the silent gap.
    public static func softStopDelay(currentTime: Double, clipDuration: Double) -> Double {
        guard currentTime.isFinite, clipDuration.isFinite, currentTime >= 0, currentTime < clipDuration else { return 0 }
        return clipDuration - currentTime
    }
}

/// One large, glanceable instruction for indoor navigation: an arrow and the
/// distance to walk before the next action. Derived only from the verified
/// follower (or the labeled recorded preview), the same source as speech.
public struct IndoorDirection: Equatable {
    public enum Arrow: String { case straight, left, right, back, arrived }
    public let arrow: Arrow
    /// Metres to travel before the next action; nil when the action is now.
    public let distance: Float?
    public let headline: String
    public let detail: String?

    public var symbol: String {
        switch arrow {
        case .straight: return "arrow.up"
        case .left: return "arrow.turn.up.left"
        case .right: return "arrow.turn.up.right"
        case .back: return "arrow.uturn.down"
        case .arrived: return "checkmark.circle.fill"
        }
    }
    /// Large number and short unit, e.g. ("30", "ft").
    public static func distanceParts(_ metres: Float, feet: Bool) -> (value: String, unit: String) {
        let unit = feet ? "ft" : "m"
        guard metres.isFinite, metres >= 0 else { return ("–", unit) }
        let value = metres * (feet ? 3.28084 : 1)
        guard value < 100_000 else { return ("–", unit) }
        return value < 1 ? ("<1", unit) : (String(Int(value.rounded())), unit)
    }
    public func spoken(feet: Bool) -> String {
        var parts = [headline]
        if let distance { parts.append(LiveGuidance.distance(distance, feet: feet)) }
        if let detail { parts.append(detail) }
        return parts.joined(separator: ", ")
    }
    private static func turnArrow(_ direction: String) -> Arrow {
        direction == "left" ? .left : direction == "right" ? .right : .back
    }
    private static func turnPhrase(_ direction: String) -> String {
        direction == "around" ? "turn around" : "turn " + direction
    }

    /// Nil when there is no trustworthy live instruction to draw.
    public static func live(_ follower: HallwayFollower) -> IndoorDirection? {
        let room = follower.route.room.label
        switch follower.state {
        case .arrived:
            return IndoorDirection(arrow: .arrived, distance: nil, headline: "You’ve arrived", detail: room)
        case .nearRoom:
            guard follower.stable else { return nil }
            return IndoorDirection(arrow: .straight, distance: follower.remaining, headline: "Almost there", detail: "Stop at " + room)
        case .offRoute:
            guard follower.stable else { return nil }
            let text = follower.instruction
            if text.hasSuffix("to your left.") { return IndoorDirection(arrow: .left, distance: nil, headline: "Path is to your left", detail: "Move left to rejoin it") }
            if text.hasSuffix("to your right.") { return IndoorDirection(arrow: .right, distance: nil, headline: "Path is to your right", detail: "Move right to rejoin it") }
            if text.hasSuffix("behind you.") { return IndoorDirection(arrow: .back, distance: nil, headline: "Path is behind you", detail: "Turn around to rejoin it") }
            if text.hasSuffix("ahead of you.") { return IndoorDirection(arrow: .straight, distance: nil, headline: "Path is ahead", detail: "Go straight to rejoin it") }
            return nil
        case .guiding:
            guard follower.stable else { return nil }
            let text = follower.instruction
            if text.hasPrefix("Turn around") || text.hasPrefix("Moving away") {
                return IndoorDirection(arrow: .back, distance: nil, headline: "Turn around", detail: "You are facing away from " + room)
            }
            // Stairs, heading checks and other warnings keep their own wording.
            guard text.hasPrefix("Continue straight") else { return nil }
            if let turn = follower.nextMeasuredTurn {
                let ahead = max(0, turn.along - follower.progress)
                if ahead <= 1.5 {
                    let phrase = turnPhrase(turn.direction)
                    return IndoorDirection(arrow: turnArrow(turn.direction), distance: nil,
                        headline: phrase.prefix(1).uppercased() + phrase.dropFirst() + " now", detail: nil)
                }
                return IndoorDirection(arrow: .straight, distance: ahead, headline: "Go straight", detail: "then " + turnPhrase(turn.direction))
            }
            return IndoorDirection(arrow: .straight, distance: follower.remaining, headline: "Go straight", detail: "to " + room)
        default:
            return nil
        }
    }
    /// Directions from the recorded start only; never a live position.
    public static func preview(_ preview: RecordedRoutePreview) -> IndoorDirection {
        if let turn = preview.firstTurn, preview.firstLegDistance <= 1.5 {
            let phrase = turnPhrase(turn)
            return IndoorDirection(arrow: turnArrow(turn), distance: nil,
                headline: phrase.prefix(1).uppercased() + phrase.dropFirst(), detail: "at the recorded start")
        }
        return IndoorDirection(arrow: .straight, distance: preview.firstLegDistance, headline: "Go straight",
            detail: preview.firstTurn.map { "then " + turnPhrase($0) } ?? "to " + preview.destination)
    }
}
