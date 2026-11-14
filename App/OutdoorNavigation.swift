import SwiftUI
import MapKit
import CoreLocation
import ARKit
import IndoorbilityCore

@MainActor final class OutdoorLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var message = "Location is off"
    private var requested = false
    let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation; manager.headingFilter = 3; manager.headingOrientation = .portrait; manager.activityType = .fitness; manager.distanceFilter = kCLDistanceFilterNone; manager.pausesLocationUpdatesAutomatically = false }
    func start() {
        requested = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            updateHeadingOrientation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        default: message = "Allow location in iPhone Settings to use outdoor directions."
        }
    }
    func stop() { requested = false; manager.stopUpdatingLocation(); manager.stopUpdatingHeading(); location = nil; heading = nil }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if requested { start() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard requested, let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) < 10 else { return }
        guard location.map({ value.timestamp > $0.timestamp }) ?? true else { return }
        if let previous = location {
            let elapsed = value.timestamp.timeIntervalSince(previous.timestamp)
            let jump = value.distance(from: previous)
            if elapsed > 0, elapsed < 4, jump > max(35, value.horizontalAccuracy + previous.horizontalAccuracy + elapsed * 4) {
                return
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        let metrics = NavigationPerformance.shared
        if let previous = location { metrics.record("GPS capture interval ms", value.timestamp.timeIntervalSince(previous.timestamp)*1000) }
        metrics.record("GPS reported horizontal uncertainty m", value.horizontalAccuracy)
        metrics.record("GPS capture → callback ms", max(0, -value.timestamp.timeIntervalSinceNow)*1000)
        metrics.position("GPS", captured: now + value.timestamp.timeIntervalSinceNow)
        location = value; message = "Location updated"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let failure = error as? CLError, failure.code == .locationUnknown { message = "Updating GPS…"; return }
        message = error.localizedDescription; location = nil
    }
    func updateHeadingOrientation() {
        let orientation: CLDeviceOrientation
        switch UIDevice.current.orientation {
        case .landscapeLeft: orientation = .landscapeLeft
        case .landscapeRight: orientation = .landscapeRight
        case .portraitUpsideDown: orientation = .portraitUpsideDown
        case .portrait: orientation = .portrait
        default: return // Keep the last orientation when the phone is flat.
        }
        if manager.headingOrientation != orientation { manager.headingOrientation = orientation; heading = nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard requested else { return }
        heading = newHeading.magneticHeading.isFinite && newHeading.trueHeading.isFinite && newHeading.headingAccuracy >= 0 && newHeading.headingAccuracy <= 20 ? newHeading : nil
    }
    var entranceFix: EntranceLocation? {
        guard let location, location.horizontalAccuracy <= 20, abs(location.timestamp.timeIntervalSinceNow) < 5 else { return nil }
        return EntranceLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                accuracy: location.horizontalAccuracy, confirmedAt: Date())
    }
}

@MainActor final class OutdoorSearch: ObservableObject {
    @Published var results: [MKMapItem] = []
    @Published var error: String?
    @Published var loading = false
    var nearby: CLLocation?
    private var request: MKLocalSearch?
    func cancel() { request?.cancel(); request = nil; results = []; error = nil; loading = false }
    func search(_ query: String) async {
        request?.cancel(); let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: nearby?.coordinate ?? CLLocationCoordinate2D(latitude: 40.3487, longitude: -74.6593), latitudinalMeters: 12000, longitudinalMeters: 12000)
        let search = MKLocalSearch(request: request); self.request = search
        loading = true; error = nil
        do { let response = try await search.start(); guard self.request === search else { return }; results = response.mapItems.sorted { lhs, rhs in
            guard let nearby else { return false }
            return (lhs.placemark.location?.distance(from: nearby) ?? .infinity) < (rhs.placemark.location?.distance(from: nearby) ?? .infinity)
        } }
        catch { if self.request === search { results = []; self.error = "Place search couldn’t connect. Try again." } }
        if self.request === search { loading = false }
    }
}

struct OutdoorRouteView: View {
    let destination: MKMapItem
    @ObservedObject var settings: AppStore
    var indoor: IndoorJourneyTarget?
    var automaticallyStart = false
    var initialRoom: String? = nil
    @StateObject private var location = OutdoorLocation()
    @StateObject private var google = GoogleWalkingNavigation()
    // Apple is the default even when a Google SDK key is installed. Google is
    // available only as an explicit retry after Apple cannot load a route.
    @State private var useGoogle = false
    @State private var standardWalkingAllowed = false
    @State private var fallbackNotice: String?
    @State private var lastGoogleSpeech = ""
    @State private var lastGoogleSpeechAt = Date.distantPast
    @StateObject private var camera = SpatialSession()
    @State private var showingMap = false
    @State private var accessibility = false
    @State private var readingSign = false
    @State private var signTask: Task<Void, Never>?
    @State private var signText: String?
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var followUser = true
    @State private var handoffAttempted = false
    @State private var announcedIndoorEntrance = false
    @State private var preloadingIndoorMap = false
    @State private var preloadedIndoorMap: ARWorldMap?
    @State private var trail = OutdoorTrace()
    @State private var trailOrigin: MKMapPoint?
    @State private var trailScale = 1.0
    @State private var arrived = false
    @State private var lastReplan = Date.distantPast
    @State private var awarenessMessage: String?
    @State private var lastAwarenessText = ""
    @State private var lastAwarenessSpeech = Date.distantPast
    @State private var awarenessUntil = Date.distantPast
    @State private var insideBuilding = false
    @State private var nearBuilding = false
    @State private var continueOutside = false
    @State private var announcedNearby = false
    @State private var roomQuery = ""
    @State private var roomRequest: RoomMappingRequest?
    @State private var roomTarget: IndoorJourneyTarget?
    @StateObject private var roomVoice = VoiceCommandInput()
    @StateObject private var roomLibrary = ScanLibrary()
    @StateObject private var roomMemory = JourneyLibrary()
    @Environment(\.dismiss) private var dismiss
    @State private var route: MKRoute?
    @State private var walking: OutdoorProgress?
    @State private var approach = ApproachFeedback()
    @State private var displayTime = Date()
    @State private var walkingOrigin: MKMapPoint?
    @State private var walkingScale = 1.0
    @State private var spokenWalking = ""
    @State private var lastWalkingAnnouncement = Date.distantPast
    @State private var lastWalkingFix: Date?
    @State private var guidanceFix: CLLocation?
    @AppStorage("guidanceFeet") private var feet = false
    @State private var error: String?
    @State private var directions: MKDirections?
    @State private var nextRouteRetry = Date.distantFuture
    @State private var routeRetryDelay: TimeInterval = 5
    @State private var presented = false
    @State private var approachDistance: Double?
    @State private var started = false
    /// When GPS started; the first route waits briefly for a settled fix instead of
    /// building turn-by-turn directions from a 25 m guess.
    @State private var gpsStartedAt = Date()
    @Environment(\.scenePhase) private var phase
    private var requiresVerifiedStepFreeRoute: Bool { settings.preferences.avoidStairs && !standardWalkingAllowed }
    private var usesGoogle: Bool { useGoogle && GoogleWalkingNavigation.hasKey }
    private var hasOutdoorRoute: Bool { usesGoogle ? google.active : route != nil }
    private var outdoorArrivalReady: Bool {
        guard started, !arrived, !insideBuilding, !presented else { return false }
        let fix = usesGoogle ? location.location : guidanceFix
        guard let fix else { return false }
        let completed = usesGoogle
            ? google.active && reliableGoogleFix && (google.distanceToDestination ?? .infinity) <= 8
            : walking?.status == .nearDestination
        return DestinationProximity.canConfirmOutdoorArrival(routeComplete: completed,
            distance: fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)),
            accuracy: fix.horizontalAccuracy, age: abs(displayTime.timeIntervalSince(fix.timestamp)))
    }
    private var indoorEntranceNearby: Bool {
        guard indoor != nil, !insideBuilding, !arrived else { return false }
        let fix: CLLocation?
        let remaining: Double?
        if usesGoogle && google.active {
            guard reliableGoogleFix else { return false }
            fix = location.location; remaining = google.distanceToDestination
        } else if let walking, route != nil {
            guard walking.status == .guiding || walking.status == .nearDestination,
                  !walking.wrongWay else { return false }
            fix = guidanceFix; remaining = walking.remainingRouteDistance
        } else {
            fix = location.location; remaining = nil
        }
        guard let fix else { return false }
        // For a saved indoor journey, destination is its recorded entrance pin,
        // not the room's local AR coordinates or the building's search center.
        return DestinationProximity.shouldOfferSavedIndoorRoute(
            distance: fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)),
            accuracy: fix.horizontalAccuracy, age: abs(displayTime.timeIntervalSince(fix.timestamp)),
            remainingRouteDistance: remaining)
    }
    private var reliableGoogleFix: Bool {
        guard let fix = location.location else { return false }
        return fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 12 && abs(fix.timestamp.timeIntervalSinceNow) <= 5 && (google.lastUpdate.map { displayTime.timeIntervalSince($0) <= 5 } ?? false)
    }
    private var outdoorGuidanceActive: Bool {
        if usesGoogle { return google.active && reliableGoogleFix && !google.instruction.isEmpty }
        guard walking?.status == .guiding, let guidanceFix else { return false }
        return displayTime.timeIntervalSince(guidanceFix.timestamp) <= 5
    }
    private var outdoorInstruction: String {
        if usesGoogle { return google.instruction }
        if walking?.wrongWay == true { return "Turn around when safe" }
        return walking?.travelInstruction ?? "Continue along the mapped path"
    }
    var body: some View {
        let _ = NavigationPerformance.shared.bodyEvaluated("Outdoor navigation")
        ZStack {
            if automaticallyStart && !showingMap {
                Color.black.ignoresSafeArea()
                SpatialCamera(session: camera).ignoresSafeArea().accessibilityHidden(true)
                    .gesture(DragGesture(minimumDistance: 35).onEnded { value in
                        if value.translation.width > abs(value.translation.height) { showingMap = true }
                    })
            }
            VStack(spacing: 0) {
                if automaticallyStart {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").frame(width: 48, height: 48)
                                .background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("End directions")
                        Spacer()
                        Menu {
                            Button(showingMap ? "Camera" : "Map", systemImage: showingMap ? "camera" : "map") { showingMap.toggle() }
                            Button("Accessibility", systemImage: "accessibility") { accessibility = true }
                                .accessibilityIdentifier("cameraNavigationAccessibility")
                            Button("Read a sign", systemImage: "text.viewfinder", action: readSign)
                            Button(settings.allSoundMuted ? "Unmute" : "Mute", systemImage: settings.allSoundMuted ? "speaker.wave.2" : "speaker.slash") {
                                settings.allSoundMuted.toggle()
                            }
                            Button("I’m already inside", action: confirmInside)
                            if UserDefaults.standard.bool(forKey: "agentDeveloperMode") {
                                ShareLink("Export timing", item: NavigationPerformance.shared.lines.joined(separator: "\n"))
                            }
                        } label: {
                            Image(systemName: "ellipsis").frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                        }.accessibilityLabel("Navigation options")
                    }.padding()
                    if !showingMap, !insideBuilding, outdoorGuidanceActive {
                        DirectionBadge(instruction: outdoorInstruction, reliable: true, proximity: approach.trend)
                    }
                }
                if !automaticallyStart || showingMap {
            outdoorMap
                } else { Spacer(minLength: 30) }
            CameraGuidancePanel(maxHeight: insideBuilding ? 420 : automaticallyStart && !showingMap ? 310 : 380) {
            VStack(alignment: .leading, spacing: 12) {
                if let awarenessMessage { Label(awarenessMessage, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Color.indoorTeal).fixedSize(horizontal: false, vertical: true) }
                if let signText { Text(signText).font(.subheadline).accessibilityIdentifier("navigationSignText") }
                if !automaticallyStart || showingMap || insideBuilding {
                    Text(indoor?.route.room.label ?? destination.name ?? "Destination").font(.headline)
                }
                if let indoor {
                    if showingMap { Text("Via \(indoor.route.entrance.label)").font(.caption).foregroundStyle(.secondary) }
                    if handoffAttempted && !presented && !indoorEntranceNearby {
                        Button("Open indoor guidance", action: openIndoorGuidance)
                    }
                }
                if insideBuilding {
                    Text("Which room?").font(.headline)
                    TextField("Room number, for example 005", text: $roomQuery)
                        .textFieldStyle(.roundedBorder).submitLabel(.go).onSubmit(openRoom)
                        .accessibilityIdentifier("buildingRoomSearch")
                    Button("Find room", action: openRoom).buttonStyle(.borderedProminent)
                    HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 64) { text in roomQuery = text; openRoom() }
                    Text("Choose a saved route, or record and publish a new one.").font(.footnote)
                    if let error { Text(error).font(.footnote) }
                } else if nearBuilding && !continueOutside && !hasOutdoorRoute {
                    Text("You’re near this destination").font(.headline)
                    Text("Already inside?")
                    Button("Yes, I’m inside", action: confirmInside).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button("No, show outdoor directions") { continueOutside = true; Task { await calculate(force: true) } }.buttonStyle(.bordered)
                    HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 64) { text in
                        let answer = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                        if ["yes", "yes please", "i'm inside", "i’m inside"].contains(answer) { confirmInside() }
                        else if ["no", "outside", "no thanks"].contains(answer) { continueOutside = true; Task { await calculate(force: true) } }
                        else { settings.speak("Say yes if you are inside, or no for outdoor directions.") }
                    }
                } else {
                    if !automaticallyStart {
                        Button("I’m already inside", action: confirmInside).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    }
                if let fallbackNotice { Text(fallbackNotice).font(.caption).foregroundStyle(.secondary) }
                if automaticallyStart && !showingMap {
                    walkingInstruction
                    if let cameraError = camera.error {
                        Text(cameraError).font(.footnote)
                        Button("Try camera again") { Task { await camera.start(navigation: true, outdoorPreview: true) } }
                    }
                }
                if showingMap { walkingInstruction }
                if let route, !automaticallyStart {
                    Text("\(route.distance.formatted(.number.precision(.fractionLength(0)))) m outdoors")
                    Text("Locked walking path · GPS is snapped to this route. Step-free access has not been verified").font(.footnote).foregroundStyle(.secondary)
                    if settings.preferences.avoidStairs {
                        Text("Your no-stairs constraint applies to reviewed indoor paths. This outdoor route cannot be confirmed step-free.").font(.footnote)
                    }
                    DisclosureGroup("Outdoor directions") {
                        ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                            if !step.instructions.isEmpty { Text(step.instructions).padding(.vertical, 4) }
                        }
                    }
                }
                if !started {
                    Button(requiresVerifiedStepFreeRoute ? "Locate the destination" : indoor == nil ? "Show walking route" : "Begin journey") { started = true; gpsStartedAt = Date(); location.start() }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44)
                } else if requiresVerifiedStepFreeRoute {
                    Text("Standard walking routes may include stairs.").font(.caption).foregroundStyle(Color.indoorCameraCaption)
                } else if !hasOutdoorRoute && !indoorEntranceNearby && error == nil && google.error == nil {
                    if location.manager.authorizationStatus == .denied || location.manager.authorizationStatus == .restricted {
                        Text("Location permission is off.").font(.subheadline)
                        Button("Open location settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }.frame(minHeight: 44)
                    } else {
                        ProgressView {
                            Text(location.location == nil ? location.message : (location.location?.horizontalAccuracy ?? 99) > 15 ? "Getting a precise GPS fix…" : "Finding route…")
                                .font(.caption).foregroundStyle(Color.indoorCameraCaption)
                        }.tint(Color.indoorTeal)
                    }
                }
                if let message = usesGoogle ? google.error : error {
                    Text(message).foregroundStyle(.secondary)
                    Button("Try again") { self.error = nil; google.stop(); Task { await calculate(force: true) } }
                    if !usesGoogle && route == nil && GoogleWalkingNavigation.hasKey {
                        Button("Try Google directions") {
                            directions?.cancel(); directions = nil; nextRouteRetry = .distantFuture
                            error = nil; fallbackNotice = nil; useGoogle = true
                            Task { await calculate(force: true) }
                        }
                    }
                }
                if indoor != nil && !hasOutdoorRoute && !indoorEntranceNearby { Text("At the entrance, match your saved indoor map.").font(.caption).foregroundStyle(.secondary) }
                }
            }
            }.padding(.horizontal, automaticallyStart ? 16 : 0)
                .padding(.bottom, 8)
            if automaticallyStart && !showingMap {
                HStack { Spacer(); CameraReadSignButton(busy: readingSign, action: readSign) }
                    .padding(.horizontal, 18).padding(.bottom, 8)
            }
            }
        }.overlay {
            if arrived { arrivalScreen }
            VoiceEdgeGlow(active: roomVoice.listening)
        }.navigationTitle("Directions").navigationBarTitleDisplayMode(.inline)
            .toolbar(automaticallyStart ? .hidden : .visible, for: .navigationBar)
            .task(id: presented) {
                if automaticallyStart && !showingMap && !presented && !arrived && roomRequest == nil && roomTarget == nil { await camera.start(navigation: true, outdoorPreview: true) }
            }
            .onChange(of: showingMap) { _, map in
                if map { camera.stop(); awarenessMessage = nil; awarenessUntil = .distantPast }
                else { Task { await camera.start(navigation: true, outdoorPreview: true) } }
            }
            .onChange(of: google.error) { _, message in
                guard usesGoogle, let message else { return }
                useGoogle = false
                fallbackNotice = "Google unavailable. Using Apple walking directions."
                google.stop(); error = nil
                nextRouteRetry = .distantFuture
                gpsStartedAt = Date().addingTimeInterval(-10)
                Task { await calculate() }
                #if DEBUG
                print("Google navigation: \(message)")
                #endif
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                displayTime = now
                location.updateHeadingOrientation()
                if lastWalkingFix.map({ now.timeIntervalSince($0) > 3 }) ?? true { approach.reset() }
                if now >= awarenessUntil { awarenessMessage = nil }
                if phase == .active, started, !presented, roomRequest == nil, roomTarget == nil,
                   !insideBuilding, !arrived, now >= nextRouteRetry, directions == nil {
                    Task { await calculate() }
                }
                if !insideBuilding, !presented, roomRequest == nil, roomTarget == nil,
                   walking != nil, walking?.status != .locating,
                   let lastWalkingFix, now.timeIntervalSince(lastWalkingFix) > 10 {
                    walking?.pause(); settings.stopSpeech(); speakWalking()
                }
                if phase == .active, !presented, roomRequest == nil, roomTarget == nil { if usesGoogle { speakGoogle() } else { speakWalking() } }
                settings.updateJourneySound(active: started && outdoorGuidanceActive && !arrived && !insideBuilding && !presented &&
                    roomRequest == nil && roomTarget == nil && !roomVoice.busy &&
                    phase == .active && now >= awarenessUntil)
            }
            .onChange(of: location.location) { _, fix in
                guard let fix, started, !arrived else { return }
                // A saved indoor map already knows the room, so skip the "are you inside?" question.
                nearBuilding = indoor == nil && DestinationProximity.shouldOfferIndoorChoice(
                    distance: fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)),
                    accuracy: fix.horizontalAccuracy, age: abs(fix.timestamp.timeIntervalSinceNow))
                guard !insideBuilding else { return }
                recordTrail(fix)
                updateWalking(fix)
                // Show the live GPS fix even while route matching is uncertain.
                // Guidance and arrival continue to use the separately accepted fix.
                if followUser { recenter(on: fix) }
                if nearBuilding && !continueOutside && !hasOutdoorRoute {
                    directions?.cancel(); directions = nil
                    if !announcedNearby {
                        announcedNearby = true
                        settings.speak("You appear to be near \(destination.name ?? "your destination"). Are you already inside?", force: true)
                    }
                    return
                }
                if !requiresVerifiedStepFreeRoute && !hasOutdoorRoute && directions == nil && error == nil && google.error == nil { Task { await calculate() } }
                if let indoor, fix.horizontalAccuracy <= 20,
                   fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)) <= 100 {
                    preloadIndoorMap(indoor)
                }
            }
            .onChange(of: indoorEntranceNearby) { _, nearby in
                guard nearby, !announcedIndoorEntrance, !presented, phase == .active else { return }
                announcedIndoorEntrance = true
                settings.stopSpeech()
                settings.speak("Near the entrance. Your saved indoor route is ready. Tap Continue indoors to match your position.", force: true)
            }
            .onChange(of: outdoorArrivalReady) { _, ready in
                if ready { finishOutdoorArrival() }
            }
            .fullScreenCover(isPresented: $presented, onDismiss: {
                // Keep the outdoor route and destination when the indoor camera
                // cannot localize or the user returns to the GPS screen.
                if phase == .active && !arrived { started = true; location.start(); resumeCamera() }
            }) {
                if let indoor { HallwayLaunchView(route: indoor.route, draft: indoor.draft, library: indoor.library, settings: settings, approachDistance: approachDistance, preloadedWorldMap: preloadedIndoorMap) }
            }
            .sheet(item: $roomRequest, onDismiss: resumeCamera) { request in
                RecordDestinationView(settings: settings, request: request, alreadyInside: insideBuilding, buildingDestination: destination, resumeDirections: {
                    insideBuilding = false
                    continueOutside = true
                    roomRequest = nil
                })
            }
            .fullScreenCover(item: $roomTarget, onDismiss: resumeCamera) { target in
                HallwayLaunchView(route: target.route, draft: target.draft, library: target.library, settings: settings)
            }
            .sheet(isPresented: $accessibility) { NavigationAccessibilitySheet(store: settings) }
            .onAppear {
                camera.onPostureAlert = { _ in }
                camera.onSafetyAlert = { text in
                    // Camera posture affects camera sensing, not GPS walking directions.
                    guard camera.postureIssue == nil else { return }
                    announceAwareness(text, urgent: true)
                }
                camera.onObjectAlert = { text in announceAwareness(text) }
                camera.onSurfaceAlert = { distance in
                    guard UserDefaults.standard.bool(forKey: "depthAdvisories") else { return }
                    announceAwareness("Possible surface ahead, about " + LiveGuidance.distance(distance, feet: feet) + ". Pause and check your surroundings.")
                }
                if let initialRoom, roomQuery.isEmpty { roomQuery = initialRoom }; if automaticallyStart { started = true; gpsStartedAt = Date(); location.start() } }
            .onDisappear { signTask?.cancel(); signTask = nil; readingSign = false; settings.updateJourneySound(active: false); camera.stop(); location.stop(); directions?.cancel(); directions = nil; google.stop() }
            .onChange(of: phase) { _, value in
                if value == .background {
                    settings.updateJourneySound(active: false); trail.interrupt(); walking?.pause()
                    google.stop(); settings.stopSpeech(); camera.stop(); location.stop()
                    directions?.cancel(); directions = nil; started = false
                } else if value == .inactive {
                    // Temporary system overlays must not discard the GPS route or
                    // cancel Google's terms and route requests.
                    settings.updateJourneySound(active: false)
                } else if value == .active && !started && automaticallyStart && !arrived && !presented && roomRequest == nil && roomTarget == nil {
                    started = true; gpsStartedAt = Date(); location.start()
                    if !showingMap { Task { await camera.start(navigation: true, outdoorPreview: true) } }
                }
            }
    }
    @ViewBuilder private var outdoorMap: some View {
        if usesGoogle, let session = google.session {
            GoogleWalkingMap(session: session)
        } else {
        Map(position: $mapPosition, interactionModes: [.pan, .zoom]) {
            if let fix = location.location, abs(fix.timestamp.timeIntervalSinceNow) < 10 {
                if fix.horizontalAccuracy > 0 && fix.horizontalAccuracy <= 100 {
                    MapCircle(center: fix.coordinate, radius: fix.horizontalAccuracy)
                        .foregroundStyle(Color.blue.opacity(0.12))
                }
                Annotation("You", coordinate: fix.coordinate) {
                    if fix.speed >= 0.7, fix.course >= 0, fix.courseAccuracy >= 0, fix.courseAccuracy <= 25 {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 23, weight: .bold))
                            .foregroundStyle(.blue)
                            .rotationEffect(.degrees(fix.course))
                            .padding(5).background(.white, in: Circle())
                    } else {
                        Circle().fill(.blue).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(.white, lineWidth: 3))
                    }
                }
            }
            Marker(destination.name ?? "Destination", coordinate: destination.placemark.coordinate)
            if let route { MapPolyline(route.polyline).stroke(Color.indoorTeal, lineWidth: 6) }
            if let origin = trailOrigin {
                ForEach(Array(trail.segments.enumerated()), id: \.offset) { _, segment in
                    if segment.count >= 2 {
                        MapPolyline(coordinates: segment.map { MKMapPoint(x: origin.x + $0.x / trailScale, y: origin.y + $0.y / trailScale).coordinate })
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 7]))
                    }
                }
            }
        }.onMapCameraChange(frequency: .continuous) { _ in
            if mapPosition.positionedByUser { followUser = false }
        }
        .mapControls { MapCompass() }
        .overlay(alignment: .topTrailing) {
            VStack {
                Button("Recenter", systemImage: "location.fill") {
                    followUser = true
                    if let fix = location.location { recenter(on: fix) }
                }.buttonStyle(.borderedProminent)
                if let route {
                    Button("Overview", systemImage: "map") {
                        followUser = false
                        let bounds = route.polyline.boundingMapRect
                        mapPosition = .rect(bounds.insetBy(dx: -bounds.size.width * 0.2 - 100, dy: -bounds.size.height * 0.2 - 100))
                    }.buttonStyle(.bordered)
                }
            }.labelStyle(.iconOnly).padding()
        }
            .overlay(alignment: .bottomLeading) {
                if trail.segments.contains(where: { $0.count >= 2 }) {
                    Text("Orange dots: approximate walked path").font(.caption2)
                        .padding(8).background(.regularMaterial, in: Capsule()).padding(8).allowsHitTesting(false)
                }
            }
    }
    }
    private func preloadIndoorMap(_ target: IndoorJourneyTarget) {
        guard !preloadingIndoorMap, preloadedIndoorMap == nil else { return }
        preloadingIndoorMap = true
        let url = target.library.directory(target.draft.id).appending(path: "world.arworldmap")
        let cache = target.library.navigationWorldMapCache(target.draft.id)
        Task {
            let map = await Task.detached(priority: .utility) { () -> ARWorldMap? in
                try? NavigationWorldMapArchive.load(sourceURL: url, cacheURL: cache)
            }.value
            if indoor?.id == target.id { preloadedIndoorMap = map }
            preloadingIndoorMap = false
        }
    }
    private func openIndoorGuidance() {
        guard let indoor, arrived || indoorEntranceNearby || handoffAttempted else { return }
        if let fix = location.location {
            approachDistance = fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude))
        }
        preloadIndoorMap(indoor)
        handoffAttempted = true
        directions?.cancel(); directions = nil; nextRouteRetry = .distantFuture
        settings.stopSpeech(); settings.updateJourneySound(active: false)
        google.stop(); camera.stop(); presented = true
    }
    private func finishOutdoorArrival() {
        guard !arrived else { return }
        if let fix = guidanceFix ?? location.location {
            approachDistance = fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude))
        }
        arrived = true
        directions?.cancel(); directions = nil; nextRouteRetry = .distantFuture
        settings.updateJourneySound(active: false)
        google.stop(); camera.stop(); location.stop(); settings.stopSpeech()
        let place = destination.name ?? "your destination"
        settings.speak(indoor == nil ? "You’ve arrived at \(place)." : "You’ve arrived at the entrance to \(place). Your indoor route is ready.", force: true)
        settings.cue(.arrived)
    }
    private func recenter(on fix: CLLocation) {
        guard fix.horizontalAccuracy >= 0, abs(fix.timestamp.timeIntervalSinceNow) < 10 else { return }
        mapPosition = .region(MKCoordinateRegion(center: fix.coordinate, latitudinalMeters: 180, longitudinalMeters: 180))
    }
    private func recordTrail(_ fix: CLLocation) {
        guard phase == .active, !arrived, !presented, roomRequest == nil, roomTarget == nil else { trail.interrupt(); return }
        let point = MKMapPoint(fix.coordinate)
        if trailOrigin == nil, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 20 {
            trailOrigin = point; trailScale = MKMetersPerMapPointAtLatitude(fix.coordinate.latitude)
        }
        guard let origin = trailOrigin else { return }
        trail.update(.init((point.x-origin.x)*trailScale, (point.y-origin.y)*trailScale), accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970)
    }
    private var arrivalScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "mappin.circle.fill").font(.system(size: 72)).foregroundStyle(Color.indoorTeal)
            Text("You’ve arrived").font(.largeTitle.bold())
            Text(destination.name ?? "Your destination").font(.title2).multilineTextAlignment(.center)
            Text(destination.placemark.title ?? "").foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let indoor {
                Text("Continue to \(indoor.route.room.label)").font(.headline)
                Button("Continue indoors", action: openIndoorGuidance)
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("continueSavedIndoorRoute")
            } else {
                Button("Find a room") { arrived = false; confirmInside() }.buttonStyle(.borderedProminent)
            }
            Button("Done") { dismiss() }.buttonStyle(.bordered)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.indoorBackground.ignoresSafeArea())
    }
    private var destinationDistanceText: String? {
        if usesGoogle {
            guard google.active, reliableGoogleFix, let distance = google.distanceToDestination else { return nil }
            return "About \(Int((distance * 3.28084 / 5).rounded() * 5)) ft along route"
        }
        guard let walking, walking.status == .guiding || walking.status == .nearDestination,
              let fix = guidanceFix, displayTime.timeIntervalSince(fix.timestamp) <= 5 else { return nil }
        let feet = max(0, (walking.remainingRouteDistance * 3.28084 / 5).rounded() * 5)
        return "About \(Int(feet)) ft along route"
    }
    private var walkingInstruction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outdoor guidance · GPS").font(.caption).foregroundStyle(Color.indoorCameraCaption)
                .accessibilityIdentifier("outdoorRoutingProvider")
                .accessibilityValue(usesGoogle ? "Google walking directions" : "Apple walking directions")
            if let destinationDistanceText { Text(destinationDistanceText).font(.headline).monospacedDigit() }
            if showingMap, let heading = location.heading, abs(displayTime.timeIntervalSince(heading.timestamp)) <= 3 {
                let degrees = heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
                let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
                Label("Phone facing " + labels[Int((degrees + 22.5) / 45) % 8], systemImage: "location.north.line")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let fix = location.location, fix.horizontalAccuracy > 12 {
                Text("GPS is approximate. Check the map.").font(.caption).foregroundStyle(.secondary)
            }
            if indoorEntranceNearby {
                Text("You’re near the entrance").font(.headline)
                Button("Continue indoors", action: openIndoorGuidance)
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("continueSavedIndoorRoute")
                Text("Match your position to the saved indoor map.").font(.subheadline)
            } else if requiresVerifiedStepFreeRoute {
                Label("Step-free route unavailable", systemImage: "figure.roll").font(.headline)
                Button("View standard walking route") {
                    standardWalkingAllowed = true
                    Task { await calculate(force: true) }
                }.buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("standardOutdoorRoute")
            } else if usesGoogle {
                if !reliableGoogleFix {
                    Label("GPS uncertain. Check the map.", systemImage: "location.slash").font(.headline)
                } else if google.active && !google.instruction.isEmpty {
                    Label(google.instruction, systemImage: walkingSymbol(google.instruction)).font(.title3.bold()).accessibilityIdentifier("outdoorLiveInstruction")
                    if let distance = google.distanceToTurn { Text("Next turn in about \(Int((distance * 3.28084 / 5).rounded() * 5)) ft").font(.subheadline) }
                } else { Text("Finding your walking route…").font(.headline) }
                if google.active, reliableGoogleFix, let distance = google.distanceToDestination, distance <= 20, let fix = location.location, fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)) + fix.horizontalAccuracy <= 30 {
                    Text("Near your destination—check the entrance.").font(.headline)
                    if indoor == nil { Button("I’m here", action: finishOutdoorArrival).buttonStyle(.borderedProminent) }
                }
            } else if let walking {
                switch walking.status {
                case .locating:
                    Label("GPS uncertain. Check the map.", systemImage: "location.slash").font(.headline)
                case .offRoute:
                    Text("You may be off the route; check the map.").font(.headline)
                    Button("Find a new route") { settings.stopSpeech(); Task { await calculate(force: true) } }.buttonStyle(.borderedProminent)
                case .nearDestination:
                    Text("Near your destination—check the entrance.").font(.headline)
                    Button("I’m here", action: finishOutdoorArrival).buttonStyle(.borderedProminent)
                case .guiding:
                    Label(walking.wrongWay ? "You may be going the wrong way. Turn around when safe." : walking.travelInstruction.isEmpty ? "Continue along the mapped path" : walking.travelInstruction, systemImage: walking.wrongWay ? "arrow.uturn.backward" : walkingSymbol(walking.travelInstruction))
                        .font(.title3.bold()).accessibilityIdentifier("outdoorLiveInstruction")
                    if !walking.wrongWay { Text(walking.upcomingDetail(feet: true)).font(.subheadline) }
                    if !walking.wrongWay, let next = walking.nextInstruction, !next.isEmpty { Text("Then: " + next).font(.subheadline) }
                }
            } else { Text("Finding your walking route…").font(.headline) }
            if !showingMap && camera.postureIssue != nil { Text("Raise the camera for obstacle sensing.").font(.caption).foregroundStyle(.secondary) }
            CameraGuidanceActions(showingMap: showingMap, repeatGuidance: repeatOutdoorGuidance, toggleMap: { showingMap.toggle() }) {
                HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 44, compact: true, result: handleWalkingVoice)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func repeatOutdoorGuidance() {
        if indoorEntranceNearby { settings.speak("Near the entrance. Tap Continue indoors to match your saved route.", force: true) }
        else if requiresVerifiedStepFreeRoute { settings.speak("A step-free outdoor route is unavailable. Standard walking directions may include stairs.", force: true) }
        else if usesGoogle && google.active { speakGoogle(force: true) }
        else if walking != nil { speakWalking(force: true) }
        else { settings.speak("Finding your walking route. Check your connection and location.", force: true) }
    }
    private func readSign() {
        guard !readingSign else { return }
        roomVoice.cancel(); settings.stopSpeech()
        guard !showingMap, let frame = camera.scene.session.currentFrame,
              ProcessInfo.processInfo.systemUptime - frame.timestamp < 0.8 else {
            signText = "Open the camera and point at a sign."
            settings.speak(signText!, force: true); return
        }
        readingSign = true
        signTask = Task {
            let evidence = await AgentSceneObservation.read(frame)
            defer { readingSign = false }
            guard !Task.isCancelled else { return }
            guard phase == .active, !presented, !insideBuilding,
                  AgentSceneObservation.isFresh(frame, current: camera.scene.session.currentFrame) else {
                signText = "Hold the camera steady and try again."
                settings.speak(signText!, force: true); return
            }
            signText = evidence["recognizedText"] ?? "No readable text found."
            settings.speak(signText!, force: true)
        }
    }
    private func announceAwareness(_ text: String, urgent: Bool = false) {
        guard !showingMap, !roomVoice.busy, phase == .active, !presented, roomRequest == nil, roomTarget == nil, urgent || Date() >= awarenessUntil else { return }
        // Camera evidence is advisory outdoors; it never changes GPS progress or arrival.
        // Safety speech remains prioritized by the audio queue, without latching GPS off.
        let now = Date()
        guard text != lastAwarenessText || now.timeIntervalSince(lastAwarenessSpeech) >= 30 else { return }
        lastAwarenessText = text; lastAwarenessSpeech = now
        awarenessMessage = text; awarenessUntil = now.addingTimeInterval(6)
        settings.speak(text, priority: .safety); settings.cue(.attention)
    }
    private func handleWalkingVoice(_ text: String) {
        let value = text.lowercased()
        if ["stop", "stop guidance", "end directions", "cancel"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) {
            settings.stopSpeech(); dismiss()
        } else if (indoorEntranceNearby || arrived && indoor != nil) && ["continue indoors", "start indoor route", "indoor route"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))) {
            openIndoorGuidance()
        } else if value.contains("read"), value.contains("sign") {
            readSign()
        } else if value.contains("lost") || value.contains("help") || value.contains("where am") {
            showingMap = true
            settings.speak(walking?.status == .guiding
                ? "Your route is on the map. " + (walking?.wrongWay == true ? "You may be going the wrong way. Turn around when safe." : walking?.travelInstruction ?? "Check your surroundings.")
                : "Let’s check the map. I need a reliable GPS position before giving directions.", priority: .safety)
        } else if value.contains("repeat") { if usesGoogle { speakGoogle(force: true) } else { speakWalking(force: true) } }
        else if value.contains("inside") { confirmInside() }
        else if value.contains("another way") || value.contains("new route") || value.contains("recalculate") {
            Task { await calculate(force: true) }
        } else if value.contains("camera") { showingMap = false }
        else if value.contains("map") { showingMap = true }
        else if RoomMappingRequest.resolve(text, selectedBuilding: buildingName) != nil {
            roomQuery = text; openRoom()
        }
        else { settings.speak("Do you want the map, new directions, or a room inside?") }
    }
    private func walkingSymbol(_ instruction: String) -> String {
        let value = instruction.lowercased()
        if value.contains("left") { return "arrow.turn.up.left" }
        if value.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
    private func installWalking(_ route: MKRoute) {
        guard route.polyline.pointCount > 0 else { walking = nil; return }
        let origin = route.polyline.points()[0]
        walkingOrigin = origin; walkingScale = MKMetersPerMapPointAtLatitude(origin.coordinate.latitude)
        let legs = route.steps.compactMap { step -> OutdoorProgress.Leg? in
            guard step.polyline.pointCount >= 2 else { return nil }
            let points = (0..<step.polyline.pointCount).map { i in
                let p = step.polyline.points()[i]
                return OutdoorProgress.Point((p.x-origin.x)*walkingScale, (p.y-origin.y)*walkingScale)
            }
            return OutdoorProgress.Leg(instruction: step.instructions, points: points)
        }
        walking = OutdoorProgress(legs: legs); guidanceFix = nil; lastWalkingFix = nil; approach.reset(); spokenWalking = ""
        if let fix = location.location { updateWalking(fix) }
    }
    private func updateWalking(_ fix: CLLocation) {
        let began = ProcessInfo.processInfo.systemUptime
        NavigationPerformance.shared.record("GPS capture → SwiftUI update ms", max(0, -fix.timestamp.timeIntervalSinceNow)*1000)
        defer { NavigationPerformance.shared.record("Outdoor progress processing ms", (ProcessInfo.processInfo.systemUptime-began)*1000) }
        guard let origin = walkingOrigin, walking != nil else { return }
        let p = MKMapPoint(fix.coordinate)
        walking?.update(.init((p.x-origin.x)*walkingScale, (p.y-origin.y)*walkingScale), accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970, course: fix.speed >= 0.7 && fix.courseAccuracy >= 0 && fix.courseAccuracy <= 25 ? fix.course : nil)
        if walking?.acceptedTimestamp == fix.timestamp.timeIntervalSince1970,
           walking?.status == .guiding || walking?.status == .nearDestination {
            lastWalkingFix = fix.timestamp; guidanceFix = fix
        }
        if let walking, walking.status == .guiding {
            approach.update(distance: walking.remainingRouteDistance, accuracy: fix.horizontalAccuracy,
                            timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970)
        } else { approach.reset() }
        if walking?.shouldReplaceRoute() == true, Date().timeIntervalSince(lastReplan) > 45, directions == nil, fix.horizontalAccuracy <= 12 {
            lastReplan = Date()
            settings.speak("Checking a new walking route.", priority: .direction)
            Task { await calculate(force: true) }
        }
        speakWalking()
        let canTick = walking?.status == .guiding && walking?.wrongWay == false &&
            fix.horizontalAccuracy <= 12 && fix.speed >= 0.5 && !roomVoice.busy &&
            phase == .active && !presented && roomRequest == nil && roomTarget == nil &&
            !insideBuilding && !arrived && Date() >= awarenessUntil
        settings.travelFeedback(position: canTick ? SIMD2((p.x-origin.x)*walkingScale, (p.y-origin.y)*walkingScale) : nil, context: "outdoor")
    }
    private func speakWalking(force: Bool = false) {
        guard let walking, !insideBuilding, !arrived, !roomVoice.busy, phase == .active, !presented, roomRequest == nil, roomTarget == nil else { return }
        if indoorEntranceNearby {
            if force { settings.speak("Near the entrance. Tap Continue indoors to match your saved route.", force: true) }
            return
        }
        let text: String
        switch walking.status {
        case .locating: text = "GPS uncertain. Check the map."
        case .offRoute: text = "You may be off the route. Check the map or find a new route."
        case .nearDestination: text = "Near your destination. Check the entrance."
        case .guiding: text = walking.wrongWay ? "You may be going the wrong way. Turn around when safe." : (walking.travelInstruction.isEmpty ? "Follow the mapped path." : walking.travelInstruction) + ". " + walking.upcomingDetail(feet: true) + "."
        }
        let key = "\(walking.index)-\(walking.status)-\(walking.wrongWay)-\(walking.travelledOnLeg > 3)-\(walking.announcementBand)"
        let reminder = walking.status == .guiding && Date().timeIntervalSince(lastWalkingAnnouncement) >= 12
        let newLeg = !spokenWalking.isEmpty && !spokenWalking.hasPrefix("\(walking.index)-")
        if force || (spokenWalking != key && (newLeg || walking.status != .guiding || walking.wrongWay || Date().timeIntervalSince(lastWalkingAnnouncement) >= 3)) || reminder {
            spokenWalking = key; lastWalkingAnnouncement = Date()
            settings.speak(text, priority: walking.status == .guiding ? .direction : .safety, positionTime: lastWalkingFix.map { ProcessInfo.processInfo.systemUptime + $0.timeIntervalSinceNow })
            settings.cue(walking.status == .guiding && !walking.wrongWay ? (newLeg ? .turn : .approach) : .attention, instruction: text)
        }
    }
    private func speakGoogle(force: Bool = false) {
        guard google.active, !insideBuilding, !arrived, !roomVoice.busy, phase == .active, !presented else { return }
        if indoorEntranceNearby {
            if force { settings.speak("Near the entrance. Tap Continue indoors to match your saved route.", force: true) }
            return
        }
        let reliable = reliableGoogleFix && !google.instruction.isEmpty
        let distance = google.distanceToTurn ?? .infinity
        let band = distance <= 5 ? "now" : distance <= 15 ? "near" : "ahead"
        let text = reliable ? google.instruction + (distance.isFinite && distance > 5 ? ". In about \(Int((distance * 3.28084 / 5).rounded() * 5)) feet." : ".") : "GPS uncertain. Check the map."
        let announcement = reliable ? google.instruction + band : "uncertain"
        guard force || (announcement != lastGoogleSpeech && Date().timeIntervalSince(lastGoogleSpeechAt) >= 3) else { return }
        lastGoogleSpeech = announcement; lastGoogleSpeechAt = Date()
        settings.speak(text, priority: reliableGoogleFix ? .direction : .safety)
    }
    private func confirmInside() {
        google.stop()
        insideBuilding = true; directions?.cancel(); directions = nil; route = nil; walking = nil; settings.stopSpeech(); error = nil
        if !roomQuery.isEmpty { openRoom() } else { settings.speak("Which room would you like to go to?") }
    }
    private var buildingName: String {
        let name = destination.name ?? "Selected building"
        return name.lowercased().contains("friend") && name.lowercased().contains("center") ? FriendCenter.name : name
    }
    private func resumeCamera() {
        if automaticallyStart && !showingMap && !presented { Task { await camera.start(navigation: true, outdoorPreview: true) } }
    }
    private func openRoom() {
        guard let request = RoomMappingRequest.resolve(roomQuery, selectedBuilding: buildingName) else {
            error = "Please give one room number in this building."; return
        }
        guard request.building.caseInsensitiveCompare(buildingName) == .orderedSame else {
            error = "This is \(buildingName). Choose the other destination on Home first."; return
        }
        roomLibrary.reload(); roomMemory.refresh(from: roomLibrary)
        let saved = DestinationSearch.matches("Room " + request.room, in: roomMemory.preferredDestinations.filter { $0.building == request.building })
        do {
            if let choice = saved.first, let draft = roomLibrary.scans.first(where: { $0.id == choice.scanID }) {
                guard let route = try roomLibrary.hallway(draft) else { throw MapError.invalid("The saved route is unavailable.") }
                guard roomLibrary.visitorReady(route), try roomLibrary.navigationStore(route).blockedEdges.isEmpty else {
                    throw MapError.invalid("This route needs review or has a reported closure.")
                }
                camera.stop(); roomTarget = IndoorJourneyTarget(route: route, draft: draft, library: roomLibrary)
            } else { camera.stop(); roomRequest = request }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func calculate(force: Bool = false) async {
        if usesGoogle {
            guard started, !arrived, !insideBuilding, !requiresVerifiedStepFreeRoute, location.location != nil else { return }
            if force { google.stop() }
            guard google.error == nil else { return }
            google.start(destination: destination.placemark.coordinate, title: destination.name ?? "Destination")
            return
        }
        // First route: wait up to ~10 s for a ≤15 m fix, then accept ≤30 m.
        // Re-routes need a good fix so a drifting position can't send you around the block.
        let settling = route == nil && Date().timeIntervalSince(gpsStartedAt) < 10
        let required: Double = route != nil ? 15 : settling ? 15 : 30
        guard !arrived, !insideBuilding, directions == nil, (!nearBuilding || continueOutside || route != nil), !requiresVerifiedStepFreeRoute, let fix = location.location, fix.horizontalAccuracy <= required, abs(fix.timestamp.timeIntervalSinceNow) <= 10 else { return }
        if !force, route != nil, walking?.shouldReplaceRoute() != true {
            error = nil
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: fix.coordinate))
        request.destination = destination; request.transportType = .walking
        let task = MKDirections(request: request); directions = task
        nextRouteRetry = .distantFuture
        do {
            let response = try await task.calculate()
            guard directions === task else { return }
            if let refreshed = response.routes.first {
                route = refreshed
                installWalking(refreshed)
                if followUser { recenter(on: fix) }
                error = nil; routeRetryDelay = 5
            } else {
                // Keep a loaded route when a refresh returns no alternative.
                error = "No new walking route found."
            }
        } catch {
            guard directions === task else { return }
            if !Task.isCancelled {
                self.error = route == nil ? "Waiting for maps. Retrying…" : "Using saved directions. Retrying maps…"
                nextRouteRetry = Date().addingTimeInterval(routeRetryDelay)
                routeRetryDelay = min(60, routeRetryDelay * 2)
            }
        }
        if directions === task { directions = nil }
    }
}

struct IndoorJourneyTarget: Identifiable {
    var id: UUID { route.id }
    let route: HallwayRoute
    let draft: ScanDraft
    let library: ScanLibrary
}

extension ScanLibrary {
    func navigationTarget(_ destination: JourneyDestination, preferences: Preferences) throws -> IndoorJourneyTarget {
        guard let draft = scans.first(where: { $0.id == destination.scanID }),
              let route = try hallway(draft), route.id == destination.routeID,
              route.scanID == destination.scanID, visitorReady(route) else {
            throw MapError.invalid("This saved room is unavailable. Open its recording in Routes.")
        }
        let state = try navigationStore(route)
        _ = try VerifiedNavigationTools.calculateRoute(in: route.building, start: "entrance", destination: "room",
            preferences: preferences, blocked: state.blockedEdges)
        return IndoorJourneyTarget(route: route, draft: draft, library: self)
    }
}


struct NativeDestinationSearchView: View {
    let query: String
    @ObservedObject var settings: AppStore
    @StateObject private var search = OutdoorSearch()
    @StateObject private var nearby = OutdoorLocation()
    @State private var text = ""
    var body: some View {
        List {
            Section {
                TextField("Building or address", text: $text).submitLabel(.search)
                    .onSubmit { find() }
                Button("Search", action: find).disabled(search.loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if search.loading { ProgressView("Finding building…") }
            if search.error != nil {
                Text("Couldn’t search right now. Check your connection and try again.").font(.subheadline)
            } else if !search.loading && search.results.isEmpty {
                Text("Check the building name or add its city.").foregroundStyle(.secondary)
            }
            Section("Choose your building") {
                ForEach(Array(search.results.enumerated()), id: \.offset) { _, item in
                    NavigationLink { OutdoorRouteView(destination: item, settings: settings, automaticallyStart: true) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name ?? "Destination").font(.headline)
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
        }.navigationTitle("Find building").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(Color.indoorBackground).tint(.indoorTeal)
            .task {
                text = query == FriendCenter.name ? "Friend Center Princeton University" : query
                nearby.start(); find()
            }
            .onDisappear { nearby.stop(); search.cancel() }
            .onChange(of: nearby.location) { _, fix in search.nearby = fix }
    }
    private func find() { Task { search.nearby = nearby.location; await search.search(text) } }
}

/// Provider-backed suggestions; never invents places or room coordinates.
@MainActor final class NearbySuggestions: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    @Published var coordinates: [String: CLLocation] = [:]
    private var enrichment: Task<Void, Never>?
    private var origin: CLLocation?
    static func key(_ result: MKLocalSearchCompletion) -> String { result.title + "\n" + result.subtitle }
    @Published var error: String?
    private var completer: MKLocalSearchCompleter?
    private var lookup: MKLocalSearch?
    func update(_ query: String, near location: CLLocation?) {
        enrichment?.cancel(); origin = location
        completer?.cancel(); completer?.delegate = nil; lookup?.cancel(); lookup = nil
        results = []; error = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { completer = nil; return }
        let next = MKLocalSearchCompleter()
        next.delegate = self; next.resultTypes = [.address, .pointOfInterest]
        next.region = MKCoordinateRegion(center: location?.coordinate ?? CLLocationCoordinate2D(latitude: 40.3487, longitude: -74.6593), latitudinalMeters: 12000, longitudinalMeters: 12000)
        completer = next; next.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard self.completer === completer else { return }
        results = completer.results
        enrichment?.cancel()
        guard origin != nil else { return }
        let candidates = Array(results.prefix(5))
        enrichment = Task {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            for candidate in candidates {
                guard !Task.isCancelled, self.completer === completer else { return }
                let key = Self.key(candidate)
                if coordinates[key] != nil { continue }
                let request = MKLocalSearch(request: MKLocalSearch.Request(completion: candidate))
                let response = try? await withTaskCancellationHandler {
                    try await request.start()
                } onCancel: { request.cancel() }
                guard !Task.isCancelled, self.completer === completer else { return }
                // Ambiguous suggestions have no distance rather than a guessed coordinate.
                if let items = response?.mapItems, items.count == 1, let point = items.first?.placemark.location {
                    if coordinates.count >= 50 { coordinates.removeAll() }
                    coordinates[key] = point
                }
            }
        }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard self.completer === completer else { return }
        results = []; self.error = "Live suggestions are unavailable. You can still search or choose a saved room."
    }
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        lookup?.cancel()
        let request = MKLocalSearch(request: MKLocalSearch.Request(completion: completion)); lookup = request
        do {
            let response = try await request.start()
            guard lookup === request else { return nil }
            lookup = nil
            guard response.mapItems.count == 1 else {
                error = "Choose a more specific address for this place."; return nil
            }
            return response.mapItems.first
        } catch {
            if lookup === request { self.error = "Unable to find this place. Please try again."; lookup = nil }
            return nil
        }
    }
}
