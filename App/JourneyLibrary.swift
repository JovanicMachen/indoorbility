import SwiftUI
import IndoorbilityCore
import CoreLocation

struct EntranceLocation: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let confirmedAt: Date
}

@MainActor final class JourneyLibrary: ObservableObject {
    @Published private(set) var destinations: [JourneyDestination] = []
    @Published var error: String?
    private var groupKeys: [UUID: String] = [:]
    private var starts: [UUID: String] = [:]
    var preferredDestinations: [JourneyDestination] {
        var seen = Set<String>()
        return destinations.filter { seen.insert(groupKeys[$0.id] ?? $0.id.uuidString).inserted }
    }
    func alternatives(to item: JourneyDestination) -> [JourneyDestination] {
        destinations.filter { groupKeys[$0.id] != nil && groupKeys[$0.id] == groupKeys[item.id] }
    }
    func startingLabel(_ item: JourneyDestination) -> String { starts[item.id] ?? "Confirmed start landmark" }
    private let url = URL.applicationSupportDirectory.appending(path: "Indoorbility/destinations.json")
    init() { reload() }
    func reload() {
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                destinations = try JSONDecoder().decode([JourneyDestination].self, from: Data(contentsOf: url))
            }
        } catch { self.error = "Could not read remembered destinations. Existing data was preserved." }
    }
    func remember(_ route: HallwayRoute, building: String, arrived: Bool = false) throws {
        guard error == nil else { throw MapError.invalid(error!) }
        guard ScanLibrary().visitorReady(route) else { return }
        var updated = destinations
        var item = updated.first(where: { $0.id == route.id }) ?? JourneyDestination(route: route, building: building)
        if arrived { item.lastVisited = Date(); item.successfulVisits = min(1000000, max(0, item.successfulVisits ?? 0) + 1) }
        updated.removeAll { $0.id == item.id }; updated.insert(item, at: 0)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: url, options: .atomic)
        destinations = updated
    }
    /// Explicit deletion removes visit history as well as the visible destination.
    func forget(scanID: UUID) throws {
        let all: [JourneyDestination] = FileManager.default.fileExists(atPath: url.path)
            ? try JSONDecoder().decode([JourneyDestination].self, from: Data(contentsOf: url)) : []
        let remaining = all.filter { $0.scanID != scanID }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(remaining).write(to: url, options: .atomic)
        destinations.removeAll { $0.scanID == scanID }
    }
    func refresh(from scans: ScanLibrary) {
        reload()
        guard error == nil else { return }
        do {
            for draft in scans.scans {
                if let route = try scans.hallway(draft), scans.visitorReady(route), !destinations.contains(where: { $0.id == route.id }) {
                    try remember(route, building: draft.name)
                }
            }
            // Hide removed scans; never silently erase their saved visit history from disk.
            groupKeys = [:]; starts = [:]
            var evidence: [UUID: RecordingEvidence] = [:]
            destinations = destinations.filter { item in
                guard let draft = scans.scans.first(where: { $0.id == item.scanID }),
                      let route = try? scans.hallway(draft) else { return false }
                guard route.id == item.routeID, scans.visitorReady(route),
                      let state = try? scans.navigationStore(route), state.blockedEdges.isEmpty else { return false }
                let directory = scans.directory(draft.id)
                let review = (try? Data(contentsOf: directory.appending(path: "volunteer-review.json"))).flatMap { try? JSONDecoder().decode(VolunteerReview.self, from: $0) }
                let validReview = review.flatMap { (try? $0.validate(for: route)) != nil ? $0 : nil }
                let metadata = (try? Data(contentsOf: directory.appending(path: "room-metadata.json"))).flatMap { try? JSONDecoder().decode(VerifiedRoomMetadata.self, from: $0) }
                let floor = metadata.flatMap { $0.buildingID == draft.id && $0.roomID == route.room.id ? $0.floorLabel : nil }
                // Unknown-floor recordings remain separate; no number-to-floor inference.
                groupKeys[item.id] = [item.building.lowercased().trimmingCharacters(in: .whitespaces), floor ?? item.id.uuidString, item.room.lowercased().trimmingCharacters(in: .whitespaces)].joined(separator: "|")
                starts[item.id] = route.entrance.label
                evidence[item.id] = RecordingEvidence(id: item.id, fieldReviewed: validReview != nil,
                    successfulVisits: item.successfulVisits ?? 0, measuredError: validReview?.endpointError, reviewedAt: validReview?.reviewedAt)
                return true
            }
            destinations.sort { a, b in
                guard let lhs = evidence[a.id], let rhs = evidence[b.id] else { return a.id.uuidString < b.id.uuidString }
                return RecordingEvidence.preferred(lhs, over: rhs)
            }
        } catch { self.error = error.localizedDescription }
    }
}
