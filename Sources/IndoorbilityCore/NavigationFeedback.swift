import Foundation

public enum SpeechImportance: Int, Comparable, Sendable {
    case routine, direction, safety
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
public struct PendingSpeech: Equatable, Sendable {
    public let text: String
    public let priority: SpeechImportance
    public let expires: Double
    public let requestedAt: Double
    public let positionTime: Double?
    public init(_ text: String, priority: SpeechImportance, now: Double, positionTime: Double? = nil) {
        self.text = text; self.priority = priority; self.requestedAt = now; self.positionTime = positionTime
        expires = now + (priority == .safety ? 6 : 10)
    }
}
public struct NavigationSpeechQueue {
    private var lines: [PendingSpeech] = []
    public init() {}
    public static func shouldInterrupt(active: PendingSpeech, incoming: PendingSpeech) -> Bool {
        incoming.text != active.text &&
            ((incoming.priority == .safety && active.priority != .safety) ||
             (incoming.priority == .direction && active.priority != .safety))
    }
    public mutating func clear() { lines = [] }
    public mutating func push(_ line: PendingSpeech) {
        lines.removeAll { $0.text == line.text }
        if line.priority == .direction || line.priority == .safety { lines.removeAll { $0.priority == .direction } }
        let index = lines.firstIndex { $0.priority < line.priority } ?? lines.endIndex
        lines.insert(line, at: index)
        if lines.count > 3 { lines.removeLast() }
    }
    public mutating func resumeInterrupted(_ line: PendingSpeech) {
        // A newer queued turn supersedes the interrupted one.
        guard !lines.contains(where: { $0.priority == line.priority }) else { return }
        push(line)
    }
    public mutating func next(now: Double) -> PendingSpeech? {
        lines.removeAll { $0.expires < now }
        return lines.isEmpty ? nil : lines.removeFirst()
    }
}

public struct PhoneCoach {
    private var candidate: String?
    private var since = 0.0
    private var last = -Double.infinity
    public private(set) var issue: String?
    public init() {}
    public mutating func update(pitch: Double, roll: Double, now: Double) -> String? {
        guard pitch.isFinite, roll.isFinite, now.isFinite else { return nil }
        let threshold = issue == nil ? 30.0 : 20.0
        let next: String? = abs(roll) > threshold ? "Hold the phone upright, with the camera facing ahead." : pitch < -threshold ? "Raise the camera slightly to face ahead." : pitch > threshold ? "Lower the camera slightly to face ahead." : nil
        if next != candidate { candidate = next; since = now }
        guard now - since >= 0.8 else { return nil }
        let previous = issue; issue = next
        if let next, previous != next || now - last >= 10 { last = now; return next }
        if previous != nil && next == nil { last = now; return "Phone position is better." }
        return nil
    }
}

public enum FloorEvidence: String { case unknown, observed, possibleDrop }
public struct FloorDepthSample: Sendable {
    public let ahead: Float, height: Float
    public init(ahead: Float, height: Float) { self.ahead = ahead; self.height = height }
}
public enum FloorAssessment {
    public static func evaluate(floor: Float?, samples: [FloorDepthSample]) -> FloorEvidence {
        guard let floor, floor.isFinite else { return .unknown }
        let valid = samples.filter { $0.ahead.isFinite && $0.height.isFinite && $0.ahead >= 0.4 && $0.ahead <= 2 }
        let lower = valid.filter { $0.height < floor - 0.15 }
        // Several returns spanning two distance bins; never turn missing depth into a drop or clear path.
        if lower.count >= 6 && Set(lower.map { Int($0.ahead * 5) }).count >= 2 { return .possibleDrop }
        let bins = Set(valid.filter { abs($0.height-floor) < 0.08 }.map { Int($0.ahead * 4) })
        return [2,3,4,5].allSatisfy { bins.contains($0) } ? .observed : .unknown
    }
}
