import Foundation

/// Cancellation shared by the UI and an audio worker. A queued playback must
/// recheck after slow activation so Stop/Mute cannot be undone by old work.
public final class AudioRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var current = UUID()
    public init() {}
    @discardableResult public func renew() -> UUID {
        lock.lock(); defer { lock.unlock() }
        current = UUID(); return current
    }
    public func contains(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return current == token
    }
}

public enum FloorPlaneBounds {
    /// Point relative to the plane center, rotated into the new planeExtent's
    /// rectangle. ARKit no longer bakes this yaw into the anchor transform.
    public static func contains(x: Float, z: Float, width: Float, height: Float, yaw: Float) -> Bool {
        guard [x, z, width, height, yaw].allSatisfy(\.isFinite), width > 0, height > 0 else { return false }
        let localX = cos(yaw)*x - sin(yaw)*z
        let localZ = sin(yaw)*x + cos(yaw)*z
        return abs(localX) < width/2 && abs(localZ) < height/2
    }
}

public enum SpeechImportance: Int, Comparable, Sendable {
    case ambient, routine, direction, safety
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}
public struct PendingSpeech: Equatable, Sendable {
    public let id = UUID()
    public let text: String
    public let priority: SpeechImportance
    public let expires: Double
    public let requestedAt: Double
    public let positionTime: Double?
    public let userRequested: Bool
    public let deduplicationKey: String
    public init(_ text: String, priority: SpeechImportance, now: Double, positionTime: Double? = nil,
                userRequested: Bool = false, deduplicationKey: String? = nil) {
        self.text = text; self.priority = priority; self.requestedAt = now; self.positionTime = positionTime
        self.userRequested = userRequested
        self.deduplicationKey = deduplicationKey ?? text
        expires = now + (priority == .safety ? 6 : priority == .direction ? 5 : 10)
    }
}
public struct NavigationSpeechQueue {
    private var lines: [PendingSpeech] = []
    public init() {}
    public var pendingIDs: Set<UUID> { Set(lines.map(\.id)) }
    public static func shouldInterrupt(active: PendingSpeech, incoming: PendingSpeech) -> Bool {
        incoming.text != active.text &&
            (incoming.priority == .safety && active.priority != .safety ||
             incoming.priority == .direction && active.priority == .ambient)
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
    public mutating func next(now: Double, isRelevant: (PendingSpeech) -> Bool = { _ in true }) -> PendingSpeech? {
        lines.removeAll { $0.expires < now || !isRelevant($0) }
        return lines.isEmpty ? nil : lines.removeFirst()
    }
}

/// Speech is rationed independently of position updates. Explicit replies and
/// Repeat are never discarded merely because an ordinary sentence is playing.
public struct SpeechAdmission {
    private var started: [String: Double] = [:]
    public init() {}
    public mutating func reset() { started = [:] }
    public mutating func forget(_ key: String) { started.removeValue(forKey: key) }
    public func allows(_ line: PendingSpeech, active: PendingSpeech?, now: Double) -> Bool {
        guard !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if line.userRequested { return true }
        if active?.deduplicationKey == line.deduplicationKey { return false }
        if let last = started[line.deduplicationKey], now-last < (line.priority == .safety ? 3 : 8) { return false }
        // Existing routine calls include button confirmations and answers. Only
        // explicitly optional commentary may be discarded because voice is busy.
        return active == nil || line.priority != .ambient
    }
    public mutating func didStart(_ line: PendingSpeech, now: Double) {
        started = started.filter { now-$0.value < 60 }
        started[line.deduplicationKey] = now
        if started.count > 32 { started = [line.deduplicationKey: now] }
    }
}

public enum VoiceResponseTiming {
    /// Tap-to-talk ends after a pause; hold-to-talk waits for release instead.
    public static let pauseSeconds = 1.2
    /// Give the recognizer a bounded chance to finalize after audio ends.
    public static let finalResultSeconds = 1.0
    public static let acknowledgmentSeconds = 0.65
    public static let acknowledgment = "Checking that."
}

public enum AgentSpeechPolicy {
    public static func normalizedCommand(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
    /// Internal lookups stay silent. Final responses still use validated device
    /// results; urgent controls and live turn timing never wait for cloud AI.
    public static func presentImmediately(tool: AgentTool, status: AgentToolResult.Status) -> Bool {
        if status != .success { return true }
        return [.changeDestination, .replanRoute, .repeatInstruction, .describeCurrentView,
                .addShoppingItem, .optimizeShoppingRoute].contains(tool)
    }
    public static func isImmediateLocalCommand(_ text: String, hasDestination: Bool) -> Bool {
        let value = normalizedCommand(text)
        if ["stop", "pause", "pause guidance", "stop guidance", "cancel"].contains(value) { return true }
        return hasDestination && ["repeat", "repeat directions", "repeat instruction", "say that again", "where am i"].contains(value)
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
