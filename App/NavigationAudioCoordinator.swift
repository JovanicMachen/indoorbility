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
    func speak(_ text: String, priority: SpeechImportance = .routine, positionTime: Double? = nil) {
        let line = PendingSpeech(text, priority: priority, now: ProcessInfo.processInfo.systemUptime, positionTime: positionTime)
        if current?.text == text { return }
        if let active = current, NavigationSpeechQueue.shouldInterrupt(active: active, incoming: line) {
            // An obsolete direction must not finish (or resume after a warning).
            current = nil; utterance = nil; synth.stopSpeaking(at: .immediate)
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

/// User-supplied travel tick plus synthesized directional cues.
@MainActor final class NavigationAudioCoordinator: NSObject {
    private var player: AVAudioPlayer?
    private var journeyPlayer: AVAudioPlayer?
    private var interrupted = false
    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }
    @objc private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: value) else { return }
        interrupted = type == .began
        if interrupted { stop() }
    }
    func setJourneyLoop(active: Bool) {
        guard active, !interrupted else { journeyPlayer?.pause(); return }
        guard journeyPlayer?.isPlaying != true else { return }
        do {
            if journeyPlayer == nil {
                guard let url = Bundle.main.url(forResource: "JourneyLoop", withExtension: "mp3") else { return }
                journeyPlayer = try AVAudioPlayer(contentsOf: url)
                journeyPlayer?.numberOfLoops = -1
                journeyPlayer?.prepareToPlay()
            }
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
            journeyPlayer?.volume = 0
            journeyPlayer?.play()
            journeyPlayer?.setVolume(0.08, fadeDuration: 0.4)
        } catch { lastCue = "Playback unavailable" }
    }
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
    func stop() { player?.stop(); journeyPlayer?.stop() }
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
