import AVFoundation
import SwiftUI
import CoreHaptics
import simd
import IndoorbilityCore

@MainActor final class NavigationSpeechCoordinator: NSObject, AVSpeechSynthesizerDelegate {
    var isSpeaking: Bool { current != nil }
    private let synth = AVSpeechSynthesizer()
    private var queue = NavigationSpeechQueue()
    private var current: PendingSpeech?
    private var utterance: AVSpeechUtterance?
    override init() {
        super.init(); synth.usesApplicationAudioSession = false; synth.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(announcementFinished(_:)), name: UIAccessibility.announcementDidFinishNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }
    @objc private func interrupted() { stop() }
    func stop() { queue.clear(); current = nil; utterance = nil; synth.stopSpeaking(at: .immediate) }
    func speak(_ text: String, priority: SpeechImportance = .routine) {
        let line = PendingSpeech(text, priority: priority, now: ProcessInfo.processInfo.systemUptime)
        if current?.text == text { return }
        if priority == .safety, let active = current, active.priority != .safety {
            queue.resumeInterrupted(active); current = nil; utterance = nil; synth.stopSpeaking(at: .immediate)
        }
        queue.push(line); advance()
    }
    private func advance() {
        guard current == nil, UIApplication.shared.applicationState == .active,
              let line = queue.next(now: ProcessInfo.processInfo.systemUptime) else { return }
        current = line
        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .announcement, argument: line.text); return
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
              current?.text == text else { return }
        current = nil; advance()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.utterance === utterance else { return }
            self.current = nil; self.utterance = nil; self.advance()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.utterance === utterance else { return }
            self.current = nil; self.utterance = nil; self.advance()
        }
    }
}

/// Original low-volume synthesized tones; no downloaded or system notification sounds.
@MainActor final class NavigationAudioCoordinator {
    private var player: AVAudioPlayer?
    private(set) var lastCue = "None"
    func travelTick() {
        guard player?.isPlaying != true,
              let url = Bundle.main.url(forResource: "TravelTick", withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 0.12
            player?.numberOfLoops = 0
            player?.play()
        } catch { lastCue = "Playback unavailable" }
    }
    func stop() { player?.stop() }
    func play(_ cue: GuidanceCue) {
        stop()
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
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data); player?.volume = 0.45
            if player?.play() == true { lastCue = cue.rawValue }
        } catch { lastCue = "Playback unavailable" }
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
    var body: some View {
        Toggle("Mute all app sound", isOn: $store.allSoundMuted)
        Toggle("Audio cues", isOn: $cues)
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
    private var engine: CHHapticEngine?
    func play(_ cue: GuidanceCue, instruction: String) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            let times: [Double]
            if cue == .attention { times = [0, 0.12, 0.24] }
            else if cue == .arrived { times = [0, 0.2, 0.5] }
            else if cue == .turn && instruction.lowercased().contains("right") { times = [0, 0.18] }
            else { times = [0] }
            let events = times.map { CHHapticEvent(eventType: .hapticTransient, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: cue == .attention ? 1 : 0.7), CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)], relativeTime: $0) }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine?.makePlayer(with: pattern).start(atTime: 0)
        } catch { engine = nil }
    }
}

@MainActor final class DirectionalBeacon {
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()
    private let node = AVAudioPlayerNode()
    private var configured = false
    func stop() { node.stop(); engine.pause() }
    func ping(_ vector: SIMD3<Float>) {
        guard vector.x.isFinite, vector.y.isFinite, vector.z.isFinite,
              AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP].contains($0.portType) }) else { stop(); return }
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
            if !configured {
                engine.attach(environment); engine.attach(node)
                engine.connect(node, to: environment, format: format)
                engine.connect(environment, to: engine.mainMixerNode, format: nil)
                node.renderingAlgorithm = .HRTFHQ; configured = true
            }
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            let length = max(0.01, simd_length(vector))
            let p = vector / length * 2
            node.position = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 6615)!
            buffer.frameLength = 6615
            for i in 0..<6615 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 600 / 44100) * sin(.pi * Double(i)/6615) * 0.15) }
            node.stop(); node.scheduleBuffer(buffer); node.play()
        } catch { stop() }
    }
}
