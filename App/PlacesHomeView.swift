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
    @State private var query = ""
    @State private var recordingRoom: FriendCenter.Room?
    @State private var requestedRoom: RoomMappingRequest?
    @SceneStorage("selectedRoomBuilding") private var selectedRoomBuilding = ""
    @State private var selected: IndoorJourneyTarget?
    @State private var proposal: JourneyDestination?
    @State private var confirmation = DestinationConfirmation()
    @State private var outdoorProposal: MKMapItem?
    @State private var outdoorConfirmed: MKMapItem?
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
    private var matches: [JourneyDestination] { DestinationSearch.matches(query, in: memory.preferredDestinations) }
    private var knownFriendRooms: [FriendCenter.Room] {
        let text = query.lowercased()
        guard selectedRoomBuilding == FriendCenter.name || text.contains("friend") || text.contains("frend") else { return [] }
        return FriendCenter.search(query)
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
        ZStack {
            Color.indoorBackground.ignoresSafeArea()
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
                    if !searchExpanded {
                        voiceAndAccessibility
                            .padding(.top, 12)
                    }
                    }.padding(.horizontal, searchExpanded ? 0 : 8)
                        .frame(maxWidth: .infinity, minHeight: searchExpanded ? nil : max(0, geometry.size.height - 48))
                        .offset(y: searchExpanded ? 0 : min(30, geometry.size.height * 0.04))
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
                                            Button("From " + memory.startingLabel(option) + " · \(option.successfulVisits ?? 0) completed visits") { propose(option) }
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
                    if !query.isEmpty && !google.results.isEmpty && proposal == nil && outdoorProposal == nil {
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
                    if outdoor.error != nil, !query.isEmpty, matches.isEmpty, knownFriendRooms.isEmpty, RoomMappingRequest.attached(query) == nil, suggestions.results.isEmpty { Text("Place search couldn’t connect. Try again.").font(.footnote) }
                    if let error = google.error, !query.isEmpty { Text(error).font(.footnote) }
                    AgentActivityView(agent: assistant.agent)
                    if !message.isEmpty { Text(message).font(.callout).foregroundStyle(highContrast ? Color.primary : Color.secondary).accessibilityIdentifier("destinationStatus") }
                    if !voice.transcript.isEmpty { Text(voice.transcript).font(.callout) }
                }.padding(.horizontal, 24).padding(.bottom, 24)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: searchExpanded)
            }.scrollDismissesKeyboard(.interactively)
                .clipped()
            }
            VoiceEdgeGlow(active: voice.listening)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !searchFocused && searchExpanded {
                voiceAndAccessibility
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color.indoorBackground)
            }
        }

        .toolbar(.hidden, for: .navigationBar)

        .onAppear {
            library.reload(); memory.refresh(from: library)
            assistant.catalog = memory.preferredDestinations; assistant.preferences = store.preferences
            assistant.found = { propose(memory.alternatives(to: $0).first ?? $0, speak: false) }
            assistant.floorInfo = { floorDescription($0) }
            assistant.fallback = { _ in resolveLocally() }
            assistant.speak = { message = $0; store.speak($0, force: true) }
            if let pending = UserDefaults.standard.string(forKey: "pendingDestinationQuery"), !pending.isEmpty {
                UserDefaults.standard.removeObject(forKey: "pendingDestinationQuery")
                query = pending; resolvingQuery = pending; resolve()
            }
        }
        .onDisappear { nearby.stop(); suggestions.update("", near: nil); outdoor.cancel(); google.cancel(); assistant.agent.cancel(); assistant.found = { _ in }; assistant.fallback = { _ in }; assistant.speak = { _ in }; assistant.floorInfo = { _ in "Floor label unknown" } }
        .onChange(of: searchFocused) { _, focused in if focused { nearby.start() } }
        .onChange(of: nearby.location) { _, fix in
            outdoor.nearby = fix
            if searchFocused { suggestions.update(placeSearchText, near: fix) }
        }
        .task(id: query) {
            let text = placeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            outdoor.cancel(); google.cancel(); searched = false
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
        .fullScreenCover(isPresented: $showOutdoor) { if let outdoorConfirmed { NavigationStack { OutdoorRouteView(destination: outdoorConfirmed, settings: store, automaticallyStart: true, initialRoom: selectedOutdoorRoom) } } }
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
                        ForEach(knownFriendRooms) { room in
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
                                HStack { Image(systemName: "door.left.hand.closed"); VStack(alignment: .leading) { Text(item.room).font(.headline); Text(item.building).font(.subheadline); if let entrance = entranceLocation(item) { distanceLabel(to: CLLocation(latitude: entrance.latitude, longitude: entrance.longitude)) } }; Spacer(); Image(systemName: "chevron.right") }.padding().background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                        }
                        if !suggestions.results.isEmpty {
                            Text(nearby.location == nil ? "Places · Princeton area" : "Places near you").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(suggestions.results.prefix(5).enumerated()), id: \.offset) { _, item in
                                Button {
                                    searchFocused = false
                                    Task { if let place = await suggestions.resolve(item) { openOutdoor(place) } }
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
                        if let error = suggestions.error { Text(error).font(.footnote) }
                        if outdoor.loading { ProgressView("Checking places…") }
                        if searched { ForEach(Array(outdoor.results.prefix(5).enumerated()), id: \.offset) { _, item in
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
              (-90...90).contains(value.latitude), (-180...180).contains(value.longitude), (0...20).contains(value.accuracy) else { return nil }
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
                    if outdoor.results.isEmpty { message = outdoor.error ?? "No matching destination found. Check the building name; the room has not been mapped." }
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
        Task { await outdoor.search(text); guard generation == searchGeneration else { return }; searched = true; message = outdoor.error ?? "Choose the exact place to confirm it." }
    }
    private func propose(_ item: JourneyDestination, speak: Bool = true) {
        selectedRoomBuilding = item.building
        outdoorProposal = nil; proposal = item; confirmation.propose(item.id, now: ProcessInfo.processInfo.systemUptime)
        message = "Say yes or no, or use the buttons."
        if speak { store.speak("I found \(item.room), \(item.building). \(floorDescription(item)). Is this where you want to go?", force: true) }
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
                guard let draft = library.scans.first(where: { $0.id == item.scanID }), let route = try library.hallway(draft), route.id == item.routeID else { throw MapError.invalid("This saved route is unavailable. Review it in Settings → Your maps.") }
                guard try library.navigationStore(route).blockedEdges.isEmpty else { throw MapError.invalid("This route has a reported closure. Choose another reviewed recording.") }
                guard library.visitorReady(route) else { throw MapError.invalid("This route needs its volunteer field review before navigation is available.") }
                selected = IndoorJourneyTarget(route: route, draft: draft, library: library)
            } catch { message = error.localizedDescription }
        } else if let item = outdoorProposal { selectedOutdoorRoom = RoomMappingRequest.resolve(query, selectedBuilding: selectedRoomBuilding)?.room; outdoorConfirmed = item; showOutdoor = true }
        proposal = nil; outdoorProposal = nil
    }
    private func receive(_ text: String) {
        let normalized = text.lowercased().replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        if normalized.contains("lost") || normalized == "help" || normalized.contains("where am i") {
            message = "Where would you like to go? Say a building or address."
            store.speak(message)
            return
        }
        if ["yes", "yes please", "correct", "yes let’s go", "yes lets go", "yes let\'s go", "let’s go", "lets go", "let\'s go"].contains(normalized) { accept(); return }
        if ["no", "cancel", "no thanks"].contains(normalized) { decline(); return }
        query = text; resolvingQuery = text
        resolve()
    }
}

struct DestinationJourneyView: View {
    @AppStorage("highContrast") private var highContrast = false
    let target: IndoorJourneyTarget
    @ObservedObject var settings: AppStore
    @State private var camera = false
    @Environment(\.dismiss) private var dismiss
    private var entrance: EntranceLocation? {
        guard let data = try? Data(contentsOf: target.library.directory(target.draft.id).appending(path: "entrance-location.json")),
              let value = try? JSONDecoder().decode(EntranceLocation.self, from: data),
              (-90...90).contains(value.latitude), (-180...180).contains(value.longitude), value.accuracy >= 0, value.accuracy <= 20 else { return nil }
        return value
    }
    var body: some View {
        List {
            Section {
                Text(target.route.room.label).font(.largeTitle.bold())
                Text(target.draft.name).foregroundStyle(highContrast ? Color.primary : Color.secondary)
                Text("\(target.route.distance.formatted(.number.precision(.fractionLength(0)))) m from \(target.route.entrance.label)")
                Button("Go with camera", systemImage: "location.north.fill") { camera = true }
                    .buttonStyle(.borderedProminent).frame(minHeight: 48)
            }
            if let entrance {
                Section {
                    NavigationLink("Directions to the entrance") {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: entrance.latitude, longitude: entrance.longitude)))
                        OutdoorRouteView(destination: named(item), settings: settings, indoor: target)
                    }
                }
            }
            Section {
                DisclosureGroup("Preview indoor path") { TraceView(samples: target.draft.samples, landmarks: [target.route.entrance, target.route.room]) }
                Text("The camera will try to recognize the entrance and saved map. If it cannot, it will ask you to confirm a known landmark.").font(.footnote).foregroundStyle(highContrast ? Color.primary : Color.secondary)
            }
        }.navigationTitle("Your destination").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fullScreenCover(isPresented: $camera) { HallwayLaunchView(route: target.route, draft: target.draft, library: target.library, settings: settings) }
    }
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
    var requestCamera: (() -> Void)?
    var floorInfo: (JourneyDestination) -> String = { _ in "Floor label unknown" }
    private var ledger = AgentExecutionLedger()
    private var utterance = ""
    func beginAgentTurn(_ text: String) { utterance = text; ledger.invalidate() }
    func agentContext() -> AgentContext {
        AgentContext(sessionId: ledger.sessionId, sessionRevision: ledger.revision, buildingId: "not-localized", floor: nil,
            tracking: "uncertain", destinationId: "", avoidStairs: preferences.avoidStairs,
            instruction: "Discovery only. Resolve a saved destination and ask for confirmation. No active camera or verified position. Floor unknown unless separately confirmed.",
            knownDestinations: catalog.prefix(100).map { ["id": $0.id.uuidString, "name": $0.room, "building": $0.building, "mapId": $0.scanID.uuidString] }, knownClosures: [])
    }
    func handleVoice(_ text: String) { fallback(text) }
    func presentAgentResult(_ result: AgentToolResult) { voiceResponse = result.userSafeExplanation; speak(result.userSafeExplanation) }
    func executeAgent(_ call: AgentCall) async -> AgentToolResult {
        var status = AgentToolResult.Status.success; var text = ""; var data: [String: String] = [:]
        do {
            if let previous = try ledger.validate(call) { return previous }
            switch call.tool {
            case .resolveDestination:
                let matches = DestinationSearch.matches(utterance, in: catalog)
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
