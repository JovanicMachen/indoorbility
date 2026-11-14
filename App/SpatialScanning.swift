import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import IndoorbilityCore

@MainActor final class ScanLibrary: ObservableObject {
    @Published var scans: [ScanDraft] = []
    @Published var error: String?
    let root = URL.applicationSupportDirectory.appending(path: "Indoorbility/Scans")
    init() { reload() }
    func directory(_ id: UUID) -> URL { root.appending(path: id.uuidString) }
    func reload() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            scans = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { !$0.lastPathComponent.hasPrefix(".") }.map {
                    let draft = try JSONDecoder().decode(ScanDraft.self, from: Data(contentsOf: $0.appending(path: "scan.json")))
                    try draft.validate(); return draft
                }.sorted { $0.createdAt > $1.createdAt }
        } catch { self.error = "Could not read saved scans: \(error.localizedDescription)" }
    }
    func save(_ draft: ScanDraft, map: ARWorldMap, mesh: Data) throws {
        try draft.validate()
        let staging = root.appending(path: ".\(draft.id.uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try JSONEncoder().encode(draft).write(to: staging.appending(path: "scan.json"), options: .atomic)
        try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
            .write(to: staging.appending(path: "world.arworldmap"), options: .atomic)
        try mesh.write(to: staging.appending(path: "mesh.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: directory(draft.id))
        reload()
    }
    func delete(_ draft: ScanDraft) throws {
        let source = directory(draft.id)
        let removed = root.appending(path: ".deleted-" + UUID().uuidString)
        try FileManager.default.moveItem(at: source, to: removed)
        do { try JourneyLibrary().forget(scanID: draft.id) }
        catch {
            try FileManager.default.moveItem(at: removed, to: source)
            throw error
        }
        // Hidden tombstones cannot return as routes if cleanup is interrupted.
        try? FileManager.default.removeItem(at: removed)
        reload()
    }
    func hallway(_ draft: ScanDraft) throws -> HallwayRoute? {
        let url = directory(draft.id).appending(path: "hallway.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let route = try JSONDecoder().decode(HallwayRoute.self, from: Data(contentsOf: url))
        try route.validate(for: draft)
        return route
    }
    func saveHallway(_ route: HallwayRoute, draft: ScanDraft) throws {
        try route.validate(for: draft)
        // Every new or edited mapper route is a draft until its exact geometry is field-reviewed.
        try Data("{\"reviewRequired\":true}".utf8).write(to: directory(draft.id).appending(path: "volunteer-draft.json"), options: .atomic)
        try JSONEncoder().encode(route).write(to: directory(draft.id).appending(path: "hallway.json"), options: .atomic)
        objectWillChange.send()
    }
    func navigationStore(_ route: HallwayRoute) throws -> AppStore {
        try AppStore(building: route.building, stateURL: directory(route.scanID).appending(path: "route-\(route.id.uuidString)-state.json"))
    }
    func worldMap(_ draft: ScanDraft) throws -> ARWorldMap {
        let data = try Data(contentsOf: directory(draft.id).appending(path: "world.arworldmap"))
        guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
            throw MapError.invalid("Saved spatial map could not be opened.")
        }
        return map
    }
}

struct MeshRecord: Codable, Sendable {
    let vertices: [SpatialPoint]
    let triangles: [UInt32]
}

@MainActor final class SpatialSession: NSObject, ObservableObject, @preconcurrency ARSessionDelegate {
    @Published var status = "Camera is off"
    @Published var position: SpatialPoint?
    @Published var samples: [ScanSample] = []
    @Published var landmarks: [ScanLandmark] = []
    @Published var meshCount = 0
    @Published var canSave = false
    @Published var running = false
    @Published var error: String?
    let scene = ARSCNView(frame: .zero)
    private var meshes: [UUID: ARMeshAnchor] = [:]
    private var pendingMesh: [UUID: ARMeshAnchor] = [:]
    private var meshWorkerBusy = false
    private var activeConfiguration: ARWorldTrackingConfiguration?
    private var sawRelocalizing = false
    private var hasInitialMap = false
    private var trackingWasNormal = false
    private(set) var savedMapRelocalized = false
    private(set) var sessionResets = 0
    private(set) var sessionResumes = 0
    private(set) var trackingInterruptions = 0
    private(set) var stalePoseFrames = 0
    private(set) var frameGaps = 0
    private(set) var callbackTiming = TimingWindow()
    private(set) var arrivalTiming = TimingWindow()
    private(set) var meshTiming = TimingWindow()
    private(set) var depthTiming = TimingWindow()
    private(set) var frameTiming = TimingWindow()
    var compareSurfaces = false
    var onMeasuredDepth: ((DepthObservation) -> Void)?
    var canResume: Bool { activeConfiguration != nil }
    func resumeTracking() {
        guard !running, let config = activeConfiguration else { return }
        startToken = UUID(); segment += 1; lastFrameTime = 0; lastDisplayTime = 0
        config.initialWorldMap = nil // Reuse the existing session coordinate frame, not the initial snapshot.
        scene.session.run(config) // Preserve world coordinates and anchors.
        sessionResumes += 1; running = true
        status = "Finding your position. Confirm a known landmark."
    }
    private var segment = 0
    private var lastTime: TimeInterval = 0
    private var locating = false
    private var startToken = UUID()
    var onFrame: ((ARFrame) -> Void)?
    @Published var showingMesh = false
    private var previewTask: Task<Void, Never>?
    private var meshNodes: [UUID: SCNNode] = [:]
    @Published var depth = DepthObservation(timestamp: 0)
    @Published var trackingDetail = "Not running"
    @Published var mappingDetail = "No map"
    @Published var routeAlignmentStatus = "Not verified"
    @Published var frameInterval: TimeInterval = 0
    @Published var depthProcessingMS: Double = 0
    @Published var skippedDepthFrames = 0
    @Published var lateDepthFrames = 0
    @Published var lastValidPoseTime: TimeInterval = 0
    @Published var showDepthOverlay = false
    var onSurfaceAlert: ((Float) -> Void)?
    var onSafetyAlert: ((String) -> Void)?
    var onPostureAlert: ((String) -> Void)?
    @Published var floorEvidence = "Not assessed"
    @Published var floorHazard = false
    private var floorRecovery = 0
    @Published var postureIssue: String?
    private var coach = PhoneCoach()
    private var floorFilter = ObjectAlertFilter()
    private var floorBusy = false
    private var lastFloorTime: TimeInterval = 0
    var onObjectAlert: ((String) -> Void)?
    @Published var objectEvidence = "Not assessed"
    private var objectBusy = false
    private var lastObjectTime: TimeInterval = 0
    private var objectFilter = ObjectAlertFilter()
    private var awareness = SceneAwarenessFilter()
    private var depthBusy = false
    private var lastDepthTime: TimeInterval = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastDisplayTime: TimeInterval = 0
    private var lastMeshRender: [UUID: TimeInterval] = [:]
    private let depthNode = SCNNode()
    private let routeNode = SCNNode()
    private var renderedPath: [SpatialPoint] = []
    var onPose: ((SpatialPoint?, Float?, TimeInterval, Bool) -> Void)?
    override init() {
        super.init()
        scene.session.delegate = self
        scene.session.delegateQueue = .main
        scene.automaticallyUpdatesLighting = true
        scene.scene.rootNode.addChildNode(depthNode)
        scene.scene.rootNode.addChildNode(routeNode)
    }
    static var supportsLiDAR: Bool { ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) }
    func start(map: ARWorldMap? = nil, navigation: Bool = false) async {
        guard !running else { return }
        let token = UUID(); startToken = token
        let allowed: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
        else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        guard startToken == token else { return }
        guard allowed else { error = "Allow Camera in iPhone Settings to scan this space."; return }
        guard ARWorldTrackingConfiguration.isSupported, map != nil || navigation || Self.supportsLiDAR else {
            error = "This device does not support this spatial capture mode."; return
        }
        previewTask?.cancel(); hideMesh(); lastMeshRender = [:]; pendingMesh = [:]
        locating = map != nil || navigation
        samples = []; landmarks = []; meshes = [:]; meshCount = 0; position = nil; canSave = false
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) { config.sceneReconstruction = .meshWithClassification }
        else if Self.supportsLiDAR { config.sceneReconstruction = .mesh }
        let combined: ARConfiguration.FrameSemantics = [.sceneDepth, .smoothedSceneDepth]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(combined) { config.frameSemantics = combined }
        else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) { config.frameSemantics = .sceneDepth }
        else if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) { config.frameSemantics = .smoothedSceneDepth }
        config.initialWorldMap = map
        hasInitialMap = map != nil; sawRelocalizing = false; savedMapRelocalized = false
        activeConfiguration = config
        lastFloorTime = 0; lastObjectTime = 0; lastDisplayTime = 0; lastTime = 0
        trackingWasNormal = false; floorHazard = false; floorRecovery = 0
        coach = PhoneCoach(); floorFilter = ObjectAlertFilter(); objectFilter = ObjectAlertFilter()
        showingMesh = !locating; depth = DepthObservation(timestamp: 0); lastFrameTime = 0; lastDepthTime = 0
        awareness = SceneAwarenessFilter(); routeNode.isHidden = true
        sessionResets += 1
        scene.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        running = true
        status = locating ? "Point toward the marked entrance to find your position." : "Walk the known hallway with the camera facing ahead."
    }
    func stop() { coach = PhoneCoach(); floorFilter = ObjectAlertFilter(); postureIssue = nil; floorEvidence = "Not assessed"; floorHazard = false; floorRecovery = 0; objectFilter = ObjectAlertFilter(); objectEvidence = "Not assessed"; routeNode.isHidden = true; depthNode.isHidden = true; previewTask?.cancel(); hideMesh(); pendingMesh = [:]; startToken = UUID(); onPose?(nil, nil, ProcessInfo.processInfo.systemUptime, false); scene.session.pause(); running = false; position = nil; canSave = false; status = "Session paused. Reopen to start again." }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running else { return }
        let entered = ProcessInfo.processInfo.systemUptime
        defer { callbackTiming.record((ProcessInfo.processInfo.systemUptime-entered)*1000) }
        arrivalTiming.record(max(0, entered-frame.timestamp)*1000)
        if lastFrameTime > 0 {
            frameTiming.record(frame.timestamp-lastFrameTime)
            if frame.timestamp-lastFrameTime > 0.05 { frameGaps += 1 }
        }
        guard entered >= frame.timestamp, entered-frame.timestamp < 0.5 else {
            stalePoseFrames += 1; position = nil; canSave = false
            onPose?(nil, nil, frame.timestamp, false); return
        }
        let displayUpdate = frame.timestamp-lastDisplayTime >= 0.1
        if displayUpdate {
            frameInterval = lastFrameTime > 0 ? frame.timestamp-lastFrameTime : 0
            let tracking = String(describing: frame.camera.trackingState)
            let mapping = String(describing: frame.worldMappingStatus)
            if trackingDetail != tracking { trackingDetail = tracking }
            if mappingDetail != mapping { mappingDetail = mapping }
            lastDisplayTime = frame.timestamp
        }
        lastFrameTime = frame.timestamp
        // Position delivery has priority; perception work is bounded and dispatched
        // only after the navigation callback, including tracking-loss delivery.
        defer {
            consumeDepth(frame)
            consumeObjects(frame)
            consumeSafety(frame)
        }
        guard case .normal = frame.camera.trackingState else {
            if case .limited(.relocalizing) = frame.camera.trackingState { sawRelocalizing = true }
            if trackingWasNormal { trackingInterruptions += 1 }
            trackingWasNormal = false
            if position != nil { segment += 1 }
            position = nil; canSave = false; routeNode.isHidden = true; routeAlignmentStatus = "Tracking interrupted"
            onPose?(nil, nil, frame.timestamp, false)
            status = "Finding your position. Point toward a known textured landmark."
            return
        }
        trackingWasNormal = true
        if hasInitialMap && sawRelocalizing { savedMapRelocalized = true }
        let t = frame.camera.transform.columns.3
        let p = SpatialPoint(x: t.x, y: t.y, z: t.z)
        lastValidPoseTime = frame.timestamp
        if displayUpdate { position = p }
        let forward = frame.camera.transform.columns.2
        let heading: Float? = hypot(forward.x, forward.z) > 0.2 ? atan2(-forward.z, -forward.x) : nil
        onPose?(p, heading, frame.timestamp, true)
        onFrame?(frame)
        if displayUpdate { status = locating ? "Camera tracking active · verify map alignment" : "Tracking · \(meshes.count) mesh sections" }
        if !locating, frame.timestamp - lastTime > 0.1,
           samples.last?.segment != segment || (samples.last?.position.distance(to: p) ?? 1) > 0.15 {
            samples.append(ScanSample(position: p, segment: segment)); lastTime = frame.timestamp
        }
        let savable = !locating && !meshes.isEmpty && (frame.worldMappingStatus == .mapped || frame.worldMappingStatus == .extending)
        if canSave != savable { canSave = savable }
    }
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { update(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { update(anchors) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors { meshes.removeValue(forKey: anchor.identifier); pendingMesh.removeValue(forKey: anchor.identifier); meshNodes.removeValue(forKey: anchor.identifier)?.removeFromParentNode() }; meshCount = meshes.count
    }
    private func update(_ anchors: [ARAnchor]) {
        for case let anchor as ARMeshAnchor in anchors {
            meshes[anchor.identifier] = anchor
            let now = ProcessInfo.processInfo.systemUptime
            if showingMesh && now-(lastMeshRender[anchor.identifier] ?? 0) >= 0.25 {
                lastMeshRender[anchor.identifier] = now; queueMesh(anchor)
            }
        }
        if meshCount != meshes.count { meshCount = meshes.count }
    }
    func previewMappedArea() {
        previewTask?.cancel(); showingMesh = true
        for anchor in meshes.values.prefix(128) { queueMesh(anchor) }
        guard locating else { return }
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }; self?.hideMesh()
        }
    }
    func hideMesh() {
        showingMesh = false; pendingMesh = [:]
        for node in meshNodes.values { node.removeFromParentNode() }; meshNodes.removeAll()
    }
    private func queueMesh(_ anchor: ARMeshAnchor) {
        guard pendingMesh.count < 128 || pendingMesh[anchor.identifier] != nil else { return }
        pendingMesh[anchor.identifier] = anchor
        processNextMesh()
    }
    private func processNextMesh() {
        guard !meshWorkerBusy, showingMesh, running, let anchor = pendingMesh.values.first else { return }
        pendingMesh.removeValue(forKey: anchor.identifier); meshWorkerBusy = true
        let token = startToken, started = ProcessInfo.processInfo.systemUptime
        Task {
            let data = await Task.detached(priority: .utility) {
                let faces = anchor.geometry.faces
                return Data(bytes: faces.buffer.contents(), count: faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex)
            }.value
            meshWorkerBusy = false
            if token == startToken, running, showingMesh, meshes[anchor.identifier] != nil {
                meshTiming.record((ProcessInfo.processInfo.systemUptime-started)*1000)
                renderMesh(anchor, faceData: data)
            }
            processNextMesh()
        }
    }
    private func renderMesh(_ anchor: ARMeshAnchor, faceData: Data) {
        let mesh = anchor.geometry
        // Use ARKit's Metal vertex buffer directly; no main-thread vertex copying.
        let source = SCNGeometrySource(buffer: mesh.vertices.buffer, vertexFormat: .float3, semantic: .vertex,
            vertexCount: mesh.vertices.count, dataOffset: mesh.vertices.offset, dataStride: mesh.vertices.stride)
        let faces = mesh.faces
        let data = faceData
        let geometry = SCNGeometry(sources: [source], elements: [SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: faces.count, bytesPerIndex: faces.bytesPerIndex)])
        let material = SCNMaterial(); material.fillMode = .lines; material.diffuse.contents = UIColor(red: 0.72, green: 0.43, blue: 0.59, alpha: 0.65); material.isDoubleSided = true; material.lightingModel = .constant
        geometry.materials = [material]
        let node = meshNodes[anchor.identifier] ?? SCNNode()
        node.geometry = geometry; node.simdTransform = anchor.transform
        // Reuse the same measured vertex/index buffers for a subtle surface fill.
        // No inferred objects or synthetic geometry are added.
        let fill = node.childNodes.first ?? SCNNode()
        let fillGeometry = SCNGeometry(sources: [source], elements: geometry.elements)
        let fillMaterial = SCNMaterial()
        fillMaterial.diffuse.contents = UIColor(red: 1, green: 0.77, blue: 0.66, alpha: 0.14)
        fillMaterial.lightingModel = .constant; fillMaterial.isDoubleSided = true
        fillMaterial.writesToDepthBuffer = false
        fillGeometry.materials = [fillMaterial]; fill.geometry = fillGeometry
        if fill.parent == nil { node.addChildNode(fill) }
        if meshNodes[anchor.identifier] == nil { scene.scene.rootNode.addChildNode(node); meshNodes[anchor.identifier] = node }
    }
    private func consumeSafety(_ frame: ARFrame) {
        guard locating, case .normal = frame.camera.trackingState else { postureIssue = nil; floorEvidence = "Position uncertain"; return }
        let m = frame.camera.transform
        let pitch = asin(max(-1, min(1, -m.columns.2.y))) * 180 / .pi
        let roll = atan2(m.columns.1.y, -m.columns.0.y) * 180 / .pi
        if UserDefaults.standard.bool(forKey: "phoneCoaching") {
            if let message = coach.update(pitch: Double(pitch), roll: Double(roll), now: frame.timestamp) { (onPostureAlert ?? onSafetyAlert)?(message) }
            postureIssue = coach.issue
        } else { coach = PhoneCoach(); postureIssue = nil }
        guard UserDefaults.standard.bool(forKey: "floorAlerts") else {
            floorHazard = false; floorRecovery = 0; floorFilter = ObjectAlertFilter(); floorEvidence = "Off"; return
        }
        guard !floorBusy, frame.timestamp-lastFloorTime >= 0.3 else { return }
        floorBusy = true; lastFloorTime = frame.timestamp
        let token = startToken
        Task {
            let result = await Task.detached(priority: .utility) { FloorSensor.read(frame) }.value
            floorBusy = false
            guard running, token == startToken, UserDefaults.standard.bool(forKey: "floorAlerts") else { return }
            let valid = AgentSceneObservation.isFresh(frame, current: scene.session.currentFrame)
            floorEvidence = valid ? result.rawValue : "Reading expired"
            floorRecovery = valid && result == .observed ? floorRecovery + 1 : 0
            if floorRecovery >= 3 { floorHazard = false }
            if floorFilter.update(kind: result == .possibleDrop ? "drop" : nil, capturedAt: frame.timestamp,
                                  now: ProcessInfo.processInfo.systemUptime, reliable: valid) {
                floorHazard = true
                onSafetyAlert?("Stop and check. A possible step down or floor drop is ahead.")
            }
        }
    }
    /// A short-lookahead point from the verified route, converted into portrait-listener coordinates.
    func soundTarget(path: [SpatialPoint], progress: Float, alignment: ScanAlignment) -> SIMD3<Float>? {
        guard running, postureIssue == nil, let frame = scene.session.currentFrame,
              case .normal = frame.camera.trackingState, ProcessInfo.processInfo.systemUptime-frame.timestamp < 0.5 else { return nil }
        var along: Float = 0
        var target = path.last
        for (a,b) in zip(path, path.dropFirst()) {
            let length = a.distance(to: b)
            if along + length >= progress + 2 {
                let t = min(1, max(0, (progress+2-along)/max(0.001,length)))
                target = SpatialPoint(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t, z: a.z+(b.z-a.z)*t); break
            }
            along += length
        }
        guard let target else { return nil }
        let x = target.x-alignment.translation.x, z = target.z-alignment.translation.z
        let world = SIMD4<Float>(cos(alignment.yaw)*x+sin(alignment.yaw)*z, target.y-alignment.translation.y, -sin(alignment.yaw)*x+cos(alignment.yaw)*z, 1)
        let local = simd_inverse(frame.camera.transform) * world
        return SIMD3(local.y, -local.x, local.z)
    }
    private func consumeObjects(_ frame: ARFrame) {
        guard locating, UserDefaults.standard.bool(forKey: "depthAdvisories"),
              !objectBusy, frame.timestamp - lastObjectTime >= 0.7 else { return }
        guard case .normal = frame.camera.trackingState else {
            objectEvidence = "Tracking uncertain"; objectFilter = ObjectAlertFilter(); return
        }
        objectBusy = true; lastObjectTime = frame.timestamp
        let epoch = startToken
        Task {
            let kind = await Task.detached(priority: .utility) { CameraObjectEvidence.read(frame) }.value
            objectBusy = false
            guard running, epoch == startToken, UserDefaults.standard.bool(forKey: "depthAdvisories") else { return }
            let valid = AgentSceneObservation.isFresh(frame, current: scene.session.currentFrame)
            objectEvidence = valid ? CameraObjectEvidence.description(kind) : "Observation expired"
            if objectFilter.update(kind: kind, capturedAt: frame.timestamp, now: ProcessInfo.processInfo.systemUptime, reliable: valid) {
                onObjectAlert?(CameraObjectEvidence.description(kind) + " Pause and check your surroundings.")
            }
        }
    }
    private func consumeDepth(_ frame: ARFrame) {
        guard frame.timestamp > lastDepthTime, frame.timestamp-lastDepthTime >= 0.1 else { return }
        guard !depthBusy else { skippedDepthFrames += 1; return }
        depthBusy = true; lastDepthTime = frame.timestamp
        let epoch = startToken, points = showDepthOverlay || compareSurfaces, started = ProcessInfo.processInfo.systemUptime
        let normal: Bool = { if case .normal = frame.camera.trackingState { return true }; return false }()
        Task {
            let observation = await Task.detached(priority: .userInitiated) { SceneAwarenessService.read(frame, includePoints: points) }.value
            depthBusy = false
            guard running, epoch == startToken else { return }
            let now = ProcessInfo.processInfo.systemUptime
            depthProcessingMS = (now-started)*1000
            depthTiming.record(depthProcessingMS)
            guard now-observation.timestamp < 0.5, AgentSceneObservation.isFresh(frame, current: scene.session.currentFrame) else { lateDepthFrames += 1; depthNode.isHidden = true; return }
            depth = observation
            onMeasuredDepth?(observation)
            let currentlyNormal: Bool = { if case .normal = scene.session.currentFrame?.camera.trackingState { return true }; return false }()
            if let distance = awareness.update(distance: observation.distance, coverage: observation.coverage, timestamp: observation.timestamp, now: now, tracking: normal && currentlyNormal, upright: observation.upright) { onSurfaceAlert?(distance) }
            depthNode.isHidden = !showDepthOverlay || !normal || !currentlyNormal
            if showDepthOverlay {
                let vertices = observation.points.map { SCNVector3($0.x, $0.y, $0.z) }
                let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .point)
                element.pointSize = 5; element.minimumPointScreenSpaceRadius = 2; element.maximumPointScreenSpaceRadius = 5
                let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [element])
                let material = SCNMaterial(); material.diffuse.contents = UIColor(red: 1, green: 0.77, blue: 0.66, alpha: 0.9); material.lightingModel = .constant
                geometry.materials = [material]; depthNode.geometry = geometry
            }
        }
    }
    func showRoute(_ path: [SpatialPoint], alignment: ScanAlignment, verified: Bool) {
        routeNode.isHidden = !verified
        let alignmentStatus = verified ? "Verified mapped route" : "Finding map alignment"
        if routeAlignmentStatus != alignmentStatus { routeAlignmentStatus = alignmentStatus }
        if !verified { depthNode.isHidden = true }
        guard verified else { return }
        // Saved coordinates -> live world. This also supports manual landmark recovery.
        var transform = matrix_identity_float4x4
        transform.columns.0 = SIMD4(cos(alignment.yaw), 0, sin(alignment.yaw), 0)
        transform.columns.2 = SIMD4(-sin(alignment.yaw), 0, cos(alignment.yaw), 0)
        transform.columns.3 = SIMD4(alignment.translation.x, alignment.translation.y, alignment.translation.z, 1)
        routeNode.simdTransform = transform.inverse
        guard renderedPath != path else { return }; renderedPath = path
        routeNode.childNodes.forEach { $0.removeFromParentNode() }
        var last: SpatialPoint?
        for (a,b) in zip(path, path.dropFirst()) {
            guard a.horizontalDistance(to: b) > 0.01, last == nil || a.distance(to: last!) >= 0.7 else { continue }; last = a
            let shape = UIBezierPath(); shape.move(to: CGPoint(x: -0.18, y: -0.15)); shape.addLine(to: CGPoint(x: 0, y: 0.15)); shape.addLine(to: CGPoint(x: 0.18, y: -0.15)); shape.addLine(to: CGPoint(x: 0, y: -0.02)); shape.close()
            let geometry = SCNShape(path: shape, extrusionDepth: 0.025)
            geometry.firstMaterial?.diffuse.contents = UIColor(red: 1, green: 0.77, blue: 0.66, alpha: 1)
            let node = SCNNode(geometry: geometry)
            // Floating route markers at a fixed offset below recorded phone height, not an inferred floor surface.
            let forward = simd_normalize(SIMD3<Float>(b.x-a.x, 0, b.z-a.z))
            let right = SIMD3<Float>(-forward.z, 0, forward.x)
            var marker = matrix_identity_float4x4
            marker.columns.0 = SIMD4(right.x, right.y, right.z, 0)
            marker.columns.1 = SIMD4(forward.x, forward.y, forward.z, 0)
            marker.columns.2 = SIMD4(0, 1, 0, 0)
            marker.columns.3 = SIMD4(a.x, a.y-0.5, a.z, 1)
            node.simdTransform = marker
            routeNode.addChildNode(node)
        }
    }
    func sessionWasInterrupted(_ session: ARSession) {
        trackingInterruptions += 1; trackingWasNormal = false; segment += 1
        position = nil; canSave = false; routeNode.isHidden = true; depthNode.isHidden = true
        onPose?(nil, nil, ProcessInfo.processInfo.systemUptime, false)
        status = "Camera interrupted. Guidance is paused."
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        // ARKit resumes the same session. Do not reset anchors or invent a recovered map position.
        lastFrameTime = 0
        status = "Point at a known sign, then confirm your position."
    }
    func session(_ session: ARSession, didFailWithError error: Error) { stop(); self.error = error.localizedDescription }
    func mark(_ label: String) {
        guard let position, !label.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        landmarks.append(ScanLandmark(label: label, kind: "checkpoint", position: position))
    }
    @discardableResult func save(name: String, library: ScanLibrary) async throws -> ScanDraft {
        guard canSave else { throw MapError.invalid("Keep scanning until the space is mapped.") }
        let captureToken = startToken
        let map: ARWorldMap = try await withCheckedThrowingContinuation { continuation in
            scene.session.getCurrentWorldMap { map, error in
                if let map { continuation.resume(returning: map) }
                else { continuation.resume(throwing: error ?? MapError.invalid("Could not capture the world map.")) }
            }
        }
        guard captureToken == startToken, running, canSave else {
            throw MapError.invalid("Mapping was interrupted before the save completed. Restart this walk; no new route was saved.")
        }
        let anchors = Array(meshes.values)
        let records = await Task.detached(priority: .utility) {
            var records: [MeshRecord] = []
        for anchor in anchors {
            let geometry = anchor.geometry
            var vertices: [SpatialPoint] = []
            for index in 0..<geometry.vertices.count {
                let ptr = geometry.vertices.buffer.contents().advanced(by: geometry.vertices.offset + geometry.vertices.stride * index)
                let v = SIMD3<Float>(ptr.load(as: Float.self), ptr.advanced(by: 4).load(as: Float.self), ptr.advanced(by: 8).load(as: Float.self))
                let world = anchor.transform * SIMD4<Float>(v.x, v.y, v.z, 1)
                vertices.append(SpatialPoint(x: world.x, y: world.y, z: world.z))
            }
            let faces = geometry.faces
            let count = faces.count * faces.indexCountPerPrimitive
            var indices: [UInt32] = []
            for index in 0..<count {
                let ptr = faces.buffer.contents().advanced(by: index * faces.bytesPerIndex)
                indices.append(faces.bytesPerIndex == 2 ? UInt32(ptr.load(as: UInt16.self)) : ptr.load(as: UInt32.self))
            }
            records.append(MeshRecord(vertices: vertices, triangles: indices))
        }
            return records
        }.value
        guard captureToken == startToken, running, canSave else { throw MapError.invalid("Mapping interrupted during export. No route was saved.") }
        let draft = ScanDraft(name: name, usesLiDAR: true, hasWorldMap: true, samples: samples, landmarks: landmarks,
                              meshVertexCount: records.reduce(0) { $0 + $1.vertices.count },
                              meshTriangleCount: records.reduce(0) { $0 + $1.triangles.count / 3 })
        try library.save(draft, map: map, mesh: JSONEncoder().encode(records))
        stop()
        return draft
    }
}

struct SpatialCamera: UIViewRepresentable {
    let session: SpatialSession
    func makeUIView(context: Context) -> ARSCNView { session.scene }
    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}

struct TraceView: View {
    let samples: [ScanSample]
    let landmarks: [ScanLandmark]
    var position: SpatialPoint?
    var nextTurn: SpatialPoint? = nil
    var cameraHeading: Float? = nil
    var movementHeading: Float? = nil
    var selectedSegment: Int? = nil
    var body: some View {
        Canvas { context, size in
            // Fixed route bounds: drifting/live positions never recenter or rotate the map.
            let points = samples.map(\.position) + landmarks.map(\.position)
            let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 1
            let minZ = points.map(\.z).min() ?? 0, maxZ = points.map(\.z).max() ?? 1
            let scale = min((size.width - 40) / CGFloat(max(maxX-minX, 2)), (size.height - 40) / CGFloat(max(maxZ-minZ, 2)))
            func point(_ p: SpatialPoint) -> CGPoint { CGPoint(x: size.width/2 + CGFloat(p.x-(maxX+minX)/2)*scale, y: size.height/2 + CGFloat(p.z-(maxZ+minZ)/2)*scale) }
            var path = Path()
            for (index, sample) in samples.enumerated() {
                if index == 0 || samples[index-1].segment != sample.segment { path.move(to: point(sample.position)) }
                else { path.addLine(to: point(sample.position)) }
            }
            context.stroke(path, with: .color(.indoorTeal.opacity(0.5)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            if let index = selectedSegment, samples.indices.contains(index), samples.indices.contains(index+1) {
                var selected = Path(); selected.move(to: point(samples[index].position)); selected.addLine(to: point(samples[index+1].position))
                context.stroke(selected, with: .color(.green), lineWidth: 8)
            }
            if let nextTurn {
                let p = point(nextTurn)
                context.stroke(Path(ellipseIn: CGRect(x: p.x-10, y: p.y-10, width: 20, height: 20)), with: .color(.indoorTeal), lineWidth: 3)
                context.draw(Text("Next turn").font(.caption2), at: CGPoint(x: p.x, y: p.y-20))
            }
            if let position {
                for (heading, color) in [(cameraHeading, Color.orange), (movementHeading, Color.blue)] {
                    if let heading {
                        let p = point(position)
                        var direction = Path(); direction.move(to: p)
                        direction.addLine(to: CGPoint(x: p.x+CGFloat(cos(heading))*28, y: p.y+CGFloat(sin(heading))*28))
                        context.stroke(direction, with: .color(color), lineWidth: 3)
                    }
                }
            }
            for mark in landmarks { let p = point(mark.position); context.fill(Path(ellipseIn: CGRect(x:p.x-5,y:p.y-5,width:10,height:10)), with: .color(.orange)); context.draw(Text(mark.label).font(.caption2), at: CGPoint(x:p.x,y:p.y+15)) }
            if let position { let p = point(position); context.fill(Path(ellipseIn: CGRect(x:p.x-8,y:p.y-8,width:16,height:16)), with: .color(.indoorTeal)) }
        }.frame(height: 210).background(Color.indoorBackground, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityLabel("Recorded walking trace, \(landmarks.count) landmarks. \(position == nil ? "No live position." : "Live position available.")")
    }
}

struct SpatialCaptureView: View {
    @ObservedObject var library: ScanLibrary
    var draft: ScanDraft?
    @StateObject private var session = SpatialSession()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var name = "My space"
    @State private var landmark = ""
    @State private var saving = false
    @State private var saved = false
    @State private var naming = false
    @State private var marking = false
    var supported: Bool { draft == nil ? SpatialSession.supportsLiDAR : ARWorldTrackingConfiguration.isSupported }
    var body: some View {
        ZStack {
            Color.indoorBackground.ignoresSafeArea()
            if supported { SpatialCamera(session: session).ignoresSafeArea().accessibilityHidden(true) }
            VStack {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 48, height: 48).background(.regularMaterial, in: Circle()) }
                        .accessibilityLabel("Close scan").disabled(saving)
                    Spacer()
                    Text(draft == nil ? "Scan an area" : "Find saved area").font(.headline).padding(14).background(.regularMaterial, in: Capsule())
                }.padding()
                Spacer()
                ScanInstructionPanel {
                    if !supported {
                        Text("LiDAR device required").font(.title2.bold())
                        Text("Use a supported physical iPhone or iPad to capture real surfaces.")
                    } else {
                        ScanInstructionHeading(
                            status: draft != nil ? "Finding your saved area" : session.meshCount > 0 ? "Capturing surfaces" : "Finding surfaces…",
                            title: draft == nil ? "Look around the area" : "Find a familiar landmark",
                            instruction: draft == nil ? "Gently scan the walls and furniture; colored surfaces show what’s captured." : "Point at a familiar landmark to find your saved area.",
                            active: session.running
                        )
                        if session.position == nil { Text("Hold still near a textured surface while tracking settles.").font(.callout) }
                        if let draft {
                            DisclosureGroup("Saved landmarks") {
                                ForEach(draft.landmarks) { mark in Text(mark.label) }
                            }
                            Button("Show captured surfaces") { session.previewMappedArea() }.buttonStyle(.bordered)
                        } else {
                            HStack {
                                Button("Mark a place") { landmark = ""; marking = true }.buttonStyle(.bordered)
                                    .disabled(session.position == nil || saving)
                                Spacer()
                                Button(saving ? "Saving…" : "Finish scan") { naming = true }.buttonStyle(.borderedProminent)
                                    .disabled(!session.canSave || saving)
                            }
                            Text(session.canSave ? "Ready to save this captured area." : "Keep looking around to collect enough detail to save.").font(.caption)
                            Text("\(session.landmarks.count) labeled places").font(.caption)
                        }
                        Text("Blank areas may be unscanned. Mesh is not proof of a clear or accessible path.").font(.caption).foregroundStyle(.secondary)
                        if !session.running { Button("Restart camera") { Task { await start() } } }
                    }
                    if let error = session.error { Text(error).foregroundStyle(.red) }
                }.controlSize(.large).tint(.indoorTeal)
            }
        }.toolbar(.hidden, for: .navigationBar, .tabBar)
            .task { await start() }
            .onDisappear { session.stop() }
            .onChange(of: phase) { _, value in if value == .background || (value == .inactive && session.running) { session.stop() } }
            .alert("Name this place", isPresented: $marking) {
                TextField("For example: LL elevator", text: $landmark)
                Button("Mark") { session.mark(landmark) }.disabled(landmark.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { }
            } message: { Text("Stand beside the actual landmark before marking it.") }
            .alert("Save captured area", isPresented: $naming) {
                TextField("Area name", text: $name)
                Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) { }
            } message: { Text("Saves the measured mesh, spatial map and labels on this iPhone. Review a hallway route before visitors use it.") }
            .alert("Scan saved", isPresented: $saved) { Button("Done") { dismiss() } } message: { Text("Your captured surfaces and landmarks are saved locally.") }
    }
    private func start() async {
        guard supported else { return }
        do { let map = try draft.map { try library.worldMap($0) }; await session.start(map: map) }
        catch { session.error = error.localizedDescription }
    }
    private func save() {
        saving = true
        Task {
            do { try await session.save(name: name, library: library); saved = true }
            catch { session.error = error.localizedDescription }
            saving = false
        }
    }
}
