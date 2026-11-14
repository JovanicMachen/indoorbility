import Foundation

/// A requested destination is not evidence that the room or its floor exists.
public struct RoomMappingRequest: Identifiable, Equatable, Sendable {
    public var id: String { building + "|" + room }
    public let building: String
    public let room: String
    public let verifiedFloor: String?
    public init(building: String, room: String, verifiedFloor: String? = nil) {
        self.building = building; self.room = room; self.verifiedFloor = verifiedFloor
    }
    /// Only room language may inherit a selected building; an explicit other place must not.
    public static func roomNumber(_ text: String) -> String? {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let filler: Set<String> = ["take", "walk", "guide", "me", "to", "room", "number", "please", "go", "navigate", "find", "the", "actually", "instead"]
        let meaningful = words.filter { !filler.contains($0) }
        guard !meaningful.isEmpty, !meaningful.contains("or") else { return nil }
        let digits = ["zero":"0", "oh":"0", "one":"1", "two":"2", "three":"3", "four":"4", "five":"5", "six":"6", "seven":"7", "eight":"8", "nine":"9"]
        let numeric = meaningful.filter { $0.allSatisfy(\.isNumber) }
        if numeric.count == 1 && meaningful.count == 1 {
            return (1...4).contains(numeric[0].count) ? numeric[0] : nil
        }
        if meaningful.allSatisfy({ digits[$0] != nil }), meaningful.count <= 4 {
            return meaningful.compactMap { digits[$0] }.joined()
        }
        // Support speech transcripts such as “one hundred twelve”, but not another building name.
        let numberWords: Set<String> = Set(digits.keys).union(["ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred", "thousand", "and"])
        guard numeric.isEmpty, meaningful.allSatisfy({ numberWords.contains($0) }),
              !meaningful.contains("and") || meaningful.contains("hundred") || meaningful.contains("thousand") else { return nil }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US"); formatter.numberStyle = .spellOut
        guard let value = formatter.number(from: meaningful.joined(separator: " "))?.intValue, (0...9999).contains(value) else { return nil }
        return String(value)
    }
    /// Extracts a building search and room request, not a verified place or room.
    public static func attached(_ text: String) -> Self? {
        if let known = friend(text) { return known }
        var words = text.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        let prefixes = ["take me to", "navigate to", "go to", "find", "please"]
        var cleaned = words.joined(separator: " ")
        for prefix in prefixes {
            if cleaned.lowercased().hasPrefix(prefix + " ") { cleaned = String(cleaned.dropFirst(prefix.count + 1)) }
        }
        words = cleaned.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        let lower = words.map { $0.lowercased() }
        if let marker = lower.firstIndex(where: { ["room", "rm", "rm."].contains($0) }), marker > 0 {
            let building = words[..<marker].joined(separator: " ")
            guard let number = roomNumber(words[(marker + 1)...].joined(separator: " ")) else { return nil }
            return Self(building: building, room: number)
        }
        // A trailing number on a building-like name is a room candidate. Street addresses stay searches.
        let buildingKinds: Set<String> = ["hall", "center", "centre", "building", "library", "tower", "annex", "lab", "laboratory", "school", "hospital"]
        guard lower.dropLast().contains(where: { buildingKinds.contains($0) }),
              let last = words.last, last.allSatisfy(\.isNumber), let number = roomNumber(last),
              !words.dropLast().contains(where: { $0.contains(where: \.isNumber) }),
              !lower.contains("or"), !lower.contains("and") else { return nil }
        return Self(building: words.dropLast().joined(separator: " "), room: number)
    }
    public static func resolve(_ text: String, selectedBuilding: String?) -> Self? {
        if let explicit = attached(text) { return explicit }
        guard let building = selectedBuilding?.trimmingCharacters(in: .whitespacesAndNewlines), !building.isEmpty,
              let room = roomNumber(text) else { return nil }
        let floor = building == FriendCenter.name ? FriendCenter.rooms.first { $0.id == room }?.level : nil
        return Self(building: building, room: room, verifiedFloor: floor)
    }
    public static func friend(_ text: String) -> Self? {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !words.contains("frist"), words.contains("friend") || words.contains("frend") else { return nil }
        let roomWords = words.filter { !["friend", "frend", "center", "for", "engineering", "education"].contains($0) }
        guard let number = roomNumber(roomWords.joined(separator: " ")) else { return nil }
        let known = FriendCenter.rooms.first { $0.id == number }
        return Self(building: FriendCenter.name, room: number, verifiedFloor: known?.level)
    }
}
