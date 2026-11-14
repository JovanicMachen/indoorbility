import ARKit
import Vision
import IndoorbilityCore

/// One requested frame; local evidence only, no image upload.
enum AgentSceneObservation {
    static func isFresh(_ captured: ARFrame, current: ARFrame?) -> Bool {
        guard let current, case .normal = current.camera.trackingState,
              ProcessInfo.processInfo.systemUptime-current.timestamp >= 0,
              ProcessInfo.processInfo.systemUptime-current.timestamp < 0.5 else { return false }
        let a = captured.camera.transform, b = current.camera.transform
        return SceneObservationValidity.isFresh(capturedAt: captured.timestamp, now: ProcessInfo.processInfo.systemUptime,
            movement: simd_length(a.columns.3-b.columns.3), forwardAgreement: simd_dot(a.columns.2, b.columns.2))
    }

    static func read(_ frame: ARFrame) async -> [String: String] {
        let image = frame.capturedImage
        return await Task.detached(priority: .utility) {
            var result = ["source": "on-device Vision OCR and ARKit sceneDepth", "objectIdentity": "unknown", "safety": "Not obstacle avoidance; unseen hazards remain unknown."]
            result["objectIdentity"] = CameraObjectEvidence.description(CameraObjectEvidence.read(frame))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            do {
                try VNImageRequestHandler(cvPixelBuffer: image, orientation: .right).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first }.filter { $0.confidence >= 0.8 }.prefix(8).map { String($0.string.prefix(100)) }
                result["recognizedText"] = text.isEmpty ? "No confident text recognized" : text.joined(separator: "; ")
            } catch { result["recognizedText"] = "Text recognition unavailable" }
            let observation = SceneAwarenessService.read(frame, includePoints: false)
            if observation.upright, let distance = observation.distance {
                result["measuredDepthMetres"] = String(format: "%.1f", distance)
                result["confidenceCoverage"] = String(format: "%.2f", observation.coverage)
            }
            if result["measuredDepthMetres"] == nil { result["measuredDepth"] = "Unavailable or low confidence" }
            return result
        }.value
    }
}

/// Local ML classification, separate from central LiDAR distance (not object distance).
enum CameraObjectEvidence {
    static func read(_ frame: ARFrame) -> String? {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = true
        do {
            try VNImageRequestHandler(cvPixelBuffer: frame.capturedImage, orientation: .right).perform([request])
            if (request.results ?? []).contains(where: {
                $0.confidence >= 0.85 && $0.boundingBox.midX >= 0.25 && $0.boundingBox.midX <= 0.75 && $0.boundingBox.height >= 0.15
            }) { return "person" }
        } catch { /* No confident visual identity; depth remains independent. */ }
        // Inspect a bounded sample of classified mesh faces in front of the current camera.
        // These are reconstructed surfaces, not proof a movable object is still there.
        let inverse = simd_inverse(frame.camera.transform)
        var counts = [String: Int]()
        for anchor in frame.anchors.compactMap({ $0 as? ARMeshAnchor }).prefix(24) {
            let mesh = anchor.geometry
            guard let classifications = mesh.classification else { continue }
            let faces = mesh.faces, vertices = mesh.vertices
            for face in stride(from: 0, to: faces.count, by: max(1, faces.count / 128)) {
                let raw = classifications.buffer.contents().advanced(by: classifications.offset + face * classifications.stride).load(as: UInt8.self)
                let kind: String
                if Int(raw) == ARMeshClassification.table.rawValue { kind = "table" }
                else if Int(raw) == ARMeshClassification.seat.rawValue { kind = "seat" }
                else { continue }
                guard faces.indexCountPerPrimitive == 3 else { continue }
                var center = SIMD3<Float>(repeating: 0)
                for corner in 0..<3 {
                    let ptr = faces.buffer.contents().advanced(by: (face * 3 + corner) * faces.bytesPerIndex)
                    let index = faces.bytesPerIndex == 2 ? Int(ptr.load(as: UInt16.self)) : Int(ptr.load(as: UInt32.self))
                    guard index < vertices.count else { continue }
                    let v = vertices.buffer.contents().advanced(by: vertices.offset + index * vertices.stride).assumingMemoryBound(to: Float.self)
                    center += SIMD3(v[0], v[1], v[2]) / 3
                }
                let p = inverse * anchor.transform * SIMD4(center.x, center.y, center.z, 1)
                guard p.z < -0.3, p.z > -3, abs(p.x) < -p.z * 0.4, abs(p.y) < -p.z * 0.7 else { continue }
                counts[kind, default: 0] += 1
                if counts[kind, default: 0] >= 3 { return kind }
            }
        }
        return nil
    }
    static func description(_ kind: String?) -> String {
        switch kind {
        case "person": return "Possible person ahead in the camera view. Distance to the person is unknown."
        case "table": return "Possible table ahead in the reconstructed map; its current presence is unconfirmed."
        case "seat": return "Possible seat ahead in the reconstructed map; its current presence is unconfirmed."
        default: return "No object confidently identified; this does not mean the path is clear."
        }
    }
}
