import Foundation

/// Source-reviewed identity data, deliberately separate from routable metric geometry.
/// Neither a room number nor an OCR match establishes a camera pose.
public enum FriendCenter {
    public struct Room: Identifiable, Equatable, Sendable {
        public let id: String
        public let level: String
        public let approach: String
        public var source: URL { URL(string: "https://www.accessableusa.com/princeton-university/access-guides/friend-center-\(id)")! }
    }
    public static let name = "Friend Center for Engineering Education"
    public static let levels = ["LL", "L", "1", "2", "3"]
    public static let reviewedOn = "2026-11-14"
    public static let source = URL(string: "https://www.accessableusa.com/princeton-university/access-guides/friend-center")!
    public static let rooms = [
        Room(id: "006", level: "LL", approach: "The guide places this room left of the elevator exit; an alternate entrance is also along the left corridor."),
        Room(id: "008", level: "LL", approach: "The guide places the main entrance right of the elevator exit, with an alternate entrance to the left.")
    ]
    public static let buildingFacts = [
        "Signed levels: LL, L, 1, 2, 3. One elevator and two stairways are reported.",
        "Olden Street: step-free entry at L, with elevator access to LL.",
        "Shapiro Walk: step-free entry at 1; elevator access there requires a key card. The guide reports a 9% ramp alternative via L.",
        "William Street: stepped entry with manual doors.",
        "Upper-level office areas require card access. Public access must not be assumed.",
        "An LL ramp serves 016, 017 and the Computer Science link. Its geometry is not mapped here."
    ]
    public static let routeStatus = "Room verified in published sources. Measured hallway geometry and camera alignment are not yet available; indoor guidance is unavailable."
    public static let indoorRoutingAvailable = false

    /// Exact numeric tokens avoid 006 matching 1006. A different explicit building is not resolved here.
    public static func search(_ query: String) -> [Room] {
        let tokens = query.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        if tokens.contains("frist") { return [] }
        let numeric = tokens.filter { $0.allSatisfy(\.isNumber) }
        if !numeric.isEmpty { return rooms.filter { numeric.contains($0.id) } }
        return tokens.contains("friend") ? rooms : []
    }
    public static func recognizedRooms(in text: String) -> [Room] {
        let tokens = text.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return rooms.filter { tokens.contains($0.id) }
    }
}
