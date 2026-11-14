import SwiftUI
import Combine
import ARKit
import IndoorbilityCore

@MainActor final class HallwayNavigationModel: ObservableObject {
    @Published private(set) var follower: HallwayFollower
    @Published private(set) var mapDrawing: IndoorRouteMapDrawing
    @Published var error: String?
    @Published private(set) var rawPosition: SpatialPoint?
    @Published private(set) var running = false
    @Published private(set) var openingPositionMap = false
    @Published private(set) var matchingDelayed = false
    @Published private(set) var startupFailure: String?
    @Published private(set) var hasEstablishedPosition = false
    private var unstartedFollower: HallwayFollower?
    @Published private(set) var recoveryFirst: UUID?
    let camera = SpatialSession()
    private let preloadedWorldMap: ARWorldMap?
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
    @Published private(set) var readingSign = false
    private var signTask: Task<Void, Never>?
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
    private var savedRouteMatch = SavedRouteRelocalization()
    private var savedMapRecovery = SavedMapRecovery()
    private var lastVerifiedPose: (position: SpatialPoint, time: TimeInterval)?
    @Published private(set) var automaticMatchHint: String?
    private var roomRecognition: EntranceRecognition
    private var usingSavedMap = true
    private var automaticStartAllowed = true
    private var watchdog: Task<Void, Never>?
    private var starting = false
    private var lastPoseWall: TimeInterval = 0
    @Published private(set) var needsAlignment = false
    @Published private(set) var mapConfidence = MapPositionConfidence.unverified
    @Published private(set) var geometryEvidence = "Not assessed"
    private var surfaceReference: SurfaceReference?
    @Published private(set) var mapWalls = Path()
    private var preparingSavedGeometry = false
    private var fullGeometryAttempted = false
    private var comparisonBusy = false
    private var lastComparison = 0.0
    private var surfaceAgreement = SurfaceAgreementFilter()
    private(set) var worldMapLoadMS = 0.0
    private(set) var savedMeshBytes = 0
    private(set) var savedMeshPreparationMS = 0.0
    private(set) var usedCompactGeometry = false
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
         String(format: "Saved mesh input: %.1f MB; background preparation: %.1f ms", Double(savedMeshBytes)/1048576, savedMeshPreparationMS),
         "Compact navigation scan: " + (usedCompactGeometry ? "Loaded" : "Prepared from source"),
         "Recovery attempts / successes / rejected: \(recoveryAttempts) / \(recoverySuccesses) / \(recoveryFailures)",
         "Automatic saved-map recovery: " + (savedMapRecovery.isPending ? "Settling" : "Inactive"),
         "Last recovery duration: " + (recoverySeconds.map { String(format: "%.2f s", $0) } ?? "Not measured"),
         "Confirmed landmark residual: " + (confirmedLandmarkError.map { String(format: "%.2f m (manual confirmation)", $0) } ?? "Not measured"),
         "Last turn request uptime: " + (deliveredTurnTime.map { String(format: "%.3f s", $0) } ?? "None"),
         "Last turn route progress: " + (deliveredTurnProgress.map { String(format: "%.2f m", $0) } ?? "None"),
         String(format: "Room OCR processing: %.1f ms; expired: %d", roomRecognition.processingMS, roomRecognition.expiredResults)]
    }
    private func losePosition(_ message: String = "Position uncertain. Point at a known sign, then confirm the landmark.", allowAutomaticRecovery: Bool = false) {
        savedRouteMatch.reset()
        if allowAutomaticRecovery, usingSavedMap, mapConfidence == .confirmed, follower.alignment == .identity,
           let pose = lastVerifiedPose, ProcessInfo.processInfo.systemUptime-pose.time < 2 {
            savedMapRecovery.begin(lastPosition: pose.position, time: lastPoseWall)
            recoveryAttempts += 1
            automaticMatchHint = "Hold still while the saved map matches."
        } else if !allowAutomaticRecovery {
            savedMapRecovery.reset(); automaticMatchHint = nil
        }
        settings.updateJourneySound(active: false)
        if automaticStartAllowed && usingSavedMap && (mapConfidence == .unverified || mapConfidence == .savedMap) {
            mapConfidence = .unverified; needsAlignment = true
            follower.invalidate("Matching the saved map."); delivery.reset(); settings.stopSpeech()
            return
        }
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
    var verifiedMapPosition: SpatialPoint? {
        guard running, fresh, !needsAlignment, mapConfidence == .confirmed, follower.stable,
              [.guiding, .nearRoom, .arrived].contains(follower.state) else { return nil }
        return follower.position
    }
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
    init(route: HallwayRoute, draft: ScanDraft, library: ScanLibrary, settings: AppStore, preloadedWorldMap: ARWorldMap? = nil) throws {
        self.preloadedWorldMap = preloadedWorldMap
        try route.validate(for: draft)
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
        let initialFollower = HallwayFollower(route: route)
        follower = initialFollower
        unstartedFollower = initialFollower
        mapDrawing = IndoorRouteMapDrawing(route: route)
        camera.routeOverlayEnabled = false
        roomRecognition.currentFrame = { [weak camera] in camera?.scene.session.currentFrame }
        camera.onMeasuredDepth = { [weak self] in self?.compareSurfaces($0) }
        camera.onFrame = { [weak self] frame in
            guard let self else { return }
            guard !self.readingScene else { return }
            if self.follower.state == .nearRoom || (self.follower.state == .guiding && self.follower.remaining < 3) { self.roomRecognition.process(frame) }
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
    func start(useSavedMap: Bool = true, reloadSavedMap: Bool = false) async {
        // An app activation can arrive while an earlier disk load unwinds.
        // Serialize starts, then let the new activation resume rather than drop it.
        while starting {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled else { return }
        guard !running || reloadSavedMap else { return }
        starting = true
        defer { starting = false }
        let resume = !reloadSavedMap && camera.canResume && usingSavedMap == useSavedMap
        pause(); let token = UUID(); epoch = token
        if !resume {
            // The initial follower already contains the verified turn plan.
            // Reuse it instead of rebuilding the entire route a second time.
            follower = unstartedFollower ?? HallwayFollower(route: route)
            unstartedFollower = nil
        }
        announced = ""; error = nil; lastUpdate = 0; needsAlignment = true
        mapConfidence = .unverified; recoveryStarted = ProcessInfo.processInfo.systemUptime
        usingSavedMap = useSavedMap; savedRouteMatch.reset(); automaticMatchHint = nil
        roomRecognition.reset(); automaticStartAllowed = useSavedMap
        matchingDelayed = false; startupFailure = nil; openingPositionMap = !resume && useSavedMap
        guard ARWorldTrackingConfiguration.isSupported else {
            openingPositionMap = false
            startupFailure = "Live positioning needs a supported iPhone."
            error = "Live guidance requires a supported physical iPhone or iPad."; return
        }
        do {
            if resume { camera.resumeTracking() }
            else {
                let directory = library.directory(draft.id), started = ProcessInfo.processInfo.systemUptime
                let cacheURL = library.navigationWorldMapCache(draft.id)
                let cachedMap = preloadedWorldMap
                let map = try await Task.detached(priority: .userInitiated) { () throws -> ARWorldMap? in
                    guard useSavedMap else { return nil }
                    if let cachedMap { return cachedMap }
                    do { return try NavigationWorldMapArchive.load(sourceURL: directory.appending(path: "world.arworldmap"), cacheURL: cacheURL) }
                    catch { throw MapError.invalid("Saved 3D positioning map could not be opened. Try matching at landmarks.") }
                }.value
                worldMapLoadMS = (ProcessInfo.processInfo.systemUptime-started)*1000
                guard epoch == token, !Task.isCancelled else { return }
                await camera.start(map: map, navigation: true)

            }
            guard epoch == token else { return }
            openingPositionMap = false
            running = camera.running
            // Reuse a compact reference if present; do not decode the full mesh
            // alongside ARKit's first map load or while it is relocalizing.
            prepareSavedGeometry(cacheOnly: true)
            camera.compareSurfaces = surfaceReference != nil
            lastPoseWall = ProcessInfo.processInfo.systemUptime
            let matchingBegan = lastPoseWall
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled, let self else { return }
                    if self.running && self.needsAlignment && !self.matchingDelayed &&
                        ProcessInfo.processInfo.systemUptime-matchingBegan >= 20 {
                        self.matchingDelayed = true
                    }
                    if self.running && !self.camera.running { self.running = false; self.losePosition() }
                    if self.running && !self.fresh && self.follower.stable && self.follower.localized {
                        self.settings.updateJourneySound(active: false)
                        // GPS mode re-acquires by itself once frames resume.
                        self.follower.update(position: nil, heading: nil, time: ProcessInfo.processInfo.systemUptime, trackingNormal: false)
                        self.rawPosition = nil; self.settings.directionalCue(nil)
                    } else if self.running && !self.fresh && self.follower.stable {
                        self.losePosition(allowAutomaticRecovery: true); self.rawPosition = nil
                        self.camera.showRoute(self.route.path, alignment: self.follower.alignment, verified: false)
                        self.recoveryFirst = nil; self.firstObservation = nil
                        self.settings.stopSpeech(); self.settings.speak(self.follower.instruction, priority: .safety)
                    }
                }
            }
            if !running {
                startupFailure = camera.error ?? "Camera could not start."
                error = startupFailure
            }
        } catch {
            guard epoch == token else { return }
            openingPositionMap = false; startupFailure = error.localizedDescription
            self.error = error.localizedDescription
        }
    }
    private func prepareSavedGeometry(cacheOnly: Bool = false) {
        guard !preparingSavedGeometry, surfaceReference == nil, cacheOnly || !fullGeometryAttempted else { return }
        preparingSavedGeometry = true
        if !cacheOnly { fullGeometryAttempted = true }
        let url = library.directory(draft.id).appending(path: "mesh.json")
        let cache = library.navigationGeometryCache(draft.id)
        // The disposable outline serves any destination in this same scan.
        let region = CGRect.infinite
        let started = ProcessInfo.processInfo.systemUptime
        Task {
            let prepared = await Task.detached(priority: .utility) { () -> (SurfaceReference?, [SIMD4<Float>], Int, Bool) in
                guard let source = try? CompactNavigationGeometry.Source.read(url) else { return (nil, [], 0, false) }
                let size = source.size
                if let compact = CompactNavigationGeometry.load(at: cache, source: source) {
                    let edges = stride(from: 0, to: compact.edges.count, by: 4).map {
                        SIMD4(compact.edges[$0], compact.edges[$0+1], compact.edges[$0+2], compact.edges[$0+3])
                    }
                    return (SurfaceReference(points: compact.points), edges, size, true)
                }
                guard !cacheOnly else { return (nil, [], size, false) }
                guard size <= 80*1024*1024, let data = try? Data(contentsOf: url),
                      let meshes = try? JSONDecoder().decode([MeshRecord].self, from: data),
                      meshes.allSatisfy({ mesh in
                          mesh.vertices.allSatisfy { $0.isFinite && abs($0.x) < 100000 && abs($0.y) < 100000 && abs($0.z) < 100000 } &&
                          mesh.triangles.count % 3 == 0 && mesh.triangles.allSatisfy { Int($0) < mesh.vertices.count }
                      }) else { return (nil, [], size, false) }
                var points: [SpatialPoint] = []
                let total = meshes.reduce(0) { $0 + $1.vertices.count }, step = max(1, total/50000)
                for mesh in meshes {
                    for i in stride(from: 0, to: mesh.vertices.count, by: step) {
                        points.append(mesh.vertices[i]); if points.count >= 50000 { break }
                    }
                    if points.count >= 50000 { break }
                }
                let edges = SavedIndoorMapGeometry.edges(meshes, region: region)
                let compact = CompactNavigationGeometry(points: points, edges: edges.flatMap { [$0.x, $0.y, $0.z, $0.w] })
                try? compact.save(at: cache, sourceURL: url, expected: source)
                return (SurfaceReference(points: points), edges, size, false)
            }.value
            preparingSavedGeometry = false
            usedCompactGeometry = prepared.3
            savedMeshBytes = prepared.2
            savedMeshPreparationMS = (ProcessInfo.processInfo.systemUptime-started)*1000
            NavigationPerformance.shared.record("Saved mesh background preparation wall ms", savedMeshPreparationMS)
            surfaceReference = prepared.0
            camera.compareSurfaces = prepared.0 != nil && running
            var path = Path()
            for edge in prepared.1 {
                path.move(to: CGPoint(x: CGFloat(edge.x), y: CGFloat(edge.y)))
                path.addLine(to: CGPoint(x: CGFloat(edge.z), y: CGFloat(edge.w)))
            }
            mapWalls = path
        }
    }
    func pause() {
        settings.updateJourneySound(active: false); savedRouteMatch.reset()
        savedMapRecovery.reset(); lastVerifiedPose = nil
        signTask?.cancel(); signTask = nil; readingSign = false
        settings.stopSpeech(); delivery.reset()
        agent.cancel(); ledger.invalidate()
        watchdog?.cancel(); watchdog = nil
        epoch = UUID(); running = false; camera.stop(); rawPosition = nil
        openingPositionMap = false
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
        if normal, usingSavedMap, camera.savedMapRelocalized, mapConfidence == .unverified {
            // A matched world map supplies the transform. The follower still
            // needs sustained tracking and a unique position on its saved path.
            needsAlignment = false; mapConfidence = .savedMap; delivery.reset()
        }
        let routeAvailable = available
        let previousState = follower.state
        follower.update(position: p, heading: heading, time: time, trackingNormal: normal, routeAvailable: routeAvailable)
        if previousState != follower.state && [.trackingLost, .offRoute, .blocked, .arrived].contains(follower.state) { settings.stopSpeech() }
        camera.showRoute(route.path, alignment: follower.alignment, verified: !camera.floorHazard && camera.postureIssue == nil && heading != nil && normal && !needsAlignment && follower.stable && [.guiding, .nearRoom].contains(follower.state))
        if follower.localized {
            if previousState != follower.state && follower.state == .arrived { recordArrival() }
        } else if [.trackingLost, .offRoute].contains(follower.state) && previousState != follower.state {
            if automaticStartAllowed && (mapConfidence == .unverified || mapConfidence == .savedMap) {
                // ARKit normally enters .relocalizing while opening a saved map.
                // This is startup, not a failure of an established alignment.
                savedRouteMatch.reset(); needsAlignment = true; mapConfidence = .unverified; delivery.reset()
            } else { losePosition(allowAutomaticRecovery: !normal && [.guiding, .nearRoom].contains(previousState)) }
            roomRecognition.reset(); recoveryFirst = nil; firstObservation = nil
        }
        if automaticStartAllowed {
            let matched = savedRouteMatch.update(
                mapMatched: usingSavedMap && camera.savedMapRelocalized && !needsAlignment && mapConfidence == .savedMap,
                // Both filters independently require two seconds of valid
                // poses. Run their evidence windows together, not consecutively.
                trackingStable: normal && routeAvailable && !camera.floorHazard,
                position: p, time: time)
            if matched, follower.stable, follower.state == .ready, let p {
                do {
                    try follower.startInRelocalizedMap(livePosition: p, relocalized: camera.savedMapRelocalized)
                    automaticStartAllowed = false; automaticMatchHint = nil; mapConfidence = .confirmed
                    if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
                    delivery.reset()
                    settings.speak("Map matched. Continuing to \(route.room.label).")
                } catch { automaticMatchHint = "Move away from the junction and look around to match the route." }
            }
        }
        if savedMapRecovery.isPending {
            let matched = savedMapRecovery.update(mapMatched: usingSavedMap && camera.savedMapRelocalized,
                trackingStable: normal && routeAvailable && !camera.floorHazard, position: p, time: time)
            if matched, follower.stable, let p {
                do {
                    try follower.resumeInRelocalizedMap(livePosition: p, relocalized: camera.savedMapRelocalized)
                    needsAlignment = false; mapConfidence = .confirmed; automaticMatchHint = nil
                    savedMapRecovery.reset(); delivery.reset(); recoverySuccesses += 1
                    if let began = recoveryStarted { recoverySeconds = ProcessInfo.processInfo.systemUptime-began }
                    settings.speak("Position found. Continuing to \(route.room.label).")
                } catch {
                    recoveryFailures += 1
                    savedMapRecovery.reset(); automaticMatchHint = "Match this route at a known landmark."
                }
            } else if !savedMapRecovery.isPending {
                recoveryFailures += 1; automaticMatchHint = "Match this route at a known landmark."
            }
        }
        if normal, !needsAlignment, mapConfidence == .confirmed, follower.stable,
           [.guiding, .nearRoom].contains(follower.state), let position = follower.position {
            lastVerifiedPose = (position, time)
            if !hasEstablishedPosition { hasEstablishedPosition = true }
            // One background conversion after successful positioning; playback
            // uses the exact route independently of optional surface detail.
            prepareSavedGeometry()
        }
        if ArrivalEvidence.canConfirm(state: follower.state, trackingStable: follower.stable, poseFresh: fresh,
                                      labelMatches: roomRecognition.matchedRecently, routeAvailable: routeAvailable) {
            confirmArrival()
        } else if follower.state == .nearRoom, verifiedMapPosition != nil, routeAvailable, !camera.floorHazard {
            // Geometric arrival at the saved endpoint needs no extra setup.
            // Do not count this as an independently verified room-label visit.
            try? follower.finishRecordedRoute(positionVerified: true)
        }
        if !camera.floorHazard && fresh && follower.stable && follower.state == .guiding && !needsAlignment && !listeningForCommand && !agent.busy && time >= surfaceWarningUntil {
            if time-lastBeacon >= 3 { lastBeacon = time; settings.directionalCue(camera.soundTarget(path: route.path, progress: follower.progress, alignment: follower.alignment)) }
        } else { settings.directionalCue(nil) }
        deliverGuidance()
        let canTick = !camera.floorHazard && camera.postureIssue == nil && fresh && follower.stable &&
            follower.state == .guiding && !needsAlignment && !listeningForCommand && !agent.busy && time >= surfaceWarningUntil
        let travelPoint = canTick ? follower.position.map { SIMD2(Double($0.x), Double($0.z)) } : nil
        settings.updateJourneySound(active: !camera.floorHazard && fresh && follower.stable &&
            follower.state == .guiding && !needsAlignment && !listeningForCommand && time >= surfaceWarningUntil)
        settings.travelFeedback(position: travelPoint, context: "indoor")
    }

    func speechNotUnderstood() {
        listeningForCommand = false
        voiceResponse = VoiceCommandInput.notUnderstood
        settings.speak(VoiceCommandInput.notUnderstood)
    }
    func readSign() {
        guard !readingSign else { return }
        agent.cancel(); settings.stopSpeech()
        guard running, let frame = camera.scene.session.currentFrame,
              ProcessInfo.processInfo.systemUptime-frame.timestamp < 0.8 else {
            voiceResponse = "Point the camera at a sign."
            settings.speak(voiceResponse!, force: true); return
        }
        let token = epoch
        readingSign = true
        signTask = Task {
            let evidence = await AgentSceneObservation.read(frame)
            guard !Task.isCancelled, epoch == token else { return }
            readingSign = false
            guard AgentSceneObservation.isFresh(frame, current: camera.scene.session.currentFrame) else {
                voiceResponse = "Hold the camera steady and try again."
                settings.speak(voiceResponse!, force: true); return
            }
            voiceResponse = evidence["recognizedText"] ?? "No readable text found."
            settings.speak(voiceResponse!, force: true)
        }
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
        usingSavedMap && camera.savedMapRelocalized
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
                savedMapRecovery.reset(); automaticMatchHint = nil
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
                savedMapRecovery.reset(); automaticMatchHint = nil
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
        settings.updateJourneySound(active: false)
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
    var preloadedWorldMap: ARWorldMap? = nil
    @State private var model: HallwayNavigationModel?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let model { HallwayGuidanceView(model: model) }
            else { VStack(spacing: 20) { Text(error ?? "Opening route…"); Button("Close") { dismiss() } } }
        }.task {
            guard model == nil else { return }
            do { model = try HallwayNavigationModel(route: route, draft: draft, library: library, settings: settings, preloadedWorldMap: preloadedWorldMap) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private enum SavedIndoorMapGeometry {
    static func bounds(_ route: HallwayRoute) -> CGRect {
        let xs = route.path.map { CGFloat($0.x) }, zs = route.path.map { CGFloat($0.z) }
        return CGRect(x: (xs.min() ?? 0)-3, y: (zs.min() ?? 0)-3,
                      width: max(6, (xs.max() ?? 0)-(xs.min() ?? 0)+6),
                      height: max(6, (zs.max() ?? 0)-(zs.min() ?? 0)+6))
    }
    static func edges(_ meshes: [MeshRecord], region: CGRect) -> [SIMD4<Float>] {
        let total = meshes.reduce(0) { $0 + $1.triangles.count/3 }
        let step = max(1, Int(ceil(Double(total)/1500)))
        var edges: [SIMD4<Float>] = [], ordinal = 0
        for mesh in meshes {
            for i in stride(from: 0, to: mesh.triangles.count, by: 3) {
                defer { ordinal += 1 }
                guard ordinal % step == 0 else { continue }
                let p = (0..<3).map { mesh.vertices[Int(mesh.triangles[i+$0])] }
                let a = SIMD3(p[1].x-p[0].x, p[1].y-p[0].y, p[1].z-p[0].z)
                let b = SIMD3(p[2].x-p[0].x, p[2].y-p[0].y, p[2].z-p[0].z)
                let normal = simd_cross(a, b), length = simd_length(normal)
                // Project measured vertical surfaces; never manufacture walls
                // or treat an unscanned region as a clear walkable floor.
                guard length > 0.00001, abs(normal.y)/length < 0.6 else { continue }
                let pairs = [(p[0], p[1]), (p[1], p[2]), (p[2], p[0])]
                guard let edge = pairs.max(by: { $0.0.horizontalDistance(to: $0.1) < $1.0.horizontalDistance(to: $1.1) }),
                      region.contains(CGPoint(x: CGFloat(edge.0.x), y: CGFloat(edge.0.z))) || region.contains(CGPoint(x: CGFloat(edge.1.x), y: CGFloat(edge.1.z))) else { continue }
                edges.append(SIMD4(edge.0.x, edge.0.z, edge.1.x, edge.1.z))
            }
        }
        return edges
    }
}

/// Prepare immutable drawing data once per destination change, not per pose.
/// This is a display cache; the follower retains the full verified route.
struct IndoorRouteMapDrawing {
    let bounds: CGRect
    let path: Path
    let directionArrows: Path
    @MainActor init(route: HallwayRoute) {
        let began = ProcessInfo.processInfo.systemUptime
        bounds = SavedIndoorMapGeometry.bounds(route)
        var line = Path()
        for (i, p) in route.path.enumerated() {
            let q = CGPoint(x: CGFloat(p.x), y: CGFloat(p.z))
            if i == 0 { line.move(to: q) } else { line.addLine(to: q) }
        }
        path = line
        // Static arrows describe the recording, never a guessed live bearing.
        // Prepare this bounded overlay once, not at every pose update.
        var arrows = Path(), travelled: Float = 0, next: Float = 0.75
        var count = 0
        for (a, b) in zip(route.path, route.path.dropFirst()) {
            let length = a.distance(to: b), horizontal = a.horizontalDistance(to: b)
            guard length > 0 else { continue }
            while next <= travelled+length && count < 120 {
                if horizontal > 0.05 {
                    let t = (next-travelled)/length
                    let x = a.x+(b.x-a.x)*t, z = a.z+(b.z-a.z)*t
                    let dx = (b.x-a.x)/horizontal, dz = (b.z-a.z)/horizontal
                    arrows.move(to: CGPoint(x: CGFloat(x-dx*0.3-dz*0.22), y: CGFloat(z-dz*0.3+dx*0.22)))
                    arrows.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(z)))
                    arrows.addLine(to: CGPoint(x: CGFloat(x-dx*0.3+dz*0.22), y: CGFloat(z-dz*0.3-dx*0.22)))
                    count += 1
                }
                next += 2.5
            }
            travelled += length
            if count >= 120 { break }
        }
        directionArrows = arrows
        NavigationPerformance.shared.record("Indoor route drawing preparation ms", (ProcessInfo.processInfo.systemUptime-began)*1000)
    }
}

/// Real saved surfaces and route in local AR metres. This view never converts
/// them into geographic GPS coordinates or invents a live position.
private struct IndoorNavigationMap: View {
    let route: HallwayRoute
    let drawing: IndoorRouteMapDrawing
    let walls: Path
    let position: SpatialPoint?
    let nextTurn: SpatialPoint?
    @State private var followUser = true
    @State private var overview = true
    @State private var center: CGPoint?
    @State private var panStart: CGPoint?
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    private var bounds: CGRect { drawing.bounds }
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let origin = center ?? CGPoint(x: bounds.midX, y: bounds.midY)
            let fit = min(size.width/bounds.width, size.height/bounds.height)
            let base = overview || position == nil ? fit : min(size.width/18, size.height/22)
            let scale = max(0.1, base * zoom * magnification)
            ZStack(alignment: .bottomTrailing) {
                Color.indoorBackground
                Canvas { context, _ in
                    func point(_ p: SpatialPoint) -> CGPoint {
                        CGPoint(x: size.width/2 + (CGFloat(p.x)-origin.x)*scale,
                                y: size.height/2 + (CGFloat(p.z)-origin.y)*scale)
                    }
                    var world = context
                    world.translateBy(x: size.width/2, y: size.height/2)
                    world.scaleBy(x: scale, y: scale)
                    world.translateBy(x: -origin.x, y: -origin.y)
                    world.stroke(walls, with: .color(Color.indoorInk.opacity(0.24)), style: StrokeStyle(lineWidth: 0.12, lineCap: .round))
                    world.stroke(drawing.path, with: .color(.white), style: StrokeStyle(lineWidth: 10/scale, lineCap: .round, lineJoin: .round))
                    world.stroke(drawing.path, with: .color(.indoorTeal), style: StrokeStyle(lineWidth: 5/scale, lineCap: .round, lineJoin: .round))
                    world.stroke(drawing.directionArrows, with: .color(.white), style: StrokeStyle(lineWidth: 2/scale, lineCap: .round, lineJoin: .round))
                    for mark in [route.entrance, route.room] {
                        let p = point(mark.position)
                        context.fill(Path(ellipseIn: CGRect(x: p.x-7, y: p.y-7, width: 14, height: 14)), with: .color(.indoorTeal))
                        context.draw(Text(mark.label).font(.caption.bold()).foregroundColor(.indoorInk), at: CGPoint(x: p.x, y: p.y+22))
                    }
                    if let nextTurn {
                        let p = point(nextTurn)
                        context.stroke(Path(ellipseIn: CGRect(x: p.x-12, y: p.y-12, width: 24, height: 24)), with: .color(.indoorTeal), lineWidth: 3)
                    }
                    if let position {
                        let p = point(position)
                        context.fill(Path(ellipseIn: CGRect(x: p.x-11, y: p.y-11, width: 22, height: 22)), with: .color(.white))
                        context.fill(Path(ellipseIn: CGRect(x: p.x-8, y: p.y-8, width: 16, height: 16)), with: .color(.blue))
                    }
                }.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 8).onChanged { value in
                        if panStart == nil { panStart = origin }
                        followUser = false
                        if let anchor = panStart {
                            center = CGPoint(x: anchor.x-value.translation.width/scale, y: anchor.y-value.translation.height/scale)
                        }
                    }.onEnded { _ in panStart = nil })
                    .simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { zoom = min(8, max(0.5, zoom * $0.magnification)) })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Saved indoor route from \(route.entrance.label) to \(route.room.label)")
                    .accessibilityValue((position == nil ? "Position not matched" : "Live position matched") + (walls.isEmpty ? "; route trace" : "; captured surfaces shown") + "; recorded direction arrows")
                    .accessibilityIdentifier("indoorSavedRouteMap")
                VStack(spacing: 10) {
                    Button { followUser = false; overview = true; zoom = 1; center = CGPoint(x: bounds.midX, y: bounds.midY) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 46, height: 46)
                    }.accessibilityLabel("Full indoor route").accessibilityIdentifier("indoorRouteOverview")
                    Button {
                        followUser = true; overview = false; zoom = 1
                        if let position { center = CGPoint(x: CGFloat(position.x), y: CGFloat(position.z)) }
                    } label: { Image(systemName: "location.fill").frame(width: 46, height: 46) }
                        .disabled(position == nil).accessibilityLabel("Recenter").accessibilityIdentifier("indoorRouteRecenter")
                }.buttonStyle(.plain).foregroundStyle(Color.indoorTeal)
                    .background(Color.indoorCard, in: Capsule()).padding(12)
            }.clipped()
        }
        .onChange(of: position) { _, p in
            if followUser, let p { center = CGPoint(x: CGFloat(p.x), y: CGFloat(p.z)); overview = false }
        }
    }

}

private struct HallwayGuidanceView: View {
    @ObservedObject var model: HallwayNavigationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var voice = VoiceCommandInput()
    @State private var map = true
    @State private var cameraVisible = false
    @AppStorage("guidanceFeet") private var feet = false
    var body: some View {
        let _ = NavigationPerformance.shared.bodyEvaluated("Indoor navigation")
        ZStack {
            Color.indoorBackground.ignoresSafeArea()
            // Keep the same AR session mounted while viewing the indoor map.
            SpatialCamera(session: model.camera).ignoresSafeArea().opacity(cameraVisible ? 1 : 0.001).accessibilityHidden(true)
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline).frame(width: 48, height: 48)
                            .background(Color.indoorCard, in: Circle())
                    }.accessibilityLabel("End navigation")
                    VStack(spacing: 3) {
                        Text(model.route.room.label).font(.headline).lineLimit(1)
                        Text(model.draft.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                    navigationOptions.background(Color.indoorCard, in: Circle())
                }.foregroundStyle(Color.indoorInk).padding(.horizontal, 16).padding(.top, 8)
                if map {
                    IndoorNavigationMap(route: model.route, drawing: model.mapDrawing, walls: model.mapWalls,
                        position: model.verifiedMapPosition,
                        nextTurn: guidanceActive ? model.follower.nextMeasuredTurn.map { model.route.path[$0.index] } : nil)
                } else { Spacer() }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            guidanceCard.padding(.horizontal, 12).padding(.vertical, 8)
        }.swipeLeftToGoBack(enabled: !map) { dismiss() }
            .overlay { VoiceEdgeGlow(active: voice.listening) }
            .task(id: phase) { if phase == .active { await model.start() } }
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
            .onChange(of: cameraVisible) { _, visible in model.camera.routeOverlayEnabled = visible }
            .onDisappear { voice.cancel(); model.listeningForCommand = false; model.pause() }
            .onChange(of: phase) { _, value in if value == .background { voice.cancel(); model.listeningForCommand = false; model.pause() } }
            .alert("Check your position", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
    private var navigationMicrophone: some View {
        HoldToTalk(voice: voice, before: {
                        model.agent.cancel(); model.settings.stopSpeech(); model.listeningForCommand = true
                    }, onUnrecognized: model.speechNotUnderstood, haptics: model.settings.preferences.haptics, diameter: 44, compact: true, result: { text in model.listeningForCommand = false; model.submitVoice(text) })
    }
    private var guidanceActive: Bool {
        !model.camera.floorHazard && model.verifiedMapPosition != nil && [.guiding, .nearRoom].contains(model.follower.state)
    }
    private var previewActive: Bool {
        !model.hasEstablishedPosition && !guidanceActive &&
            ![.blocked, .arrived, .nearRoom].contains(model.follower.state)
    }
    private func repeatDirections() {
        model.settings.speak(previewActive ? model.follower.recordedPreview.narration(feet: feet) : model.guidance.text, force: true)
    }
    private var navigationOptions: some View {
        Menu {
            Button("Map", systemImage: "map") { map = true; cameraVisible = false }
            Button("Camera", systemImage: "camera") { map = false; cameraVisible = true }
        } label: {
            Image(systemName: "ellipsis").frame(width: 44, height: 44)
        }.accessibilityLabel("Navigation options")
    }
    private var positioningStatus: String {
        if model.openingPositionMap { return "Opening saved route" }
        if model.startupFailure != nil { return "Positioning unavailable" }
        if model.matchingDelayed && model.needsAlignment { return "Match near the recorded path" }
        return "Matching your position"
    }
    private var instructionTitle: String {
        if previewActive { return model.follower.recordedPreview.instruction(feet: feet) }
        if model.follower.state == .arrived { return "You’ve arrived" }
        if model.follower.state == .blocked { return "Route closed" }
        if model.follower.state == .nearRoom { return "Reaching the endpoint" }
        if guidanceActive { return model.guidance.primary ?? model.guidance.text }
        if model.follower.state == .offRoute { return "Guidance paused" }
        if model.matchingDelayed && model.needsAlignment { return "Match near the recorded path" }
        return model.needsAlignment || model.follower.state == .ready ? "Finding your position" : "Position unavailable"
    }
    private var guidanceCard: some View {
        VStack(spacing: 12) {
            if previewActive {
                Text("Route preview · from recorded start").font(.caption.bold())
                    .foregroundStyle(Color.indoorTeal).accessibilityIdentifier("recordedRoutePreview")
            }
            Image(systemName: previewActive ? model.follower.recordedPreview.symbol : model.follower.state == .arrived || guidanceActive
                  ? LiveGuidance.symbol(for: instructionTitle, reliable: true) : "location.magnifyingglass")
                .font(.system(size: 48, weight: .bold)).foregroundStyle(Color.indoorTeal)
                .accessibilityHidden(true)
            Text(instructionTitle).font(.title2.bold()).multilineTextAlignment(.center)
                .monospacedDigit().accessibilityIdentifier("liveInstruction")
                .accessibilityLabel(previewActive ? "Route preview from recorded start. \(instructionTitle). Live position not matched." : instructionTitle)
            if !guidanceActive && model.follower.state != .arrived {
                Text(positioningStatus).font(.caption.bold()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("indoorPositioningStatus")
                Text(model.startupFailure ?? (model.openingPositionMap ? "Preparing positioning data…" : model.automaticMatchHint ?? "Look around near the recorded route."))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if model.openingPositionMap {
                    ProgressView().accessibilityLabel("Opening positioning map")
                } else if model.startupFailure != nil || model.matchingDelayed {
                    Button("Try matching again") { Task { await model.start(reloadSavedMap: true) } }
                        .accessibilityIdentifier("retryIndoorPositioning")
                }
            }
            if let warning = model.surfaceWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill").font(.subheadline)
                    .accessibilityIdentifier("liveSurfaceWarning")
            }
            if let pending = model.pendingDestination {
                Text("Go to \(pending.label)?").font(.headline)
                HStack {
                    Button("No") { model.declineDestination() }
                    Spacer()
                    Button("Change destination") { model.confirmDestination() }.buttonStyle(.borderedProminent)
                }
            }
            AgentActivityView(agent: model.agent)
            if voice.busy || model.voiceResponse != nil {
                Text(voice.busy ? voice.status : model.voiceResponse ?? "").font(.callout).lineLimit(3)
                    .accessibilityIdentifier("liveVoiceResponse")
            }
            HStack(alignment: .center) {
                Button("Repeat", action: repeatDirections)
                    .frame(minWidth: 64, minHeight: 48).accessibilityIdentifier("repeatCameraGuidance")
                Spacer()
                navigationMicrophone
                Spacer()
                Button(model.follower.state == .arrived ? "Done" : "Stop") { dismiss() }
                    .frame(minWidth: 64, minHeight: 48).accessibilityIdentifier("stopIndoorDirections")
            }.foregroundStyle(Color.indoorTeal)
        }.padding(18).frame(maxWidth: .infinity)
            .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 24))
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
        mapDrawing = IndoorRouteMapDrawing(route: next.route)
        roomRecognition = EntranceRecognition(label: target.label, distinctiveEntrance: false)
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
