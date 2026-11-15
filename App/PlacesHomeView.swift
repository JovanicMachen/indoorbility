import SwiftUI
import MapKit
import IndoorbilityCore

struct PlacesHomeView: View {
    @ObservedObject var store: AppStore
    @StateObject private var library = ScanLibrary()
    @StateObject private var memory = JourneyLibrary()
    @StateObject private var outdoor = OutdoorSearch()
    @StateObject private var nearby = OutdoorLocation()
    @StateObject private var suggestions = NearbySuggestions()
    @StateObject private var google = GooglePlacesService()
    @StateObject private var voice = VoiceCommandInput()
    @StateObject private var assistant = DestinationAgentHost()
    @AppStorage("highContrast") private var highContrast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var pickedRecording = false
    @State private var query = ""
    @State private var recordingRoom: FriendCenter.Room?
    @State private var requestedRoom: RoomMappingRequest?
    @SceneStorage("selectedRoomBuilding") private var selectedRoomBuilding = ""
    @State private var selected: IndoorJourneyTarget?
    @State private var pendingIndoorTarget: IndoorJourneyTarget?
    @State private var pendingEntrance: EntranceLocation?
    @State private var chooseStartingLocation = false
    @State private var proposal: JourneyDestination?
    @State private var confirmation = DestinationConfirmation()
    @State private var outdoorProposal: MKMapItem?
    @State private var outdoorConfirmed: MKMapItem?
    @State private var outdoorIndoor: IndoorJourneyTarget?
    @State private var selectedOutdoorRoom: String?
    @State private var outdoorID = UUID()
    @State private var showOutdoor = false
    @State private var accessibility = false
    @State private var map = false
    @State private var mapSearch = ""
    @State private var mapRequest: String?
    @StateObject private var mapVoice = VoiceCommandInput()
    @State private var message = ""
    @State private var searched = false
    @State private var searchGeneration = UUID()
    @State private var resolvingQuery = ""
    @State private var voiceCorrection: String?
    private var matches: [JourneyDestination] { DestinationSearch.matches(query, in: memory.preferredDestinations) }
    private var knownFriendRooms: [FriendCenter.Room] {
        let text = query.lowercased()
        guard selectedRoomBuilding == FriendCenter.name || text.contains("friend") || text.contains("frend") else { return [] }
        return FriendCenter.search(query)
    }
    private var hasIndoorRoomMatches: Bool {
        !matches.isEmpty || (!knownFriendRooms.isEmpty && RoomMappingRequest.friend(query) != nil)
    }
    private var placeSearchText: String { RoomMappingRequest.attached(query)?.building ?? query }
    private var searchExpanded: Bool {
        searchFocused || !query.isEmpty || proposal != nil || outdoorProposal != nil || !message.isEmpty || voice.busy
    }
    private var voiceAndAccessibility: some View {
        VStack(spacing: 12) {
            HoldToTalk(voice: voice, before: { store.stopSpeech() }, onUnrecognized: { store.speak(VoiceCommandInput.notUnderstood) }, haptics: store.preferences.haptics, diameter: searchExpanded ? 90 : 136, result: receive)
            Button { accessibility = true } label: {
                Label("Accessibility", systemImage: "accessibility").frame(minHeight: 48).padding(.horizontal, 20)
            }.buttonStyle(.bordered).tint(.indoorTeal)
        }
    }
    var body: some View {
        GeometryReader { viewport in
        ZStack {
            if !searchExpanded && !highContrast {
                DestinationBackdrop()
            }
            GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("Where to?").font(.system(searchExpanded ? .title2 : .largeTitle, design: .rounded, weight: .semibold)).foregroundStyle(Color.indoorTeal).multilineTextAlignment(.center)
                            .accessibilityIdentifier("destinationPrompt")
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .trailing) {
                                if searchExpanded {
                                    Button(action: goBack) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                        .accessibilityLabel("Close search").accessibilityIdentifier("closeDestinationSearch")
                                }
                            }
                        if !searchExpanded {
                            DestinationTypingHint(active: true)
                                .foregroundStyle(highContrast ? Color.primary : Color.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(highContrast ? Color.primary : Color.secondary)
                        TextField("Search destinations", text: $query)
                            .focused($searchFocused)
                            .submitLabel(.search).onSubmit(resolve).accessibilityIdentifier("destinationSearch")
                        if !query.isEmpty { Button(action: resolve) { Image(systemName: "arrow.right.circle.fill").font(.title2) }.accessibilityLabel("Find destination") }
                    }.padding(18).background(Color.indoorCard, in: Capsule()).overlay(Capsule().stroke(Color.indoorTeal.opacity(highContrast ? 0.7 : 0.12)))
                        .shadow(color: Color.indoorTeal.opacity(highContrast ? 0 : 0.07), radius: 16, y: 5)
                    }.padding(.horizontal, searchExpanded ? 0 : 8)
                        .frame(maxWidth: .infinity, minHeight: searchExpanded ? nil : max(0, geometry.size.height - 48))
                        .offset(y: searchExpanded ? 0 : min(110, max(0, geometry.size.height - 260) * 0.6))
                    if proposal != nil || outdoorProposal != nil {
                        Panel {
                            Text("Your destination").font(.headline)
                            Text(proposal.map { "\($0.room) · \($0.building)" } ?? outdoorProposal?.name ?? "Destination").font(.title2.bold())
                            Text(proposal.map(floorDescription) ?? "Outdoor directions · indoor route not mapped").foregroundStyle(highContrast ? Color.primary : Color.secondary)
                            if let item = proposal {
                                Text("Start at " + memory.startingLabel(item)).font(.subheadline)
                                let options = memory.alternatives(to: item)
                                if options.count > 1 {
                                    DisclosureGroup("Other recordings (\(options.count))") {
                                        Text("Ranked by review and previous visits; confirm the starting point.").font(.footnote)
                                        ForEach(options) { option in
                                            Button("From " + memory.startingLabel(option) + (startDistance(option).map { " · " + LiveGuidance.distance(Float($0), feet: UserDefaults.standard.bool(forKey: "guidanceFeet")) + " away" } ?? " · \(option.successfulVisits ?? 0) completed visits")) { propose(option, choosing: false) }
                                        }
                                    }
                                }
                                if item.building == FriendCenter.name, let known = FriendCenter.search(item.room).first {
                                    Button("Record another route") { recordingRoom = known }
                                }
                            }
                            HStack {
                                Button("No, change it", action: decline).buttonStyle(.bordered).frame(minHeight: 48)
                                Spacer()
                                Button("Yes, let’s go", action: accept).buttonStyle(.borderedProminent).frame(minHeight: 48)
                            }
                        }
                    } else if !query.isEmpty {
                        destinationResults
                    }
                    if !query.isEmpty && !hasIndoorRoomMatches && !google.results.isEmpty && proposal == nil && outdoorProposal == nil {
                        DisclosureGroup("More places · Google Maps") {
                            ForEach(google.results) { place in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.displayName?.text ?? "Place").font(.headline)
                                    Text(place.formattedAddress ?? "").font(.caption)
                                    if let point = place.location { distanceLabel(to: CLLocation(latitude: point.latitude, longitude: point.longitude)) }
                                    ForEach(Array((place.attributions ?? []).enumerated()), id: \.offset) { _, attribution in
                                        if let provider = attribution.provider { Text(provider).font(.caption2) }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            }
                            Text("Google Maps").font(.caption.weight(.medium))
                            Text("Choose a walking destination from the results above to get directions here.").font(.footnote)
                        }.padding().background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 22))
                    }
                    if !query.isEmpty, proposal == nil, outdoorProposal == nil,
                       matches.isEmpty, knownFriendRooms.isEmpty, RoomMappingRequest.attached(query) == nil,
                       suggestions.results.isEmpty, outdoor.results.isEmpty, google.results.isEmpty,
                       !outdoor.loading, outdoor.error != nil || suggestions.error != nil || google.error != nil {
                        Text("Can’t connect. Try again or choose a saved room.").font(.footnote)
                            .accessibilityIdentifier("placeSearchStatus")
                    }
                    AgentActivityView(agent: assistant.agent)
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(highContrast ? Color.primary : Color.secondary).accessibilityIdentifier("destinationStatus") }
                    if !voice.transcript.isEmpty { Text(voice.transcript).font(.callout) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { searchFocused = false }
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: searchExpanded)
            }.scrollDismissesKeyboard(.interactively)
                .clipped()
            }
            VoiceEdgeGlow(active: voice.listening)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Keep one microphone identity: moving it between conditional branches
            // invokes onDisappear and cancels recognition as soon as listening starts.
            voiceAndAccessibility
                .padding(searchFocused ? 0 : 24)
                // Lift the idle controls toward the middle while preserving
                // their identity and the keyboard/search-results layout.
                .padding(.bottom, searchExpanded ? 0 : min(120, viewport.size.height * 0.14))
                .frame(maxWidth: .infinity)
                .frame(height: searchFocused ? 0 : nil)
                .clipped()
                .opacity(searchFocused ? 0 : 1)
                .allowsHitTesting(!searchFocused)
                .accessibilityHidden(searchFocused)
        }
        .background {
            Color.indoorBackground.ignoresSafeArea()
            if !searchExpanded && !highContrast { HomeHolidayBackdrop() }
        }

        .overlay(alignment: .top) {
            if !searchExpanded && !highContrast { HolidayGarland() }
        }
        .swipeLeftToGoBack(action: goBack)
        .toolbar(.hidden, for: .navigationBar)

        .onAppear {
            library.reload(); memory.refresh(from: library)
            assistant.catalog = memory.preferredDestinations; assistant.preferences = store.preferences
            VoiceCommandInput.knownPlaces = Array(Set(memory.destinations.flatMap { [$0.room, $0.building] }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 2 })).sorted()
            assistant.found = { propose($0, speak: false) }
            assistant.floorInfo = { floorDescription($0) }
            assistant.fallback = { _ in resolveLocally() }
            assistant.speak = { message = $0; store.speak($0, force: true, userRequested: true) }
            assistant.acknowledge = { store.speak(VoiceResponseTiming.acknowledgment, priority: .ambient) }
            if let pending = UserDefaults.standard.string(forKey: "pendingDestinationQuery"), !pending.isEmpty {
                UserDefaults.standard.removeObject(forKey: "pendingDestinationQuery")
                query = pending; resolvingQuery = pending; resolve()
            }
        }
        .onDisappear { searchGeneration = UUID(); voice.cancel(); nearby.stop(); suggestions.update("", near: nil); outdoor.cancel(); google.cancel(); assistant.agent.cancel(); assistant.found = { _ in }; assistant.fallback = { _ in }; assistant.speak = { _ in }; assistant.acknowledge = {}; assistant.floorInfo = { _ in "Floor label unknown" } }
        .onChange(of: searchFocused) { _, focused in if focused { nearby.start() } }
        .onChange(of: nearby.location) { _, fix in
            outdoor.nearby = fix
            // A better GPS fix can show a different door is closer. Switch quietly
            // unless the user picked a recording themselves.
            if let current = proposal, !pickedRecording, confirmation.isCurrent(current.id, now: ProcessInfo.processInfo.systemUptime) {
                let nearer = nearestRecording(for: current)
                if nearer.id != current.id { proposal = nearer; confirmation.propose(nearer.id, now: ProcessInfo.processInfo.systemUptime) }
            }
            if searchFocused { suggestions.update(placeSearchText, near: fix) }
        }
        .task(id: query) {
            let text = placeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            outdoor.cancel(); google.cancel(); searched = false
            if assistant.agent.canAnswerGeneralQuestion(text) { suggestions.update("", near: nil); return }
            suggestions.update(text, near: nearby.location)
            guard text.count >= 3 else { return }
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled else { return }
            searched = true
            async let native: Void = outdoor.search(text)
            async let places: Void = google.search(text)
            _ = await (native, places)
        }
        .onChange(of: query) { _, value in
            guard value != resolvingQuery else { return }
            assistant.agent.cancel(); confirmation.cancel(); proposal = nil; outdoorProposal = nil; searched = false; searchGeneration = UUID()
        }
        .onChange(of: voice.busy) { _, busy in if !busy && !voice.status.hasPrefix("Heard:") { message = voice.status } }
        .confirmationDialog("Where are you starting?", isPresented: $chooseStartingLocation, titleVisibility: .visible) {
            Button("I’m at the route start") {
                if let target = pendingIndoorTarget { selected = target }
                pendingIndoorTarget = nil; pendingEntrance = nil
            }
            Button("Walking directions to the start") {
                if let target = pendingIndoorTarget, let pin = pendingEntrance {
                    let place = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: pin.latitude, longitude: pin.longitude)))
                    place.name = target.draft.name
                    selectedOutdoorRoom = nil; outdoorIndoor = target; outdoorConfirmed = place; showOutdoor = true
                }
                pendingIndoorTarget = nil; pendingEntrance = nil
            }
            Button("Cancel", role: .cancel) { pendingIndoorTarget = nil; pendingEntrance = nil }
        } message: { Text("GPS suggests the saved start may be farther away. Choose where you are.") }
        .sheet(item: $requestedRoom, onDismiss: {
            library.reload(); memory.refresh(from: library); assistant.catalog = memory.preferredDestinations
        }) { request in RecordDestinationView(settings: store, request: request) }
        .sheet(item: $recordingRoom, onDismiss: {
            library.reload(); memory.refresh(from: library); assistant.catalog = memory.preferredDestinations
            proposal = nil; confirmation.cancel()
        }) { known in RecordDestinationView(settings: store, room: known) }
        .sheet(isPresented: $accessibility) { GuidancePreferencesView(store: store) }
        .sheet(isPresented: $map, onDismiss: {
            library.reload(); memory.refresh(from: library); assistant.catalog = memory.preferredDestinations
            guard let text = mapRequest else { return }
            mapRequest = nil; query = text; resolvingQuery = text; resolve()
        }) { NavigationStack { Map {
            UserAnnotation()
            ForEach(memory.destinations) { item in
                if let entrance = entranceLocation(item) {
                    Marker(item.room + " · " + item.building, coordinate: CLLocationCoordinate2D(latitude: entrance.latitude, longitude: entrance.longitude))
                }
            }
        }.navigationTitle("My maps").toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { ScanHubView(store: store).onDisappear {
                    library.reload(); memory.refresh(from: library); assistant.catalog = memory.preferredDestinations
                } } label: { Label("Saved", systemImage: "tray.full") }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { map = false } }
        }
            .safeAreaInset(edge: .top) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Destination and room", text: $mapSearch)
                        .submitLabel(.search).onSubmit(submitMapSearch).accessibilityIdentifier("mapDestinationSearch")
                    Button("Find", action: submitMapSearch).disabled(mapSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(.regularMaterial)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("Search a destination and room, or choose a saved route.").font(.footnote)
                    if !memory.preferredDestinations.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(memory.preferredDestinations) { item in
                                    Button(item.building + " · " + item.room) {
                                        mapSearch = item.building + " " + item.room; submitMapSearch()
                                    }.buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                    HoldToTalk(voice: mapVoice, before: { store.stopSpeech() }, onUnrecognized: { store.speak(VoiceCommandInput.notUnderstood) }, haptics: store.preferences.haptics, diameter: 64) { text in
                        mapSearch = text; submitMapSearch()
                    }
                }.padding().background(.regularMaterial)
            }
            .overlay { VoiceEdgeGlow(active: mapVoice.listening) }
        } }
        .fullScreenCover(item: $selected) { target in HallwayLaunchView(route: target.route, draft: target.draft, library: target.library, settings: store) }
        .fullScreenCover(isPresented: $showOutdoor) { if let outdoorConfirmed { NavigationStack { OutdoorRouteView(destination: outdoorConfirmed, settings: store, indoor: outdoorIndoor, automaticallyStart: true, initialRoom: selectedOutdoorRoom) } } }
        }
    }
    private func goBack() {
        guard searchExpanded else { return }
        if proposal != nil || outdoorProposal != nil {
            proposal = nil; outdoorProposal = nil; confirmation.cancel(); store.stopSpeech()
            return
        }
        searchFocused = false
        voice.cancel(); assistant.agent.cancel(); outdoor.cancel(); google.cancel()
        suggestions.update("", near: nil); confirmation.cancel(); store.stopSpeech()
        searchGeneration = UUID(); proposal = nil; outdoorProposal = nil
        query = ""; resolvingQuery = ""; message = ""; searched = false; selectedRoomBuilding = ""
        voiceCorrection = nil; voice.clearTranscript()
    }
    private func submitMapSearch() {
        let text = mapSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        mapRequest = text; map = false
    }
    @ViewBuilder private var destinationResults: some View {

                        if let request = RoomMappingRequest.resolve(query, selectedBuilding: selectedRoomBuilding), knownFriendRooms.isEmpty, matches.isEmpty {
                            Button { searchFocused = false; resolve() } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Room " + request.room + " · " + request.building).font(.headline)
                                    Text("Choose this destination · trace a route if needed").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                    .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        }
                        ForEach(knownFriendRooms.filter { room in
                            !matches.contains { $0.building == FriendCenter.name && FriendCenter.search($0.room).contains(where: { $0.id == room.id }) }
                        }) { room in
                            Button { chooseKnownRoom(room) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Room \(room.id) · Friend Center").font(.headline)
                                    Text("Level \(room.level) · room information only").font(.subheadline)
                                    Text("Choose this room").font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        }
                        if matches.isEmpty, knownFriendRooms.count == 1, let known = knownFriendRooms.first {
                            Button("Record a route to Room " + known.id) { searchFocused = false; recordingRoom = known }
                                .buttonStyle(.borderedProminent)
                        }
                        ForEach(matches.prefix(5)) { item in
                            Button { propose(item) } label: {
                                HStack { Image(systemName: "door.left.hand.closed"); VStack(alignment: .leading) { Text(item.room).font(.headline); Text(item.building).font(.subheadline) }; Spacer(); Image(systemName: "chevron.right") }.padding().background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        }
                        if !hasIndoorRoomMatches && !suggestions.results.isEmpty {
                            Text(nearby.location == nil ? "Places · Princeton area" : "Places near you").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(suggestions.results.prefix(5).enumerated()), id: \.offset) { _, item in
                                Button {
                                    searchFocused = false
                                    let generation = searchGeneration
                    Task {
                        if let place = await suggestions.resolve(item), generation == searchGeneration { openOutdoor(place) }
                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(.headline)
                                        Text(item.subtitle).font(.caption)
                                        if let point = suggestions.coordinates[NearbySuggestions.key(item)] { distanceLabel(to: point) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                                        .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(.plain)
                            }
                        }
                        if !hasIndoorRoomMatches && outdoor.loading { ProgressView("Checking places…") }
                        if !hasIndoorRoomMatches && searched { ForEach(Array(outdoor.results.prefix(5).enumerated()), id: \.offset) { _, item in
                            Button { openOutdoor(item) } label: {
                                VStack(alignment: .leading) { Text(item.name ?? "Place").font(.headline); Text(item.placemark.title ?? "").font(.caption); if let point = item.placemark.location { distanceLabel(to: point) } }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        } }
    }
    @ViewBuilder private func distanceLabel(to point: CLLocation) -> some View {
        if let fix = nearby.location, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 100,
           abs(fix.timestamp.timeIntervalSinceNow) < 30 {
            let miles = fix.distance(from: point) / 1609.344
            Text(miles < 0.1 ? "Less than 0.1 mi away · straight-line" : "About \(miles.formatted(.number.precision(.fractionLength(1)))) mi away · straight-line")
                .font(.caption.weight(.medium)).foregroundStyle(Color.indoorTeal)
        }
    }
    private func chooseKnownRoom(_ room: FriendCenter.Room) {
        selectedRoomBuilding = FriendCenter.name
        searchFocused = false
        if let saved = memory.preferredDestinations.first(where: {
            $0.building == FriendCenter.name && FriendCenter.search($0.room).contains(where: { $0.id == room.id })
        }) { propose(saved) }
        else { recordingRoom = room }
    }
    private func entranceLocation(_ destination: JourneyDestination) -> EntranceLocation? {
        let url = library.directory(destination.scanID).appending(path: "entrance-location.json")
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(EntranceLocation.self, from: data),
              (-90...90).contains(value.latitude), (-180...180).contains(value.longitude), (0...35).contains(value.accuracy) else { return nil }
        return value
    }
    private func floorDescription(_ destination: JourneyDestination) -> String {
        let url = library.directory(destination.scanID).appending(path: "room-metadata.json")
        guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(VerifiedRoomMetadata.self, from: data), value.buildingID == destination.scanID, !value.floorLabel.isEmpty,
              let draft = library.scans.first(where: { $0.id == destination.scanID }),
              let route = try? library.hallway(draft), route.room.id == value.roomID else { return "Floor label unknown · reviewed same-floor path" }
        return "Floor \(value.floorLabel) · manually confirmed"
    }
    private func resolve() {
        searchFocused = false
        resolvingQuery = query
        confirmation.cancel(); proposal = nil; outdoorProposal = nil
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if assistant.agent.canAnswerGeneralQuestion(query) {
            assistant.agent.submit(query, model: assistant)
            return
        }
        store.setPreference(\.avoidStairs, LocalNavigationAgent.constraints(for: query, base: store.preferences).avoidStairs)
        library.reload(); memory.refresh(from: library)
        if let request = RoomMappingRequest.resolve(query, selectedBuilding: selectedRoomBuilding) {
            selectedRoomBuilding = request.building
            let saved = DestinationSearch.matches("Room " + request.room, in: memory.preferredDestinations.filter { $0.building == request.building })
            if saved.count == 1 { propose(saved[0]); return }
            if saved.isEmpty, RoomMappingRequest.attached(query) != nil, request.building != FriendCenter.name {
                message = "Room \(request.room). Choose the matching destination below so I can check whether you’re nearby."
                let generation = UUID(); searchGeneration = generation
                Task {
                    await outdoor.search(request.building)
                    guard generation == searchGeneration else { return }
                    searched = true
                    if outdoor.results.isEmpty { message = outdoor.error == nil ? "No match. Check the building name." : "" }
                }
                return
            }
            if saved.isEmpty {
                requestedRoom = request
                message = ""
                store.speak(message, force: true)
                return
            }
        }
        if matches.count == 1 { propose(matches[0]); return }
        if RoomMappingRequest.roomNumber(query) != nil && selectedRoomBuilding.isEmpty {
            message = "Which building is this room in? Choose a building first, then enter the room number."
            store.speak(message, force: true); return
        }
                if matches.isEmpty, knownFriendRooms.count == 1, let known = knownFriendRooms.first {
            message = "I found Room \(known.id) in Friend Center, Level \(known.level). There is no available reviewed recording. Would you like to record a route you know?"
            recordingRoom = known
            store.speak(message, force: true)
            return
        }
        if matches.count == 1 { propose(matches[0]); return }
        assistant.catalog = memory.preferredDestinations; assistant.preferences = store.preferences
        assistant.agent.submit(query, model: assistant)
    }
    private func resolveLocally() {
        confirmation.cancel(); proposal = nil; outdoorProposal = nil
        store.setPreference(\.avoidStairs, LocalNavigationAgent.constraints(for: query, base: store.preferences).avoidStairs)
        if matches.count == 1 { propose(matches[0]); return }
        if matches.count > 1 { message = "Which building or room? Choose a match above."; store.speak(message); return }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        message = "No saved indoor room matches. Checking outdoor places; indoor guidance needs a reviewed map."
        let generation = UUID(); searchGeneration = generation; let text = query
        Task {
            await outdoor.search(text); guard generation == searchGeneration else { return }
            // Speech can mangle names ("louis rm strng"). Try the closest saved
            // name, then an AI spelling fix, and search once more.
            if outdoor.results.isEmpty, outdoor.error == nil {
                var fixed = SpokenPlaceMatch.correct(text, names: VoiceCommandInput.knownPlaces)
                if fixed == nil { fixed = await assistant.agent.correctPlaceName(SpokenPlaceMatch.cleaned(text), known: VoiceCommandInput.knownPlaces) }
                guard generation == searchGeneration else { return }
                if let fixed {
                    message = "Searching for \(fixed)…"
                    await outdoor.search(fixed); guard generation == searchGeneration else { return }
                    if !outdoor.results.isEmpty { store.speak("Did you mean \(fixed)? Choose it below.") }
                }
            }
            searched = true; message = outdoor.error == nil ? (outdoor.results.isEmpty ? "No match. Try saying the name another way." : "Choose your destination.") : ""
        }
    }
    /// Metres from your GPS fix to where this recording starts, when both are known.
    private func startDistance(_ item: JourneyDestination) -> Double? {
        guard let pin = entranceLocation(item), let fix = nearby.location, fix.horizontalAccuracy >= 0 else { return nil }
        return fix.distance(from: CLLocation(latitude: pin.latitude, longitude: pin.longitude))
    }
    /// A room can have recordings from several doors. Use the one that starts
    /// nearest to you; without a good GPS fix keep the saved ranking.
    private func nearestRecording(for item: JourneyDestination) -> JourneyDestination {
        let options = memory.alternatives(to: item)
        guard options.count > 1 else { return options.first ?? item }
        let order = RouteChoice.ranked(options.map(startDistance), fixAccuracy: nearby.location?.horizontalAccuracy)
        return options[order[0]]
    }
    private func propose(_ item: JourneyDestination, speak: Bool = true, choosing: Bool = true) {
        nearby.start() // so Start can decide between GPS walk and camera
        let item = choosing ? nearestRecording(for: item) : item
        pickedRecording = !choosing
        selectedRoomBuilding = item.building
        outdoorProposal = nil; proposal = item; confirmation.propose(item.id, now: ProcessInfo.processInfo.systemUptime)
        message = "Say yes or no, or use the buttons."
        let ways = memory.alternatives(to: item).count
        let start = ways <= 1 ? "" : startDistance(item) != nil
            ? " There are \(ways) recorded ways in. The closest starts at \(memory.startingLabel(item))."
            : " There are \(ways) recorded ways in. This one starts at \(memory.startingLabel(item))."
        if speak { store.speak("I found \(item.room), \(item.building). \(floorDescription(item)).\(start) Is this where you want to go?", force: true) }
    }
    private func openOutdoor(_ item: MKMapItem) {
        selectedOutdoorRoom = RoomMappingRequest.resolve(query, selectedBuilding: selectedRoomBuilding)?.room
        let name = item.name ?? ""
        selectedRoomBuilding = name.lowercased().contains("friend") && name.lowercased().contains("center") ? FriendCenter.name : name
        searchFocused = false; assistant.agent.cancel(); confirmation.cancel()
        proposal = nil; outdoorProposal = nil; outdoorConfirmed = item; showOutdoor = true
    }
    private func proposeOutdoor(_ item: MKMapItem) {
        searchFocused = false
        proposal = nil; outdoorProposal = item; outdoorID = UUID(); confirmation.propose(outdoorID, now: ProcessInfo.processInfo.systemUptime)
        store.speak("I found \(item.name ?? "this place"), \(item.placemark.title ?? ""). Is this where you want to go?", force: true)
    }
    private func decline() { assistant.agent.cancel(); confirmation.cancel(); proposal = nil; outdoorProposal = nil; message = "Tell me a different room or building."; store.speak(message) }
    private func accept() {
        assistant.agent.cancel()
        let id = proposal?.id ?? outdoorID
        guard confirmation.accept(id, now: ProcessInfo.processInfo.systemUptime) != nil else { decline(); message = "That confirmation expired. Choose the destination again."; return }
        store.stopSpeech()
        if let item = proposal {
            do {
                let target = try library.navigationTarget(item, preferences: store.preferences)
                if let pin = entranceLocation(item), let fix = nearby.location,
                   DestinationProximity.shouldAskAboutOutdoorDirections(
                       distance: fix.distance(from: CLLocation(latitude: pin.latitude, longitude: pin.longitude)),
                       fixAccuracy: fix.horizontalAccuracy, pinAccuracy: pin.accuracy,
                       fixAge: abs(fix.timestamp.timeIntervalSinceNow)) {
                    // A saved GPS pin may have been recorded indoors or moved. Ask
                    // instead of sending someone away from their actual location.
                    pendingIndoorTarget = target; pendingEntrance = pin; chooseStartingLocation = true
                } else { selected = target }
            } catch { message = error.localizedDescription }
        } else if let item = outdoorProposal { outdoorIndoor = nil; selectedOutdoorRoom = RoomMappingRequest.resolve(query, selectedBuilding: selectedRoomBuilding)?.room; outdoorConfirmed = item; showOutdoor = true }
        proposal = nil; outdoorProposal = nil
    }
    private func receive(_ text: String) {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if ["stop", "stop listening", "pause", "cancel"].contains(normalized) {
            voiceCorrection = nil; assistant.agent.cancel(); outdoor.cancel(); google.cancel()
            searchGeneration = UUID(); confirmation.cancel(); proposal = nil; outdoorProposal = nil
            store.stopSpeech(); message = "Stopped."; return
        }
        if normalized == "repeat" { store.repeatNarration(); return }
        if let correction = voiceCorrection {
            voiceCorrection = nil
            if ["yes", "yes please", "correct"].contains(normalized) {
                query = correction; resolvingQuery = correction
                Task { @MainActor in
                    await Task.yield()
                    guard query == correction else { return }
                    resolve()
                }
                return
            }
        }
        if normalized.contains("friend circle"), normalized.contains(where: \.isNumber) {
            voiceCorrection = text.replacingOccurrences(of: "friend circle", with: "Friend Center", options: .caseInsensitive)
            message = "Did you mean Friend Center?"
            store.speak(message); return
        }
        if normalized.contains("lost") || normalized == "help" || normalized.contains("where am i") {
            message = "Where would you like to go? Say a building or address."
            store.speak(message)
            return
        }
        if ["yes", "yes please", "correct", "yes let’s go", "yes lets go", "yes let\'s go", "let’s go", "lets go", "let\'s go"].contains(normalized) {
            guard proposal != nil || outdoorProposal != nil else {
                message = "Which room or building?"; store.speak(message); return
            }
            accept(); return
        }
        if ["no", "cancel", "no thanks"].contains(normalized) { decline(); return }
        query = text; resolvingQuery = text
        // Let SwiftUI commit the query before resolution reads it.
        searchFocused = false
        Task { @MainActor in
            await Task.yield()
            guard query == text else { return }
            resolve()
        }
    }
}

struct DestinationJourneyView: View {
    @AppStorage("highContrast") private var highContrast = false
    let target: IndoorJourneyTarget
    @ObservedObject var settings: AppStore
    var automaticallyStart = false
    @State private var automaticLaunchConsumed = false
    @State private var camera = false
    @State private var outdoor = false
    @StateObject private var here = OutdoorLocation()
    @Environment(\.dismiss) private var dismiss
    /// Straight-line metres from you to the saved entrance, when both are known.
    private var distanceToEntrance: Double? {
        guard let entrance, let fix = here.location, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 65 else { return nil }
        return fix.distance(from: CLLocation(latitude: entrance.latitude, longitude: entrance.longitude))
    }
    /// One button, like a normal GPS: walk to the building by GPS, then the camera
    /// takes over inside the saved 3D map. Close by (or no GPS pin), go straight to camera.
    private func startNavigation() {
        if let entrance, let fix = here.location,
           DestinationProximity.shouldAskAboutOutdoorDirections(
                distance: fix.distance(from: CLLocation(latitude: entrance.latitude, longitude: entrance.longitude)),
                fixAccuracy: fix.horizontalAccuracy, pinAccuracy: entrance.accuracy, fixAge: abs(fix.timestamp.timeIntervalSinceNow)) {
            outdoor = true
        } else { camera = true }
    }
    private var entrance: EntranceLocation? {
        guard let data = try? Data(contentsOf: target.library.directory(target.draft.id).appending(path: "entrance-location.json")),
              let value = try? JSONDecoder().decode(EntranceLocation.self, from: data),
              (-90...90).contains(value.latitude), (-180...180).contains(value.longitude), value.accuracy >= 0, value.accuracy <= 35 else { return nil }
        return value
    }
    var body: some View {
        Group {
        if automaticallyStart {
            ProgressView("Opening \(target.route.room.label)…").frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.indoorBackground)
        } else {
        List {
            Section {
                Text(target.route.room.label).font(.largeTitle.bold())
                Text(target.draft.name).foregroundStyle(highContrast ? Color.primary : Color.secondary)
                Text("\(target.route.distance.formatted(.number.precision(.fractionLength(0)))) m from \(target.route.entrance.label)")
                if let distance = distanceToEntrance, distance > 60 {
                    Text("You're about \(Int((distance * 3.28084 / 50).rounded() * 50)) ft from the entrance. GPS will walk you there, then the camera takes over.")
                        .font(.footnote).foregroundStyle(highContrast ? Color.primary : Color.secondary)
                }
                Button("Start", systemImage: "location.north.fill") { startNavigation() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 48).accessibilityIdentifier("startSavedRoute")
            }
            Section {
                Button("I'm already at \(target.route.entrance.label)", systemImage: "camera") { camera = true }
                if entrance != nil { Button("Walking directions to the entrance", systemImage: "figure.walk") { outdoor = true } }
            }
            Section {
                DisclosureGroup("Preview indoor path") { TraceView(samples: target.draft.samples, landmarks: [target.route.entrance, target.route.room]) }
                Text("Inside, the camera matches your saved 3D map and guides you from wherever you are on the path.").font(.footnote).foregroundStyle(highContrast ? Color.primary : Color.secondary)
            }
        }
        }
        }.navigationTitle("Your destination").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $camera, onDismiss: finishAutomaticJourney) { HallwayLaunchView(route: target.route, draft: target.draft, library: target.library, settings: settings) }
            .fullScreenCover(isPresented: $outdoor, onDismiss: finishAutomaticJourney) {
                if let entrance {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: entrance.latitude, longitude: entrance.longitude)))
                    NavigationStack { OutdoorRouteView(destination: named(item), settings: settings, indoor: target, automaticallyStart: true) }
                }
            }
            .task {
                if entrance != nil { here.start() }
                guard automaticallyStart, !automaticLaunchConsumed, !camera, !outdoor else { return }
                automaticLaunchConsumed = true
                // Give a fresh GPS fix a short opportunity to choose the outdoor
                // leg. If unavailable, camera matching still cannot assert a pose.
                if entrance != nil {
                    for _ in 0..<30 {
                        if let fix = here.location, fix.horizontalAccuracy <= 30, abs(fix.timestamp.timeIntervalSinceNow) <= 5 { break }
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                    }
                }
                guard !Task.isCancelled else { return }
                startNavigation()
            }
            .onDisappear { here.stop() }
    }
    private func finishAutomaticJourney() { if automaticallyStart { dismiss() } }
    private func named(_ item: MKMapItem) -> MKMapItem { item.name = target.draft.name; return item }
}

/// Cloud intent coordinator for discovery; no live pose is asserted on Home/Help.
@MainActor final class DestinationAgentHost: ObservableObject, NavigationAgentHost {
    @Published var voiceResponse: String?
    let agent = NavigationAgent()
    var catalog: [JourneyDestination] = []
    var preferences = Preferences()
    var found: (JourneyDestination) -> Void = { _ in }
    var fallback: (String) -> Void = { _ in }
    var speak: (String) -> Void = { _ in }
    var acknowledge: () -> Void = {}
    var requestCamera: (() -> Void)?
    var floorInfo: (JourneyDestination) -> String = { _ in "Floor label unknown" }
    private var ledger = AgentExecutionLedger()
    private var utterance = ""
    func beginAgentTurn(_ text: String) { utterance = text; ledger.invalidate() }
    func acknowledgeAgentRequest() { acknowledge() }
    func agentContext() -> AgentContext {
        AgentContext(sessionId: ledger.sessionId, sessionRevision: ledger.revision, buildingId: "not-localized", floor: nil,
            tracking: "uncertain", destinationId: "", avoidStairs: preferences.avoidStairs,
            instruction: "Discovery only. Resolve a saved destination and ask for confirmation. No active camera or verified position. Floor unknown unless separately confirmed.",
            knownDestinations: catalog.prefix(100).map { ["id": $0.id.uuidString, "name": $0.room, "building": $0.building, "mapId": $0.scanID.uuidString] }, knownClosures: [])
    }
    func handleVoice(_ text: String) { fallback(text) }
    func presentClarification(_ text: String) { voiceResponse = text; speak(text) }
    func presentAgentResult(_ result: AgentToolResult) { voiceResponse = result.userSafeExplanation; speak(result.userSafeExplanation) }
    func executeAgent(_ call: AgentCall) async -> AgentToolResult {
        var status = AgentToolResult.Status.success; var text = ""; var data: [String: String] = [:]
        do {
            if let previous = try ledger.validate(call) { return previous }
            switch call.tool {
            case .resolveDestination:
                var matches = DestinationSearch.matches(utterance, in: catalog)
                // The AI may pass a repaired spelling ("Louis Armstrong" for "louis rm strng").
                // It still has to match a saved place; the AI cannot add one.
                if matches.count != 1, !call.argument.isEmpty {
                    let repaired = DestinationSearch.matches(call.argument, in: catalog)
                    if repaired.count == 1 { matches = repaired }
                }
                guard matches.count == 1, let destination = matches.first else {
                    fallback(utterance)
                    throw MapError.invalid(matches.isEmpty ? "No verified indoor location matches. Check the outdoor search results or choose a saved room." : "Several places match. Choose the building and room on screen.")
                }
                found(destination)
                text = "I found \(destination.room), \(destination.building). \(floorInfo(destination)). Is this where you want to go?"
                data = ["destinationId": destination.id.uuidString, "confirmationRequired": "true", "floor": "unknown"]
            case .getNavigationState:
                text = "No indoor position is verified here. Choose a saved room, then confirm your entrance in camera guidance."
                status = .unverified
            case .getAccessibilityPreferences:
                text = preferences.avoidStairs ? "Avoid stairs is on. Only reviewed step-free indoor paths may be used." : "Avoid stairs is off. Change it in Accessibility."
            case .getNearbyMappedDestinations:
                text = catalog.isEmpty ? "No reviewed rooms are saved. Remember a route under Settings, Your maps." : "Saved rooms: " + catalog.prefix(5).map { "\($0.room), \($0.building)" }.joined(separator: "; ") + ". Your proximity to them is unknown."
            case .describeCurrentView:
                status = .unavailable; text = "No fresh camera observation is available yet. Open camera assistance, then request a reading."
                requestCamera?()
            case .getKnownClosures:
                status = .unavailable; text = "Select a mapped route before checking its confirmed closures."
            case .repeatInstruction:
                text = voiceResponse ?? "Choose a destination on Home, or ask about your saved rooms and accessibility settings."
            default:
                status = .unavailable; text = "Confirm a saved destination on Home first. Camera guidance must verify your position before calculating a live route."
            }
        } catch { status = .error; text = error.localizedDescription }
        let result = AgentToolResult(callId: call.callId, sessionRevision: ledger.revision, status: status, data: data, userSafeExplanation: text)
        ledger.record(call, result: result); return result
    }
}
