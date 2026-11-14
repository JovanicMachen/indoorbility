import SwiftUI
import MapKit
import IndoorbilityCore

/// Destination identity comes from the reviewed catalog, never generated geometry.
struct RecordDestinationView: View {
    @ObservedObject var settings: AppStore
    let request: RoomMappingRequest
    private var buildingDestination: MKMapItem? = nil
    private var resumeDirections: (() -> Void)? = nil
    private var resolvedBuilding: MKMapItem? {
        buildingDestination ?? BuildingDirectionsCatalog.destination(for: request.building)
    }
    init(settings: AppStore, room: FriendCenter.Room) {
        self.settings = settings
        request = RoomMappingRequest(building: FriendCenter.name, room: room.id, verifiedFloor: room.level)
    }
    init(settings: AppStore, request: RoomMappingRequest, alreadyInside: Bool = false, buildingDestination: MKMapItem? = nil, resumeDirections: (() -> Void)? = nil) {
        self.settings = settings; self.request = request; self.buildingDestination = buildingDestination; self.resumeDirections = resumeDirections
        _inside = State(initialValue: alreadyInside)
    }
    @State private var inside = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceCommandInput()
    @State private var record = false
    @State private var directions = false
    @State private var message = ""
    private func openDirections() {
        if let resumeDirections { resumeDirections() }
        else { directions = true }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "door.left.hand.open").font(.system(size: 36, weight: .medium))
                            .foregroundStyle(Color.indoorTeal).frame(width: 80, height: 80)
                            .background(Color.indoorPeach.opacity(0.3), in: RoundedRectangle(cornerRadius: 24))
                        Text("Room \(request.room)").font(.largeTitle.weight(.semibold))
                        Text(request.building == FriendCenter.name ? "Friend Center" : request.building)
                            .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let floor = request.verifiedFloor { Text("Level " + floor).font(.subheadline).foregroundStyle(.secondary) }
                    }.padding(.vertical, 16).frame(maxWidth: .infinity)
                    Panel {
                        Text("Indoor route not saved").font(.headline)
                        Toggle("I’m already inside", isOn: $inside)
                    }
                    if !inside {
                        PrimaryButton(title: "Directions to building", systemImage: "location.fill") { openDirections() }
                    }
                    Button { record = true } label: {
                        Label("Record route", systemImage: "record.circle")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }.buttonStyle(.bordered).tint(.indoorTeal)
                        .accessibilityIdentifier("recordKnownDestination")
                    if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    HoldToTalk(voice: voice, before: { settings.stopSpeech() }, onUnrecognized: { settings.speak(VoiceCommandInput.notUnderstood) }, haptics: settings.preferences.haptics) { text in
                        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                        if value.contains("lost") || value.contains("help") {
                            message = "Outside? Choose Directions to building. Inside? Ask staff for the room; record the route once you know it."
                            settings.speak(message)
                        } else if value.contains("direction") || value.contains("outside") || value.contains("building") && !value.contains("inside") {
                            openDirections()
                        } else if value.contains("inside") { inside = true; message = "Choose Record route when you know the way."; settings.speak(message) }
                        else if value.contains("record") || value.contains("trace") || ["yes", "yes please"].contains(value) { record = true }
                        else if ["no", "cancel", "no thanks"].contains(value) { dismiss() }
                        else { message = "Building directions or record a route?"; settings.speak(message) }
                    }
                    if !voice.busy && !voice.status.hasPrefix("Tap Listen") && !voice.status.hasPrefix("Heard:") && voice.status != VoiceCommandInput.notUnderstood {
                        Text(voice.status).font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }.background(Color.indoorBackground)
                .tint(.indoorTeal)
                .navigationTitle("Destination").navigationBarTitleDisplayMode(.inline)
                .swipeLeftToGoBack { dismiss() }
                .toolbar { Button("Close") { dismiss() } }
                .fullScreenCover(isPresented: $directions) {
                    NavigationStack {
                        if let destination = resolvedBuilding {
                            OutdoorRouteView(destination: destination, settings: settings, automaticallyStart: true, initialRoom: request.room)
                        } else { NativeDestinationSearchView(query: request.building, settings: settings) }
                    }
                }
                .navigationDestination(isPresented: $record) { RememberRouteView(settings: settings, requestedRoom: request, onFinished: { dismiss() }) }
                .overlay { VoiceEdgeGlow(active: voice.listening) }
        }
    }
}

/// Published building map references only; these are not verified entrance or room positions.
enum BuildingDirectionsCatalog {
    static func destination(for building: String) -> MKMapItem? {
        guard building == FriendCenter.name else { return nil }
        // HackPrinceton's published Friend Center venue map (reviewed 2026-11-14):
        // https://github.com/hackprinceton/static-f17/blob/master/travel.md
        // Map center is a building-area destination, not a step-free entrance guarantee.
        let item = MKMapItem(placemark: MKPlacemark(coordinate:
            CLLocationCoordinate2D(latitude: 40.35032908895552, longitude: -74.65377999190959)))
        item.name = FriendCenter.name
        return item
    }
}
