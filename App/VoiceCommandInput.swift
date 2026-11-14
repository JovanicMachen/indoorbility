import AVFoundation
import Speech
import Combine
import SwiftUI

/// One explicitly started utterance. Partial recognition never executes commands.
@MainActor final class VoiceCommandInput: ObservableObject {
    static let notUnderstood = "Didn’t catch that."
    @Published private(set) var busy = false
    @Published private(set) var listening = false
    @Published private(set) var transcript = ""
    @Published private(set) var status = "Tap Listen, say a command, then tap Done."
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var token = UUID()
    private var tapped = false
    private var ownsAudio = false
    private var completion: ((String) -> Void)?
    private var interruption: AnyCancellable?
    init() {
        interruption = NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self, self.busy else { return }
                self.cancel(); self.status = "Listening was interrupted. Hold to speak again, or type your request."
            }
    }

    func start(onResult: @escaping (String) -> Void) async {
        cancel()
        let current = token
        busy = true; transcript = ""; status = "Checking microphone and speech access…"
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard current == token else { return }
        guard permission == .authorized else { fail("Speech access is off. Allow Speech Recognition in iPhone Settings, or use the buttons."); return }
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard current == token else { return }
        guard mic else { fail("Microphone access is off. Allow Microphone in iPhone Settings, or use the buttons."); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            fail("On-device English speech recognition is unavailable. Use the buttons or optional face controls."); return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
            try audio.setActive(true); ownsAudio = true
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { fail("No microphone input is available."); return }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.contextualStrings = ["yes", "no", "repeat", "pause guidance", "start guidance", "open settings", "narration on", "narration off", "I am lost", "directions to the building", "Friend Center", "room"]
            self.request = request; completion = onResult
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapped = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                Task { @MainActor in
                    guard let self, current == self.token else { return }
                    if let text, text != self.transcript {
                        self.transcript = text
                        self.silence?.cancel()
                        self.silence = Task { [weak self] in
                            try? await Task.sleep(for: .seconds(2.5))
                            guard !Task.isCancelled, self?.token == current else { return }
                            self?.finish()
                        }
                    }
                    if final, let text {
                        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.fail(Self.notUnderstood); return }
                        // On-device final segments can report zero confidence; that is not proof of silence.
                        // Destination resolution and confirmation still validate recognized requests.
                        self.deliver(text)
                    } else if error != nil {
                        // The recognizer can end with an error after delivering usable text.
                        // Submit once on termination; never execute changing partial results.
                        self.deliverOrFail()
                    }
                }
            }
            engine.prepare(); try engine.start()
            listening = true; status = "Listening… Say one command, then tap Done."
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, self?.token == current else { return }
                self?.finish()
            }
        } catch { fail("Microphone could not start. Please try again or use the buttons.") }
    }
    func finish() {
        guard listening else { return }
        timeout?.cancel(); silence?.cancel(); stopAudio(deactivate: false); listening = false
        status = "Finishing…"
        request?.endAudio()
        let current = token
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, self?.token == current else { return }
            self?.deliverOrFail()
        }
    }
    func clearTranscript() { transcript = "" }
    private func deliverOrFail() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { fail(Self.notUnderstood) } else { deliver(text) }
    }
    private func deliver(_ text: String) {
        let handler = completion
        cancel(); status = "Heard: \(text)"
        handler?(text)
    }
    func cancel() {
        token = UUID(); timeout?.cancel(); timeout = nil; silence?.cancel(); silence = nil
        stopAudio(); request?.endAudio(); task?.cancel()
        task = nil; request = nil; completion = nil; busy = false; listening = false
    }
    private func stopAudio(deactivate: Bool = true) {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        if deactivate && ownsAudio { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation); ownsAudio = false }
    }
    private func fail(_ message: String) { cancel(); status = message }
}
