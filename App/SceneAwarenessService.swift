import ARKit
import SwiftUI
import IndoorbilityCore

struct DepthObservation: Sendable {
    var timestamp: TimeInterval
    var width = 0
    var height = 0
    var coverage: Float = 0
    var confidenceCounts = [0, 0, 0]
    var distance: Float?
    var points: [SIMD3<Float>] = []
    var upright = false
}

/// Bounded work: sample a central calibrated region, off the AR frame callback.
enum SceneAwarenessService {
    static func read(_ frame: ARFrame, includePoints: Bool) -> DepthObservation {
        var result = DepthObservation(timestamp: frame.timestamp)
        let transform = frame.camera.transform
        let forward = -transform.columns.2
        result.upright = abs(forward.y) < 0.35
        guard let depth = frame.sceneDepth ?? frame.smoothedSceneDepth, let confidence = depth.confidenceMap else { return result }
        let buffer = depth.depthMap
        CVPixelBufferLockBaseAddress(buffer, .readOnly); CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        result.width = width; result.height = height
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetWidth(confidence) == width, CVPixelBufferGetHeight(confidence) == height,
              let base = CVPixelBufferGetBaseAddress(buffer), let scores = CVPixelBufferGetBaseAddress(confidence) else { return result }
        let intrinsics = frame.camera.intrinsics
        let sx = Float(width) / Float(frame.camera.imageResolution.width), sy = Float(height) / Float(frame.camera.imageResolution.height)
        let fx = intrinsics[0][0]*sx, fy = intrinsics[1][1]*sy, cx = intrinsics[2][0]*sx, cy = intrinsics[2][1]*sy
        var values: [Float] = []; var total = 0
        let margin = UserDefaults.standard.bool(forKey: "depthWideRegion") ? 3 : 4
        for y in stride(from: height*margin/10, to: height*(10-margin)/10, by: 2) {
            let row = base.advanced(by: y*CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)
            let score = scores.advanced(by: y*CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: width*margin/10, to: width*(10-margin)/10, by: 2) {
                total += 1
                if score[x] < 3 { result.confidenceCounts[Int(score[x])] += 1 }
                let d = row[x]
                guard score[x] == 2, d.isFinite, d > 0.25, d < 5 else { continue }
                let calibrated = transform * SIMD4<Float>((Float(x)-cx)*d/fx, -(Float(y)-cy)*d/fy, -d, 1)
                // Restrict advisories to a horizontal band around phone height, rejecting down-facing floor samples.
                guard abs(calibrated.y-transform.columns.3.y) < 0.35 else { continue }
                values.append(d)
                if includePoints {
                    let world = transform * SIMD4<Float>((Float(x)-cx)*d/fx, -(Float(y)-cy)*d/fy, -d, 1)
                    result.points.append(SIMD3(world.x, world.y, world.z))
                }
            }
        }
        result.coverage = total > 0 ? Float(values.count)/Float(total) : 0
        if values.count >= 20, result.coverage >= 0.65 { values.sort(); result.distance = values[values.count/2] }
        return result
    }
}

struct SensorDiagnosticsView: View {
    @ObservedObject var camera: SpatialSession
    var navigationDetails: () -> [String] = { [] }
    @Environment(\.dismiss) private var dismiss
    private var performanceLines: [String] {
        [String(format: "Delivered frame rate: %.1f fps", (camera.frameTiming.mean ?? 0) > 0 ? 1/(camera.frameTiming.mean ?? 1) : 0),
         String(format: "Delegate mean / p95: %.2f / %.2f ms", (camera.callbackTiming.mean ?? 0), (camera.callbackTiming.p95 ?? 0)),
         String(format: "Capture-to-callback mean / p95: %.2f / %.2f ms", (camera.arrivalTiming.mean ?? 0), (camera.arrivalTiming.p95 ?? 0)),
         String(format: "Depth processing mean / p95: %.2f / %.2f ms", (camera.depthTiming.mean ?? 0), (camera.depthTiming.p95 ?? 0)),
         String(format: "Mesh face copy mean / p95: %.2f / %.2f ms", (camera.meshTiming.mean ?? 0), (camera.meshTiming.p95 ?? 0)),
         "Session resets / resumes: \(camera.sessionResets) / \(camera.sessionResumes)",
         "Tracking interruptions: \(camera.trackingInterruptions)",
         "Frame intervals over 50 ms: \(camera.frameGaps) (not a dropped-frame count)",
         "Stale pose / depth results rejected: \(camera.stalePoseFrames) / \(camera.lateDepthFrames)",
         camera.depth.timestamp > 0 ? String(format: "Depth age: %.3f s", ProcessInfo.processInfo.systemUptime-camera.depth.timestamp) : "Depth age: unavailable",
         "Rolling timing window: up to 300 samples; physical accuracy not measured here."] + NavigationPerformance.shared.lines
    }
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Form {
                    LabeledContent("LiDAR mesh support", value: SpatialSession.supportsLiDAR ? "Yes" : "No")
                    LabeledContent("Raw depth support", value: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ? "Yes" : "No")
                    LabeledContent("Floor evidence", value: camera.floorEvidence)
                    LabeledContent("Phone position", value: camera.postureIssue ?? "No confirmed posture issue")
                    LabeledContent("Object evidence (local)", value: camera.objectEvidence)
                    LabeledContent("Tracking", value: camera.trackingDetail)
                    LabeledContent("World map", value: camera.mappingDetail)
                    LabeledContent("Route alignment", value: camera.routeAlignmentStatus)
                    LabeledContent("Depth buffer", value: camera.depth.width > 0 ? "Available" : "Unavailable")
                    LabeledContent("Depth size", value: "\(camera.depth.width) × \(camera.depth.height)")
                    LabeledContent("Depth age", value: camera.depth.timestamp > 0 ? String(format: "%.2f s", ProcessInfo.processInfo.systemUptime-camera.depth.timestamp) : "No frame")
                    LabeledContent("Central confidence coverage", value: String(format: "%.0f%%", camera.depth.coverage*100))
                    LabeledContent("Confidence low / medium / high", value: camera.depth.confidenceCounts.map(String.init).joined(separator: " / "))
                    LabeledContent("Central surface distance", value: camera.depth.distance.map { String(format: "%.2f m", $0) } ?? "Cannot assess reliably")
                    LabeledContent("Camera interval", value: String(format: "%.1f ms", camera.frameInterval*1000))
                    LabeledContent("Depth processing", value: String(format: "%.1f ms", camera.depthProcessingMS))
                    LabeledContent("Skipped while processing", value: String(camera.skippedDepthFrames))
                    LabeledContent("Late results rejected", value: String(camera.lateDepthFrames))
                    LabeledContent("Mesh anchors", value: String(camera.meshCount))
                    LabeledContent("Last valid camera pose", value: camera.lastValidPoseTime > 0 ? String(format: "%.2f s ago", ProcessInfo.processInfo.systemUptime-camera.lastValidPoseTime) : "None")
                    ForEach(Array(navigationDetails().enumerated()), id: \.offset) { _, detail in Text(detail) }
                    ForEach(Array(performanceLines.enumerated()), id: \.offset) { _, detail in Text(detail) }
                    ShareLink("Export diagnostic snapshot", item: (performanceLines + navigationDetails()).joined(separator: "\n"))
                    Toggle("Show calibrated depth points", isOn: $camera.showDepthOverlay)
                    Text("Peach points are measured central depth samples projected with this frame’s camera calibration and pose. Not a full hazard map.").font(.footnote)
                }
            }.navigationTitle("Sensor diagnostics").toolbar { Button("Done") { dismiss() } }
        }
    }
}

/// On-demand camera help can be tested without pretending an indoor route exists.
struct CameraAssistanceView: View {
    @ObservedObject var settings: AppStore
    @StateObject private var camera = SpatialSession()
    @StateObject private var voice = VoiceCommandInput()
    @State private var response = "Point the camera ahead, then ask for a reading. Your indoor position is not verified here."
    @State private var reading = false
    @State private var diagnostics = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            SpatialCamera(session: camera).ignoresSafeArea().accessibilityHidden(true)
            VStack {
                HStack {
                    Button("Done") { dismiss() }.frame(minHeight: 48)
                    Spacer(); Text("Camera help").font(.headline); Spacer()
                    if UserDefaults.standard.bool(forKey: "agentDeveloperMode") { Button { diagnostics = true } label: { Image(systemName: "waveform.path.ecg").frame(width: 48, height: 48) }.accessibilityLabel("Sensor diagnostics") }
                }.padding(.horizontal).background(.regularMaterial, in: Capsule())
                Spacer()
                VStack(spacing: 16) {
                    Text(camera.running ? response : camera.error ?? camera.status).font(.body)
                    if voice.busy || !voice.status.hasPrefix("Tap Listen") { Text(voice.status).font(.footnote) }
                    if camera.running {
                        Button(reading ? "Reading…" : "What’s ahead?") { read() }.buttonStyle(.borderedProminent).disabled(reading)
                    } else { Button("Start camera") { Task { await camera.start(navigation: true) } }.buttonStyle(.borderedProminent) }
                    HoldToTalk(voice: voice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, result: { text in
                        let value = text.lowercased()
                        if ["ahead", "front", "read", "see"].contains(where: value.contains) { read() }
                        else { response = "This camera can read visible text and central depth. Choose a saved destination on Home for directions."; settings.speak(response, force: true) }
                    })
                }.padding(24).frame(maxWidth: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
            }.padding(12)
            VoiceEdgeGlow(active: voice.listening)
        }.task { await camera.start(navigation: true) }
            .onDisappear { voice.cancel(); camera.stop() }
            .onChange(of: phase) { _, state in if state == .background { voice.cancel(); camera.stop() } }
            .sheet(isPresented: $diagnostics) { SensorDiagnosticsView(camera: camera) }
    }
    private func read() {
        guard !reading else { return }
        guard camera.running, let frame = camera.scene.session.currentFrame,
              case .normal = frame.camera.trackingState,
              ProcessInfo.processInfo.systemUptime-frame.timestamp < 0.5 else {
            response = "I can’t reliably check the area ahead right now. Point toward a textured surface and try again."; settings.speak(response, force: true); return
        }
        reading = true
        Task {
            let evidence = await AgentSceneObservation.read(frame)
            defer { reading = false }
            guard camera.running, AgentSceneObservation.isFresh(frame, current: camera.scene.session.currentFrame) else {
                response = "That camera reading is no longer fresh. Please ask again."; return
            }
            let distance = evidence["measuredDepthMetres"].map { "Measured central surface: about \($0) metres. " } ?? "I can’t reliably measure the area ahead right now. "
            response = distance + "Text: \(evidence["recognizedText"] ?? "unknown"). \(evidence["objectIdentity"] ?? "Object identity is unknown.") This cannot confirm a clear path."
            settings.speak(response, force: true)
        }
    }
}

/// Floor evidence is separate from the phone-height obstacle band.
enum FloorSensor {
    static func read(_ frame: ARFrame) -> FloorEvidence {
        let camera = frame.camera.transform.columns.3
        let point = SIMD4<Float>(camera.x, camera.y, camera.z, 1)
        // Only accept a classified horizontal floor whose measured extent contains the phone.
        let floors = frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter {
            guard $0.alignment == .horizontal, $0.classification == .floor else { return false }
            let p = simd_inverse($0.transform) * point
            let extent = $0.planeExtent
            return FloorPlaneBounds.contains(x: p.x - $0.center.x, z: p.z - $0.center.z,
                width: extent.width, height: extent.height, yaw: extent.rotationOnYAxis) && p.y > 0.3 && p.y < 2.5
        }
        guard let floor = floors.max(by: { $0.transform.columns.3.y < $1.transform.columns.3.y }),
              let depth = frame.sceneDepth, let confidence = depth.confidenceMap else { return .unknown }
        let buffer = depth.depthMap
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_DepthFloat32 else { return .unknown }
        CVPixelBufferLockBaseAddress(buffer, .readOnly); CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly); CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetWidth(confidence) == w, CVPixelBufferGetHeight(confidence) == h,
              let base = CVPixelBufferGetBaseAddress(buffer), let scores = CVPixelBufferGetBaseAddress(confidence) else { return .unknown }
        let k = frame.camera.intrinsics
        let sx = Float(w)/Float(frame.camera.imageResolution.width), sy = Float(h)/Float(frame.camera.imageResolution.height)
        var forward = -SIMD3(frame.camera.transform.columns.2.x, 0, frame.camera.transform.columns.2.z)
        guard simd_length(forward) > 0.3 else { return .unknown }
        forward = simd_normalize(forward)
        let right = SIMD3(-forward.z, Float(0), forward.x)
        var samples: [FloorDepthSample] = []
        for y in stride(from: 0, to: h, by: 4) {
            let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: Float.self)
            let conf = scores.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: w, by: 4) {
                let d = row[x]
                guard conf[x] == 2, d.isFinite, d > 0.2, d < 4 else { continue }
                let p = frame.camera.transform * SIMD4((Float(x)-k[2][0]*sx)*d/(k[0][0]*sx), -(Float(y)-k[2][1]*sy)*d/(k[1][1]*sy), -d, 1)
                let delta = SIMD3(p.x-camera.x, p.y-camera.y, p.z-camera.z)
                guard abs(simd_dot(delta, right)) < 0.35, p.y < floor.transform.columns.3.y + 0.15 else { continue }
                samples.append(.init(ahead: simd_dot(delta, forward), height: p.y))
            }
        }
        return FloorAssessment.evaluate(floor: floor.transform.columns.3.y, samples: samples)
    }
}
