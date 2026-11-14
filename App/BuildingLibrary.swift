import SwiftUI
import IndoorbilityCore

@MainActor enum BuildingLibrary {
    static let root = URL.applicationSupportDirectory.appending(path: "Indoorbility/Buildings")
    static func all() throws -> [BuildingNetwork] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(BuildingNetwork.self, from: Data(contentsOf: $0)) }
    }
    static func save(_ network: BuildingNetwork) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(network).write(to: root.appending(path: network.id.uuidString + ".json"), options: .atomic)
    }
    static func saveImported(_ network: BuildingNetwork) throws {
        // Imports are separate copies; never overwrite local edits or inherit a field-review assertion.
        var copy = network; copy.id = UUID(); try save(copy)
    }
    static func floor(_ draft: ScanDraft, library: ScanLibrary) throws -> String {
        let metadata = try JSONDecoder().decode(VerifiedRoomMetadata.self, from: Data(contentsOf: library.directory(draft.id).appending(path: "room-metadata.json")))
        guard metadata.buildingID == draft.id, let route = try library.hallway(draft), metadata.roomID == route.room.id, !metadata.floorLabel.isEmpty else { throw MapError.invalid("Review this recording’s signed floor first.") }
        return metadata.floorLabel
    }
}

struct BuildingCollectionsView: View {
    @ObservedObject var library: ScanLibrary
    @ObservedObject var settings: AppStore
    @State private var networks: [BuildingNetwork] = []
    @State private var message = ""
    var body: some View {
        List {
            Section("Buildings") {
                ForEach(networks) { network in
                    NavigationLink(network.name + " · " + network.floor) { BuildingConnectionsView(library: library, settings: settings, network: network) }
                }
                if networks.isEmpty { Text("Start with a reviewed recording, then connect another area using two shared landmarks.") }
            }
            Section("Start a building map") {
                ForEach(library.scans) { draft in
                    if let route = try? library.hallway(draft), library.visitorReady(route) {
                        Button(draft.name + " · " + route.room.label) {
                            do {
                                try BuildingLibrary.save(BuildingNetwork(name: draft.name, floor: BuildingLibrary.floor(draft, library: library), route: route))
                                networks = try BuildingLibrary.all()
                            } catch { message = error.localizedDescription }
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message) }
        }.navigationTitle("Building maps").onAppear { do { networks = try BuildingLibrary.all() } catch { message = error.localizedDescription } }
    }
}

struct BuildingConnectionsView: View {
    @ObservedObject var library: ScanLibrary
    @ObservedObject var settings: AppStore
    @State var network: BuildingNetwork
    @State private var baseID: UUID?
    @State private var newID: UUID?
    @State private var a: UUID?
    @State private var b: UUID?
    @State private var c: UUID?
    @State private var d: UUID?
    @State private var confirmed = false
    @State private var message = ""
    private var members: [ScanDraft] { library.scans.filter { scan in network.segments.contains { $0.scanID == scan.id } } }
    private var candidates: [ScanDraft] { library.scans.filter { scan in !network.segments.contains { $0.scanID == scan.id } && (try? BuildingLibrary.floor(scan, library: library)) == network.floor } }
    var body: some View {
        Form {
            Section(network.name + " · " + network.floor) {
                Text("\(network.segments.count) recordings · \(network.links.count) confirmed connections")
                NavigationLink("Share building map") { MapTransferView(library: library, drafts: members, network: network) }
            }
            Section("Connect another recording") {
                scanPicker("Existing area", selection: $baseID, scans: members)
                scanPicker("New area", selection: $newID, scans: candidates)
                if let base = members.first(where: { $0.id == baseID }), let next = candidates.first(where: { $0.id == newID }) {
                    Text("Match two physical landmarks at least 2 metres apart. The first must lie on both walked paths.").font(.footnote)
                    landmarkPicker("Existing landmark 1", selection: $a, draft: base)
                    landmarkPicker("New landmark 1", selection: $c, draft: next)
                    landmarkPicker("Existing landmark 2", selection: $b, draft: base)
                    landmarkPicker("New landmark 2", selection: $d, draft: next)
                    Toggle("Same building, floor and physical landmarks", isOn: $confirmed)
                    Button("Connect recordings") { connect(base, next) }.disabled(!confirmed || [a,b,c,d].contains(nil))
                }
            }
            Section("Prepare connected directions") {
                Text("Choose a start and destination, then preview and publish the route.").font(.footnote)
                ForEach(members) { destination in
                    if destination.id != network.segments.first?.scanID {
                        Button("Prepare route to " + ((try? library.hallway(destination))?.room.label ?? destination.name)) {
                            do { try prepare(destination); message = "Route saved. Open Saved rooms & areas to publish it." }
                            catch { message = error.localizedDescription }
                        }
                    }
                }
            }
            if !message.isEmpty { Text(message) }
        }.navigationTitle("Connected areas")
            .onChange(of: baseID) { _,_ in a = nil; b = nil; confirmed = false }
            .onChange(of: newID) { _,_ in c = nil; d = nil; confirmed = false }
    }
    private func scanPicker(_ title: String, selection: Binding<UUID?>, scans: [ScanDraft]) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(nil as UUID?)
            ForEach(scans) { scan in Text((try? library.hallway(scan))?.room.label ?? scan.name).tag(Optional(scan.id)) }
        }
    }
    private func landmarkPicker(_ title: String, selection: Binding<UUID?>, draft: ScanDraft) -> some View {
        Picker(title, selection: selection) {
            Text("Choose").tag(nil as UUID?)
            ForEach(draft.landmarks) { Text($0.label).tag(Optional($0.id)) }
        }
    }
    private func connect(_ base: ScanDraft, _ next: ScanDraft) {
        do {
            guard let old = try library.hallway(base), let new = try library.hallway(next), library.visitorReady(old), library.visitorReady(new),
                  let pa = base.landmarks.first(where: { $0.id == a }), let pb = base.landmarks.first(where: { $0.id == b }),
                  let pc = next.landmarks.first(where: { $0.id == c }), let pd = next.landmarks.first(where: { $0.id == d }) else { throw MapError.invalid("Review both recordings and select two landmarks first.") }
            var updated = network
            try updated.extend(base: old, new: new, baseA: pa.position, baseB: pb.position, newA: pc.position, newB: pd.position, confirmedFloor: BuildingLibrary.floor(next, library: library))
            try BuildingLibrary.save(updated); network = updated; confirmed = false; newID = nil
            message = "Connected. Original recordings are unchanged."
        } catch { message = error.localizedDescription }
    }
    private func prepare(_ destination: ScanDraft) throws {
        guard let first = network.segments.first, let base = members.first(where: { $0.id == first.scanID }), let end = try library.hallway(destination) else { throw MapError.invalid("A source recording is missing.") }
        var routes: [UUID: HallwayRoute] = [:], blocked = Set<UUID>()
        for scan in members {
            guard let route = try library.hallway(scan), library.visitorReady(route), try BuildingLibrary.floor(scan, library: library) == network.floor else { throw MapError.invalid("Review all source recordings first.") }
            routes[route.id] = route
            if !(try library.navigationStore(route)).blockedEdges.isEmpty { blocked.insert(route.id) }
        }
        let path = try network.path(from: first.routeID, to: end.id, routes: routes, blocked: blocked)
        guard let start = routes[first.routeID], let p = path.points.first, let q = path.points.last else { throw MapError.invalid("No connected path.") }
        let entry = ScanLandmark(label: start.entrance.label, kind: "entrance", position: p)
        let room = ScanLandmark(label: end.room.label, kind: "room", position: q)
        // Copy only measured mesh geometry, transformed into the original world-map coordinates.
        var meshes: [MeshRecord] = []
        for segment in network.segments where path.routeIDs.contains(segment.routeID) {
            let source = try JSONDecoder().decode([MeshRecord].self, from: Data(contentsOf: library.directory(segment.scanID).appending(path: "mesh.json")))
            meshes += source.map { MeshRecord(vertices: $0.vertices.map(segment.alignment.apply), triangles: $0.triangles) }
        }
        let draft = ScanDraft(name: network.name, usesLiDAR: true, hasWorldMap: true, samples: path.points.map { ScanSample(position: $0, segment: 0) }, landmarks: [entry, room], meshVertexCount: meshes.reduce(0) { $0 + $1.vertices.count }, meshTriangleCount: meshes.reduce(0) { $0 + $1.triangles.count / 3 })
        let route = try HallwayRoute.make(draft: draft, entranceID: entry.id, roomID: room.id, reviewed: true)
        try library.save(draft, map: library.worldMap(base), mesh: JSONEncoder().encode(meshes))
        do {
            try library.saveHallway(route, draft: draft)
            try JSONEncoder().encode(VerifiedRoomMetadata(buildingID: draft.id, roomID: room.id, floorLabel: network.floor)).write(to: library.directory(draft.id).appending(path: "room-metadata.json"), options: .atomic)
            // Provenance is checked before guidance so source closures/deletions invalidate this copy.
            try JSONEncoder().encode(Array(path.routeIDs)).write(to: library.directory(draft.id).appending(path: "source-routes.json"), options: .atomic)
        } catch { try? library.delete(draft); throw error }
    }
}
