import ARKit
import Vision
import Foundation
import IndoorbilityCore

@MainActor final class EntranceRecognition {
    private var busy = false
    var currentFrame: (() -> ARFrame?)?
    private var consecutiveMatches = 0
    private var previousEvidence: TimeInterval = 0
    private(set) var processingMS = 0.0
    private(set) var expiredResults = 0
    private var lastFrame: TimeInterval = 0
    private var lastMatch: TimeInterval = -.infinity
    private var generation = UUID()
    let label: String
    let distinctiveEntrance: Bool
    init(label: String, distinctiveEntrance: Bool = true) { self.label = label; self.distinctiveEntrance = distinctiveEntrance }
    var matchedRecently: Bool { ProcessInfo.processInfo.systemUptime - lastMatch < 1.5 }
    func reset() { consecutiveMatches = 0; previousEvidence = 0; generation = UUID(); lastMatch = -.infinity; lastFrame = 0 }
    func process(_ frame: ARFrame) {
        // A generic "Entrance" alone cannot independently identify the marked door.
        guard !busy,
              frame.timestamp-lastFrame > 0.6 else { return }
        busy = true; lastFrame = frame.timestamp
        let capturedAt = frame.timestamp
        let buffer = frame.capturedImage, token = generation, label = label, entrance = distinctiveEntrance
        let started = ProcessInfo.processInfo.systemUptime
        Task {
            let matched = await Task.detached(priority: .utility) {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right)
                do {
                    try handler.perform([request])
                    return (request.results ?? []).contains {
                        guard let candidate = $0.topCandidates(1).first, candidate.confidence >= 0.8 else { return false }
                        return LandmarkTextEvidence.matches(candidate.string, expected: label, confidence: candidate.confidence, entrance: entrance)
                    }
                } catch { return false }
            }.value
            processingMS = (ProcessInfo.processInfo.systemUptime-started)*1000
            if generation == token {
                let fresh = ProcessInfo.processInfo.systemUptime-capturedAt < 0.75 &&
                    AgentSceneObservation.isFresh(frame, current: currentFrame?())
                if !fresh { expiredResults += 1 }
                if fresh && matched {
                    consecutiveMatches = capturedAt-previousEvidence <= 1.5 ? consecutiveMatches+1 : 1
                    previousEvidence = capturedAt
                    if consecutiveMatches >= 2 { lastMatch = capturedAt }
                } else { consecutiveMatches = 0; lastMatch = -.infinity }
            }
            busy = false
        }
    }
}
