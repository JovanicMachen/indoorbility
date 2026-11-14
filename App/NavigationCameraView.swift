import SwiftUI
import VisionKit
import PhotosUI
import AVFoundation
import IndoorbilityCore

/// Camera surface for navigation. Text is captured for review, never treated as an AR pose.
struct NavigationCameraView: View {
    @ObservedObject var store: AppStore
    var isForeground = true
    let onConfirmStart: (String) -> Bool
    @Environment(\.scenePhase) private var phase
    @State private var active = false
    @State private var visible = false
    @State private var busy = false
    @State private var generation = 0
    @State private var recognized = ""
    @State private var error: String?
    @State private var denied = false
    @State private var photo: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var source: BarrierReport.Source = .photo
    @State private var review: SignEvidence?
    @State private var announcedText = false

    private var supported: Bool { DataScannerViewController.isSupported }
    var body: some View {
        ZStack {
            Color.black
            if active {
                LiveSignCamera(text: $recognized, error: $error)
            } else if let preview {
                Image(uiImage: preview).resizable().scaledToFit().padding(.vertical, 70)
            }
            VStack(spacing: 12) {
                HStack {
                    Label(source == .demo ? "Sample sign" : active ? "Camera" : "Camera off", systemImage: "camera.fill")
                    Spacer()
                    Text("Demo building")
                }.font(.caption.weight(.medium)).padding(10).background(.black.opacity(0.65), in: Capsule())
                Spacer(minLength: 0)
                if !active && preview == nil {
                    VStack(spacing: 10) {
                        Image(systemName: "viewfinder").font(.system(size: 42, weight: .light)).accessibilityHidden(true)
                        Text(supported ? "Scan a room or closure sign" : "Camera unavailable on this device")
                            .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                        if supported {
                            Button(denied ? "Open Settings" : "Enable camera") {
                                if denied, let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                else { Task { await startCamera(requestPermission: true) } }
                            }.buttonStyle(.borderedProminent).accessibilityIdentifier("enableNavigationCamera")
                        } else {
                            Button("Try sample sign") {
                                if let data = SignRecognition.sampleImage(startingPoint: true).pngData() {
                                    Task { await read(data, source: .demo) }
                                }
                            }.buttonStyle(.borderedProminent).disabled(busy).accessibilityIdentifier("inlineSampleSign")
                        }
                    }.padding(12).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                }
                if busy { ProgressView("Reading sign…").tint(.white) }
                Spacer(minLength: 0)
                if let error { Text(error).font(.caption).multilineTextAlignment(.center).padding(8).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8)) }
                if !recognized.isEmpty {
                    Text(recognized.replacingOccurrences(of: "\n", with: " · ")).font(.caption).lineLimit(2)
                        .padding(8).background(.black.opacity(0.75), in: Capsule()).accessibilityIdentifier("inlineRecognizedText")
                }
                HStack {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Image(systemName: "photo").font(.title2).frame(width: 48, height: 48)
                    }.accessibilityLabel("Choose sign photo").disabled(busy)
                    Spacer()
                    Button {
                        active = false
                        review = SignEvidence(text: recognized, source: source)
                    } label: {
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 62, height: 62)
                            .overlay { Circle().fill(.white).padding(6) }
                            .opacity(recognized.isEmpty || busy ? 0.35 : 1)
                    }.buttonStyle(.plain).disabled(recognized.isEmpty || busy)
                        .accessibilityLabel("Review captured sign").accessibilityIdentifier("captureNavigationSign")
                    Spacer()
                    Button { Task { await startCamera(requestPermission: true) } } label: {
                        Image(systemName: "arrow.clockwise").font(.title2).frame(width: 48, height: 48)
                    }.disabled(!supported || busy).accessibilityLabel("Restart camera")
                }
                Text("Read sign").font(.caption)
            }.foregroundStyle(.white).padding(16)
        }.clipShape(RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 12).padding(.bottom, 10)
            .onAppear {
                visible = true
                store.speak(supported ? "Camera view. Point the back camera at a room or entrance sign. Enable camera if asked." : "Camera is unavailable here. Choose a sign photo, try the sample sign, or switch to Map.")
                Task { await startCamera(requestPermission: false) }
            }
            .task(id: recognized) {
                guard !recognized.isEmpty, !announcedText else { return }
                do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                guard visible, isForeground, review == nil, !announcedText else { return }
                announcedText = true
                store.speak("Text found. Select Review captured sign to hear it and confirm a starting point.")
            }
            .onDisappear { visible = false; stop() }
            .onChange(of: isForeground) { _, value in
                if !value { stop() }
                else if preview == nil { Task { await startCamera(requestPermission: false) } }
            }
            .onChange(of: phase) { _, value in
                if value != .active { stop() }
                else if review == nil && preview == nil { Task { await startCamera(requestPermission: false) } }
            }
            .onChange(of: error) { _, value in if let value { active = false; store.speak(value) } }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                stop()
                let token = generation
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw MapError.invalid("Unable to open this photo.") }
                        guard visible, token == generation else { return }
                        await read(data, source: .photo)
                    } catch { if visible && token == generation { self.error = error.localizedDescription } }
                }
            }
            .sheet(item: $review, onDismiss: {
                if preview == nil { Task { await startCamera(requestPermission: false) } }
            }) { evidence in
                CapturedSignReview(store: store, evidence: evidence, onConfirmStart: onConfirmStart)
            }
    }
    private func stop() { generation += 1; active = false; busy = false }
    private func startCamera(requestPermission: Bool) async {
        guard visible, isForeground, phase == .active, supported, review == nil else { return }
        let token = generation
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        let allowed: Bool
        if status == .authorized { allowed = true }
        else if status == .notDetermined && requestPermission { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        else { allowed = false }
        guard visible, isForeground, token == generation, review == nil else { return }
        denied = AVCaptureDevice.authorizationStatus(for: .video) == .denied || AVCaptureDevice.authorizationStatus(for: .video) == .restricted
        guard allowed else {
            if denied { store.speak("Camera access is off. Open Settings to allow it, choose a photo, or use the map.") }
            return
        }
        guard DataScannerViewController.isAvailable else { error = "Text scanning is unavailable. Choose a photo or use the map."; return }
        error = nil; recognized = ""; announcedText = false; preview = nil; source = .photo; active = true
        store.speak("Camera ready. Point the back camera at a sign. Hold steady until text is found.")
    }
    private func read(_ data: Data, source: BarrierReport.Source) async {
        stop()
        let token = generation
        announcedText = false
        store.speak("Reading the sign photo.")
        busy = true; recognized = ""; error = nil; preview = UIImage(data: data); self.source = source
        defer { if token == generation { busy = false } }
        do {
            let text = try await SignRecognition.read(data)
            guard visible, token == generation else { return }
            recognized = text
            if text.isEmpty { error = "No readable text. Try a closer photo." }
        } catch { if visible && token == generation { self.error = error.localizedDescription } }
    }
}

struct CapturedSignReview: View {
    @ObservedObject var store: AppStore
    let evidence: SignEvidence
    let onConfirmStart: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var reportPresented = false
    @State private var controlsPresented = false
    var body: some View {
        NavigationStack {
            Form {
                Section(evidence.source == .demo ? "Sample image text" : "Recognized text") {
                    Text(evidence.text).textSelection(.enabled)
                }
                Section {
                    let matches = SignLocationMatcher.candidates(in: evidence.text, building: store.building)
                    if matches.isEmpty { Text("No matching starting point. You can select one on the map.").foregroundStyle(.secondary) }
                    ForEach(matches) { node in
                        Button("Use \(node.label) as start", systemImage: "location.circle") {
                            if onConfirmStart(node.id) { dismiss() }
                        }.frame(minHeight: 44).accessibilityIdentifier("inlineConfirmStart_\(node.id)")
                    }
                } header: { Text("Starting point") } footer: {
                    Text("Matches are in the fictional demo building. Confirming a sign does not provide live indoor positioning.")
                }
                Section {
                    Button("Answer by voice or face", systemImage: "mic") { controlsPresented = true }
                        .accessibilityIdentifier("answerSignCommands")
                }
                Section("Closure") {
                    Text(BarrierInterpreter.interpret(evidence.text, in: store.building).message).font(.subheadline).foregroundStyle(.secondary)
                    Button("Review a closure report", systemImage: "flag") { reportPresented = true }
                }
            }.navigationTitle("Check sign").navigationBarTitleDisplayMode(.inline)
                .onAppear { store.speak("Captured sign: " + evidence.text + ". Review the starting point below. Nothing changes until you confirm.") }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { store.speak("Sign review cancelled. Your starting point has not changed."); dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Read sign", systemImage: "speaker.wave.2") { store.speak("Captured sign: " + evidence.text) }
                            .disabled(!store.preferences.speech && !UIAccessibility.isVoiceOverRunning)
                    }
                }
                .sheet(isPresented: $controlsPresented) {
                    let matches = SignLocationMatcher.candidates(in: evidence.text, building: store.building)
                    AccessibleControlView(store: store, startingPoint: matches.count == 1 ? matches.first?.id : nil,
                                          signText: evidence.text, onStartConfirmed: { dismiss() }, onExitToSettings: { dismiss() })
                }
                .sheet(isPresented: $reportPresented) { ReportView(store: store, evidence: evidence) }
                .alert("Starting point not saved", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
    }
}
