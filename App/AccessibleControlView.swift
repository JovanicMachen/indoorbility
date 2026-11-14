import SwiftUI
import AVFoundation

import IndoorbilityCore

struct AccessibleControlView: View {
    @ObservedObject var store: AppStore
    var startingPoint: String? = nil
    var signText: String? = nil
    var onStartConfirmed: () -> Void = {}
    var onExitToSettings: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var voice = VoiceCommandInput()
    @StateObject private var face = FaceCommandInput()
    @State private var confirmation = CommandConfirmation()
    @State private var message = "Choose an action or tap Listen."
    @State private var mode = "Voice"
    @State private var option = -1
    @State private var visible = false
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var options: [(String, AccessibleCommand)] {
        [("Start guidance", .start), ("Pause guidance", .pause),
         ("Narration on", .narration(true)), ("Narration off", .narration(false)),
         ("Haptics on", .haptics(true)), ("Haptics off", .haptics(false)),
         ("One instruction on", .focused(true)), ("One instruction off", .focused(false)),
         ("Avoid stairs", .avoidStairs(true)), ("Allow stairs", .avoidStairs(false)), ("Open settings", .settings)]
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Input", selection: $mode) { Text("Voice").tag("Voice"); Text("Face").tag("Face") }
                        .pickerStyle(.segmented).accessibilityIdentifier("commandMode")
                    Text(confirmation.command == nil ? message : confirmation.question)
                        .font(.headline).accessibilityIdentifier("commandPrompt")
                    if confirmation.command != nil { Text("Answer Yes or No within 30 seconds.").font(.caption) }
                    HStack {
                        Button("Yes") { handle(.yes) }.disabled(confirmation.command == nil).accessibilityIdentifier("commandYes")
                        Spacer()
                        Button("No") { handle(.no) }.disabled(confirmation.command == nil).accessibilityIdentifier("commandNo")
                        Spacer()
                        Button("Repeat") { handle(.repeatPrompt) }
                    }.buttonStyle(.borderless).frame(minHeight: 44).disabled(voice.busy)
                    Button("Next option") { handle(.next) }.disabled(voice.busy).accessibilityIdentifier("commandNext")
                }
                if mode == "Voice" {
                    Section("Push to talk") {
                        Button {
                            if voice.listening { voice.finish() }
                            else {
                                store.stopSpeech(); store.speechSuspended = true
                                Task { await voice.start { text in
                                    store.speechSuspended = false
                                    guard visible, phase == .active else { return }
                                    let places = Dictionary(uniqueKeysWithValues: store.building.nodes.map { ($0.id, $0.label) })
                                    guard let command = AccessibleCommand.parse(text, destinations: places) else {
                                        say("I didn’t recognize that command. Nothing changed. Say one command, such as Repeat or Open settings."); return
                                    }
                                    handle(command)
                                } }
                            }
                        } label: {
                            Label(voice.listening ? "Done listening" : "Listen", systemImage: voice.listening ? "stop.circle.fill" : "mic.fill")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }.buttonStyle(.borderedProminent).disabled(voice.busy && !voice.listening)
                            .accessibilityIdentifier("listenCommand")
                        if voice.busy { Button("Cancel listening") { voice.cancel(); store.speechSuspended = false; say("Listening cancelled. Nothing changed.") } }
                        Text(voice.status).font(.subheadline).accessibilityIdentifier("voiceStatus")
                        if !voice.transcript.isEmpty { Text("Heard: \(voice.transcript)").font(.caption) }
                        Text("Say Yes, No, Repeat, Next, Start guidance, Pause guidance, Open settings, or Go to followed by a place name. Listening ends after eight seconds. Wait for spoken prompts to finish before tapping Listen.").font(.footnote)
                        Text("English commands use on-device recognition when available. Audio is not saved. There is no always-on microphone.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else { faceControls }
                Section("Choose an action") {
                    if let startingPoint {
                        Button("Use scanned starting point") { propose(.checkpoint(startingPoint)) }.disabled(voice.busy)
                    }
                    ForEach(options.indices, id: \.self) { index in
                        Button(options[index].0) { propose(options[index].1) }.disabled(voice.busy)
                    }
                    ForEach(store.building.destinations(matching: "")) { place in
                        Button("Go to \(place.label)") { propose(.destination(place.id)) }.disabled(voice.busy)
                    }
                }
            }.navigationTitle("Voice & face controls").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
                .onAppear {
                    visible = true
                    if let startingPoint { propose(.checkpoint(startingPoint)) }
                    else { say("Voice controls. Tap Listen to speak, or choose an action. Face controls are optional.") }
                    face.onGesture = { gesture in
                        guard visible, phase == .active, mode == "Face", !face.practice else { return }
                        handle(gesture == .yes ? .yes : gesture == .no ? .no : .next)
                    }
                }
                .onDisappear { visible = false; shutdown(); face.onGesture = nil }
                .onChange(of: mode) { _, _ in shutdown(); say("\(mode) controls selected. Choose an action to continue.") }
                .onChange(of: phase) { _, value in if value == .background { shutdown(); message = "Controls paused. Choose an action to continue." }
                    else if value == .inactive { if voice.listening { voice.cancel(); store.speechSuspended = false }; if face.running { face.stop() } } }
                .onChange(of: face.calibrated) { _, value in if value { say("Calibration complete. Practice Yes by tilting your head, No by turning sideways, and Next by smiling. Hold each gesture, then relax.") } }
                .onChange(of: face.status) { _, status in
                    if visible && mode == "Face" && (status.hasPrefix("Face tracking lost") || status.hasPrefix("Face tracking stopped") || status.hasPrefix("Face controls paused") || status.hasPrefix("Camera access is off")) {
                        store.speak(status, force: true)
                    }
                }
                .onChange(of: face.practiced) { _, _ in if face.practice { store.speak(face.status, force: true) } }
                .onChange(of: voice.busy) { _, busy in store.speechSuspended = busy }
                .onChange(of: voice.status) { _, status in if !voice.busy && visible && !status.hasPrefix("Heard:") { store.speechSuspended = false; store.speak(status, force: true) } }
                .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
                    guard voice.busy,
                          let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          value == AVAudioSession.InterruptionType.began.rawValue else { return }
                    voice.cancel(); store.speechSuspended = false; confirmation.clear(); message = "Audio interrupted. Choose an action and try again."
                }
        }
    }
    private var faceControls: some View {
        Section("Optional face controls") {
            if FaceCommandInput.supported {
                if face.running { FaceCameraPreview(input: face).frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true) }
                Text(face.status).accessibilityIdentifier("faceStatus")
                Button(face.running ? "Recalibrate" : "Start face controls") {
                    if face.running { face.calibrate() } else { Task { await face.start() } }
                    say("Face the front camera, relax your expression and hold still for two seconds.")
                }
                Text("Tilt your head up or down for Yes. Turn your head sideways for No. Smile for Next. Hold one gesture for about a second, then return to neutral. Keep the phone still and practice while seated.").font(.footnote)
                Slider(value: $face.movement, in: 0.15...0.45) { Text("Head movement required") }
                    .accessibilityValue("\(Int(face.movement * 180 / .pi)) degrees")
                    .onChange(of: face.movement) { _, _ in face.calibrate() }
                Text("Practice completed: \(face.practiced.sorted().joined(separator: ", "))").font(.caption)
                Button(face.practice ? "Enable gesture actions" : "Return to practice") {
                    face.practice.toggle(); face.resetGesture(); confirmation.clear()
                    say(face.practice ? "Practice mode. Gestures will not change anything." : "Gesture actions enabled. Smile for the next option. Hear the question before answering Yes or No.")
                }.disabled(!face.calibrated || face.practiced.count < 3)
                if face.running { Button("Stop face controls") { face.stop(); confirmation.clear(); say("Face controls stopped.") } }
            } else {
                Text("Face controls need a supported physical iPhone or iPad. You can use voice or the buttons here.")
                    .accessibilityIdentifier("faceUnavailable")
            }
            Text("The front camera replaces sign scanning while this panel is open. Face frames and calibration stay in memory and are discarded when closed. No face identity is detected or saved.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private func shutdown() { voice.cancel(); face.stop(); confirmation.clear(); store.speechSuspended = false; store.stopSpeech() }
    private func say(_ text: String) { message = text; store.speak(text, force: true) }
    private func propose(_ command: AccessibleCommand) {
        let question: String
        switch command {
        case .checkpoint(let id): question = "Use \(store.building.node(id)?.label ?? "this checkpoint") as your starting point in the demo map?"
        case .destination(let id): question = "Plan a route to \(store.building.node(id)?.label ?? "this destination")?"
        case .start: question = "Start checkpoint guidance?"
        case .pause: question = "Pause guidance?"
        case .settings: question = "Open Settings?"
        case .narration(let on): question = "Turn narration \(on ? "on" : "off")?"
        case .haptics(let on): question = "Turn haptics \(on ? "on" : "off")?"
        case .focused(let on): question = "Turn one instruction at a time \(on ? "on" : "off")?"
        case .avoidStairs(let on): question = on ? "Exclude stairs from routes?" : "Allow stairs in routes? Step-free routing will be turned off."
        default: return
        }
        confirmation.propose(command, question: question, at: now)
        face.resetGesture(); say(question + " Answer Yes or No.")
    }
    private func handle(_ command: AccessibleCommand) {
        switch command {
        case .yes:
            guard let action = confirmation.answer(yes: true, at: now) else { say("There is no current question, or it expired. Choose an action first."); return }
            apply(action)
        case .no:
            _ = confirmation.answer(yes: false, at: now); say("Cancelled. Nothing changed.")
        case .repeatPrompt:
            say(confirmation.command != nil ? confirmation.question : signText.map { "Captured sign: " + $0 } ?? message)
        case .next:
            option = (option + 1) % options.count; propose(options[option].1)
        default: propose(command)
        }
    }
    private func apply(_ command: AccessibleCommand) {
        store.errorMessage = nil
        switch command {
        case .checkpoint(let id):
            store.change { try $0.confirmCheckpoint(id) }
            if store.errorMessage == nil { say("Starting point confirmed."); onStartConfirmed(); dismiss() }
        case .destination(let id):
            guard !store.session.needsPosition else { say("Confirm your starting point first. Scan a known sign or choose it on Navigate."); return }
            store.change { try $0.selectDestination(id) }
            if store.errorMessage == nil { say(store.session.route == nil ? "No route is available with these closures and preferences." : "Route ready. Say Start guidance when ready.") }
        case .start:
            guard store.session.route != nil, !store.session.arrived else { say("Choose a destination and confirm your starting point before starting guidance."); return }
            store.change { $0.startGuidance() }; say(store.instruction)
        case .pause: store.change { $0.stopGuidance() }; say("Guidance paused.")
        case .settings: store.selectedTab = 3; onExitToSettings(); dismiss()
        case .narration(let value): store.setPreference(\.speech, value); settingResult()
        case .haptics(let value): store.setPreference(\.haptics, value); settingResult()
        case .focused(let value): store.setPreference(\.reducedInformation, value); settingResult()
        case .avoidStairs(let value): store.setPreference(\.avoidStairs, value); settingResult()
        default: break
        }
        if let error = store.errorMessage { say(error) }
    }
    private func settingResult() { if store.errorMessage == nil { say("Setting updated.") } }
}
