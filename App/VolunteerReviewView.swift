import SwiftUI
import SceneKit
import simd
import IndoorbilityCore

private enum ScanPreviewStyle {
    static let background = Color(red: 0.78, green: 0.70, blue: 0.60)
}

extension ScanLibrary {
    /// Saves local availability after structural checks, without a second setup form.
    func publishRecording(_ route: HallwayRoute, draft: ScanDraft) throws {
        guard let current = try hallway(draft), current == route else {
            throw MapError.invalid("Route changed. Reopen this scan.")
        }
        let publication = try RoutePublication(route: current, draft: draft)
        try JSONEncoder().encode(publication).write(to: directory(draft.id).appending(path: "route-publication.json"), options: .atomic)
        try JourneyLibrary().remember(current, building: draft.name)
        objectWillChange.send()
    }
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
                        ScanPreviewStyle.background
                        if checking { ProgressView("Loading your scan…") }
                        else { Text("3D scan unavailable").foregroundStyle(.secondary) }
                    }.frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                } else {
                    MeshGalleryView(meshes: meshes)
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
                    meshes = try await SavedMeshLoader.load(file)
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
            try library.publishRecording(route, draft: draft)
            saved = true; error = nil
            settings.speak("Route published.")
        } catch { self.error = error.localizedDescription }
    }
}

/// Displays actual saved triangles with a slow, continuous camera orbit.
struct RecordedMeshPreview: UIViewRepresentable {
    let meshes: [MeshRecord]
    let rotating: Bool
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = UIColor(ScanPreviewStyle.background)
        view.autoenablesDefaultLighting = false
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 1, green: 0.91, blue: 0.87, alpha: 1)
        ambient.light?.intensity = 650; scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 1000; key.eulerAngles = SCNVector3(-0.7, -0.6, 0)
        scene.rootNode.addChildNode(key)
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        let model = SCNNode()
        scene.rootNode.addChildNode(model)
        let total = meshes.reduce(0) { $0 + $1.triangles.count / 3 }
        let strideSize = max(1, Int(ceil(Double(total) / 60000)))
        var low = SCNVector3(Float.infinity, Float.infinity, Float.infinity)
        var high = SCNVector3(-Float.infinity, -Float.infinity, -Float.infinity)
        var minY = Float.infinity, maxY = -Float.infinity
        for mesh in meshes { for p in mesh.vertices { minY = min(minY, p.y); maxY = max(maxY, p.y) } }
        for mesh in meshes where !mesh.triangles.isEmpty {
            var vertices: [SCNVector3] = []
            var colors: [SIMD4<Float>] = []
            var normals: [SCNVector3] = []
            for triangle in stride(from: 0, to: mesh.triangles.count / 3, by: strideSize) {
                for offset in 0..<3 {
                    let p = mesh.vertices[Int(mesh.triangles[triangle * 3 + offset])]
                    vertices.append(SCNVector3(p.x, p.y, p.z))
                    let height = max(0, min(1, (p.y-minY)/max(0.01, maxY-minY)))
                    let plum = SIMD3<Float>(0.39, 0.20, 0.36)
                    let peach = SIMD3<Float>(0.98, 0.77, 0.65)
                    let color = plum + (peach-plum)*height
                    colors.append(SIMD4(color.x, color.y, color.z, 1))
                    low = SCNVector3(min(low.x,p.x), min(low.y,p.y), min(low.z,p.z))
                    high = SCNVector3(max(high.x,p.x), max(high.y,p.y), max(high.z,p.z))
                }
                let a = vertices[vertices.count-3], b = vertices[vertices.count-2], c = vertices[vertices.count-1]
                let cross = simd_cross(SIMD3(b.x-a.x,b.y-a.y,b.z-a.z), SIMD3(c.x-a.x,c.y-a.y,c.z-a.z))
                let normal = simd_length_squared(cross) > 0.000001 ? simd_normalize(cross) : SIMD3<Float>(0,1,0)
                normals.append(contentsOf: Array(repeating: SCNVector3(normal.x, normal.y, normal.z), count: 3))
            }
            let colorSource = SCNGeometrySource(data: colors.withUnsafeBytes { Data($0) }, semantic: .color,
                vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
                elements: [SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.85
            material.metalness.contents = 0.08
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
            orbit.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 40)), forKey: "rotate")
        } else if !rotating { orbit.removeAction(forKey: "rotate") }
        view.allowsCameraControl = !rotating
        view.isPlaying = rotating
    }
    static func dismantleUIView(_ view: SCNView, coordinator: ()) {
        view.scene?.rootNode.childNodes.forEach { $0.removeAllActions() }
        view.isPlaying = false
        view.scene = nil
    }
}

enum SavedMeshLoader {
    static func load(_ file: URL) async throws -> [MeshRecord] {
        try await Task.detached(priority: .userInitiated) {
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 160 * 1024 * 1024 else { throw MapError.invalid("Scan is too large to preview.") }
            let data = try Data(contentsOf: file)
            let records = try JSONDecoder().decode([MeshRecord].self, from: data)
            guard records.contains(where: { !$0.triangles.isEmpty }) else { throw MapError.invalid("No 3D surfaces were saved.") }
            for mesh in records {
                guard mesh.vertices.allSatisfy({ $0.isFinite && abs($0.x) < 100000 && abs($0.y) < 100000 && abs($0.z) < 100000 }), mesh.triangles.count % 3 == 0,
                      mesh.triangles.allSatisfy({ Int($0) < mesh.vertices.count }) else {
                    throw MapError.invalid("The saved 3D scan is damaged.")
                }
            }
            // Prepare a bounded display copy off the main thread. Saved scan data is untouched.
            let total = records.reduce(0) { $0 + $1.triangles.count / 3 }
            let step = max(1, Int(ceil(Double(total) / 60000)))
            var vertices: [SpatialPoint] = []
            vertices.reserveCapacity(min(total, 60000) * 3)
            var ordinal = 0
            for mesh in records {
                for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
                    if ordinal % step == 0 {
                        for offset in 0..<3 { vertices.append(mesh.vertices[Int(mesh.triangles[i+offset])]) }
                    }
                    ordinal += 1
                }
            }
            return [MeshRecord(vertices: vertices, triangles: (0..<vertices.count).map(UInt32.init))]
        }.value
    }
}

struct SavedScanPreview: View {
    let file: URL
    @State private var meshes: [MeshRecord] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        Group {
            if !meshes.isEmpty { MeshGalleryView(meshes: meshes) }
            else {
                VStack(spacing: 12) {
                    if loading { ProgressView("Opening 3D scan…") }
                    else {
                        Image(systemName: "cube.transparent").font(.largeTitle)
                        Text("3D preview unavailable").font(.headline)
                        Text(error ?? "No surfaces were saved.").font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 280).padding()
                    .background(ScanPreviewStyle.background, in: RoundedRectangle(cornerRadius: 28))
            }
        }.task(id: file) {
            loading = true; meshes = []; error = nil
            do {
                let loaded = try await SavedMeshLoader.load(file)
                guard !Task.isCancelled else { return }
                meshes = loaded
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct MeshGalleryView: View {
    let meshes: [MeshRecord]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var paused = false
    @State private var visible = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Your space in 3D", systemImage: "cube.transparent").font(.headline)
                Spacer()
                Text("360°").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }.padding(20)
            RecordedMeshPreview(meshes: meshes, rotating: visible && phase == .active && !paused && !reduceMotion)
                .frame(height: 320)
                .accessibilityLabel("Captured LiDAR surfaces, shown as a three-dimensional model")
            HStack {
                Text(paused || reduceMotion ? "Drag to explore · pinch to zoom" : "A new view, every turn")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !reduceMotion {
                    Button { paused.toggle() } label: {
                        Image(systemName: paused ? "play.fill" : "pause.fill")
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel(paused ? "Rotate 3D scan" : "Pause rotation and explore")
                }
            }.padding(.horizontal, 20).padding(.bottom, 12)
        }.background(ScanPreviewStyle.background, in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.indoorTeal.opacity(0.1), lineWidth: 1))
            .onAppear { visible = true }.onDisappear { visible = false }
    }
}
