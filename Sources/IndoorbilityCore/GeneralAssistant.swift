import Foundation

public struct AssistantConversationMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) { self.role = role; self.content = content }
}

/// Conversation is ephemeral, bounded and separate from map/task ownership.
public struct GeneralConversation {
    public private(set) var messages: [AssistantConversationMessage] = []
    public init() {}
    public mutating func clear() { messages = [] }
    public mutating func append(question: String, answer: String) {
        messages += [.init(role: .user, content: String(question.prefix(1000))),
                     .init(role: .assistant, content: String(answer.prefix(650)))]
        if messages.count > 6 { messages.removeFirst(messages.count-6) }
    }
}

public enum GeneralQuestionPolicy {
    public static let offlineMessage = "General questions need an AI connection. Local navigation still works."
    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static let livePatterns = [
        #"\b(take|guide|navigate|walk|lead|bring|direct)\s+me\b"#,
        #"\b(go|head|turn)\s+(left|right|around|back|to|toward|towards|straight)\b"#,
        #"\b(get|walk|go)\s+to\b"#,
        #"\b(room|suite|floor|level)\s*[-#]?\s*(\d+|zero|one|two|three|four|five|six|seven|eight|nine)\b"#,
        #"\b(where am i|how far|how much farther|which way|nearest|closest|near me|nearby|in front|ahead of me|my location|my position|my route|my destination)\b"#,
        #"\b(read|scan)\s+(a |the |this )?(sign|label|text)\b"#,
        #"\b(what do you see|what can you see|what's ahead|what is ahead|describe (the |my )?(view|surroundings)|is it safe|can i cross)\b"#,
        #"\b(find|locate)\s+(the |a |an )?(exit|entrance|room|restroom|bathroom|elevator|lift)\b"#,
        #"^(please )?(avoid stairs|reroute|recalculate|repeat|pause|stop|mute|unmute|add |buy |start |record )"#
    ]
    private static func matches(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
    public static func isGeneral(_ text: String, followsGeneral: Bool = false) -> Bool {
        let text = normalize(text)
        guard !text.isEmpty, text.count <= 1000, !matches(text, patterns: livePatterns) else { return false }
        if ["hi", "hello", "hey", "thanks", "thank you"].contains(text.trimmingCharacters(in: .punctuationCharacters)) { return true }
        if text.range(of: #"^(what|what's|who|who's|why|how|when|where|is|are|can|could|would|should|do|does|did|tell me|explain|define|help me understand|give me)\b"#, options: .regularExpression) != nil { return true }
        if text.range(of: #"^[\d\s()+*/.^%−-]+[+*/.^%−-][\d\s()+*/.^%−-]+\??$"#, options: .regularExpression) != nil { return true }
        return followsGeneral && text.range(of: #"^(and |also |more detail|a bit more|simpler|shorter|say that more simply)"#, options: .regularExpression) != nil
    }
    /// Defense in depth for knowledge-only output, not a proof of factual accuracy.
    /// General answers have no device tools or live scene/route context.
    public static func acceptsAnswer(_ answer: String) -> Bool {
        let text = normalize(answer)
        guard !text.isEmpty, answer.count <= 650 else { return false }
        return !matches(text, patterns: [
            #"\b(turn|go|walk|head|move)\s+(left|right|straight|forward|backward|around)\b"#,
            #"\b(you are at|you're at|you have arrived|you've arrived|i changed your (route|destination)|i can see|i see (a|the))\b"#,
            #"\b(your destination|the exit|the entrance) is (on|to) (your |the )?(left|right)\b"#
        ])
    }
}

/// Older navigation-only servers omit kind and answer. They remain compatible.
public struct AgentFinalResponse: Decodable {
    public let responseCallId: String?
    public let clarification: String
    public let kind: String?
    public let answer: String?
    public func validatedGeneralAnswer(for question: String, followsGeneral: Bool) throws -> String {
        guard kind == "general", responseCallId == nil, clarification == "none",
              GeneralQuestionPolicy.isGeneral(question, followsGeneral: followsGeneral),
              let answer, GeneralQuestionPolicy.acceptsAnswer(answer) else {
            throw MapError.invalid("That AI answer could not be validated. Your route is unchanged.")
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
