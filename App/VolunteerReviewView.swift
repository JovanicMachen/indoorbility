import SwiftUI
import SceneKit
import IndoorbilityCore

extension ScanLibrary {
    func requiresVolunteerReview(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: directory(id).appending(path: "volunteer-draft.json").path)
    }
    func visitorReady(_ route: HallwayRoute) -> Bool {
        visitorReady(route, visited: [])
    }
    private func visitorReady(_ route: HallwayRoute, visited: Set<UUID>) -> Bool {
        guard !visited.contains(route.id), visited.count < 32 else { return false }
        guard sourceRoutesAvailable(route, visited: visited) else { return false }
        guard requiresVolunteerReview(route.scanID) else { return true } // Preserve existing reviewed routes.
        if let draft = scans.first(where: { $0.id == route.scanID }),
           let bytes = try? Data(contentsOf: directory(route.scanID).appending(path: "route-publication.json")),
           let publication = try? JSONDecoder().decode(RoutePublication.self, from: bytes),
           (try? publication.validate(for: route, draft: draft)) != nil { return true }
        guard let data = try? Data(contentsOf: directory(route.scanID).appending(path: "volunteer-review.json")),
              let review = try? JSONDecoder().decode(VolunteerReview.self, from: data),
              (try? review.validate(for: route)) != nil else { return false }
        return true
    }
    func sourceRoutesAvailable(_ route: HallwayRoute, visited: Set<UUID> = []) -> Bool {
        let provenance = directory(route.scanID).appending(path: "source-routes.json")
        if FileManager.default.fileExists(atPath: provenance.path) {
            guard let data = try? Data(contentsOf: provenance), let ids = try? JSONDecoder().decode([UUID].self, from: data), !ids.isEmpty, ids.count <= 32 else { return false }
            let sources = scans.compactMap { try? hallway($0) }
            for id in ids {
                guard let source = sources.first(where: { $0.id == id }), visitorReady(source, visited: visited.union([route.id])),
                      let state = try? navigationStore(source), state.blockedEdges.isEmpty else { return false }
            }
        }

        return true
    }

}

struct VolunteerReviewView: View {
    @ObservedObject var library: ScanLibrary
    @ObservedObject var settings: AppStore
    let draft: ScanDraft
    let route: HallwayRoute
    @State private var meshes: [MeshRecord] = []
    @State private var checking = true
    @State private var checksPassed = false
    @State private var saved = false
    @State private var error: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(route.room.label).font(.largeTitle.bold())
                Text(draft.name).foregroundStyle(.secondary)
                if meshes.isEmpty {
                    ZStack {
                        Color.indoorCard
                        if checking { ProgressView("Loading your scan…") }
                        else { Text("3D scan unavailable").foregroundStyle(.secondary) }
                    }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    RecordedMeshPreview(meshes: meshes, rotating: !reduceMotion)
                        .frame(height: 320).clipShape(RoundedRectangle(cornerRadius: 24))
                        .accessibilityLabel("Recorded 3D surroundings")
                }
                Label(saved ? "Published on this iPhone" : checking ? "Checking recording…" : error == nil ? "Recording checked" : "Recording needs attention",
                      systemImage: saved ? "checkmark.circle.fill" : "viewfinder")
                    .foregroundStyle(Color.indoorTeal).font(.headline)
                Text("\(route.entrance.label) → \(route.room.label)").font(.headline)
                Text(String(format: "Recorded distance · %.1f m", route.distance)).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
                Button(saved ? "Published" : "Publish route", action: publish)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(checking || !checksPassed || saved)
                Text("Checks cover the recording, not building access or live obstacles.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(Color.indoorBackground).navigationTitle("Your scan")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                saved = library.visitorReady(route)
                do {
                    let file = library.directory(draft.id).appending(path: "mesh.json")
                    meshes = try await Task.detached(priority: .userInitiated) {
                        let data = try Data(contentsOf: file)
                        guard data.count <= 160 * 1024 * 1024 else { throw MapError.invalid("Scan is too large to preview.") }
                        let records = try JSONDecoder().decode([MeshRecord].self, from: data)
                        guard records.contains(where: { !$0.triangles.isEmpty }) else { throw MapError.invalid("No 3D surfaces were saved.") }
                        for mesh in records {
                            guard mesh.vertices.allSatisfy(\.isFinite), mesh.triangles.count % 3 == 0,
                                  mesh.triangles.allSatisfy({ Int($0) < mesh.vertices.count }) else {
                                throw MapError.invalid("The saved 3D scan is damaged.")
                            }
                        }
                        return records
                    }.value
                    guard let current = try library.hallway(draft), current == route else {
                        throw MapError.invalid("Route changed. Reopen this scan.")
                    }
                    _ = try library.worldMap(draft)
                    _ = try RoutePublication(route: current, draft: draft)
                    checksPassed = true
                } catch { self.error = error.localizedDescription }
                checking = false
            }
    }
    private func publish() {
        do {
            guard let current = try library.hallway(draft), current == route else {
                throw MapError.invalid("Route changed. Reopen this scan.")
            }
            let publication = try RoutePublication(route: current, draft: draft)
            try JSONEncoder().encode(publication).write(to: library.directory(draft.id).appending(path: "route-publication.json"), options: .atomic)
            try JourneyLibrary().remember(current, building: draft.name)
            library.objectWillChange.send()
            saved = true; error = nil
            settings.speak("Route published.")
        } catch { self.error = error.localizedDescription }
    }
}

/// Displays actual saved triangles. Camera orbits the scan once every 30 seconds.
private struct RecordedMeshPreview: UIViewRepresentable {
    let meshes: [MeshRecord]
    let rotating: Bool
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = UIColor(Color.indoorCard)
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        let model = SCNNode()
        scene.rootNode.addChildNode(model)
        let total = meshes.reduce(0) { $0 + $1.triangles.count / 3 }
        let strideSize = max(1, Int(ceil(Double(total) / 60000)))
        var low = SCNVector3(Float.infinity, Float.infinity, Float.infinity)
        var high = SCNVector3(-Float.infinity, -Float.infinity, -Float.infinity)
        for mesh in meshes where !mesh.triangles.isEmpty {
            var vertices: [SCNVector3] = []
            for triangle in stride(from: 0, to: mesh.triangles.count / 3, by: strideSize) {
                for offset in 0..<3 {
                    let p = mesh.vertices[Int(mesh.triangles[triangle * 3 + offset])]
                    vertices.append(SCNVector3(p.x, p.y, p.z))
                    low = SCNVector3(min(low.x,p.x), min(low.y,p.y), min(low.z,p.z))
                    high = SCNVector3(max(high.x,p.x), max(high.y,p.y), max(high.z,p.z))
                }
            }
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)],
                elements: [SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(Color.indoorTeal).withAlphaComponent(0.85)
            material.isDoubleSided = true
            geometry.materials = [material]
            model.addChildNode(SCNNode(geometry: geometry))
        }
        let center = SCNVector3((low.x+high.x)/2, (low.y+high.y)/2, (low.z+high.z)/2)
        model.position = SCNVector3(-center.x, -center.y, -center.z)
        let radius = max(1, sqrt(pow(high.x-low.x,2)+pow(high.y-low.y,2)+pow(high.z-low.z,2))/2)
        let orbit = SCNNode(); orbit.name = "orbit"
        scene.rootNode.addChildNode(orbit)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(radius * 1.25)
        camera.camera?.zFar = Double(radius * 10 + 100)
        camera.position = SCNVector3(0, radius * 1.2, radius * 2.5)
        camera.look(at: SCNVector3Zero)
        orbit.addChildNode(camera); view.pointOfView = camera
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        guard let orbit = view.scene?.rootNode.childNode(withName: "orbit", recursively: false) else { return }
        if rotating && orbit.action(forKey: "rotate") == nil {
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 30)), forKey: "rotate")
        } else if !rotating { orbit.removeAction(forKey: "rotate") }
        view.isPlaying = rotating
    }
    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.scene?.rootNode.childNodes.forEach { $0.removeAllActions() }
        view.isPlaying = false
        view.scene = nil
    }
}
