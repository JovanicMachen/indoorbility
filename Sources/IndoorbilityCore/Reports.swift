import Foundation

public struct Preferences: Codable, Equatable {
    public var avoidStairs = true
    public var speech = false
    public var haptics = true
    public var reducedInformation = false
    public init() {}
}

public struct BarrierReport: Codable, Identifiable, Equatable {
    public enum Lifecycle: String, Codable { case proposed, confirmed, resolved }
    public enum Source: String, Codable { case manual, photo, demo }
    public let id: UUID
    public let targetEdgeID: String
    public let proposedStatus: String
    public let source: Source
    public let createdAt: Date
    public let recognizedText: String?
    public var confirmedAt: Date?
    public var resolvedAt: Date?
    public var lastReviewedAt: Date?
    public func needsReview(at date: Date = Date()) -> Bool {
        isActive && date.timeIntervalSince(lastReviewedAt ?? confirmedAt ?? createdAt) >= 24 * 60 * 60
    }
    public var lifecycle: Lifecycle

    public init(targetEdgeID: String, id: UUID = UUID(), date: Date = Date(), source: Source = .manual, recognizedText: String? = nil) {
        self.id = id; self.targetEdgeID = targetEdgeID; self.createdAt = date
        self.recognizedText = recognizedText
        self.source = source; proposedStatus = "unavailable"; lifecycle = .proposed
    }
    public var isActive: Bool { lifecycle == .confirmed && resolvedAt == nil }
    public mutating func confirm(at date: Date = Date()) {
        guard lifecycle == .proposed else { return }
        lifecycle = .confirmed; confirmedAt = date
    }
    public mutating func resolve(at date: Date = Date()) {
        guard isActive else { return }
        lifecycle = .resolved; resolvedAt = date
    }
}

public struct SavedState: Codable, Equatable {
    public var version = 1
    public let buildingID: String
    public var preferences = Preferences()
    public var reports: [BarrierReport] = []
    public init(buildingID: String) { self.buildingID = buildingID }
    public var blockedEdges: Set<String> { Set(reports.filter(\.isActive).map(\.targetEdgeID)) }

    public func validate(for building: Building) throws {
        guard version == 1, buildingID == building.buildingID,
              Set(reports.map(\.id)).count == reports.count,
              reports.allSatisfy({ report in
                  building.edges.contains { $0.id == report.targetEdgeID } &&
                  report.proposedStatus == "unavailable" &&
                  (report.lifecycle != .confirmed || (report.confirmedAt != nil && report.resolvedAt == nil)) &&
                  (report.lifecycle != .resolved || (report.confirmedAt != nil && report.resolvedAt != nil))
              }) else { throw MapError.invalid("Saved reports could not be validated. Your saved file has been preserved.") }
    }
}

public protocol StatePersistence {
    func load(for building: Building) throws -> SavedState?
    func save(_ state: SavedState) throws
}

public struct FileStatePersistence: StatePersistence {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load(for building: Building) throws -> SavedState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try JSONDecoder().decode(SavedState.self, from: Data(contentsOf: url))
        try state.validate(for: building)
        return state
    }
    /// Explicit recovery keeps the original bytes before allowing a fresh demo session.
    @discardableResult public func backupForRecovery(id: UUID = UUID()) throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let backup = url.deletingLastPathComponent().appendingPathComponent("state-backup-\(id.uuidString).json")
        try FileManager.default.moveItem(at: url, to: backup)
        return backup
    }
    public func save(_ state: SavedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
