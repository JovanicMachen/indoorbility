import ARKit
import AVFoundation
import SwiftUI
import IndoorbilityCore

@MainActor final class FaceCommandInput: NSObject, ObservableObject, @preconcurrency ARSessionDelegate {
    @Published private(set) var status = "Face controls are off."
    @Published private(set) var running = false
    @Published private(set) var calibrated = false
    @Published private(set) var practiced: Set<String> = []
    @Published var practice = true
    @Published var movement = 0.25
    let scene = ARSCNView(frame: .zero)
    static var supported: Bool { ARFaceTrackingConfiguration.isSupported }
    var onGesture: ((FaceGestureGate.Gesture) -> Void)?
    private var gate = FaceGestureGate()
    private var generation = UUID()
    private var neutral: SIMD3<Float>?
    private var calibrationStart: TimeInterval?
    private var calibrationPose: SIMD3<Float>?
    private var calibrating = false

    override init() {
        super.init()
        scene.session.delegate = self
        scene.session.delegateQueue = .main
    }
    func start() async {
        stop()
        let token = generation
        guard Self.supported else { status = "Face controls need a supported physical iPhone or iPad."; return }
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard token == generation else { return }
        guard allowed else { status = "Camera access is off. Enable it in iPhone Settings or use touch controls."; return }
        let configuration = ARFaceTrackingConfiguration()
        configuration.maximumNumberOfTrackedFaces = 1
        scene.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        running = true
        calibrate()
    }
    func calibrate() {
        neutral = nil; calibrated = false; practice = true; practiced = []
        calibrationStart = nil; calibrationPose = nil; calibrating = true; gate.reset()
        status = "Face the front camera with a relaxed expression. Hold still for two seconds."
    }
    func stop() {
        generation = UUID(); scene.session.pause(); running = false
        neutral = nil; calibrated = false; calibrating = false; gate.reset(); practice = true
    }
    func resetGesture() { gate.reset() }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running else { return }
        guard case .normal = frame.camera.trackingState,
              let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else {
            gate.reset(); calibrationStart = nil; calibrationPose = nil
            status = "Face tracking lost. Face the camera again."
            return
        }
        let relative = simd_inverse(frame.camera.transform) * face.transform
        let forward = relative.columns.2
        let pose = SIMD3<Float>(atan2(forward.y, forward.z), atan2(forward.x, forward.z),
            ((face.blendShapes[.mouthSmileLeft]?.floatValue ?? 0) + (face.blendShapes[.mouthSmileRight]?.floatValue ?? 0)) / 2)
        if calibrating {
            if let initial = calibrationPose, simd_distance(initial, pose) < 0.08 {
                if frame.timestamp - (calibrationStart ?? frame.timestamp) >= 2 {
                    neutral = pose; calibrated = true; calibrating = false; gate.reset()
                    status = "Calibrated. Practice Yes, No and Next before enabling actions."
                }
            } else { calibrationPose = pose; calibrationStart = frame.timestamp }
            return
        }
        guard let neutral else { return }
        func difference(_ a: Float, _ b: Float) -> Float { abs(atan2(sin(a - b), cos(a - b))) }
        let yes = difference(pose.x, neutral.x) > Float(movement)
        let no = difference(pose.y, neutral.y) > Float(movement)
        let next = pose.z - neutral.z > 0.35
        let count = [yes, no, next].filter { $0 }.count
        // Ambiguous combinations never arm or fire an action.
        guard count <= 1 else { gate.reset(); status = "Try one gesture at a time."; return }
        let gesture: FaceGestureGate.Gesture? = yes ? .yes : no ? .no : next ? .next : nil
        if let result = gate.update(gesture, at: frame.timestamp, tracked: true) {
            let name = result == .yes ? "Yes" : result == .no ? "No" : "Next"
            if practice { practiced.insert(name); status = "Practice: \(name). Return to neutral." }
            else { status = "\(name). Return to neutral."; onGesture?(result) }
        } else if gesture == nil { status = practice ? "Practice: tilt for Yes, turn for No, smile for Next." : "Ready. Tilt for Yes, turn for No, smile for Next." }
    }
    func sessionWasInterrupted(_ session: ARSession) { stop(); status = "Face controls paused. Start again to recalibrate." }
    func session(_ session: ARSession, didFailWithError error: Error) { stop(); status = "Face tracking stopped. Start again to recalibrate." }
}

struct FaceCameraPreview: UIViewRepresentable {
    let input: FaceCommandInput
    func makeUIView(context: Context) -> ARSCNView { input.scene }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
