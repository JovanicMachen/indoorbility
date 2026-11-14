import Foundation

public enum AccessibleCommand: Equatable {
    case yes, no, next, repeatPrompt, pause, start, settings
    case narration(Bool), haptics(Bool), focused(Bool), avoidStairs(Bool)
    case destination(String), checkpoint(String)

    public static func parse(_ text: String, destinations: [String: String] = [:]) -> Self? {
        let words = normalize(text)
        switch words {
        case "yes", "confirm": return .yes
        case "no", "cancel": return .no
        case "next", "next option": return .next
        case "repeat", "repeat that", "read the sign": return .repeatPrompt
        case "pause", "pause guidance", "stop guidance": return .pause
        case "start", "start guidance": return .start
        case "settings", "open settings": return .settings
        case "narration on": return .narration(true)
        case "narration off": return .narration(false)
        case "haptics on": return .haptics(true)
        case "haptics off": return .haptics(false)
        case "one instruction on": return .focused(true)
        case "one instruction off": return .focused(false)
        case "avoid stairs": return .avoidStairs(true)
        case "allow stairs": return .avoidStairs(false)
        default:
            guard words.hasPrefix("go to ") else { return nil }
            let name = String(words.dropFirst(6))
            let matches = destinations.filter { normalize($0.value) == name }
            return matches.count == 1 ? .destination(matches.first!.key) : nil
        }
    }
    private static func normalize(_ text: String) -> String {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

/// No action is emitted until a neutral hold arms the gate. Sustained gestures fire once.
public struct FaceGestureGate {
    public enum Gesture: Equatable { case yes, no, next }
    private var candidate: Gesture?
    private var began: TimeInterval?
    private var lastTime: TimeInterval?
    private var armed = false
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func update(_ gesture: Gesture?, at time: TimeInterval, tracked: Bool) -> Gesture? {
        guard tracked, time.isFinite else { reset(); return nil }
        if let lastTime, time <= lastTime || time - lastTime > 0.3 { reset() }
        lastTime = time
        if gesture != candidate { candidate = gesture; began = time }
        if began == nil { began = time }
        if gesture == nil {
            if time - (began ?? time) >= 0.5 { armed = true }
            return nil
        }
        guard armed, time - (began ?? time) >= 0.8 else { return nil }
        armed = false
        return gesture
    }
}

/// A response can consume only the current, unexpired question, and only once.
public struct CommandConfirmation {
    public private(set) var command: AccessibleCommand?
    public private(set) var question = "No action waiting for confirmation."
    private var expiresAt: TimeInterval = 0
    public init() {}
    public mutating func propose(_ command: AccessibleCommand, question: String, at time: TimeInterval) {
        self.command = command; self.question = question; expiresAt = time + 30
    }
    public mutating func answer(yes: Bool, at time: TimeInterval) -> AccessibleCommand? {
        defer { clear() }
        guard yes, time < expiresAt else { return nil }
        return command
    }
    public mutating func clear() { command = nil; question = "No action waiting for confirmation."; expiresAt = 0 }
}
