import SwiftUI
import CoreLocation
import IndoorbilityCore

struct RememberRouteView: View {
    @ObservedObject var settings: AppStore
    @StateObject private var library = ScanLibrary()
    @StateObject private var camera = SpatialSession()
    @StateObject private var location = OutdoorLocation()
    @StateObject private var confirmationVoice = VoiceCommandInput()
    @State private var building = ""
    @State private var room = ""
    @State private var floorLabel = ""
    @State private var entrance = ""
    @State private var capturedDraft: ScanDraft?
    @State private var stage = 0
    @State private var sharedLandmark = ""
    @State private var markingLandmark = false
    @State private var saving = false
    @State private var error: String?
    @State private var entranceFix: EntranceLocation?
    /// Best GPS fix seen while standing at the start, so the saved 3D map gets a real
    /// map pin even when GPS is weaker near a building.
    @State private var bestStartFix: CLLocation?
    @State private var completed: IndoorJourneyTarget?
    @State private var scanning = false
    @State private var testRoute = false
    @State private var diagnostics = false
    @State private var editDestination = false
    @State private var coach = ScanCoach()
    @State private var coachTip: ScanCoach.Tip?
    @State private var lastTrackingWarning = -Double.infinity
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    private var onFinished: (() -> Void)?
    private var startingLabel: String {
        let label = entrance.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Recording start" : label
    }
    private var labelsValid: Bool {
        let values = [building, startingLabel, room].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return values.allSatisfy { !$0.isEmpty } && values[1].caseInsensitiveCompare(values[2]) != .orderedSame
    }
    private var savedBuildings: [String] {
        Array(Set(library.scans.map(\.name))).sorted()
    }
    init(settings: AppStore, knownRoom: FriendCenter.Room? = nil, requestedRoom: RoomMappingRequest? = nil, onFinished: (() -> Void)? = nil) {
        self.settings = settings; self.onFinished = onFinished
        _editDestination = State(initialValue: false)
        _building = State(initialValue: requestedRoom?.building ?? (knownRoom == nil ? "" : FriendCenter.name))
        _room = State(initialValue: requestedRoom.map { "Room " + $0.room } ?? knownRoom.map { "Room " + $0.id } ?? "")
        _floorLabel = State(initialValue: requestedRoom?.verifiedFloor ?? knownRoom?.level ?? "")
    }
    var body: some View {
        // A ZStack always has a background, so the camera cover below stays
        // attached while recording (an empty Group dropped it: blank screen).
        ZStack {
            Color.indoorBackground.ignoresSafeArea()
            if let completed {
                ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 48, weight: .medium)).foregroundStyle(Color.indoorTeal)
                        .frame(width: 100, height: 100).background(Color.indoorPeach.opacity(0.35), in: Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Color.indoorTeal).background(Color.indoorBackground, in: Circle())
                        }.accessibilityHidden(true)
                    Text("Route saved").font(.largeTitle.bold())
                    Label("Saved on this iPhone", systemImage: "checkmark").font(.subheadline).foregroundStyle(Color.indoorTeal)
                    Text("\(completed.route.entrance.label) → \(completed.route.room.label)").font(.headline)
                    SavedScanPreview(file: completed.library.directory(completed.draft.id).appending(path: "mesh.json"))
                    Text("Return to \(completed.route.entrance.label), then test the route.")
                        .font(.subheadline).multilineTextAlignment(.center)
                    Button("Follow route") { testRoute = true }
                        .buttonStyle(.borderedProminent)
                    Button("Done") { if let onFinished { onFinished() } else { dismiss() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    NavigationLink("View 3D scan") {
                        VolunteerReviewView(library: library, settings: settings, draft: completed.draft, route: completed.route)
                    }.font(.subheadline)
                }.padding(28).frame(maxWidth: .infinity)
                }.background(Color.indoorBackground)
            } else if stage == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Record a route").font(.largeTitle.bold())
                            Text("Stand where you’re starting. Then walk to where you want to go.")
                                .font(.title3).foregroundStyle(.secondary)
                        }
                        // The one thing to fill in.
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Where are you going?").font(.title2.bold())
                            TextField("Room, area or object", text: $room)
                                .font(.title3).padding(16)
                                .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.indoorTeal.opacity(0.25)))
                                .submitLabel(.go)
                                .accessibilityIdentifier("Room or destination")
                            Text("For example: Room 006, the lounge, the coffee machine.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        // Building in one line; change only if needed.
                        if editDestination {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Building").font(.headline)
                                TextField("Building name", text: $building).textFieldStyle(.roundedBorder)
                                if !savedBuildings.isEmpty {
                                    Menu("Use saved building") {
                                        ForEach(savedBuildings, id: \.self) { name in Button(name) { building = name; editDestination = false } }
                                    }.font(.subheadline)
                                }
                            }
                        } else {
                            HStack {
                                Label(building, systemImage: "building.2").font(.headline).lineLimit(1)
                                Spacer()
                                Button("Change") { editDestination = true }.font(.subheadline)
                                    .accessibilityLabel("Change building")
                            }.padding(14).background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Button {
                            building = building.trimmingCharacters(in: .whitespacesAndNewlines)
                            room = room.trimmingCharacters(in: .whitespacesAndNewlines)
                            entrance = startingLabel
                            stage = 1; error = nil; capturedDraft = nil; scanning = true
                        } label: {
                            Label("Start recording", systemImage: "record.circle")
                                .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(!SpatialSession.supportsLiDAR || !labelsValid)
                        if !SpatialSession.supportsLiDAR {
                            Text("Recording needs an iPhone or iPad with LiDAR.").font(.footnote).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("More options") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Name the start (optional)", text: $entrance)
                                    .accessibilityIdentifier("Start location")
                                TextField("Floor (optional)", text: $floorLabel)
                                    .accessibilityIdentifier("Floor label (confirm from building signage)")
                                if !entrance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                   entrance.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(room.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                                    Text("The start and destination need different names.").font(.footnote)
                                }
                            }.textFieldStyle(.roundedBorder).padding(.top, 8)
                        }.tint(.indoorTeal)
                    }.padding(24)
                }.scrollDismissesKeyboard(.interactively).background(Color.indoorBackground)
                    .onAppear {
                        // Most people record in the same building again: preselect it.
                        if building.isEmpty, let recent = library.scans.first?.name { building = recent }
                        // No building yet: keep the field open while typing.
                        if building.isEmpty { editDestination = true }
                    }

            } else {
                // Recording is in progress (or its camera was closed by the system).
                VStack(spacing: 18) {
                    Image(systemName: "record.circle").font(.system(size: 52)).foregroundStyle(Color.indoorTeal)
                    Text("Recording to \(room)").font(.title2.bold()).multilineTextAlignment(.center)
                    Button("Open camera") { scanning = true }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("reopenRecordingCamera")
                    Button("Start over") { stage = 0; capturedDraft = nil; camera.stop() }
                }.padding(28)
            }
        }.navigationTitle(completed == nil ? "Trace route" : "Saved").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $scanning) { captureScreen }
            .fullScreenCover(isPresented: $testRoute) {
                if let completed {
                    HallwayLaunchView(route: completed.route, draft: completed.draft, library: completed.library, settings: settings)
                }
            }
            .onDisappear { if !scanning { camera.stop(); location.stop() } }
    }
    private var captureScreen: some View {
        ZStack {
            SpatialCamera(session: camera).ignoresSafeArea().accessibilityHidden(true)
            VStack {
                HStack {
                    Button { scanning = false; stage = 0 } label: {
                        Image(systemName: "xmark").frame(width: 48, height: 48).background(.regularMaterial, in: Circle())
                    }.accessibilityLabel("Close scan").disabled(saving)
                    Spacer()
                    if UserDefaults.standard.bool(forKey: "agentDeveloperMode") {
                        Menu { Button("Sensor diagnostics") { diagnostics = true } } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44).background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Scan options")
                    }
                    Text(stage == 1 ? "Start" : stage == 2 ? "Recording" : "Save").font(.headline).padding(14).background(.regularMaterial, in: Capsule())
                }.padding()
                Spacer()
                ScanInstructionPanel {
                    ScanInstructionHeading(
                        status: saving ? "Saving…" : stage == 3 ? "Recording complete" : camera.running ? (camera.meshCount > 0 ? "Mapping your surroundings" : "Finding surfaces…") : "Camera paused",
                        title: stage == 1 ? "Start at \(entrance)" : stage == 2 ? "Walk to \(room)" : "Save this route?",
                        instruction: stage == 1 ? "Gently look around, then tap Start here." : stage == 2 ? "Keep the camera ahead. When you reach the spot, stand where people should stop and tap Stop here." : "Your path and 3D map will be saved together.",
                        active: camera.running && stage < 3
                    )
                    if !camera.running && capturedDraft == nil {
                        Text(camera.error ?? "Camera paused. Restart the recording.").font(.callout)
                        Button("Restart recording") {
                            stage = 1; error = nil
                            Task { await camera.start(); location.start() }
                        }.buttonStyle(.borderedProminent)
                    } else if camera.position == nil && capturedDraft == nil {
                        Label(camera.trackingTip ?? "Hold still and point at a textured wall until tracking returns.", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(Color(red: 0.62, green: 0.20, blue: 0.20))
                            .accessibilityIdentifier("recordingTrackingTip")
                    } else if stage == 1 {
                        Button("Start here") {
                            camera.mark(entrance)
                            entranceFix = location.entranceFix ?? bestStartFix.flatMap { fix in
                                fix.horizontalAccuracy <= 35 && abs(fix.timestamp.timeIntervalSinceNow) < 10
                                    ? EntranceLocation(latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy, confirmedAt: Date()) : nil
                            }
                            location.stop(); stage = 2
                            if settings.preferences.haptics { AppHaptics.shared.success() }
                            coach = ScanCoach(); coachTip = nil
                            settings.speak("Start confirmed. Walk to \(room). Slow down at corners and sweep the phone across them.")
                        }.buttonStyle(.borderedProminent).disabled(camera.meshCount == 0)
                    } else if stage == 2 {
                        if let coachTip {
                            Label(coachTip.text, systemImage: coachTip.symbol)
                                .font(.headline).foregroundStyle(Color.indoorTeal)
                                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.indoorPeach.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityIdentifier("scanCoachTip")
                                .transition(.opacity)
                        }
                        Button("Mark shared landmark") { markingLandmark = true }.font(.footnote)
                        Button("Stop here · this is \(room)") {
                            camera.mark(room); stage = 3
                            if settings.preferences.haptics { AppHaptics.shared.success() }
                            settings.speak("End stop set. Tap Save route.", force: true)
                        }.accessibilityIdentifier("stopHereEndStop")
                            .buttonStyle(.borderedProminent)
                    } else {
                        Text(room).font(.headline)
                        Button(saving ? "Saving…" : "Save route") { save() }
                            .buttonStyle(.borderedProminent).disabled(saving || (capturedDraft == nil && !camera.canSave))
                        DisclosureGroup("Confirm by voice") {
                        HoldToTalk(voice: confirmationVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 64) { text in
                            let answer = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                            if ["yes", "yes save", "yes please", "save", "confirm"].contains(answer) {
                                save()
                            } else if ["no", "cancel", "no thanks"].contains(answer) {
                                settings.speak("Your recording is kept. Save when ready.", force: true)
                            } else {
                                settings.speak("Say save to keep this route.", force: true)
                            }
                        }.disabled(saving)
                        }
                        if capturedDraft == nil && !camera.canSave { Text("Slowly look around this spot for more detail.").font(.caption) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.controlSize(.large).tint(.indoorTeal)
            }
        }.overlay { VoiceEdgeGlow(active: confirmationVoice.listening) }.interactiveDismissDisabled(saving)
            .task { location.start(); await camera.start() }
            .onChange(of: camera.position) { _, position in
                guard stage == 2, let position, !saving else { return }
                guard let tip = coach.update(x: position.x, z: position.z, time: ProcessInfo.processInfo.systemUptime, meshCount: camera.meshCount) else { return }
                withAnimation(.easeInOut(duration: 0.25)) { coachTip = tip }
                if settings.preferences.haptics {
                    if tip.kind == .corner { AppHaptics.shared.pattern([0, 0.15], intensity: 0.9, sharpness: 0.6) }
                    else if tip.kind == .cornerDone { AppHaptics.shared.success() }
                }
                if tip.speak { settings.speak(tip.text) }
            }
            .onChange(of: camera.trackingTip) { _, tip in
                // Say it the moment tracking drops so the walk can be kept clean.
                let now = ProcessInfo.processInfo.systemUptime
                guard stage == 2, let tip, !saving, now - lastTrackingWarning >= 5 else { return }
                lastTrackingWarning = now
                if settings.preferences.haptics { AppHaptics.shared.pattern([0, 0.12, 0.24], intensity: 1, sharpness: 0.8) }
                settings.speak(tip, priority: .safety)
            }
            .onChange(of: location.location) { _, fix in
                guard stage == 1, let fix, fix.horizontalAccuracy >= 0 else { return }
                if bestStartFix.map({ fix.horizontalAccuracy <= $0.horizontalAccuracy || abs($0.timestamp.timeIntervalSinceNow) > 60 }) ?? true { bestStartFix = fix }
            }
            .alert("Shared landmark", isPresented: $markingLandmark) {
                TextField("Name for this spot", text: $sharedLandmark)
                Button("Mark here") { camera.mark(sharedLandmark); sharedLandmark = "" }.disabled(sharedLandmark.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Use the same physical spot when extending this building.") }
            .sheet(isPresented: $diagnostics) { SensorDiagnosticsView(camera: camera) }
            .onDisappear { camera.stop(); location.stop() }
            .onChange(of: phase) { _, value in
                if value == .background || (value == .inactive && camera.running) { camera.stop(); location.stop() }
            }
    }
    private func save() {
        guard !saving, labelsValid else { return }
        guard stage == 3, (capturedDraft != nil || (camera.running && camera.position != nil && camera.canSave)) else {
            error = "Hold still and look around to finish saving."
            settings.speak(error!, force: true); return
        }
        saving = true; error = nil
        Task {
            do {
                let draft: ScanDraft
                if let capturedDraft { draft = capturedDraft }
                else { draft = try await camera.save(name: building, library: library); capturedDraft = draft }
                guard let first = draft.landmarks.first, let last = draft.landmarks.last else { throw MapError.invalid("Both landmarks are required.") }
                let route = try HallwayRoute.make(draft: draft, entranceID: first.id, roomID: last.id, reviewed: true)
                try library.saveHallway(route, draft: draft)
                if !route.hasLevelChange && !floorLabel.trimmingCharacters(in: .whitespaces).isEmpty {
                    let metadata = VerifiedRoomMetadata(buildingID: draft.id, roomID: route.room.id, floorLabel: floorLabel)
                    try JSONEncoder().encode(metadata).write(to: library.directory(draft.id).appending(path: "room-metadata.json"), options: .atomic)
                }
                if let entranceFix { try JSONEncoder().encode(entranceFix).write(to: library.directory(draft.id).appending(path: "entrance-location.json"), options: .atomic) }
                try library.publishRecording(route, draft: draft)
                completed = IndoorJourneyTarget(route: route, draft: draft, library: library)
                scanning = false
                settings.speak("Route saved. Return to the start, then tap Follow route.")
            } catch {
                let message = error.localizedDescription
                // Retrying cannot fix a trace that needs re-recording; don't suggest it.
                self.error = message + (capturedDraft == nil || message.contains("Record this route again") ? "" : " Scan kept. Tap Save route to retry.")
            }
            saving = false
        }
    }
}
