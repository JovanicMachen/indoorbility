import AVFoundation
import SwiftUI
import CoreHaptics
import simd
import IndoorbilityCore

@MainActor final class NavigationSpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    var isSpeaking: Bool { current != nil }
    private let synth = AVSpeechSynthesizer()
    private var queue = NavigationSpeechQueue()
    private var admission = SpeechAdmission()
    private var relevance: [UUID: () -> Bool] = [:]
    private var lostHandlers: [UUID: () -> Void] = [:]
    private var pendingKeys: [UUID: String] = [:]
    private var announcementWatchdog: Task<Void, Never>?
    var onSpeakingChanged: (() -> Void)?
    private var current: PendingSpeech? { didSet { onSpeakingChanged?() } }
    private var utterance: AVSpeechUtterance?
    override init() {
        super.init(); synth.usesApplicationAudioSession = false; synth.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(announcementFinished(_:)), name: UIAccessibility.announcementDidFinishNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }
    @objc private func interrupted() { stop() }
    func stop() {
        announcementWatchdog?.cancel(); announcementWatchdog = nil
        queue.clear(); admission.reset(); relevance = [:]; lostHandlers = [:]; pendingKeys = [:]
        current = nil; utterance = nil; synth.stopSpeaking(at: .immediate)
    }
    @discardableResult func speak(_ text: String, priority: SpeechImportance = .routine, positionTime: Double? = nil,
               userRequested: Bool = false, speechKey: String? = nil, stillRelevant: (() -> Bool)? = nil,
               onDiscard: (() -> Void)? = nil) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let line = PendingSpeech(text, priority: priority, now: now, positionTime: positionTime,
                                 userRequested: userRequested, deduplicationKey: speechKey)
        guard admission.allows(line, active: current, now: now) else { return false }
        if let active = current, NavigationSpeechQueue.shouldInterrupt(active: active, incoming: line) {
            // Safety stops a direction immediately. Ordinary turns finish their
            // sentence; obsolete queued turns are replaced and revalidated.
            announcementWatchdog?.cancel()
            current = nil; utterance = nil; synth.stopSpeaking(at: .immediate)
        }
        relevance[line.id] = stillRelevant
        lostHandlers[line.id] = onDiscard
        pendingKeys[line.id] = line.deduplicationKey
        queue.push(line); advance()
        prunePending()
        return true
    }
    private func prunePending() {
        var keep = queue.pendingIDs
        if let current { keep.insert(current.id) }
        let removed = Set(pendingKeys.keys).subtracting(keep)
        for id in removed {
            if let key = pendingKeys.removeValue(forKey: id) { admission.forget(key) }
            let valid = relevance.removeValue(forKey: id)?() ?? true
            let handler = lostHandlers.removeValue(forKey: id)
            if valid { handler?() }
        }
    }
    private func completed(_ line: PendingSpeech, lost: Bool) {
        pendingKeys.removeValue(forKey: line.id)
        if lost { admission.forget(line.deduplicationKey) }
        let valid = relevance.removeValue(forKey: line.id)?() ?? true
        let handler = lostHandlers.removeValue(forKey: line.id)
        if lost && valid { handler?() }
    }
    private func advance() {
        let checks = relevance
        guard current == nil, UIApplication.shared.applicationState == .active,
              let line = queue.next(now: ProcessInfo.processInfo.systemUptime,
                                    isRelevant: { checks[$0.id]?() ?? true }) else { return }
        admission.didStart(line, now: ProcessInfo.processInfo.systemUptime)
        current = line
        prunePending()
        if UIAccessibility.isVoiceOverRunning {
            let announcement = NSAttributedString(string: line.text, attributes: [
                .accessibilitySpeechAnnouncementPriority: line.priority == .safety ? UIAccessibilityPriority.high : UIAccessibilityPriority.low
            ])
            UIAccessibility.post(notification: .announcement, argument: announcement)
            // VoiceOver can be disabled before its completion notification.
            announcementWatchdog?.cancel()
            announcementWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(6, Double(line.text.count)*0.12+2)))
                guard !Task.isCancelled, let self, self.current?.id == line.id else { return }
                self.completed(line, lost: true); self.current = nil; self.advance(); self.prunePending()
            }
            return
        }
        let next = AVSpeechUtterance(string: line.text)
        let defaults = UserDefaults.standard
        let selected = defaults.string(forKey: "guidanceVoice") ?? ""
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        next.voice = AVSpeechSynthesisVoice(identifier: selected) ?? AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }.max { $0.quality.rawValue < $1.quality.rawValue }
        let rate = defaults.double(forKey: "guidanceRate")
        next.rate = rate == 0 ? AVSpeechUtteranceDefaultSpeechRate : Float(min(0.6, max(0.3, rate)))
        utterance = next; synth.speak(next)
    }
    @objc private func announcementFinished(_ note: Notification) {
        guard UIAccessibility.isVoiceOverRunning,
              let text = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String,
              let line = current, line.text == text else { return }
        completed(line, lost: note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? Bool != true)
        announcementWatchdog?.cancel(); announcementWatchdog = nil
        current = nil; advance(); prunePending()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let started = ProcessInfo.processInfo.systemUptime
        Task { @MainActor in
            guard self.utterance === utterance, let line = self.current else { return }
            NavigationPerformance.shared.record("Speech request → synthesis start ms", (started-line.requestedAt)*1000)
            if let source = line.positionTime {
                NavigationPerformance.shared.record("Position capture → synthesis start ms", (started-source)*1000)
            }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.utterance === utterance else { return }
            if let line = self.current { self.completed(line, lost: false) }
            self.current = nil; self.utterance = nil; self.advance()
            self.prunePending()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.utterance === utterance else { return }
            if let line = self.current { self.completed(line, lost: true) }
            self.current = nil; self.utterance = nil; self.advance()
            self.prunePending()
        }
    }
}

/// Session configuration and AVAudioPlayer I/O share one non-main executor.
/// No player or mutable SDK object crosses this actor's boundary.
actor AppAudioWorker {
    static let shared = AppAudioWorker()
    private final class Streams {
        var cue: AVAudioPlayer?
        var loop: AVAudioPlayer?
        var ducked = false
        var pendingStop: Task<Void, Never>?
        func cancelPendingStop() { pendingStop?.cancel(); pendingStop = nil }
    }
    /// Normalized clip followed by a silent gap, rendered once as WAV data.
    private var loopAsset: (data: Data, clipDuration: TimeInterval)?
    private var clients: [UUID: Streams] = [:]
    private var waveCache: [String: Data] = [:]
    private var voiceLease: UUID?
    private var navigationActive = false
    private func streams(_ id: UUID) -> Streams {
        if let value = clients[id] { return value }
        let value = Streams(); clients[id] = value; return value
    }
    func activateNavigation() throws -> Bool {
        assert(!Thread.isMainThread)
        guard voiceLease == nil else { return false }
        if !navigationActive {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetoothHFP])
            // iOS mutes haptics in a recording-capable session unless allowed.
            try? audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audio.setActive(true)
            navigationActive = true
        }
        return true
    }
    func beginRecording(lease: UUID) throws {
        assert(!Thread.isMainThread)
        for value in clients.values { value.cancelPendingStop(); value.cue?.stop(); value.loop?.pause() }
        navigationActive = false; voiceLease = lease
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try? audio.setAllowHapticsAndSystemSoundsDuringRecording(true)
            try audio.setActive(true)
        } catch { if voiceLease == lease { voiceLease = nil }; throw error }
    }
    func endRecording(lease: UUID) {
        guard voiceLease == lease else { return } // An old request cannot deactivate a new recording.
        voiceLease = nil; navigationActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func interrupted() {
        navigationActive = false; voiceLease = nil
        for value in clients.values { value.cancelPendingStop(); value.cue?.stop(); value.loop?.stop() }
    }
    func remove(_ id: UUID) {
        clients[id]?.cancelPendingStop(); clients[id]?.cue?.stop(); clients[id]?.loop?.stop(); clients[id] = nil
    }
    func stopCue(_ id: UUID, gate: AudioRequestGate, token: UUID) {
        guard gate.contains(token) else { return }; clients[id]?.cue?.stop()
    }
    /// `finishCurrent` lets an audible clip end before pausing (travel briefly
    /// paused). Stop, Mute, interruptions and recording always stop at once.
    func loop(_ id: UUID, active: Bool, ducked: Bool, finishCurrent: Bool = false, gate: AudioRequestGate, token: UUID) throws -> Bool {
        guard gate.contains(token) else { return false }
        let value = streams(id)
        guard active else {
            value.cancelPendingStop()
            guard let player = value.loop, player.isPlaying else { return false }
            let delay = finishCurrent ? TravelLoopTiming.softStopDelay(currentTime: player.currentTime,
                                                                       clipDuration: loopAsset?.clipDuration ?? 0) : 0
            if delay <= 0 { player.pause(); player.currentTime = 0; return false }
            value.pendingStop = Task {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self.finishSoftStop(id)
            }
            return false
        }
        guard voiceLease == nil else { return false }
        let volume = ducked ? TravelLoopTiming.duckedVolume : TravelLoopTiming.normalVolume
        if value.loop?.isPlaying == true {
            value.cancelPendingStop() // Travel resumed before the clip ended: keep playing.
            if value.ducked != ducked { value.loop?.setVolume(volume, fadeDuration: 0.2) }
            value.ducked = ducked; return true
        }
        if value.loop == nil {
            guard let asset = try preparedLoop() else { return false }
            value.loop = try AVAudioPlayer(data: asset.data)
            value.loop?.numberOfLoops = -1; value.loop?.prepareToPlay()
        }
        guard try activateNavigation(), gate.contains(token) else { return false }
        value.loop?.currentTime = 0
        value.loop?.volume = volume
        guard value.loop?.play() == true else { return false }
        value.ducked = ducked
        return true
    }
    private func finishSoftStop(_ id: UUID) {
        guard let value = clients[id], value.pendingStop != nil else { return }
        value.pendingStop = nil
        value.loop?.pause(); value.loop?.currentTime = 0
    }
    /// Decodes the bundled clip once, normalizes it and appends the silent gap.
    private func preparedLoop() throws -> (data: Data, clipDuration: TimeInterval)? {
        if let loopAsset { return loopAsset }
        guard let url = Bundle.main.url(forResource: "JourneyLoop", withExtension: "mp3") else { return nil }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return nil }
        let channelCount = Int(format.channelCount), frames = Int(buffer.frameLength)
        let sampleRate = Int(format.sampleRate.rounded())
        var peak: Float = 0
        for c in 0..<channelCount { for i in 0..<frames { peak = max(peak, abs(channels[c][i])) } }
        let gain = TravelLoopTiming.gain(peak: peak)
        let gapFrames = Int(Double(sampleRate) * TravelLoopTiming.gapSeconds)
        let total = frames + gapFrames
        var pcm = Data(capacity: total * channelCount * 2)
        for i in 0..<total {
            for c in 0..<channelCount {
                let sample = i < frames ? max(-1, min(1, channels[c][i] * gain)) : 0
                var v = Int16(sample * 32767).littleEndian
                withUnsafeBytes(of: &v) { pcm.append(contentsOf: $0) }
            }
        }
        var data = Data()
        func bytes(_ text: String) { data.append(contentsOf: text.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        let blockAlign = channelCount * 2
        bytes("RIFF"); number(UInt32(36 + pcm.count)); bytes("WAVEfmt "); number(UInt32(16)); number(UInt16(1))
        number(UInt16(channelCount)); number(UInt32(sampleRate)); number(UInt32(sampleRate * blockAlign))
        number(UInt16(blockAlign)); number(UInt16(16)); bytes("data"); number(UInt32(pcm.count))
        data.append(pcm)
        let asset = (data: data, clipDuration: Double(frames) / Double(sampleRate))
        loopAsset = asset
        return asset
    }
    func cue(_ cue: GuidanceCue, id: UUID, gate: AudioRequestGate, token: UUID) throws -> Bool {
        guard gate.contains(token), voiceLease == nil else { return false }
        let value = streams(id); value.cue?.stop()
        let data = waveCache[cue.rawValue] ?? makeWave(cue)
        waveCache[cue.rawValue] = data
        guard try activateNavigation(), gate.contains(token) else { return false }
        value.cue = try AVAudioPlayer(data: data); value.cue?.volume = 0.45
        guard gate.contains(token) else { return false }
        return value.cue?.play() == true
    }
    private func makeWave(_ cue: GuidanceCue) -> Data {
        let frequencies: [Double]
        switch cue {
        case .started: frequencies = [440, 550]
        case .approach: frequencies = [520]
        case .turn: frequencies = [520, 660]
        case .changed: frequencies = [440, 600, 520]
        case .attention: frequencies = [350, 350]
        case .arrived: frequencies = [440, 550, 660]
        }
        let sampleRate = 22050
        var samples = [Int16]()
        for frequency in frequencies {
            let count = sampleRate / 8
            for i in 0..<count {
                let envelope = sin(.pi * Double(i) / Double(count))
                samples.append(Int16(2200 * envelope * sin(2 * .pi * frequency * Double(i) / Double(sampleRate))))
            }
            samples += Array(repeating: 0, count: sampleRate / 25)
        }
        var data = Data()
        func bytes(_ text: String) { data.append(contentsOf: text.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) { var v = value.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        bytes("RIFF"); number(UInt32(36 + samples.count*2)); bytes("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(sampleRate)); number(UInt32(sampleRate*2)); number(UInt16(2)); number(UInt16(16)); bytes("data"); number(UInt32(samples.count*2))
        for sample in samples { number(sample) }
        return data
    }
}

/// UI state only. Blocking audio configuration, decoding and playback live above.
@MainActor final class NavigationAudioCoordinator: NSObject {
    private let id = UUID()
    private let cueGate = AudioRequestGate()
    private let loopGate = AudioRequestGate()
    private var interrupted = false
    private var loopRequested = false
    private var loopDucked = false
    private(set) var journeyLoopPlaying = false
    private(set) var lastCue = "None"
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    deinit {
        cueGate.renew(); loopGate.renew()
        let id = id
        Task { await AppAudioWorker.shared.remove(id) }
    }
    @objc nonisolated private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        let began = type == .began
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.interrupted = began
            if began { self.stop(); await AppAudioWorker.shared.interrupted() }
        }
    }
    func setJourneyLoop(active: Bool, ducked: Bool = false, finishCurrent: Bool = false) {
        let allowed = active && !interrupted
        guard allowed != loopRequested || (allowed && ducked != loopDucked) else { return }
        loopRequested = allowed; loopDucked = ducked
        let token = loopGate.renew(), id = id, gate = loopGate
        let soft = finishCurrent && !interrupted
        if !allowed { journeyLoopPlaying = false }
        Task { [weak self] in
            do {
                let played = try await AppAudioWorker.shared.loop(id, active: allowed, ducked: ducked,
                    finishCurrent: soft, gate: gate, token: token)
                guard let self, gate.contains(token) else { return }
                self.journeyLoopPlaying = played
                if allowed && !played { self.loopRequested = false }
            } catch {
                guard let self, gate.contains(token) else { return }
                self.journeyLoopPlaying = false; self.loopRequested = false; self.lastCue = "Playback unavailable"
            }
        }
    }
    func stop() {
        stopCue(); loopRequested = false; journeyLoopPlaying = false
        let token = loopGate.renew(), id = id, gate = loopGate
        Task { _ = try? await AppAudioWorker.shared.loop(id, active: false, ducked: false, gate: gate, token: token) }
    }
    func stopCue() {
        let token = cueGate.renew(), id = id, gate = cueGate
        Task { await AppAudioWorker.shared.stopCue(id, gate: gate, token: token) }
    }
    func play(_ cue: GuidanceCue) {
        let token = cueGate.renew(), id = id, gate = cueGate
        Task { [weak self] in
            do {
                let played = try await AppAudioWorker.shared.cue(cue, id: id, gate: gate, token: token)
                guard let self, gate.contains(token) else { return }
                if played { self.lastCue = cue.rawValue }
            } catch {
                guard let self, gate.contains(token) else { return }; self.lastCue = "Playback unavailable"
            }
        }
    }
}

struct NavigationSoundSettings: View {
    @ObservedObject var store: AppStore
    @AppStorage("guidanceCues") var cues = true
    @AppStorage("travelFeedback") var travel = true
    @AppStorage("directionalSound") var directional = false
    @AppStorage("guidanceFeet") var feet = false
    @AppStorage("guidanceRate") var rate = 0.5
    @AppStorage("guidanceVoice") var voice = ""
    @AppStorage("guidanceReminders") var reminders = false
    var body: some View {
        Toggle("Mute all app sound", isOn: $store.allSoundMuted)
        Toggle("Audio cues", isOn: $cues)
        Toggle("Occasional direction reminders", isOn: $reminders)
        Toggle("Travel sounds & taps", isOn: $travel)
        Toggle("Directional sound (headphones)", isOn: $directional)
        Text("Indoor turn taps: one for left, two for right, three for attention.").font(.footnote)
        Toggle("Distances in feet", isOn: $feet)
        Slider(value: $rate, in: 0.3...0.6) { Text("Speech rate") }
        Picker("Voice", selection: $voice) {
            Text("Best installed voice").tag("")
            ForEach(AVSpeechSynthesisVoice.speechVoices(), id: \.identifier) { Text("\($0.name) · \($0.language)").tag($0.identifier) }
        }
    }
}

@MainActor final class NavigationHaptics {
    func play(_ cue: GuidanceCue, instruction: String) {
        let times: [Double]
        if cue == .attention { times = [0, 0.12, 0.24] }
        else if cue == .arrived { times = [0, 0.2, 0.5] }
        else if cue == .turn && instruction.lowercased().contains("right") { times = [0, 0.18] }
        else { times = [0] }
        AppHaptics.shared.pattern(times, intensity: cue == .attention ? 1 : 0.8, sharpness: 0.7)
    }
}

/// One Core Haptics engine for the whole app. It survives audio-session
/// changes and iOS stopping the engine, and falls back to UIKit feedback.
@MainActor final class AppHaptics {
    static let shared = AppHaptics()
    private var engine: CHHapticEngine?
    private var needsStart = true
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private func ready() -> CHHapticEngine? {
        guard supported else { return nil }
        if engine == nil {
            guard let created = try? CHHapticEngine() else { return nil }
            // Haptics only: never competes with or reconfigures speech/audio.
            created.playsHapticsOnly = true
            created.isAutoShutdownEnabled = true
            created.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.needsStart = true } }
            created.resetHandler = { [weak self] in Task { @MainActor in self?.needsStart = true } }
            engine = created; needsStart = true
        }
        if needsStart {
            do { try engine?.start(); needsStart = false } catch { engine = nil; return nil }
        }
        return engine
    }
    func pattern(_ times: [Double], intensity: Float, sharpness: Float) {
        let events = times.map { CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)], relativeTime: $0) }
        if let engine = ready(), let pattern = try? CHHapticPattern(events: events, parameters: []),
           (try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)) != nil { return }
        // Retry once with a fresh engine, then fall back to UIKit.
        engine = nil
        if let engine = ready(), let pattern = try? CHHapticPattern(events: events, parameters: []),
           (try? engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)) != nil { return }
        UIImpactFeedbackGenerator(style: intensity >= 0.9 ? .heavy : .medium).impactOccurred(intensity: CGFloat(intensity))
    }
    func tap(_ intensity: Float = 0.6) { pattern([0], intensity: intensity, sharpness: 0.5) }
    func selection() { pattern([0], intensity: 0.5, sharpness: 0.9) }
    func success() { pattern([0, 0.12], intensity: 0.8, sharpness: 0.6) }
}

@MainActor final class DirectionalBeacon {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let node = AVAudioPlayerNode()
    private var configured = false
    private var generation = 0
    private var pending: Task<Void, Never>?
    func stop() { generation += 1; pending?.cancel(); pending = nil; node.stop(); engine.pause() }
    func ping(_ vector: SIMD3<Float>) {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite,
              AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0.portType) }) else { stop(); return }
        generation += 1; let token = generation
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                guard try await AppAudioWorker.shared.activateNavigation(), !Task.isCancelled,
                      self.generation == token else { return }
                try self.playPing(vector)
            } catch { if self.generation == token { self.stop() } }
        }
    }
    private func playPing(_ vector: SIMD3<Float>) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        if !configured {
            engine.attach(environment); engine.attach(node)
            engine.connect(node, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
            node.renderingAlgorithm = .HRTFHQ; configured = true
        }
        if !engine.isRunning { try engine.start() }
        let length = max(0.01, simd_length(vector))
        let p = vector / length * 2
        node.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 6615)!
        buffer.frameLength = 6615
        for i in 0..<6615 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 600 / 44100) * sin(.pi * Double(i)/6615) * 0.15) }
        // Schedule before play. The async overload waits for completion, so it
        // cannot be awaited here before starting an otherwise empty player.
        node.stop(); node.scheduleBuffer(buffer); node.play()
    }
}

/// Opt-in, bounded timing only. No coordinates, speech text, or credentials leave the phone.
@MainActor final class NavigationPerformance: NSObject {
    static let shared = NavigationPerformance()
    private var windows: [String: TimingWindow] = [:]
    private var bodyCounts: [String: Int] = [:]
    private var pendingDisplay: [String: Double] = [:]
    private var displayLink: CADisplayLink?
    private var previousDisplay: Double?
    private var lastActivity = 0.0
    private(set) var updates = 0
    var enabled: Bool { UserDefaults.standard.bool(forKey: "agentDeveloperMode") }
    func bodyEvaluated(_ screen: String) {
        guard enabled else { return }
        bodyCounts[screen, default: 0] += 1
    }
    func record(_ name: String, _ value: Double) {
        guard enabled else { return }
        windows[name, default: TimingWindow()].record(value)
    }
    func position(_ source: String, captured: Double) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= captured else { return }
        updates += 1; lastActivity = now
        // Preserve oldest outstanding sample so coalescing does not hide a stall.
        if pendingDisplay[source] == nil { pendingDisplay[source] = captured }
        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(displayTick))
            link.add(to: .main, forMode: .common); displayLink = link
        }
    }
    @objc private func displayTick(_ link: CADisplayLink) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, UIApplication.shared.applicationState == .active, now-lastActivity < 2 else {
            displayLink?.invalidate(); displayLink = nil; previousDisplay = nil; pendingDisplay = [:]; return
        }
        if let previousDisplay {
            record("Main display callback interval ms", (now-previousDisplay)*1000)
        }
        previousDisplay = now
        for (source, captured) in pendingDisplay {
            record(source + " capture → next display opportunity ms", (now-captured)*1000)
        }
        pendingDisplay = [:]
    }
    var lines: [String] {
        guard enabled else { return ["Enable developer diagnostics to measure navigation timing."] }
        return ["Position updates observed: \(updates)",
                "Display opportunity is a scheduling proxy, not measured pixels or map-tile rendering.",
                "Synthesis start excludes VoiceOver and does not measure acoustic output."] + bodyCounts.keys.sorted().map { "\($0) body evaluations: \(bodyCounts[$0]!)" } + windows.keys.sorted().map { key in
            let window = windows[key]!
            return String(format: "%@: mean %.2f, p95 %.2f (n=%d)", key, window.mean ?? 0, window.p95 ?? 0, window.count)
        }
    }
}
