import SwiftUI
import MapKit
import CoreLocation
import IndoorbilityCore

@MainActor final class OutdoorLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var message = "Location is off"
    let manager = CLLocationManager()
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.activityType = .fitness; manager.distanceFilter = kCLDistanceFilterNone; manager.pausesLocationUpdatesAutomatically = false }
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.startUpdatingLocation()
        default: message = "Allow location in iPhone Settings to use outdoor directions."
        }
    }
    func stop() { manager.stopUpdatingLocation(); location = nil }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { manager.startUpdatingLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last, value.horizontalAccuracy >= 0,
              abs(value.timestamp.timeIntervalSinceNow) < 10 else { return }
        location = value; message = "Location updated"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let failure = error as? CLError, failure.code == .locationUnknown { message = "Updating GPS…"; return }
        message = error.localizedDescription; location = nil
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
    @StateObject private var camera = SpatialSession()
    @State private var showingMap = false
    @State private var mapPosition: MapCameraPosition = .automatic
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
    @State private var walkingOrigin: MKMapPoint?
    @State private var walkingScale = 1.0
    @State private var spokenWalking = ""
    @State private var lastWalkingAnnouncement = Date.distantPast
    @State private var lastWalkingFix: Date?
    @AppStorage("guidanceFeet") private var feet = false
    @State private var error: String?
    @State private var directions: MKDirections?
    @State private var presented = false
    @State private var approachDistance: Double?
    @State private var started = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ZStack {
            if automaticallyStart && !showingMap {
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
                    }.padding()
                    if !showingMap, !insideBuilding, !(nearBuilding && !continueOutside && route == nil) {
                        DirectionBadge(instruction: walking?.wrongWay == true ? "Turn around when safe" : walking?.instruction.isEmpty == false ? walking!.travelInstruction : "Continue along the mapped path", reliable: walking?.status == .guiding)
                    }
                }
                if !automaticallyStart || showingMap {
            outdoorMap
                } else { Spacer(minLength: 30) }
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let awarenessMessage { Label(awarenessMessage, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Color.indoorTeal).fixedSize(horizontal: false, vertical: true) }
                Text(indoor?.route.room.label ?? destination.name ?? "Destination").font(.title2.bold())
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                if automaticallyStart && !showingMap && !insideBuilding {
                    outdoorMap.frame(height: 90).clipShape(RoundedRectangle(cornerRadius: 18))
                        .allowsHitTesting(false)
                        .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { showingMap = true }
                            .gesture(DragGesture(minimumDistance: 25).onEnded { value in if abs(value.translation.width) > abs(value.translation.height) { showingMap = true } }) }
                        .accessibilityElement(children: .ignore).accessibilityLabel("Show outdoor map").accessibilityAddTraits(.isButton)
                        .accessibilityAction { showingMap = true }
                }
                if automaticallyStart {
                    Picker("Directions view", selection: $showingMap) { Text("Camera").tag(false); Text("Map").tag(true) }
                        .pickerStyle(.segmented)
                        .simultaneousGesture(DragGesture(minimumDistance: 25).onEnded { value in
                            if abs(value.translation.width) > abs(value.translation.height) { showingMap = value.translation.width > 0 }
                        })
                }
                if let indoor { Text("Via \(indoor.draft.name) · \(indoor.route.entrance.label)").foregroundStyle(.secondary) }
                if insideBuilding {
                    Text("Which room?").font(.headline)
                    TextField("Room number, for example 005", text: $roomQuery)
                        .textFieldStyle(.roundedBorder).submitLabel(.go).onSubmit(openRoom)
                        .accessibilityIdentifier("buildingRoomSearch")
                    Button("Find room", action: openRoom).buttonStyle(.borderedProminent)
                    HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 64) { text in roomQuery = text; openRoom() }
                    Text("Choose a saved route, or record and publish a new one.").font(.footnote)
                    if let error { Text(error).font(.footnote) }
                } else if nearBuilding && !continueOutside && route == nil {
                    Text("You’re near this destination").font(.headline)
                    Text("Are you already inside? Choose a room to use a saved route or record one.")
                    Button("Yes, I’m inside", action: confirmInside).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                    Button("No, show outdoor directions") { continueOutside = true; Task { await calculate() } }.buttonStyle(.bordered)
                    HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 64) { text in
                        let answer = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                        if ["yes", "yes please", "i'm inside", "i’m inside"].contains(answer) { confirmInside() }
                        else if ["no", "outside", "no thanks"].contains(answer) { continueOutside = true; Task { await calculate() } }
                        else { settings.speak("Say yes if you are inside, or no for outdoor directions.") }
                    }
                } else {
                    Button("I’m already inside", action: confirmInside).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
                if automaticallyStart && !showingMap {
                    walkingInstruction
                    if let cameraError = camera.error {
                        Text(cameraError).font(.footnote)
                        Button("Try camera again") { Task { await camera.start(navigation: true) } }
                    }
                }
                if showingMap { walkingInstruction }
                if let route, !automaticallyStart || showingMap {
                    Text("\(route.distance.formatted(.number.precision(.fractionLength(0)))) m outdoors")
                    Text("Apple walking route · step-free access has not been verified").font(.footnote).foregroundStyle(.secondary)
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
                    Button(settings.preferences.avoidStairs ? "Locate the destination" : indoor == nil ? "Show walking route" : "Begin journey") { started = true; location.start() }
                        .buttonStyle(.borderedProminent).frame(minHeight: 44)
                } else if settings.preferences.avoidStairs {
                    Text("No verified step-free outdoor route is available. The map shows the destination only; camera guidance can continue at a reviewed indoor entrance.").font(.subheadline)
                } else if route == nil && error == nil { ProgressView(location.location == nil ? location.message : "Finding route…") }
                if let error { Text(error).foregroundStyle(.secondary); Button("Try again") { self.error = nil; Task { await calculate() } } }
                if indoor != nil { Text("Near the entrance, the camera will try to match your saved map and entrance sign. GPS alone will not start indoor guidance.").font(.footnote).foregroundStyle(.secondary) }
                }
            }.padding(20)
            }.frame(maxHeight: insideBuilding ? 420 : automaticallyStart && !showingMap ? 290 : 380)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: automaticallyStart ? 28 : 0))
                .padding(automaticallyStart ? 16 : 0)
            }
        }.overlay {
            if arrived { arrivalScreen }
            VoiceEdgeGlow(active: roomVoice.listening)
        }.navigationTitle("Directions").navigationBarTitleDisplayMode(.inline)
            .toolbar(automaticallyStart ? .hidden : .visible, for: .navigationBar)
            .task(id: presented) {
                if automaticallyStart && !showingMap && !presented && roomRequest == nil && roomTarget == nil { await camera.start(navigation: true) }
            }
            .onChange(of: showingMap) { _, map in
                if map { camera.stop(); awarenessMessage = nil; awarenessUntil = .distantPast }
                else { Task { await camera.start(navigation: true) } }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
                if now >= awarenessUntil { awarenessMessage = nil }
                if !insideBuilding, !presented, roomRequest == nil, roomTarget == nil,
                   walking != nil, walking?.status != .locating,
                   let lastWalkingFix, now.timeIntervalSince(lastWalkingFix) > 10 {
                    walking?.pause(); settings.stopSpeech(); speakWalking()
                }
                if phase == .active, !presented, roomRequest == nil, roomTarget == nil { speakWalking() }
            }
            .onChange(of: location.location) { _, fix in
                guard let fix, started else { return }
                nearBuilding = DestinationProximity.shouldOfferIndoorChoice(
                    distance: fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude)),
                    accuracy: fix.horizontalAccuracy, age: abs(fix.timestamp.timeIntervalSinceNow))
                guard !insideBuilding else { return }
                recordTrail(fix)
                updateWalking(fix)
                if nearBuilding && !continueOutside && route == nil {
                    directions?.cancel(); directions = nil
                    if !announcedNearby {
                        announcedNearby = true
                        settings.speak("You appear to be near \(destination.name ?? "your destination"). Are you already inside?", force: true)
                    }
                    return
                }
                if !settings.preferences.avoidStairs && route == nil && directions == nil && error == nil { Task { await calculate() } }
                guard indoor != nil, !presented, phase == .active, fix.horizontalAccuracy <= 20 else { return }
                let distance = fix.distance(from: CLLocation(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude))
                if distance < 50 { approachDistance = distance; camera.stop(); presented = true; location.stop() }
            }
            .fullScreenCover(isPresented: $presented, onDismiss: { started = false }) {
                if let indoor { HallwayLaunchView(route: indoor.route, draft: indoor.draft, library: indoor.library, settings: settings, approachDistance: approachDistance) }
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
                if let initialRoom, roomQuery.isEmpty { roomQuery = initialRoom }; if automaticallyStart { started = true; location.start() } }
            .onDisappear { camera.stop(); location.stop(); directions?.cancel(); directions = nil }
            .onChange(of: phase) { _, value in if value != .active { trail.interrupt(); walking?.pause(); settings.stopSpeech(); camera.stop(); location.stop(); directions?.cancel(); directions = nil; started = false } else if automaticallyStart && !arrived && !presented && roomRequest == nil && roomTarget == nil { started = true; location.start(); if !showingMap { Task { await camera.start(navigation: true) } } } }
    }
    private var outdoorMap: some View {
        Map(position: $mapPosition) {
            UserAnnotation()
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
        }.mapControls { MapUserLocationButton(); MapCompass() }
            .overlay(alignment: .bottomLeading) {
                if trail.segments.contains(where: { $0.count >= 2 }) {
                    Text("Orange dots: approximate walked path").font(.caption2)
                        .padding(8).background(.regularMaterial, in: Capsule()).padding(8).allowsHitTesting(false)
                }
            }
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
            Button("Find a room") { arrived = false; confirmInside() }.buttonStyle(.borderedProminent)
            Button("Done") { dismiss() }.buttonStyle(.bordered)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.indoorBackground.ignoresSafeArea())
    }
    private var walkingInstruction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Outdoor guidance · GPS").font(.caption).foregroundStyle(.secondary)
            if let fix = location.location, fix.horizontalAccuracy > 12 {
                Text("GPS is approximate. Check the map.").font(.caption).foregroundStyle(.secondary)
            }
            if let walking {
                switch walking.status {
                case .locating:
                    Label("Waiting for a reliable location", systemImage: "location.slash").font(.headline)
                case .offRoute:
                    Text("You may be off the route; check the map.").font(.headline)
                    Button("Find a new route") { settings.stopSpeech(); Task { await calculate() } }.buttonStyle(.borderedProminent)
                case .nearDestination:
                    Text("Near your destination—check the entrance.").font(.headline)
                    Button("I’m here") { arrived = true; self.walking = nil; camera.stop(); location.stop(); settings.stopSpeech(); settings.speak("You’ve arrived at " + (destination.name ?? "your destination")); settings.cue(.arrived) }.buttonStyle(.borderedProminent)
                case .guiding:
                    Label(walking.wrongWay ? "You may be going the wrong way. Turn around when safe." : walking.travelInstruction.isEmpty ? "Continue along the mapped path" : walking.travelInstruction, systemImage: walking.wrongWay ? "arrow.uturn.backward" : walkingSymbol(walking.travelInstruction))
                        .font(.title3.bold()).accessibilityIdentifier("outdoorLiveInstruction")
                    if !walking.wrongWay { Text(walking.upcomingDetail(feet: feet)).font(.subheadline) }
                    if !walking.wrongWay, let next = walking.nextInstruction, !next.isEmpty { Text("Then: " + next).font(.subheadline) }
                }
                HStack {
                    Button("Repeat guidance") { speakWalking(force: true) }.font(.subheadline)
                    Spacer()
                    HoldToTalk(voice: roomVoice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics, diameter: 52, result: handleWalkingVoice)
                }
                if !roomVoice.transcript.isEmpty { Text(roomVoice.transcript).font(.caption).foregroundStyle(.secondary) }
            } else { Text("Finding your walking route…").font(.headline) }
            if !showingMap && camera.postureIssue != nil { Text("Raise the camera for obstacle sensing. GPS is still active.").font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.indoorPeach.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
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
        if value.contains("lost") || value.contains("help") || value.contains("where am") {
            showingMap = true
            settings.speak(walking?.status == .guiding
                ? "Your route is on the map. " + (walking?.wrongWay == true ? "You may be going the wrong way. Turn around when safe." : walking?.travelInstruction ?? "Check your surroundings.")
                : "Let’s check the map. I need a reliable GPS position before giving directions.", priority: .safety)
        } else if value.contains("repeat") { speakWalking(force: true) }
        else if value.contains("inside") { confirmInside() }
        else if value.contains("another way") || value.contains("new route") || value.contains("recalculate") {
            Task { await calculate() }
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
        walking = OutdoorProgress(legs: legs); spokenWalking = ""
        if let fix = location.location { updateWalking(fix) }
    }
    private func updateWalking(_ fix: CLLocation) {
        guard let origin = walkingOrigin, walking != nil else { return }
        let p = MKMapPoint(fix.coordinate)
        walking?.update(.init((p.x-origin.x)*walkingScale, (p.y-origin.y)*walkingScale), accuracy: fix.horizontalAccuracy, timestamp: fix.timestamp.timeIntervalSince1970, now: Date().timeIntervalSince1970, course: fix.speed >= 0.7 && fix.courseAccuracy >= 0 && fix.courseAccuracy <= 25 ? fix.course : nil)
        lastWalkingFix = fix.timestamp
        if walking?.status == .offRoute, Date().timeIntervalSince(lastReplan) > 20, directions == nil, fix.horizontalAccuracy <= 20 {
            lastReplan = Date()
            settings.speak("Checking a new walking route.", priority: .direction)
            Task { await calculate() }
        }
        speakWalking()
        let canTick = walking?.status == .guiding && walking?.wrongWay == false &&
            fix.horizontalAccuracy <= 12 && fix.speed >= 0.5 && !roomVoice.busy &&
            phase == .active && !presented && roomRequest == nil && roomTarget == nil &&
            !insideBuilding && !arrived && Date() >= awarenessUntil
        settings.travelFeedback(position: canTick ? SIMD2((p.x-origin.x)*walkingScale, (p.y-origin.y)*walkingScale) : nil, context: "outdoor")
    }
    private func speakWalking(force: Bool = false) {
        guard let walking, !insideBuilding, !roomVoice.busy, phase == .active, !presented, roomRequest == nil, roomTarget == nil else { return }
        let text: String
        switch walking.status {
        case .locating: text = "Directions paused while GPS settles."
        case .offRoute: text = "You may be off the route. Check the map or find a new route."
        case .nearDestination: text = "Near your destination. Check the entrance."
        case .guiding: text = walking.wrongWay ? "You may be going the wrong way. Turn around when safe." : (walking.travelInstruction.isEmpty ? "Follow the mapped path." : walking.travelInstruction) + ". " + walking.upcomingDetail(feet: feet) + "."
        }
        let key = "\(walking.index)-\(walking.status)-\(walking.wrongWay)-\(walking.travelledOnLeg >= 12)-\(walking.alignedWithPath)-\(walking.announcementBand)"
        let reminder = walking.status == .guiding && Date().timeIntervalSince(lastWalkingAnnouncement) >= 12
        if force || (spokenWalking != key && (walking.status != .guiding || walking.wrongWay || Date().timeIntervalSince(lastWalkingAnnouncement) >= 3)) || reminder {
            let newLeg = !spokenWalking.isEmpty && !spokenWalking.hasPrefix("\(walking.index)-")
            spokenWalking = key; lastWalkingAnnouncement = Date()
            settings.speak(text, priority: walking.status == .guiding ? .direction : .safety)
            settings.cue(walking.status == .guiding && !walking.wrongWay ? (newLeg ? .turn : .approach) : .attention, instruction: text)
        }
    }
    private func confirmInside() {
        insideBuilding = true; directions?.cancel(); directions = nil; route = nil; walking = nil; settings.stopSpeech(); error = nil
        if !roomQuery.isEmpty { openRoom() } else { settings.speak("Which room would you like to go to?") }
    }
    private var buildingName: String {
        let name = destination.name ?? "Selected building"
        return name.lowercased().contains("friend") && name.lowercased().contains("center") ? FriendCenter.name : name
    }
    private func resumeCamera() {
        if automaticallyStart && !showingMap && !presented { Task { await camera.start(navigation: true) } }
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
    private func calculate() async {
        guard !arrived, !insideBuilding, directions == nil, (!nearBuilding || continueOutside || route != nil), !settings.preferences.avoidStairs, let fix = location.location, fix.horizontalAccuracy <= 25, abs(fix.timestamp.timeIntervalSinceNow) <= 10 else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: fix.coordinate))
        request.destination = destination; request.transportType = .walking
        let task = MKDirections(request: request); directions = task
        do { let response = try await task.calculate(); guard directions === task else { return }; route = response.routes.first; if let route { installWalking(route); mapPosition = .rect(route.polyline.boundingMapRect.insetBy(dx: -route.polyline.boundingMapRect.size.width * 0.2 - 100, dy: -route.polyline.boundingMapRect.size.height * 0.2 - 100)) }; error = route == nil ? "No walking route is available." : nil }
        catch { if directions === task && !Task.isCancelled { self.error = "Could not refresh directions. Any loaded route is kept; GPS tracking does not need Wi-Fi. Retry when connected." } }
        directions = nil
    }
}

struct IndoorJourneyTarget: Identifiable {
    var id: UUID { route.id }
    let route: HallwayRoute
    let draft: ScanDraft
    let library: ScanLibrary
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
