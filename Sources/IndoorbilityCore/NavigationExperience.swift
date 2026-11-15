import Foundation

/// Building-scoped room buttons. Identical room labels in different buildings
/// stay separate; recording/floor selection remains owned by the saved catalog.
public struct SavedDestinationBuilding: Identifiable {
    public let id: String
    public let name: String
    public let rooms: [JourneyDestination]
    public static func groups(_ destinations: [JourneyDestination]) -> [Self] {
        func name(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return Dictionary(grouping: destinations.filter { !name($0.building).isEmpty }, by: { name($0.building).lowercased() })
            .map { key, rooms in
                Self(id: key, name: name(rooms[0].building), rooms: rooms.sorted {
                    let comparison = $0.room.localizedStandardCompare($1.room)
                    return comparison == .orderedSame ? $0.id.uuidString < $1.id.uuidString : comparison == .orderedAscending
                })
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// A single, expiring proposal. A reply cannot activate a replaced or consumed proposal.
public struct DestinationConfirmation {
    public private(set) var id: UUID?
    private var expires: TimeInterval = 0
    public init() {}
    public mutating func propose(_ id: UUID, now: TimeInterval) { self.id = id; expires = now + 30 }
    public mutating func cancel() { id = nil }
    public mutating func accept(_ expected: UUID, now: TimeInterval) -> UUID? {
        guard now.isFinite, now < expires, id == expected else { id = nil; return nil }
        id = nil; return expected
    }
    public func isCurrent(_ expected: UUID, now: TimeInterval) -> Bool { id == expected && now < expires }
}

public enum DestinationSearch {
    /// Exact word matches first; if none, a forgiving match for speech
    /// misspellings ("louis rm strng" → "Louis Armstrong"). Numbers must match.
    public static func matches(_ text: String, in destinations: [JourneyDestination]) -> [JourneyDestination] {
        let exact = strictMatches(text, in: destinations)
        if !exact.isEmpty { return exact }
        return SpokenPlaceMatch.best(text, among: destinations.map { [$0.room, $0.building, $0.room + " " + $0.building] })
            .map { [destinations[$0]] } ?? []
    }
    static func strictMatches(_ text: String, in destinations: [JourneyDestination]) -> [JourneyDestination] {
        var query = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for phrase in ["take me to", "go to", "please", "avoid stairs", "without stairs", "no stairs"] { query = query.replacingOccurrences(of: phrase, with: " ") }
        query = query.replacingOccurrences(of: "(?i)(room|rm)(?=[0-9])", with: "$1 ", options: .regularExpression)
        let tokens = query.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !["in", "the", "at", "room", "rm"].contains($0) }
        guard !tokens.isEmpty else { return [] }
        return destinations.filter { place in
            let words = (place.room + " " + place.building).lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            return tokens.allSatisfy { token in words.contains { word in
                if token.allSatisfy(\.isNumber) {
                    // Treat leading zeros as an alternate spelling, but keep all
                    // matches if both labels exist so the user can disambiguate.
                    return word == token || (word.allSatisfy(\.isNumber) && !word.isEmpty && Int(word) != nil && Int(word) == Int(token))
                }
                return word.hasPrefix(token)
            } }
        }
    }
}

/// Fixes speech-recognition spellings of a known place name: dropped vowels,
/// split words ("rm strng"), and near-miss letters. Only ever picks a name the
/// app already knows; room and building numbers must match exactly.
public enum SpokenPlaceMatch {
    static let fillers = ["i want to go to", "i need to go to", "i wanna go to", "take me to", "bring me to", "directions to",
                          "navigate to", "how do i get to", "go to", "get to", "find", "where is", "please", "the"]
    public static func cleaned(_ text: String) -> String {
        var q = " " + text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        for phrase in fillers { q = q.replacingOccurrences(of: " " + phrase + " ", with: " ") }
        return q.trimmingCharacters(in: .whitespaces)
    }
    static func squash(_ text: String) -> String { text.lowercased().filter { $0.isLetter || $0.isNumber } }
    static func numbers(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.compactMap { Int($0).map(String.init) })
    }
    static func skeleton(_ text: String) -> String {
        var out = ""
        for c in squash(text) where !"aeiouy".contains(c) { if out.last != c { out.append(c) } }
        return out
    }
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }; if b.isEmpty { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]; row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j]+1, row[j-1]+1, previous + (a[i-1] == b[j-1] ? 0 : 1))
                previous = current
            }
        }
        return row[b.count]
    }
    /// 0…1 similarity. People often say part of a long name ("Louis Armstrong"
    /// for "Louis Armstrong Lounge"), so runs of the name's words are tried too.
    public static func score(_ heard: String, _ name: String) -> Double {
        let words = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard words.count > 1, words.count <= 12 else { return wholeScore(heard, name) }
        var best = wholeScore(heard, name)
        for start in words.indices { for end in start..<words.count where end > start || words.count == 1 {
            let span = words[start...end].joined(separator: " ")
            best = max(best, wholeScore(heard, span) * 0.97)
        } }
        return best
    }
    static func wholeScore(_ heard: String, _ name: String) -> Double {
        let h = squash(cleaned(heard)), n = squash(name)
        guard h.count >= 5, n.count >= 4 else { return 0 } // Short words are too easy to confuse.
        guard numbers(heard) == numbers(name) || numbers(heard).isEmpty && numbers(name).isEmpty else { return 0 }
        let letters = 1 - Double(distance(Array(h), Array(n))) / Double(max(h.count, n.count))
        let hs = skeleton(h), ns = skeleton(n)
        let consonants = min(hs.count, ns.count) < 4 ? 0 : 1 - Double(distance(Array(hs), Array(ns))) / Double(max(hs.count, ns.count))
        return max(letters, consonants * 0.95)
    }
    /// Index of the single clearly-best candidate, or nil when unsure.
    /// Each candidate may have several names (room, building, both).
    public static func best(_ heard: String, among candidates: [[String]], threshold: Double = 0.72) -> Int? {
        let scored = candidates.enumerated().map { i, names in (i, names.map { score(heard, $0) }.max() ?? 0) }
            .sorted { $0.1 > $1.1 }
        guard let top = scored.first, top.1 >= threshold else { return nil }
        if scored.count > 1, scored[1].1 > top.1 - 0.08 { return nil }
        return top.0
    }
    /// The known name closest to what was heard, for correcting a search query.
    public static func correct(_ heard: String, names: [String]) -> String? {
        best(heard, among: names.map { [$0] }).map { names[$0] }
    }
}

/// Several recordings can reach the same room from different doors. Prefer
/// the one whose recorded start is nearest to you; ties keep the given order.
public enum RouteChoice {
    public struct Start {
        public let index: Int
        public let distance: Double?
        public init(index: Int, distance: Double?) { self.index = index; self.distance = distance }
    }
    /// `distances[i]` is metres from you to option i's start (nil if unknown).
    /// Returns options nearest first; unknown distances keep their order at the end.
    public static func ranked(_ distances: [Double?], fixAccuracy: Double?) -> [Int] {
        guard let accuracy = fixAccuracy, accuracy.isFinite, accuracy >= 0, accuracy <= 50 else { return Array(distances.indices) }
        return distances.indices.sorted { a, b in
            switch (distances[a], distances[b]) {
            case let (x?, y?): return abs(x - y) > accuracy * 0.5 ? x < y : a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a < b
            }
        }
    }
}

/// Optional, manually verified floor label. Never inferred from a room number.
public struct VerifiedRoomMetadata: Codable, Equatable {
    public let buildingID: UUID
    public let roomID: UUID
    public let floorLabel: String
    public let source: String
    public let confirmedAt: Date
    public init(buildingID: UUID, roomID: UUID, floorLabel: String, confirmedAt: Date = Date()) {
        self.buildingID = buildingID; self.roomID = roomID; self.floorLabel = floorLabel
        self.source = "manually-confirmed"; self.confirmedAt = confirmedAt
    }
}

/// Depth is evidence about a surface, never a semantic object or a clear path.
public struct SceneAwarenessFilter {
    private var previous: (time: TimeInterval, distance: Float)?
    private var stableCount = 0
    private var lastAlert: TimeInterval = -.infinity
    public init() {}
    public mutating func update(distance: Float?, coverage: Float, timestamp: TimeInterval, now: TimeInterval, tracking: Bool, upright: Bool) -> Float? {
        guard tracking, upright, timestamp.isFinite, now.isFinite, now >= timestamp, now-timestamp < 0.5,
              coverage >= 0.65, let distance, distance.isFinite, distance > 0.25, distance < 1.8 else {
            previous = nil; stableCount = 0; return nil
        }
        if let previous {
            guard timestamp > previous.time else { return nil }
            stableCount = timestamp-previous.time < 0.5 && abs(distance-previous.distance) < 0.3 ? stableCount+1 : 1
        } else { stableCount = 1 }
        previous = (timestamp, distance)
        guard stableCount >= 3, now-lastAlert >= 8 else { return nil }
        lastAlert = now; return distance
    }
}

public enum BuildingQualifier {
    /// Explicit building names must agree with the active saved map. GPS never participates.
    public static func matches(_ request: String, building: String) -> Bool {
        var text = request.lowercased()
        guard let range = text.range(of: " in ", options: .backwards) else { return true }
        text = String(text[range.upperBound...])
        for phrase in ["avoid stairs", "without stairs", "no stairs", "please", "instead"] { text = text.replacingOccurrences(of: phrase, with: "") }
        func words(_ value: String) -> String { value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") }
        return words(text) == words(building)
    }
}

public enum SceneObservationValidity {
    public static func isFresh(capturedAt: TimeInterval, now: TimeInterval, movement: Float, forwardAgreement: Float) -> Bool {
        capturedAt.isFinite && now.isFinite && now >= capturedAt && now-capturedAt < 1.5 &&
        movement.isFinite && movement >= 0 && movement < 0.35 && forwardAgreement.isFinite && forwardAgreement > 0.9
    }
}
