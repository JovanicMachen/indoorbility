import SwiftUI
import Combine
import ARKit
import IndoorbilityCore

@MainActor final class HallwayNavigationModel: ObservableObject {
    @Published private(set) var follower: HallwayFollower
    @Published var error: String?
    @Published private(set) var rawPosition: SpatialPoint?
    @Published private(set) var running = false
    @Published private(set) var recoveryFirst: UUID?
    let camera = SpatialSession()
    var route: HallwayRoute { follower.route }
    let reviewedRoute: HallwayRoute
    let draft: ScanDraft
    let floorLabel: String?
    let library: ScanLibrary
    let routeStore: AppStore
    let settings: AppStore
    @Published var surfaceWarning: String?
    private var surfaceWarningUntil: TimeInterval = 0
    @Published var voiceResponse: String?
    @Published private(set) var pendingDestination: ScanLandmark?
    private var destinationConfirmation = DestinationConfirmation()
    var listeningForCommand = false
    let agent = NavigationAgent()
    private var ledger = AgentExecutionLedger()
    private var agentFingerprint = ""
    private var agentUtterance = ""
    private var resolvedAgentDestinations = Set<UUID>()
    private var calculatedAgentDestination: UUID?
    private var observationAllowed = false
    private var readingScene = false
    private var shoppingMemory: AgentTaskMemory {
        get { (UserDefaults.standard.data(forKey: "agentShoppingTask").flatMap { try? JSONDecoder().decode(AgentTaskMemory.self, from: $0) }) ?? AgentTaskMemory() }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "agentShoppingTask") } }
    }
    private var firstObservation: SpatialPoint?
    private var lastUpdate: TimeInterval = 0
    private var lastBeacon: TimeInterval = 0
    private var lastSpoken: TimeInterval = 0
    private var announced = ""
    private var delivery = GuidanceDelivery()
    var guidance: GuidanceMessage { LiveGuidance.message(follower, feet: UserDefaults.standard.bool(forKey: "guidanceFeet")) }
    func deliverGuidance() {
        guard !camera.floorHazard, ProcessInfo.processInfo.systemUptime >= surfaceWarningUntil else { return }
        let value = guidance
        guard delivery.consume(value, listening: listeningForCommand, now: ProcessInfo.processInfo.systemUptime, repeatReliable: running && fresh && follower.stable && !needsAlignment && follower.state == .guiding) else { return }
        if value.cue == .turn {
            deliveredTurnTime = ProcessInfo.processInfo.systemUptime; deliveredTurnProgress = follower.progress
        }
        settings.speak(value.text, priority: value.cue == .attention ? .safety : .direction, positionTime: lastPoseWall > 0 ? lastPoseWall : nil)
        settings.cue(value.cue ?? .approach, instruction: value.text)
    }
    private var epoch = UUID()
    private var handoff = EntranceHandoff(preparingIndoor: true)
    private var entranceRecognition: EntranceRecognition
    private var roomRecognition: EntranceRecognition
    private var usingSavedMap = true
    private var automaticStartAllowed = true
    private var watchdog: Task<Void, Never>?
    private var lastPoseWall: TimeInterval = 0
    @Published private(set) var needsAlignment = false
    @Published private(set) var mapConfidence = MapPositionConfidence.unverified
    @Published private(set) var geometryEvidence = "Not assessed"
    private var surfaceReference: SurfaceReference?
    private var comparisonBusy = false
    private var lastComparison = 0.0
    private var surfaceAgreement = SurfaceAgreementFilter()
    private(set) var worldMapLoadMS = 0.0
    private(set) var recoveryAttempts = 0
    private(set) var recoverySuccesses = 0
    private(set) var recoveryFailures = 0
    private(set) var recoverySeconds: Double?
    private var recoveryStarted: Double?
    private(set) var confirmedLandmarkError: Float?
    private(set) var deliveredTurnTime: Double?
    private(set) var deliveredTurnProgress: Float?
    var diagnosticLines: [String] {
        ["Map confidence: " + mapConfidence.rawValue,
         "Selected segment: \(follower.selectedSegment); next maneuver: \(follower.nextMeasuredTurn?.direction ?? "destination")",
         "Camera heading (map radians): \(follower.cameraHeading.map(String.init(describing:)) ?? "unavailable")",
         "Measured movement (map radians): \(follower.movementHeading.map(String.init(describing:)) ?? "unavailable")",
         "Measured surface comparison: " + geometryEvidence,
         String(format: "World map load: %.1f ms", worldMapLoadMS),
         "Recovery confirmations / successes / rejected: \(recoveryAttempts) / \(recoverySuccesses) / \(recoveryFailures)",
         "Last recovery duration: " + (recoverySeconds.map { String(format: "%.2f s", $0) } ?? "Not measured"),
         "Confirmed landmark residual: " + (confirmedLandmarkError.map { String(format: "%.2f m (manual confirmation)", $0) } ?? "Not measured"),
         "Last turn request uptime: " + (deliveredTurnTime.map { String(format: "%.3f s", $0) } ?? "None"),
         "Last turn route progress: " + (deliveredTurnProgress.map { String(format: "%.2f m", $0) } ?? "None"),
         String(format: "Room OCR processing: %.1f ms; expired: %d", roomRecognition.processingMS, roomRecognition.expiredResults)]
    }
    private func losePosition(_ message: String = "Position uncertain. Point at a known sign, then confirm the landmark.") {
        if follower.localized {
            // GPS mode: never lock guidance; it re-acquires on the saved map by itself.
            follower.update(position: nil, heading: nil, time: ProcessInfo.processInfo.systemUptime, trackingNormal: false)
            settings.directionalCue(nil); return
        }
        if mapConfidence != .uncertain { recoveryStarted = ProcessInfo.processInfo.systemUptime }
        mapConfidence = .uncertain; needsAlignment = true
        surfaceAgreement = SurfaceAgreementFilter()
        follower.invalidate(message); delivery.reset()
        settings.stopSpeech(); settings.directionalCue(nil)
    }
    private func compareSurfaces(_ observation: DepthObservation) {
        guard !follower.localized, !comparisonBusy, let reference = surfaceReference, mapConfidence == .confirmed,
              fresh, follower.stable, follower.state == .guiding, observation.coverage >= 0.65,
              observation.timestamp-lastComparison >= 0.5 else { return }
        lastComparison = observation.timestamp; comparisonBusy = true
        let alignment = follower.alignment, token = epoch
        let points = observation.points
        Task {
            let result = await Task.detached(priority: .utility) {
                let step = max(1, points.count/96)
                let sampled = stride(from: 0, to: points.count, by: step).prefix(96).map {
                    alignment.apply(SpatialPoint(x: points[$0].x, y: points[$0].y, z: points[$0].z))
                }
                return reference.compare(points: sampled)
            }.value
            comparisonBusy = false
            guard token == epoch, running, mapConfidence == .confirmed,
                  ProcessInfo.processInfo.systemUptime-observation.timestamp < 0.5 else { return }
            geometryEvidence = result.rawValue
            if surfaceAgreement.update(result, time: observation.timestamp) {
                losePosition("The surroundings may have changed. Confirm a known landmark.")
                camera.showRoute(route.path, alignment: follower.alignment, verified: false)
                settings.speak(follower.instruction, priority: .safety)
            }
        }
    }
    func checkConfirmedLandmark(_ id: UUID) {
        guard fresh, follower.stable, let live = rawPosition,
              let mark = draft.landmarks.first(where: { $0.id == id }) else { return }
        confirmedLandmarkError = follower.alignment.apply(live).distance(to: mark.position)
        if confirmedLandmarkError! > 1.2 {
            losePosition("That landmark does not match. Confirm two landmarks to recover.")
        }
    }
    private var fresh: Bool { ProcessInfo.processInfo.systemUptime - lastPoseWall < 0.8 }
    private var sourceCheckTime: TimeInterval = -.infinity
    private var sourceAvailable = false
    var available: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - sourceCheckTime >= 1 {
            sourceAvailable = library.sourceRoutesAvailable(reviewedRoute)
            sourceCheckTime = now
        }
        return sourceAvailable && (try? Router.plan(in: follower.building, from: "entrance", to: "room", avoidStairs: settings.preferences.avoidStairs, excluding: routeStore.blockedEdges)) != nil
    }
    init(route: HallwayRoute, draft: ScanDraft, library: ScanLibrary, settings: AppStore) throws {
        try route.validate(for: draft)
        entranceRecognition = EntranceRecognition(label: route.entrance.label)
        roomRecognition = EntranceRecognition(label: route.room.label, distinctiveEntrance: false)
        self.reviewedRoute = route; self.draft = draft; self.library = library; self.settings = settings
        if let data = try? Data(contentsOf: library.directory(draft.id).appending(path: "room-metadata.json")),
           let metadata = try? JSONDecoder().decode(VerifiedRoomMetadata.self, from: data),
           metadata.buildingID == draft.id, metadata.roomID == route.room.id, !metadata.floorLabel.isEmpty {
            floorLabel = metadata.floorLabel
        } else { floorLabel = nil }
        routeStore = try library.navigationStore(route)
        routeStore.speechSuspended = true
        routeStore.change { try $0.setPreferences(settings.preferences) }
        follower = HallwayFollower(route: route)
        entranceRecognition.currentFrame = { [weak camera] in camera?.scene.session.currentFrame }
        roomRecognition.currentFrame = { [weak camera] in camera?.scene.session.currentFrame }
        camera.onMeasuredDepth = { [weak self] in self?.compareSurfaces($0) }
        camera.onFrame = { [weak self] frame in
            guard let self else { return }
            guard !self.readingScene else { return }
            if self.follower.state == .nearRoom || (self.follower.state == .guiding && self.follower.remaining < 3) { self.roomRecognition.process(frame) }
            else if self.follower.state != .guiding { self.entranceRecognition.process(frame) }
        }
        // Posture affects camera sensing, not the validity of an aligned route.
        // Do not send phone-position coaching through the hazard pause channel.
        camera.onPostureAlert = { _ in }
        camera.onSafetyAlert = { [weak self] text in
            guard let self, !self.listeningForCommand else { return }
            self.surfaceWarning = text; self.surfaceWarningUntil = ProcessInfo.processInfo.systemUptime + 6
            self.settings.directionalCue(nil)
            self.settings.speak(text, priority: .safety); self.settings.cue(.attention)
        }
        camera.onObjectAlert = { [weak self] text in
            guard let self, !self.listeningForCommand, !self.agent.busy, ProcessInfo.processInfo.systemUptime >= self.surfaceWarningUntil else { return }
            self.surfaceWarning = text; self.surfaceWarningUntil = ProcessInfo.processInfo.systemUptime + 6
            self.settings.directionalCue(nil); self.settings.speak(text, priority: .safety); self.settings.cue(.attention)
        }
        camera.onSurfaceAlert = { [weak self] distance in
            guard let self, ProcessInfo.processInfo.systemUptime >= self.surfaceWarningUntil, UserDefaults.standard.bool(forKey: "depthAdvisories"), !self.listeningForCommand, !self.agent.busy else { return }
            let feet = UserDefaults.standard.bool(forKey: "guidanceFeet")
            let value = distance * (feet ? 3.28084 : 1)
            let text = "Possible surface ahead, approximately " + String(format: "%.1f", value) + (feet ? " feet" : " meters") + ". Pause and check your surroundings."
            self.surfaceWarning = text; self.surfaceWarningUntil = ProcessInfo.processInfo.systemUptime + 5; self.settings.speak(text, priority: .safety); self.settings.cue(.attention)

        }
        camera.onPose = { [weak self] position, heading, time, normal in self?.receive(position, heading: heading, time: time, normal: normal) }
    }
    func start(useSavedMap: Bool = true) async {
        guard !running else { return }
        let resume = camera.canResume && usingSavedMap == useSavedMap
        pause(); let token = UUID(); epoch = token
        if !resume { follower = HallwayFollower(route: route) }
        announced = ""; error = nil; lastUpdate = 0; needsAlignment = true
        mapConfidence = .unverified; recoveryStarted = ProcessInfo.processInfo.systemUptime
        usingSavedMap = useSavedMap; handoff = EntranceHandoff(preparingIndoor: true); entranceRecognition.reset(); roomRecognition.reset(); automaticStartAllowed = useSavedMap
        guard ARWorldTrackingConfiguration.isSupported else { error = "Live guidance requires a supported physical iPhone or iPad."; return }
        do {
            if resume { camera.resumeTracking() }
            else {
                let directory = library.directory(draft.id), started = ProcessInfo.processInfo.systemUptime
                let map = try await Task.detached(priority: .userInitiated) { () throws -> ARWorldMap? in
                    guard useSavedMap else { return nil }
                    let data = try Data(contentsOf: directory.appending(path: "world.arworldmap"))
                    guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                        throw MapError.invalid("Saved positioning map could not be read.")
                    }
                    return map
                }.value
                worldMapLoadMS = (ProcessInfo.processInfo.systemUptime-started)*1000
                guard epoch == token, !Task.isCancelled else { return }
                await camera.start(map: map, navigation: true)
                Task {
                    let reference = await Task.detached(priority: .utility) { () -> SurfaceReference? in
                        let url = directory.appending(path: "mesh.json")
                        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 80*1024*1024,
                              let data = try? Data(contentsOf: url),
                              let meshes = try? JSONDecoder().decode([MeshRecord].self, from: data) else { return nil }
                        var points: [SpatialPoint] = []
                        let total = meshes.reduce(0) { $0 + $1.vertices.count }, step = max(1, total/50000)
                        for mesh in meshes {
                            for i in stride(from: 0, to: mesh.vertices.count, by: step) {
                                points.append(mesh.vertices[i]); if points.count >= 50000 { break }
                            }
                            if points.count >= 50000 { break }
                        }
                        return SurfaceReference(points: points)
                    }.value
                    guard epoch == token else { return }
                    surfaceReference = reference; camera.compareSurfaces = reference != nil
                }
            }
            guard epoch == token else { return }
            running = camera.running
            lastPoseWall = ProcessInfo.processInfo.systemUptime
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    if self.running && !self.camera.running { self.running = false; self.losePosition() }
                    if self.running && !self.fresh && self.follower.stable && self.follower.localized {
                        // GPS mode re-acquires by itself once frames resume.
                        self.follower.update(position: nil, heading: nil, time: ProcessInfo.processInfo.systemUptime, trackingNormal: false)
                        self.rawPosition = nil; self.settings.directionalCue(nil)
                    } else if self.running && !self.fresh && self.follower.stable {
                        self.losePosition(); self.rawPosition = nil
                        self.camera.showRoute(self.route.path, alignment: self.follower.alignment, verified: false)
                        self.recoveryFirst = nil; self.firstObservation = nil
                        self.settings.stopSpeech(); self.settings.speak(self.follower.instruction, priority: .safety)
                    }
                }
            }
            if !running { error = camera.error ?? "Camera could not start." }
        } catch { self.error = error.localizedDescription }
    }
    func pause() {
        settings.stopSpeech(); delivery.reset()
        agent.cancel(); ledger.invalidate()
        watchdog?.cancel(); watchdog = nil
        epoch = UUID(); running = false; camera.stop(); rawPosition = nil
        recoveryFirst = nil; firstObservation = nil
        follower.invalidate("Guidance paused. Resume to locate yourself again.")
    }
    private func receive(_ p: SpatialPoint?, heading: Float?, time: TimeInterval, normal: Bool) {
        guard running else { return }
        if normal && time >= lastUpdate && time-lastUpdate < 0.05 { return }
        let began = ProcessInfo.processInfo.systemUptime
        defer { NavigationPerformance.shared.record("Indoor follower + guidance processing ms", (ProcessInfo.processInfo.systemUptime-began)*1000) }
        NavigationPerformance.shared.position("AR", captured: time)
        lastUpdate = time
        let now = ProcessInfo.processInfo.systemUptime
        guard time.isFinite, now >= time, now-time < 0.5 else {
            if mapConfidence != .uncertain { losePosition() }
            rawPosition = nil; return
        }
        lastPoseWall = time
        if lastPoseWall > surfaceWarningUntil { surfaceWarning = nil }
        rawPosition = normal ? p : nil
        if !normal || heading == nil { recoveryFirst = nil; firstObservation = nil }
        if usingSavedMap, camera.savedMapRelocalized, !follower.localized {
            // The saved 3D map matched: AR poses are now map coordinates. Navigate like GPS.
            follower.setLocalized(); delivery.reset()
            needsAlignment = false; mapConfidence = .confirmed; automaticStartAllowed = false
            if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
            routeStore.change { try $0.confirmCheckpoint("entrance"); try $0.selectDestination("room") }
            settings.speak("Found your position in \(draft.name). Guiding you to \(route.room.label).", force: true)
            settings.cue(.started)
        }
        let routeAvailable = available
        let previousState = follower.state
        follower.update(position: p, heading: heading, time: time, trackingNormal: normal, routeAvailable: routeAvailable)
        if previousState != follower.state && [.trackingLost, .offRoute, .blocked, .arrived].contains(follower.state) { settings.stopSpeech() }
        camera.showRoute(route.path, alignment: follower.alignment, verified: !camera.floorHazard && camera.postureIssue == nil && heading != nil && normal && !needsAlignment && follower.stable && [.guiding, .nearRoom].contains(follower.state))
        if follower.localized {
            if previousState != follower.state && follower.state == .arrived { recordArrival() }
        } else if [.trackingLost, .offRoute].contains(follower.state) && previousState != follower.state { losePosition(); handoff.resetEvidence(); entranceRecognition.reset(); roomRecognition.reset(); recoveryFirst = nil; firstObservation = nil }
        if automaticStartAllowed, routeAvailable, follower.state == .ready {
            let near = follower.position.map { $0.horizontalDistance(to: route.entrance.position) <= 1 && abs($0.y-route.entrance.position.y) < 0.6 } ?? false
            let state = handoff.update(distanceToBuilding: nil, horizontalAccuracy: nil, mapMatches: usingSavedMap && camera.savedMapRelocalized && !needsAlignment,
                entranceLabelMatches: entranceRecognition.matchedRecently, positionNearEntrance: near,
                trackingNormal: normal && follower.stable, headingAvailable: heading != nil, time: time)
            if state == .indoor {
                automaticStartAllowed = false
                confirmEntrance()
                if follower.state == .guiding { settings.speak("Entrance recognized in \(draft.name). Continuing to \(route.room.label).") }
            }
        }
        if ArrivalEvidence.canConfirm(state: follower.state, trackingStable: follower.stable, poseFresh: fresh,
                                      labelMatches: roomRecognition.matchedRecently, routeAvailable: routeAvailable) {
            confirmArrival()
        }
        if !camera.floorHazard && fresh && follower.stable && follower.state == .guiding && !needsAlignment && !listeningForCommand && !agent.busy && time >= surfaceWarningUntil {
            if time-lastBeacon >= 3 { lastBeacon = time; settings.directionalCue(camera.soundTarget(path: route.path, progress: follower.progress, alignment: follower.alignment)) }
        } else { settings.directionalCue(nil) }
        deliverGuidance()
        let canTick = !camera.floorHazard && camera.postureIssue == nil && fresh && follower.stable &&
            follower.state == .guiding && !needsAlignment && !listeningForCommand && !agent.busy && time >= surfaceWarningUntil
        let travelPoint = canTick ? follower.position.map { SIMD2(Double($0.x), Double($0.z)) } : nil
        settings.travelFeedback(position: travelPoint, context: "indoor")
    }

    func speechNotUnderstood() {
        listeningForCommand = false
        voiceResponse = VoiceCommandInput.notUnderstood
        settings.speak(VoiceCommandInput.notUnderstood)
    }
    func handleVoice(_ text: String) {
        settings.stopSpeech()
        do {
            let command = text.lowercased()
            if command.contains("room"), !BuildingQualifier.matches(text, building: draft.name) { throw MapError.invalid("That building does not match the active saved map. Confirm the building on Home before changing rooms.") }
            if ["what's ahead", "what is ahead", "what is in front", "what's in front", "read the sign"].contains(where: { command.contains($0) }) {
                observationAllowed = true
                let context = agentContext()
                Task {
                    let result = await executeAgent(AgentCall(callId: UUID().uuidString, tool: .describeCurrentView, expectedRevision: context.sessionRevision, sessionId: context.sessionId))
                    presentAgentResult(result)
                }
                return
            }
            if command.hasPrefix("add ") {
                let item = String(command.dropFirst(4)).components(separatedBy: " to my ").first ?? ""
                let context = agentContext()
                Task {
                    let result = await executeAgent(AgentCall(callId: UUID().uuidString, tool: .addShoppingItem, argument: item, expectedRevision: context.sessionRevision, sessionId: context.sessionId))
                    presentAgentResult(result)
                }
                return
            }
            if ["stop", "pause", "pause guidance", "stop guidance", "cancel"].contains(command.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pause(); ledger.invalidate()
                voiceResponse = "Guidance paused. Tap Resume camera to continue."; settings.speak(voiceResponse!, force: true); return
            }
            if command.contains("avoid stairs") {
                routeStore.setPreference(\.avoidStairs, true); settings.setPreference(\.avoidStairs, true)
            }
            if command.contains("room"), command.contains("avoid stairs") {
                let target = try LiveHallwayCommand.destination(in: text, landmarks: draft.landmarks)
                _ = try candidateRoute(target)
                proposeDestination(target)
                return
            }
            if command.contains("repeat") {
                voiceResponse = guidance.text
            } else if command.contains("where am i") {
                voiceResponse = fresh && follower.stable && [.guiding, .nearRoom].contains(follower.state)
                    ? "On the mapped hallway in \(draft.name). \(Int(follower.remaining.rounded())) metres remain to \(route.room.label)."
                    : "Your position is uncertain. Confirm a known landmark."
            } else if command.contains("avoid stairs") {
                routeStore.setPreference(\.avoidStairs, true)
                settings.setPreference(\.avoidStairs, true)
                voiceResponse = !route.hasLevelChange ? "Avoid stairs is on. This route uses the reviewed step-free hallway." : "Avoid stairs is on. This route includes a level change."
            } else if command.contains("another way") {
                voiceResponse = "No alternative hallway has been verified. Your route is unchanged."
            } else {
                guard fresh, running, available, !needsAlignment else { throw MapError.invalid("Reliable guidance is unavailable. Confirm your position before changing rooms.") }
                let target = try LiveHallwayCommand.destination(in: text, landmarks: draft.landmarks)
                _ = try candidateRoute(target)
                proposeDestination(target)
                return
            }
        } catch { voiceResponse = error.localizedDescription }
        settings.speak(voiceResponse ?? "Nothing changed.", force: true)
    }
    func submitVoice(_ text: String) {
        let reply = text.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if ["stop talking", "mute", "mute all sound"].contains(reply) { settings.allSoundMuted = true; voiceResponse = "All app sound muted."; return }
        if ["turn the voice back on", "unmute"].contains(reply) { settings.allSoundMuted = false; settings.setPreference(\.speech, true); settings.speak(guidance.text); return }
        if reply.contains("how much farther") { voiceResponse = follower.stable && follower.state == .guiding ? LiveGuidance.distance(follower.remaining, feet: UserDefaults.standard.bool(forKey: "guidanceFeet")) + " remain on the mapped route." : "Position uncertain. Confirm a known landmark."; settings.speak(voiceResponse!); return }
        if ["yes", "yes please", "correct"].contains(reply) { confirmDestination(); return }
        if ["no", "no thanks", "cancel"].contains(reply), pendingDestination != nil { declineDestination(); return }
        declineDestination(speak: false)
        if reply.contains("wrong building") {
            follower.invalidate("Position needs checking. Confirm the building and a known entrance landmark.")
            camera.showRoute(route.path, alignment: follower.alignment, verified: false)
            ledger.invalidate(); voiceResponse = follower.instruction; settings.speak(follower.instruction, force: true); return
        }
        agent.submit(text, model: self)
    }
    private func proposeDestination(_ target: ScanLandmark, speak: Bool = true) {
        pendingDestination = target; destinationConfirmation.propose(target.id, now: ProcessInfo.processInfo.systemUptime)
        voiceResponse = "Go to \(target.label) in \(draft.name)? Say yes or no."
        if speak { settings.speak(voiceResponse!, force: true) }
    }
    func declineDestination(speak: Bool = true) {
        agent.cancel()
        pendingDestination = nil; destinationConfirmation.cancel()
        if speak { voiceResponse = "Destination unchanged. Tell me another room."; settings.speak(voiceResponse!, force: true) }
    }
    func confirmDestination() {
        agent.cancel()
        guard let target = pendingDestination, destinationConfirmation.accept(target.id, now: ProcessInfo.processInfo.systemUptime) != nil else {
            pendingDestination = nil; voiceResponse = "Choose a destination again; there is no current confirmation."; settings.speak(voiceResponse!, force: true); return
        }
        pendingDestination = nil
        do {
            let originalSession = ObjectIdentifier(camera.scene.session)
            try activateAgentDestination(target)
            agent.recordDeviceEvent("Confirmed route change; AR session preserved: \(originalSession == ObjectIdentifier(camera.scene.session)); speech generation: \(settings.activeSpeechGeneration)")
            voiceResponse = follower.instruction; settings.speak(follower.instruction, force: true)
        } catch { voiceResponse = error.localizedDescription; settings.speak(error.localizedDescription, force: true) }
    }
    func confirmEntrance() {
        do {
            guard fresh, !needsAlignment, available else { throw MapError.invalid("Confirm two landmarks if manually aligning. This hallway must be open. Resolve its report before starting.") }
            try follower.confirmEntrance()
            mapConfidence = .confirmed
            if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
            automaticStartAllowed = false
            routeStore.change { try $0.confirmCheckpoint("entrance"); try $0.selectDestination("room") }
            settings.speak("Starting at \(route.entrance.label). Follow the reviewed hallway to \(route.room.label).")
        } catch { self.error = error.localizedDescription }
    }
    var canConfirmSavedLandmark: Bool {
        usingSavedMap && camera.savedMapRelocalized && (mapConfidence == .savedMap || follower.localized)
    }
    func recordRecovery(_ id: UUID) {
        do {
            recoveryAttempts += 1
            guard fresh, available, follower.stable, let live = rawPosition,
                  let saved = draft.landmarks.first(where: { $0.id == id }) else { throw MapError.invalid("Wait for stable tracking at the selected landmark.") }
            if canConfirmSavedLandmark {
                try follower.recoverInSavedMap(livePosition: live, landmark: saved.position, relocalized: true)
                confirmedLandmarkError = live.distance(to: saved.position)
                needsAlignment = false; mapConfidence = .confirmed; automaticStartAllowed = false
                recoveryFirst = nil; firstObservation = nil; recoverySuccesses += 1
                if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
                settings.speak("Position confirmed. " + guidance.text)
                return
            }
            if let first = recoveryFirst, let observed = firstObservation,
               let savedFirst = draft.landmarks.first(where: { $0.id == first }) {
                guard first != id else { throw MapError.invalid("Choose a different second landmark, at least two metres away.") }
                let transform = try ScanAlignment.fit(liveA: observed, liveB: live, savedA: savedFirst.position, savedB: saved.position)
                try follower.recover(using: transform, livePosition: live)
                needsAlignment = false; mapConfidence = .confirmed
                surfaceAgreement = SurfaceAgreementFilter(); recoverySuccesses += 1
                if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
                recoveryFirst = nil; firstObservation = nil
                settings.speak("Position recovered. \(follower.remaining.formatted(.number.precision(.fractionLength(0)))) metres along the mapped route remain.")
            } else { recoveryFirst = id; firstObservation = live; settings.speak("\(saved.label) confirmed. Go to a second known mark and confirm it.") }
        } catch { recoveryFailures += 1; self.error = error.localizedDescription }
    }
    func confirmArrival() {
        do {
            guard fresh, available, mapConfidence == .confirmed, !needsAlignment else { throw MapError.invalid("Confirm your position before confirming arrival.") }
            try follower.confirmArrival()
            recordArrival()
        } catch { self.error = error.localizedDescription }
    }
    private func recordArrival() {
        if route.room.id == reviewedRoute.room.id {
            try? JourneyLibrary().remember(reviewedRoute, building: draft.name, arrived: true)
            routeStore.change { try $0.confirmCheckpoint("room") }
        }
        settings.directionalCue(nil)
        delivery.reset(); deliverGuidance()
    }
}

struct HallwaySetupView: View {
    @ObservedObject var library: ScanLibrary
    @ObservedObject var settings: AppStore
    let draft: ScanDraft
    @State private var entrance: UUID?
    @State private var room: UUID?
    @State private var reviewed = false
    @State private var route: HallwayRoute?
    @State private var error: String?
    @State private var navigating = false
    var body: some View {
        Form {
            if let route {
                Section {
                    Label(route.room.label, systemImage: "door.left.hand.closed").font(.title2.bold())
                    Text("From \(route.entrance.label) · \(route.distance.formatted(.number.precision(.fractionLength(1)))) m measured trace")
                    Button(library.visitorReady(route) ? "Go" : "Test draft", systemImage: "location.north.fill") { navigating = true }
                        .buttonStyle(.borderedProminent).frame(minHeight: 48).accessibilityIdentifier("startHallway")
                }
                Section { TraceView(samples: route.path.map { ScanSample(position: $0, segment: 0) }, landmarks: [route.entrance, route.room]) }
                if library.requiresVolunteerReview(draft.id) {
                    Section { NavigationLink("Preview & publish") { VolunteerReviewView(library: library, settings: settings, draft: draft, route: route) } }
                }
                Section { Button("Review or replace route") { self.route = nil; reviewed = false } }
            } else {
                Section {
                    Text("Map one hallway").font(.title2.bold())
                    Text("Choose the entrance and room you marked while scanning. The route follows the recorded walking trace between them.")
                }
                Section("Landmarks") {
                    Picker("Entrance", selection: $entrance) {
                        Text("Choose entrance").tag(nil as UUID?)
                        ForEach(draft.landmarks) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Picker("Room", selection: $room) {
                        Text("Choose room").tag(nil as UUID?)
                        ForEach(draft.landmarks) { Text($0.label).tag(Optional($0.id)) }
                    }
                    if draft.landmarks.count < 2 { Text("Rescan and mark the entrance and labeled room while standing beside each. Keep the phone at the same height.") }
                }
                Section("Review the path") {
                    TraceView(samples: draft.samples, landmarks: draft.landmarks)
                    Toggle("I walked this entire path and confirmed it is a clear, step-free hallway on one floor", isOn: $reviewed)
                    Text("Use one continuous entrance-to-room walk. Do not include exploration loops, shortcuts, stairs or gaps. Review the trace before saving.").font(.footnote)
                    Button("Save hallway route") {
                        do {
                            guard let entrance, let room else { return }
                            let route = try HallwayRoute.make(draft: draft, entranceID: entrance, roomID: room, reviewed: reviewed, id: try library.hallway(draft)?.id ?? UUID())
                            try library.saveHallway(route, draft: draft); self.route = route
                        } catch { self.error = error.localizedDescription }
                    }.disabled(!reviewed || entrance == nil || room == nil || entrance == room)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(draft.name).navigationBarTitleDisplayMode(.inline)
            .task { do { route = try library.hallway(draft) } catch { self.error = error.localizedDescription } }
            .fullScreenCover(isPresented: $navigating) {
                if let route { HallwayLaunchView(route: route, draft: draft, library: library, settings: settings) }
            }
    }
}

struct HallwayLaunchView: View {
    let route: HallwayRoute
    let draft: ScanDraft
    let library: ScanLibrary
    let settings: AppStore
    var approachDistance: Double? = nil
    @State private var model: HallwayNavigationModel?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let model { HallwayGuidanceView(model: model) }
            else { VStack(spacing: 20) { Text(error ?? "Opening route…"); Button("Close") { dismiss() } } }
        }.task {
            guard model == nil else { return }
            do { model = try HallwayNavigationModel(route: route, draft: draft, library: library, settings: settings) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct HallwayGuidanceView: View {
    @ObservedObject var model: HallwayNavigationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var voice = VoiceCommandInput()
    @State private var map = false
    @State private var recovery = false
    @State private var report = false
    @State private var mark: UUID?
    @State private var timeline = false
    @State private var diagnostics = false
    @State private var accessibility = false
    @AppStorage("guidanceMuted") private var muted = false
    @AppStorage("agentDeveloperMode") private var developerMode = false
    var body: some View {
        let _ = NavigationPerformance.shared.bodyEvaluated("Indoor navigation")
        ZStack {
            Color.black.ignoresSafeArea()
            SpatialCamera(session: model.camera).ignoresSafeArea().accessibilityHidden(true)
            if map {
                Color.indoorBackground.ignoresSafeArea()
                TraceView(samples: model.route.path.map { ScanSample(position: $0, segment: 0) },
                          landmarks: [model.route.entrance, model.route.room], position: model.needsAlignment ? nil : model.follower.position,
                          nextTurn: model.follower.nextMeasuredTurn.map { model.route.path[$0.index] },
                          cameraHeading: developerMode ? model.follower.cameraHeading : nil,
                          movementHeading: developerMode ? model.follower.movementHeading : nil,
                          selectedSegment: developerMode ? model.follower.selectedSegment : nil).padding()

            }
            VStack {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 46, height: 46)
                            .background(Color.indoorCard, in: Circle())
                    }.accessibilityLabel("End navigation")
                    Spacer()
                    Text(model.route.room.label).font(.subheadline.bold()).lineLimit(1)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                    Spacer()
                    navigationOptions.background(.regularMaterial, in: Circle())
                }.foregroundStyle(Color.indoorInk).padding(.horizontal, 16)
                if map { Text("Fixed map orientation").font(.caption).padding(6).background(.regularMaterial, in: Capsule()) }
                if !map && guidanceActive { DirectionBadge(instruction: model.guidance.text, reliable: guidanceActive) }
                if developerMode && map {
                    Text("Segment \(model.follower.selectedSegment) · Next: \(model.follower.nextMeasuredTurn?.direction ?? "destination")\nOrange: camera · Blue: movement · Green: selected segment")
                        .font(.caption2).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(guidanceActive ? "Indoor guidance" : status).font(.caption).foregroundStyle(.secondary)
                    if !map, let posture = model.camera.postureIssue {
                        Text(posture).font(.caption).foregroundStyle(.secondary)
                    }
                    if let warning = model.surfaceWarning { Label(warning, systemImage: "exclamationmark.triangle.fill").font(.headline)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.indoorPeach.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("liveSurfaceWarning") }
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: guidanceActive ? "location.north.fill" : "location.slash")
                            .font(.title2).foregroundStyle(Color.indoorTeal)
                            .frame(width: 28, height: 32)
                            .background(Color.indoorPeach.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                        Text(model.guidance.primary ?? model.guidance.text).font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("liveInstruction")
                        if let detail = model.guidance.secondary { Text(detail).font(.subheadline) }
                        }
                    }
                    if guidanceActive {
                        Text(LiveGuidance.distance(model.follower.remaining, feet: UserDefaults.standard.bool(forKey: "guidanceFeet")) + " remaining").foregroundStyle(.secondary)
                    }
                    if !model.running {
                        Button("Resume camera") { Task { await model.start() } }.buttonStyle(.borderedProminent)
                    } else if model.follower.localized && [.trackingLost, .offRoute, .locating].contains(model.follower.state) {
                        Text(model.follower.instruction).font(.subheadline)
                    } else if model.needsAlignment {
                        Text("Stand where you started recording and slowly look around so the camera can match your saved 3D map.").font(.subheadline)
                        Button("Match manually at a landmark") { recovery = true }.buttonStyle(.bordered)
                    } else if [.trackingLost, .offRoute].contains(model.follower.state) {
                        Button("Recover at a landmark") { recovery = true }.buttonStyle(.borderedProminent)
                    } else if model.follower.state == .ready && !model.needsAlignment {
                        Button("I’m at \(model.route.entrance.label)") { model.confirmEntrance() }.buttonStyle(.borderedProminent)
                            .disabled(!model.follower.stable)
                    } else if model.follower.state == .nearRoom {
                        Button("I confirm this is \(model.route.room.label)") { model.confirmArrival() }.buttonStyle(.borderedProminent)
                        Text("Confirm the room label before ending guidance.").font(.caption)
                    } else if model.follower.state == .arrived {
                        Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                    }
                    if let pending = model.pendingDestination {
                        Text("Go to \(pending.label)?").font(.headline)
                        HStack { Button("No") { model.declineDestination() }.buttonStyle(.bordered); Spacer(); Button("Yes, change destination") { model.confirmDestination() }.buttonStyle(.borderedProminent) }
                    }
                    AgentActivityView(agent: model.agent)
                    if voice.busy || model.voiceResponse != nil {
                        Text(voice.busy ? voice.status : model.voiceResponse ?? "")
                            .font(.callout).accessibilityIdentifier("liveVoiceResponse")
                    }
                    if guidanceActive {
                        Button("Repeat guidance") { model.settings.speak(model.guidance.text, force: true) }
                            .font(.subheadline).frame(minHeight: 44)
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }.scrollBounceBehavior(.basedOnSize)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: model.pendingDestination != nil ? 300 : 230)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 28))
                    .shadow(color: Color.indoorTeal.opacity(0.12), radius: 16, y: 5).padding(.horizontal, 16)
                HStack(alignment: .top) {
                    roundControl("Accessibility", symbol: "accessibility") { accessibility = true }
                    Spacer(minLength: 8)
                    navigationMicrophone
                    Spacer(minLength: 8)
                    roundControl(map ? "Camera" : "Map", symbol: map ? "camera" : "map") { map.toggle() }
                }.padding(.horizontal, 28).padding(.top, 8).padding(.bottom, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 16)


            }
        }.swipeLeftToGoBack { dismiss() }
            .overlay { VoiceEdgeGlow(active: voice.listening) }.task { await model.start() }
            .onChange(of: model.follower.state) { _, state in
                if [.trackingLost, .offRoute, .blocked].contains(state) {
                    model.agent.cancel()
                    if voice.busy {
                        voice.cancel(); model.listeningForCommand = false
                        model.settings.speak(model.guidance.text, force: true)
                    }
                }
            }
            .onChange(of: voice.busy) { _, busy in
                model.listeningForCommand = busy
                if !busy && !voice.status.hasPrefix("Heard:") { model.voiceResponse = voice.status }
            }
            .onDisappear { voice.cancel(); model.listeningForCommand = false; model.pause() }
            .onChange(of: phase) { _, value in if value == .background { voice.cancel(); model.listeningForCommand = false; model.pause() } }
            .sheet(isPresented: $report) { ReportView(store: model.routeStore) }
            .sheet(isPresented: $accessibility) { NavigationAccessibilitySheet(store: model.settings) }
            .sheet(isPresented: $diagnostics) { SensorDiagnosticsView(camera: model.camera, navigationDetails: {
                ["Navigation state: " + model.follower.state.rawValue,
                 "Verified route progress: " + (model.follower.stable && model.follower.state == .guiding ? String(format: "%.2f m", model.follower.progress) : "Unavailable"),
                 "Last requested speech: " + model.settings.lastNarration,
                 "Last played cue: " + model.settings.audio.lastCue] + model.diagnosticLines
            }) }
            .sheet(isPresented: $timeline) { NavigationStack { AgentTimelineView(agent: model.agent) } }
            .sheet(isPresented: $recovery) { recoverySheet }
            .alert("Check your position", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
    private var navigationMicrophone: some View {
        HoldToTalk(voice: voice, before: {
                        model.agent.cancel(); model.settings.stopSpeech(); model.listeningForCommand = true
                    }, onUnrecognized: model.speechNotUnderstood, haptics: model.settings.preferences.haptics, diameter: 48, result: { text in model.listeningForCommand = false; model.submitVoice(text) })
    }
    private var guidanceActive: Bool {
        !model.camera.floorHazard && model.running && model.follower.stable && !model.needsAlignment && [.guiding, .nearRoom].contains(model.follower.state)
    }
    private func roundControl(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title3).frame(width: 44, height: 44)
                    .background(Color.indoorCard, in: Circle())
                    .shadow(color: Color.indoorTeal.opacity(0.12), radius: 10, y: 4)
                Text(title).font(.caption).fixedSize(horizontal: false, vertical: true)
            }.frame(minWidth: 76).foregroundStyle(Color.indoorTeal)
        }.buttonStyle(.plain)
    }
    private var navigationOptions: some View {
        Menu {
            Button("Repeat directions", systemImage: "arrow.clockwise") { model.settings.speak(model.guidance.text, force: true) }
            Button(muted ? "Unmute" : "Mute", systemImage: muted ? "speaker.wave.2" : "speaker.slash") {
                model.settings.allSoundMuted.toggle()
                if !model.settings.allSoundMuted { model.settings.speak(model.guidance.text) }
            }
            Button("Accessibility", systemImage: "accessibility") { accessibility = true }
            Button("What’s ahead?") { model.agent.submit("What is in front of me?", model: model) }
            Button("Read a sign") { model.submitVoice("Read the sign in front of me") }
            Button("Recover at a landmark") { recovery = true }
            Button("Report a closure") { report = true }
            Button("Pause guidance") { model.pause() }
            ShareLink("Ask someone for help", item: "I need help in \(model.draft.name), on the mapped path from \(model.route.entrance.label) to \(model.route.room.label). Please help me confirm my current position.")
            if developerMode {
                Button("Agent timeline") { timeline = true }
                Button("Sensor diagnostics") { diagnostics = true }
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }.accessibilityLabel("Navigation options")
    }
    private var status: String {
        if !model.running { return "Camera paused" }
        if model.follower.state == .blocked { return "Hallway closed" }
        if model.follower.state == .offRoute { return model.follower.localized ? "Off the path · head back to it" : "Off route · guidance paused" }
        if model.follower.state == .arrived { return "Arrived" }
        if guidanceActive { return "Indoor guidance active" }
        if model.follower.localized { return "Finding your position" }
        return model.needsAlignment ? "Matching your saved 3D map…" : "Confirming position · guidance paused"
    }
    private var recoverySheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.canConfirmSavedLandmark ? "Confirm your location" : "Match two landmarks").font(.headline)
                    Text(model.canConfirmSavedLandmark ? "The saved map matched. Choose the landmark beside you." : "Confirm two saved places, at least two metres apart. Hold the phone at the recording height.")
                    if let id = model.recoveryFirst, let first = model.draft.landmarks.first(where: { $0.id == id }) { Text("First mark: \(first.label)") }
                    Picker("Current landmark", selection: $mark) {
                        Text("Choose landmark").tag(nil as UUID?)
                        ForEach(model.draft.landmarks) { Text($0.label).tag(Optional($0.id)) }
                    }
                    Button(model.canConfirmSavedLandmark ? "I’m here" : model.recoveryFirst == nil ? "Confirm first landmark" : "Confirm second landmark") {
                        if let mark {
                            model.recordRecovery(mark)
                            if model.follower.state == .guiding && model.recoveryFirst == nil { recovery = false }
                        }
                    }.disabled(mark == nil || !model.follower.stable)
                    if UserDefaults.standard.bool(forKey: "agentDeveloperMode") {
                        Button("Measure error at this confirmed landmark") { if let mark { model.checkConfirmedLandmark(mark) } }
                            .disabled(mark == nil || !model.follower.stable)
                        if let error = model.confirmedLandmarkError { Text(String(format: "Observed landmark residual: %.2f m", error)) }
                    }
                    Text(model.follower.stable ? "Camera tracking is stable." : "Wait for camera tracking to settle.").font(.footnote)
                    if let error = model.error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Restart tracking for manual alignment") { Task { await model.start(useSavedMap: false) } }
                    Text("Use this if the saved space will not relocalize. Guidance stays paused until both landmarks agree.").font(.footnote)
                }
            }.navigationTitle("Recover position").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { recovery = false } } }
        }.presentationDetents([.medium, .large])
    }
}

extension HallwayNavigationModel: NavigationAgentHost {
    func beginAgentTurn(_ text: String) {
        settings.stopSpeech()
        agentUtterance = String(text.prefix(1000)); resolvedAgentDestinations = []; calculatedAgentDestination = nil
        let lower = text.lowercased()
        observationAllowed = ["ahead", "front", "see", "read", "view"].contains { lower.contains($0) }
        if lower.contains("avoid stairs") {
            settings.setPreference(\.avoidStairs, true); routeStore.setPreference(\.avoidStairs, true)
        }
        _ = agentContext()
    }
    func agentContext() -> AgentContext {
        let verified = fresh && running && !needsAlignment && follower.stable && [.guiding, .nearRoom].contains(follower.state)
        let tracking = verified ? "verified" : follower.state == .trackingLost ? "lost" : "uncertain"
        let fingerprint = "\(route.room.id)|\(tracking)|\(routeStore.blockedEdges.sorted())|\(settings.preferences)|\(follower.state.rawValue)"
        if fingerprint != agentFingerprint { ledger.invalidate(); agentFingerprint = fingerprint }
        return AgentContext(sessionId: ledger.sessionId, sessionRevision: ledger.revision,
            buildingId: draft.id.uuidString, floor: nil, tracking: tracking,
            destinationId: route.room.id.uuidString, avoidStairs: settings.preferences.avoidStairs,
            instruction: verified ? guidance.text : "Position uncertain. Confirm a known landmark before guidance.",
            knownDestinations: draft.landmarks.prefix(100).map { ["id": $0.id.uuidString, "name": $0.label, "mapId": draft.id.uuidString, "floorLabel": floorLabel ?? "unknown"] },
            knownClosures: routeStore.blockedEdges.sorted())
    }
    private func candidateRoute(_ target: ScanLandmark) throws -> HallwayFollower {
        guard fresh, running, available, !needsAlignment else { throw MapError.invalid("Reliable guidance is unavailable. Recover at a known landmark first.") }
        // The reviewed graph enforces closures and stair preferences.
        _ = try VerifiedNavigationTools.calculateRoute(in: reviewedRoute.building, start: "entrance", destination: "room", preferences: settings.preferences, blocked: routeStore.blockedEdges)
        return try follower.changingDestination(to: target, on: reviewedRoute, draft: draft)
    }
    private func activateAgentDestination(_ target: ScanLandmark) throws {
        let next = try candidateRoute(target)
        settings.stopSpeech()
        follower = next; ledger.invalidate(); delivery.reset(); settings.cue(.changed)
        entranceRecognition = EntranceRecognition(label: next.route.entrance.label)
        roomRecognition = EntranceRecognition(label: target.label, distinctiveEntrance: false)
        entranceRecognition.currentFrame = { [weak camera] in camera?.scene.session.currentFrame }
        roomRecognition.currentFrame = { [weak camera] in camera?.scene.session.currentFrame }
        automaticStartAllowed = false; announced = next.instruction
        // SpatialSession and its ARSession are deliberately untouched.
    }
    func presentClarification(_ text: String) { voiceResponse = text; settings.speak(text, force: true) }
    func presentAgentResult(_ result: AgentToolResult) {
        let current = agentContext()
        guard current.sessionRevision == result.sessionRevision else { return }
        voiceResponse = result.userSafeExplanation
        if result.status != .success || current.tracking == "verified" {
            settings.speak(result.userSafeExplanation, force: true)
        }
    }
    func executeAgent(_ call: AgentCall) async -> AgentToolResult {
        _ = agentContext()
        func answer(_ status: AgentToolResult.Status, _ text: String, _ data: [String: String] = [:]) -> AgentToolResult {
            AgentToolResult(callId: call.callId, sessionRevision: agentContext().sessionRevision, status: status, data: data, userSafeExplanation: text)
        }
        do {
            if let prior = try ledger.validate(call) { return prior }
            var result: AgentToolResult
            switch call.tool {
            case .getNavigationState:
                let context = agentContext()
                result = answer(context.tracking == "verified" ? .success : .unverified, context.instruction, ["tracking": context.tracking, "destinationId": context.destinationId])
            case .getAccessibilityPreferences:
                result = answer(.success, settings.preferences.avoidStairs ? "Stairs are excluded." : "Your current preferences are retained.", ["avoidStairs": String(settings.preferences.avoidStairs), "narrowPathData": "unavailable"])
            case .getKnownClosures:
                result = answer(.success, available ? "No confirmed closure blocks this mapped hallway." : "This hallway is reported closed. No alternative hallway has been mapped.", ["edgeIds": routeStore.blockedEdges.sorted().joined(separator: ",")])
            case .getNearbyMappedDestinations:
                result = answer(.success, "Only saved landmarks on this scan are available; connectivity must be checked before routing.", Dictionary(uniqueKeysWithValues: draft.landmarks.map { ($0.id.uuidString, $0.label) }))
            case .resolveDestination:
                guard BuildingQualifier.matches(agentUtterance, building: draft.name) else { throw MapError.invalid("The requested building does not match this saved map. Confirm the building before continuing.") }
                let target: ScanLandmark
                if agentUtterance.lowercased().contains("nearest"), agentUtterance.lowercased().contains("restroom") {
                    let candidates = draft.landmarks.filter { $0.label.lowercased().contains("restroom") }.compactMap { landmark -> (ScanLandmark, Float)? in
                        guard let candidate = try? candidateRoute(landmark) else { return nil }; return (landmark, candidate.remaining)
                    }.sorted { $0.1 < $1.1 }
                    guard let best = candidates.first else { throw MapError.invalid("No reachable mapped restroom is known from your verified position.") }
                    target = best.0
                } else {
                    // Model cannot substitute a different known room for an unknown user request.
                    target = try LiveHallwayCommand.destination(in: agentUtterance, landmarks: draft.landmarks)
                }
                resolvedAgentDestinations.insert(target.id)
                result = answer(.success, "Found \(target.label) in this scan. Checking its route next.", ["destinationId": target.id.uuidString])
            case .calculateAccessibleRoute, .changeDestination:
                guard let id = UUID(uuidString: call.argument), resolvedAgentDestinations.contains(id),
                      let target = draft.landmarks.first(where: { $0.id == id }) else { throw MapError.invalid("Resolve a unique mapped destination before routing.") }
                let next = try candidateRoute(target)
                if call.tool == .changeDestination {
                    guard calculatedAgentDestination == id else { throw MapError.invalid("Calculate a verified route before changing destination.") }
                    proposeDestination(target, speak: false)
                    result = answer(.unverified, voiceResponse ?? "Confirm the destination first.", ["destinationId": id.uuidString, "confirmationRequired": "true", "routeChanged": "false"])

                } else {
                    calculatedAgentDestination = id
                    result = answer(.success, "A reviewed hallway route to \(target.label) is available.", ["destinationId": id.uuidString, "remainingMetres": String(next.remaining)])
                }
            case .replanRoute:
                guard available else {
                    follower.invalidate("This hallway is closed. No verified alternative exists. Ask staff for assistance.")
                    result = answer(.unavailable, follower.instruction); break
                }
                try activateAgentDestination(route.room)
                result = answer(.success, "Continuing on the verified hallway. No separate alternate route has been mapped.")
            case .repeatInstruction:
                result = answer(.success, agentContext().instruction)
            case .describeCurrentView:
                guard !readingScene else { throw MapError.invalid("A camera reading is already being processed.") }
                readingScene = true
                defer { readingScene = false }
                guard observationAllowed, fresh, follower.stable, let frame = camera.scene.session.currentFrame,
                      ProcessInfo.processInfo.systemUptime-frame.timestamp < 0.8 else { throw MapError.invalid("Request a camera reading while tracking is stable.") }
                observationAllowed = false
                let evidence = await AgentSceneObservation.read(frame)
                _ = agentContext(); _ = try ledger.validate(call)
                guard fresh, AgentSceneObservation.isFresh(frame, current: camera.scene.session.currentFrame) else { throw MapError.invalid("The camera observation is stale. Please request another reading.") }
                let distance = evidence["measuredDepthMetres"].map { "Measured central surface depth: about \($0) metres. " } ?? "Depth is unavailable. "
                result = answer(.success, distance + "Text seen: \(evidence["recognizedText"] ?? "unknown"). \(evidence["objectIdentity"] ?? "Object identity is unknown.") This is not obstacle avoidance.", evidence)
            case .getShoppingList:
                result = answer(.success, shoppingMemory.items.isEmpty ? "Your shopping list is empty." : "Shopping list: \(shoppingMemory.items.joined(separator: ", ")). Product locations have not been established.", ["items": shoppingMemory.items.joined(separator: ","), "storeLocation": "unknown"])
            case .addShoppingItem:
                guard agentUtterance.lowercased().contains(call.argument.lowercased()), ["add", "buy", "find"].contains(where: { agentUtterance.lowercased().contains($0) }) else { throw MapError.invalid("Only products requested in this turn can be added.") }
                var memory = shoppingMemory; try memory.add(call.argument); shoppingMemory = memory; ledger.invalidate()
                result = answer(.success, "Added \(call.argument) to your list. Its store location is unknown.")
            case .optimizeShoppingRoute:
                result = answer(.unavailable, "This hallway is not a mapped store. Product location unavailable for this store. Your list is saved; no product route was invented.")
            }
            ledger.record(call, result: result)
            return result
        } catch {
            let result = answer(.error, error.localizedDescription)
            return result
        }
    }
}
