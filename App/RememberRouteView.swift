import SwiftUI
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
    @State private var completed: IndoorJourneyTarget?
    @State private var scanning = false
    @State private var diagnostics = false
    @State private var editDestination = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    private var onFinished: (() -> Void)?
    private var labelsValid: Bool {
        let values = [building, entrance, room].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return values.allSatisfy { !$0.isEmpty } && values[1].caseInsensitiveCompare(values[2]) != .orderedSame
    }
    private var savedBuildings: [String] {
        Array(Set(library.scans.map(\.name))).sorted()
    }
    init(settings: AppStore, knownRoom: FriendCenter.Room? = nil, requestedRoom: RoomMappingRequest? = nil, onFinished: (() -> Void)? = nil) {
        self.settings = settings; self.onFinished = onFinished
        _editDestination = State(initialValue: requestedRoom == nil && knownRoom == nil)
        _building = State(initialValue: requestedRoom?.building ?? (knownRoom == nil ? "" : FriendCenter.name))
        _room = State(initialValue: requestedRoom.map { "Room " + $0.room } ?? knownRoom.map { "Room " + $0.id } ?? "")
        _floorLabel = State(initialValue: requestedRoom?.verifiedFloor ?? knownRoom?.level ?? "")
    }
    private var startField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("From").font(.headline)
            TextField("For example, main elevator", text: $entrance)
                .accessibilityLabel("Start location")
        }
    }
    var body: some View {
        Group {
            if let completed {
                VStack(spacing: 22) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 48, weight: .medium)).foregroundStyle(Color.indoorTeal)
                        .frame(width: 100, height: 100).background(Color.indoorPeach.opacity(0.35), in: Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Color.indoorTeal).background(Color.indoorBackground, in: Circle())
                        }.accessibilityHidden(true)
                    Text("Route recorded").font(.largeTitle.bold())
                    Label("Saved on this iPhone", systemImage: "checkmark").font(.subheadline).foregroundStyle(Color.indoorTeal)
                    Text("\(completed.route.entrance.label) → \(completed.route.room.label)").font(.headline)
                    Text("Publish your recording to find it in search.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Done") { if let onFinished { onFinished() } else { dismiss() } }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    NavigationLink("Preview & publish") {
                        VolunteerReviewView(library: library, settings: settings, draft: completed.draft, route: completed.route)
                    }.font(.subheadline)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.indoorBackground)
            } else if stage == 0 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Record a route").font(.largeTitle.bold())
                            Text("Link two places in the same building.").foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 14) {
                            if building.isEmpty || room.isEmpty || editDestination {
                                Text("Building").font(.headline)
                                TextField("Building name", text: $building)
                                if !savedBuildings.isEmpty {
                                    Menu("Use saved building") {
                                        ForEach(savedBuildings, id: \.self) { name in Button(name) { building = name } }
                                    }
                                }
                                startField
                                Text("To").font(.headline)
                                TextField("Room or destination", text: $room)
                            } else {
                                HStack(alignment: .top) {
                                    Image(systemName: "mappin.circle.fill").font(.title2).foregroundStyle(Color.indoorTeal)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(room).font(.title3.bold())
                                        Text(building).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Edit") { editDestination = true }.font(.subheadline)
                                }
                            }
                            Divider()
                            if !editDestination && !building.isEmpty && !room.isEmpty { startField }
                            if !entrance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               entrance.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(room.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
                                Text("Choose different start and destination names.").font(.footnote)
                            }
                            DisclosureGroup("Optional details") {
                                TextField("Floor label (optional)", text: $floorLabel)
                                    .accessibilityIdentifier("Floor label (confirm from building signage)")
                            }
                        }.textFieldStyle(.roundedBorder).padding(20)
                            .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 24))
                        Button {
                            building = building.trimmingCharacters(in: .whitespacesAndNewlines)
                            room = room.trimmingCharacters(in: .whitespacesAndNewlines)
                            entrance = entrance.trimmingCharacters(in: .whitespacesAndNewlines)
                            stage = 1; error = nil; capturedDraft = nil; scanning = true
                        } label: {
                            Text("Start recording").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(!SpatialSession.supportsLiDAR || !labelsValid)
                        Text(SpatialSession.supportsLiDAR ? "Stand at your starting landmark, then record your walk." : "Recording requires a LiDAR-equipped iPhone or iPad.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(24)
                }.scrollDismissesKeyboard(.interactively).background(Color.indoorBackground)

            }
        }.navigationTitle(completed == nil ? "Trace route" : "Saved").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $scanning) { captureScreen }
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
                        instruction: stage == 1 ? "Gently look around, then tap Start here." : stage == 2 ? "Keep the camera ahead; finish when you reach the room." : "Your path and 3D map will be saved together.",
                        active: camera.running && stage < 3
                    )
                    if !camera.running && capturedDraft == nil {
                        Text(camera.error ?? "Camera paused. Restart the recording.").font(.callout)
                        Button("Restart recording") {
                            stage = 1; error = nil
                            Task { await camera.start(); location.start() }
                        }.buttonStyle(.borderedProminent)
                    } else if camera.position == nil && capturedDraft == nil {
                        Text("Hold still and point at a textured wall until tracking returns.").font(.headline)
                    } else if stage == 1 {
                        Button("Start here") {
                            camera.mark(entrance); entranceFix = location.entranceFix; location.stop(); stage = 2
                            settings.speak("Start confirmed. Walk the known hallway to \(room).")
                        }.buttonStyle(.borderedProminent).disabled(camera.meshCount == 0)
                    } else if stage == 2 {
                        Button("Mark shared landmark") { markingLandmark = true }.font(.footnote)
                        Button("Finish recording") {
                            camera.mark(room); stage = 3
                            settings.speak("Recording complete. Tap Save route.", force: true)
                        }
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
                        if capturedDraft == nil && !camera.canSave { Text("Look around the doorway for more detail.").font(.caption) }
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.controlSize(.large).tint(.indoorTeal)
            }
        }.overlay { VoiceEdgeGlow(active: confirmationVoice.listening) }.interactiveDismissDisabled(saving)
            .task { location.start(); await camera.start() }
            .alert("Shared landmark", isPresented: $markingLandmark) {
                TextField("Name on the sign", text: $sharedLandmark)
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
                completed = IndoorJourneyTarget(route: route, draft: draft, library: library)
                scanning = false
                settings.speak("Route saved. Ready to publish.")
            } catch { self.error = error.localizedDescription + (capturedDraft == nil ? "" : " Scan kept. Tap Save route to retry.") }
            saving = false
        }
    }
}
