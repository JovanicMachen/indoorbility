import SwiftUI
import SceneKit
import simd
import IndoorbilityCore

private enum ScanPreviewStyle {
    /// Deep plum night so the vibrant surfaces stand out.
    static let background = Color(red: 0.13, green: 0.07, blue: 0.15)
    /// Floors and tables vibrant green; walls pink-magenta, a little lighter
    /// toward the ceiling so height still reads. No grey blend in between.
    static func color(height t: Float, wall: Bool) -> SIMD3<Float> {
        let h = max(0, min(1, t))
        if wall { return SIMD3<Float>(0.92, 0.12, 0.56) + SIMD3<Float>(0.08, 0.22, 0.14) * h }
        return SIMD3<Float>(0.12, 0.78, 0.36) + SIMD3<Float>(0.08, 0.17, 0.10) * h
    }
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
    /// Optional walked path, drawn as a glowing tube through the model.
    var path: [SpatialPoint] = []
    var transparentBackground = false
    /// >1 shows more of the model (full-screen viewer is taller than the card).
    var zoomOut: Double = 1
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = transparentBackground ? .clear : UIColor(ScanPreviewStyle.background)
        view.autoenablesDefaultLighting = false
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = UIColor.white
        ambient.light?.intensity = 800; scene.rootNode.addChildNode(ambient)
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
                    colors.append(SIMD4(height, 0, 0, 1)) // Placeholder; coloured once the face normal is known.
                    low = SCNVector3(min(low.x,p.x), min(low.y,p.y), min(low.z,p.z))
                    high = SCNVector3(max(high.x,p.x), max(high.y,p.y), max(high.z,p.z))
                }
                let a = vertices[vertices.count-3], b = vertices[vertices.count-2], c = vertices[vertices.count-1]
                let cross = simd_cross(SIMD3(b.x-a.x,b.y-a.y,b.z-a.z), SIMD3(c.x-a.x,c.y-a.y,c.z-a.z))
                let normal = simd_length_squared(cross) > 0.000001 ? simd_normalize(cross) : SIMD3<Float>(0,1,0)
                normals.append(contentsOf: Array(repeating: SCNVector3(normal.x, normal.y, normal.z), count: 3))
                let wall = abs(normal.y) < 0.6
                for k in (colors.count-3)..<colors.count {
                    let c = ScanPreviewStyle.color(height: colors[k].x, wall: wall)
                    colors[k] = SIMD4(c.x, c.y, c.z, 1)
                }
            }
            let colorSource = SCNGeometrySource(data: colors.withUnsafeBytes { Data($0) }, semantic: .color,
                vectorCount: colors.count, usesFloatComponents: true, componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals), colorSource],
                elements: [SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.white
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.55
            material.metalness.contents = 0.05
            material.emission.contents = UIColor(white: 0.12, alpha: 1) // Keeps colours bright in shadow.
            material.isDoubleSided = true
            geometry.materials = [material]
            model.addChildNode(SCNNode(geometry: geometry))
        }
        if let walked = ScanModelPath.node(path) {
            model.addChildNode(walked)
            for p in path {
                low = SCNVector3(min(low.x,p.x), min(low.y,p.y), min(low.z,p.z))
                high = SCNVector3(max(high.x,p.x), max(high.y,p.y), max(high.z,p.z))
            }
        }
        let center = SCNVector3((low.x+high.x)/2, (low.y+high.y)/2, (low.z+high.z)/2)
        model.position = SCNVector3(-center.x, -center.y, -center.z)
        let radius = max(1, sqrt(pow(high.x-low.x,2)+pow(high.y-low.y,2)+pow(high.z-low.z,2))/2)
        let orbit = SCNNode(); orbit.name = "orbit"
        scene.rootNode.addChildNode(orbit)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = Double(radius * 1.25) * zoomOut
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

/// The walked route as a glowing cyan tube with a green start and gold end
/// stop. Down-sampled so long walks stay cheap to draw.
enum ScanModelPath {
    static func node(_ path: [SpatialPoint]) -> SCNNode? {
        let points = path.filter(\.isFinite)
        guard points.count >= 2 else { return nil }
        let step = max(1, points.count / 160)
        var kept = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if kept.last != points.last { kept.append(points.last!) }
        let root = SCNNode()
        let glow = SCNMaterial()
        glow.diffuse.contents = UIColor(red: 0.30, green: 0.95, blue: 1.0, alpha: 1)
        glow.emission.contents = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 1)
        glow.lightingModel = .constant
        for (a, b) in zip(kept, kept.dropFirst()) {
            let va = SIMD3<Float>(a.x, a.y, a.z), vb = SIMD3<Float>(b.x, b.y, b.z)
            let length = simd_distance(va, vb)
            guard length > 0.01 else { continue }
            let tube = SCNCylinder(radius: 0.06, height: CGFloat(length)); tube.radialSegmentCount = 8
            tube.materials = [glow]
            let segment = SCNNode(geometry: tube)
            segment.simdPosition = (va + vb) / 2
            // SCNCylinder runs along +Y; turn it to point from a to b.
            segment.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(vb - va))
            root.addChildNode(segment)
        }
        func marker(_ p: SpatialPoint, _ color: UIColor) -> SCNNode {
            let sphere = SCNSphere(radius: 0.22); let m = SCNMaterial()
            m.diffuse.contents = color; m.emission.contents = color; m.lightingModel = .constant
            sphere.materials = [m]
            let node = SCNNode(geometry: sphere); node.simdPosition = SIMD3(p.x, p.y, p.z); return node
        }
        root.addChildNode(marker(kept[0], UIColor(red: 0.25, green: 0.95, blue: 0.45, alpha: 1)))
        root.addChildNode(marker(kept[kept.count-1], UIColor(red: 1.0, green: 0.80, blue: 0.20, alpha: 1)))
        return root
    }
}

/// Every saved scan as a real 3D model, on a deep night-sky backdrop.
struct ScanModelGalleryView: View {
    @ObservedObject var library: ScanLibrary
    var body: some View {
        ZStack {
            ScanModelBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your 3D spaces").font(.largeTitle.bold()).foregroundStyle(.white)
                    Text("Every LiDAR recording as a model you can spin, drag and pinch. The glowing line is the path you walked.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    if library.scans.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "cube.transparent").font(.system(size: 44)).foregroundStyle(.white.opacity(0.8))
                            Text("No 3D scans yet").font(.headline).foregroundStyle(.white)
                            Text("Record a route and its space is saved here.").font(.footnote).foregroundStyle(.white.opacity(0.7))
                        }.frame(maxWidth: .infinity).padding(.vertical, 60)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(library.scans) { draft in
                            NavigationLink { ScanModelViewer(library: library, draft: draft) } label: { card(draft) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("3D model of \(title(draft))")
                        }
                    }
                }.padding(20)
            }
        }.navigationTitle("3D models").navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .swipeLeftToGoBack()
            .onAppear { library.reload() }
    }
    private func title(_ draft: ScanDraft) -> String {
        if let route = try? library.hallway(draft) { return route.entrance.label + " → " + route.room.label }
        return draft.name
    }
    private func card(_ draft: ScanDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.92, green: 0.12, blue: 0.56).opacity(0.55), Color(red: 0.12, green: 0.78, blue: 0.36).opacity(0.45)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "cube.transparent.fill").font(.system(size: 40, weight: .light)).foregroundStyle(.white)
                    .shadow(color: .white.opacity(0.6), radius: 10)
            }.frame(height: 110).clipShape(RoundedRectangle(cornerRadius: 18))
            Text(title(draft)).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
            Text(draft.name + " · " + draft.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
        }.padding(10)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

/// One scan, full screen: the saved surfaces plus the walked path.
struct ScanModelViewer: View {
    @ObservedObject var library: ScanLibrary
    let draft: ScanDraft
    @State private var meshes: [MeshRecord] = []
    @State private var loading = true
    @State private var error: String?
    @State private var spinning = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    private var path: [SpatialPoint] {
        if let route = try? library.hallway(draft) { return route.path }
        return draft.samples.map(\.position)
    }
    var body: some View {
        ZStack {
            ScanModelBackdrop()
            if !meshes.isEmpty {
                RecordedMeshPreview(meshes: meshes, rotating: spinning && !reduceMotion && phase == .active, path: path, transparentBackground: true, zoomOut: 1.9)
                    .ignoresSafeArea(edges: .bottom)
                    .accessibilityLabel("Three-dimensional model of the scanned space with the walked path")
            } else if loading {
                ProgressView("Building your 3D model…").tint(.white).foregroundStyle(.white)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cube.transparent").font(.largeTitle)
                    Text("3D model unavailable").font(.headline)
                    Text(error ?? "No surfaces were saved.").font(.caption).opacity(0.7)
                }.foregroundStyle(.white)
            }
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    legend(Color(red: 0.25, green: 0.95, blue: 0.45), "Start")
                    legend(Color(red: 0.30, green: 0.95, blue: 1.0), "Path")
                    legend(Color(red: 1.0, green: 0.80, blue: 0.20), "End stop")
                    Spacer()
                    if !reduceMotion {
                        Button { spinning.toggle() } label: {
                            Image(systemName: spinning ? "pause.fill" : "rotate.3d").frame(width: 44, height: 44)
                        }.foregroundStyle(.white).background(.white.opacity(0.15), in: Circle())
                            .accessibilityLabel(spinning ? "Stop spinning and explore" : "Spin model")
                    }
                }.padding(14).background(.ultraThinMaterial.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
                    .environment(\.colorScheme, .dark)
                    .padding(16)
            }
        }.navigationTitle(draft.name).navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .swipeLeftToGoBack()
            .task(id: draft.id) {
                loading = true
                do { meshes = try await SavedMeshLoader.load(library.directory(draft.id).appending(path: "mesh.json")) }
                catch { self.error = error.localizedDescription }
                loading = false
            }
    }
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) { Circle().fill(color).frame(width: 10, height: 10); Text(text).font(.caption.weight(.medium)) }
            .foregroundStyle(.white)
    }
}

/// Night-sky gradient with soft glows and still stars. Static, so it costs nothing.
struct ScanModelBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.04, blue: 0.14), Color(red: 0.16, green: 0.06, blue: 0.20), Color(red: 0.03, green: 0.12, blue: 0.16)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.92, green: 0.12, blue: 0.56).opacity(0.30), .clear], center: .topTrailing, startRadius: 10, endRadius: 380)
            RadialGradient(colors: [Color(red: 0.12, green: 0.78, blue: 0.56).opacity(0.25), .clear], center: .bottomLeading, startRadius: 10, endRadius: 420)
            Canvas { context, size in
                var seed: UInt64 = 0x5EED
                for _ in 0..<70 {
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let x = CGFloat(seed >> 33 % 10000) / 10000 * size.width
                    seed = seed &* 6364136223846793005 &+ 1442695040888963407
                    let y = CGFloat(seed >> 33 % 10000) / 10000 * size.height
                    let r = CGFloat(seed % 3) * 0.5 + 0.6
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.5)))
                }
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}
