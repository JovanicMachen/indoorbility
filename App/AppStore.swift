import SwiftUI
import AVFoundation
import UIKit
import simd
import IndoorbilityCore

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var session: NavigationSession
    @Published var errorMessage: String?
    @Published var selectedTab = 0
    var speechSuspended = false
    private let persistence: any StatePersistence
    private let speaker = NavigationSpeechCoordinator()
    let audio = NavigationAudioCoordinator()
    private let hapticGuide = NavigationHaptics()
    private let beacon = DirectionalBeacon()
    private var travelPosition: SIMD2<Double>?
    private var travelTime = 0.0
    private var travelContext = ""
    private var lastPriorityCue = 0.0
    func travelFeedback(position: SIMD2<Double>?, context: String) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let position, !speechSuspended, UIApplication.shared.applicationState == .active,
              UserDefaults.standard.object(forKey: "travelFeedback") as? Bool ?? true else {
            travelPosition = nil; return
        }
        guard travelContext == context, travelPosition != nil else {
            travelContext = context; travelPosition = position; travelTime = now; return
        }
        // Repeat only while navigation supplies a reliable position. No detached audio loop
        // can continue after tracking stops, arrival, or leaving navigation.
        guard now - travelTime >= 2 else { return }
        guard !speaker.isSpeaking, !UIAccessibility.isVoiceOverRunning, now-lastPriorityCue >= 4 else { return }
        travelPosition = position; travelTime = now
        if preferences.haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.3) }
        if !allSoundMuted, UserDefaults.standard.object(forKey: "guidanceCues") as? Bool ?? true { audio.travelTick() }
    }
    func directionalCue(_ target: SIMD3<Float>?) {
        guard let target, !allSoundMuted, !speechSuspended, UserDefaults.standard.bool(forKey: "directionalSound"), UIApplication.shared.applicationState == .active else { beacon.stop(); return }
        beacon.ping(target)
    }
    @Published var allSoundMuted = UserDefaults.standard.bool(forKey: "guidanceMuted") {
        didSet { UserDefaults.standard.set(allSoundMuted, forKey: "guidanceMuted"); if allSoundMuted { stopSpeech() } }
    }
    func cue(_ cue: GuidanceCue, instruction: String = "") {
        lastPriorityCue = ProcessInfo.processInfo.systemUptime
        if preferences.haptics && !speechSuspended { hapticGuide.play(cue, instruction: instruction) }
        guard GuidanceSoundPolicy.cueAllowed(muted: allSoundMuted, enabled: UserDefaults.standard.object(forKey: "guidanceCues") as? Bool ?? true, suspended: speechSuspended) else { return }
        audio.play(cue)
    }
    @Published private(set) var lastNarration = ""
    private(set) var activeSpeechGeneration = 0

    init(building suppliedBuilding: Building? = nil, stateURL: URL? = nil) throws {
        let building = try suppliedBuilding ?? Building.demo()
        let storage = try stateURL.map { FileStatePersistence(url: $0) } ?? Self.storage()
        persistence = storage
        session = try NavigationSession(building: building, saved: storage.load(for: building))
    }

    private static func storage() throws -> FileStatePersistence {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
        return FileStatePersistence(url: directory.appendingPathComponent("Indoorbility/state.json"))
    }
    static func recoverSavedState() throws { try storage().backupForRecovery() }

    var building: Building { session.building }
    var preferences: Preferences { session.saved.preferences }
    var activeReports: [BarrierReport] { session.saved.reports.filter(\.isActive) }
    var blockedEdges: Set<String> {
        session.saved.blockedEdges.union(building.edges.filter { $0.blocked || !$0.verified }.map(\.id))
    }
    var connector: String {
        guard let route = session.route else { return "No route" }
        let connectors = building.edges.filter { route.edgeIDs.contains($0.id) && $0.kind != .hallway }
        return connectors.isEmpty ? "Same floor" : connectors.map { building.edgeLabel($0.id) }.joined(separator: ", ")
    }
    var instruction: String {
        if session.arrived { return "You have confirmed arrival at your destination." }
        guard let next = session.nextCheckpoint else { return "Confirm a checkpoint to plan your route." }
        if let current = session.checkpointID.flatMap(building.node), current.floor != next.floor {
            return "Use \(connector) to reach \(next.label). Confirm your position when you arrive."
        }
        return "Next checkpoint: \(next.label), level \(next.floor). Confirm only when you are there."
    }

    func change(_ mutation: (inout NavigationSession) throws -> Void) {
        do {
            var updated = session
            try mutation(&updated)
            // Persist before publishing. Failed writes leave the previous route and reports intact.
            if updated.saved != session.saved { try persistence.save(updated.saved) }
            let previous = session
            session = updated
            if !preferences.speech { stopSpeech() }
            if preferences.haptics { UISelectionFeedbackGenerator().selectionChanged() }
            if let message = NavigationNarration.update(from: previous, to: session, instruction: instruction) { speak(message) }
        } catch {
            errorMessage = "Change not applied: \(error.localizedDescription)"
            speak(errorMessage ?? "Change could not be saved.")
        }
    }
    func setPreference(_ key: WritableKeyPath<Preferences, Bool>, _ value: Bool) {
        change { session in
            var preferences = session.saved.preferences
            preferences[keyPath: key] = value
            try session.setPreferences(preferences)
        }
        if key == \Preferences.speech, preferences.speech == value {
            if value { speak("Narration on. " + navigationSummary) }
            else { stopSpeech() }
        }
    }
    var navigationSummary: String {
        if session.isGuiding || session.arrived { return instruction }
        if session.needsPosition { return "Scan a room or entrance sign, or choose a starting point. Then choose Where to. This is a demo map; your position is not tracked along the route." }
        return session.route == nil ? "Choose a destination to plan your route." : "Your route is ready. Select Start for checkpoint instructions."
    }
    func speak(_ text: String, force: Bool = false, priority: SpeechImportance = .routine) {
        guard GuidanceSoundPolicy.speechAllowed(muted: allSoundMuted, enabled: preferences.speech, forced: force, voiceOver: UIAccessibility.isVoiceOverRunning, active: UIApplication.shared.applicationState == .active, suspended: speechSuspended) else { return }
        audio.stop()
        lastPriorityCue = ProcessInfo.processInfo.systemUptime
        lastNarration = text
        activeSpeechGeneration += 1
        speaker.speak(text, priority: priority)
    }
    func repeatInstruction() { speak(instruction) }
    func repeatNarration() { speak(lastNarration.isEmpty ? navigationSummary : lastNarration) }
    func stopSpeech() { travelPosition = nil; activeSpeechGeneration += 1; speaker.stop(); audio.stop(); beacon.stop() }
}
