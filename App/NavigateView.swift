import SwiftUI
import IndoorbilityCore

struct NavigateView: View {
    @ObservedObject var store: AppStore
    @State private var proposedStart = "entrance"
    @State private var proposedDestination = ""
    @State private var showDestinationPicker = false
    @State private var reportPresented = false
    @State private var scanPresented = false
    @State private var controlsPresented = false
    @State private var editRoute = false
    @State private var floor = 1
    @State private var surface = "Camera"
    @Environment(\.dynamicTypeSize) private var textSize

    private var focusedGuidance: Bool { store.preferences.reducedInformation && store.session.isGuiding }
    private var planning: Bool { store.session.destinationID == nil || store.session.needsPosition || editRoute }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if !focusedGuidance {
                    VStack(spacing: 10) {
                        Picker("Navigation view", selection: $surface) {
                            Text("Camera").tag("Camera")
                            Text("Map").tag("Map")
                        }.pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 8)
                            .accessibilityIdentifier("navigationSurface")
                        if surface == "Camera" {
                            NavigationCameraView(store: store, isForeground: !reportPresented && !scanPresented && !showDestinationPicker && !controlsPresented) { id in
                                proposedStart = id
                                store.change { try $0.confirmCheckpoint(id) }
                                return store.session.checkpointID == id && store.errorMessage == nil
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else { map.frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if planning { planner }
                        else {
                            routeCard
                            Button("Change destination", systemImage: "magnifyingglass") { editRoute = true; showDestinationPicker = true }
                                .frame(maxWidth: .infinity, minHeight: 44)
                            if let route = store.session.route, !store.preferences.reducedInformation {
                                DisclosureGroup("Route details") {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("\(route.cost.formatted()) demo units · \(route.nodeIDs.count - 1) connections").font(.caption).foregroundStyle(.secondary)
                                        ForEach(route.nodeIDs, id: \.self) { id in
                                            if let node = store.building.node(id) { Label(node.label, systemImage: "circle").font(.subheadline) }
                                        }
                                        Text("Distances are example values, not metres or minutes.").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.top, 10)
                                }.font(.subheadline)
                            }
                        }
                    }.padding(20).padding(.bottom, 12)
                }
                .frame(height: focusedGuidance ? geometry.size.height : min(geometry.size.height * (textSize.isAccessibilitySize ? 0.72 : 0.58), planning && proposedDestination.isEmpty ? 290 : 385))
                .background(Color.indoorCard, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                .shadow(color: .black.opacity(0.06), radius: 12, y: -3)
            }.background(Color.indoorBackground)
        }
        .navigationTitle("Indoorbility").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.setPreference(\.speech, !store.preferences.speech) } label: {
                    Image(systemName: store.preferences.speech ? "speaker.wave.2.fill" : "speaker.slash")
                }
                .accessibilityLabel(store.preferences.speech ? "Turn narration off" : "Turn narration on")
                .accessibilityHint("Reads camera and navigation updates aloud")
                .accessibilityIdentifier("toggleNarration")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { controlsPresented = true } label: { Image(systemName: "mic") }
                    .accessibilityLabel("Voice and face controls").accessibilityIdentifier("openCommands")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { reportPresented = true } label: { Image(systemName: "flag") }
                    .accessibilityLabel("Report a closure").accessibilityIdentifier("reportToolbar")
            }
        }
        .sheet(isPresented: $controlsPresented) { AccessibleControlView(store: store) }
        .sheet(isPresented: $reportPresented) { ReportView(store: store) }
        .sheet(isPresented: $scanPresented) {
            SignScanView(store: store, purpose: .startingPoint) { id in
                proposedStart = id
                store.change { try $0.confirmCheckpoint(id) }
            }
        }
        .sheet(isPresented: $showDestinationPicker) {
            DestinationPicker(building: store.building, selection: $proposedDestination)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: store.session.destinationID) { _, id in
            if let id { proposedDestination = id; editRoute = false; surface = "Map" }
        }
        .onChange(of: store.session.checkpointID) { _, id in
            if let node = id.flatMap(store.building.node) { floor = node.floor; proposedStart = node.id }
        }
    }

    private var map: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Learning Center").font(.subheadline.weight(.semibold))
                    Text("Demo building").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Floor", selection: $floor) {
                    ForEach(store.building.floors) { Text("L\($0.id)").tag($0.id) }
                }.pickerStyle(.segmented).frame(width: 110)
            }.padding(.horizontal, 20).padding(.top, 12)
            FloorDiagram(building: store.building, route: store.session.route, blocked: store.blockedEdges,
                         checkpoint: store.session.checkpointID, floor: floor)
                .frame(minHeight: 110)
            HStack {
                Label(store.session.checkpointID.flatMap(store.building.node)?.label ?? "Starting point not set", systemImage: "location.fill")
                Spacer()
                Button { scanPresented = true } label: { Image(systemName: "camera.viewfinder").font(.title3).frame(width: 44, height: 44).background(Color.indoorCard, in: Circle()) }
                    .accessibilityLabel("Scan starting point").accessibilityIdentifier("quickScan")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var planner: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { showDestinationPicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text(store.building.node(proposedDestination)?.label ?? "Where to?")
                        .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    if !proposedDestination.isEmpty { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                }.padding(14).background(Color.indoorBackground, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityIdentifier("destinationPicker")
            if proposedDestination.isEmpty {
                Button { proposedDestination = "room_204" } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "door.left.hand.closed").frame(width: 28).foregroundStyle(Color.indoorTeal)
                        VStack(alignment: .leading, spacing: 2) { Text("Room 204").foregroundStyle(.primary); Text("Level 2").font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "arrow.up.left").foregroundStyle(.secondary)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("suggestedDestination")
                Divider()
                cameraRow
            } else {
                HStack {
                    Image(systemName: "location.circle").foregroundStyle(Color.indoorTeal)
                    Text("From").foregroundStyle(.secondary)
                    Picker("Starting point", selection: $proposedStart) {
                        ForEach(store.building.nodes) { Text($0.label).tag($0.id) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .trailing)
                }.font(.subheadline)
                if store.session.checkpointID != proposedStart {
                    HStack {
                        Button("I’m at \(store.building.node(proposedStart)?.label ?? "this point")") {
                            store.change { try $0.confirmCheckpoint(proposedStart) }
                        }.accessibilityIdentifier("confirmStart")
                        Spacer()
                        Button { scanPresented = true } label: { Label("Scan", systemImage: "camera") }
                            .accessibilityLabel("Scan starting point")
                    }.font(.subheadline).frame(minHeight: 44)
                }
                Toggle("Avoid stairs", isOn: Binding(get: { store.preferences.avoidStairs }, set: { store.setPreference(\.avoidStairs, $0) }))
                    .font(.subheadline).accessibilityIdentifier("avoidStairs")
                PrimaryButton(title: "Directions", systemImage: "arrow.turn.up.right") {
                    store.change { try $0.selectDestination(proposedDestination) }; editRoute = false; surface = "Map"
                }.disabled(store.session.needsPosition || store.session.checkpointID != proposedStart).accessibilityIdentifier("showRoute")
            }
        }
    }
    private var cameraRow: some View {
        Button { scanPresented = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder").font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Scan a starting sign").font(.subheadline.weight(.medium))
                    Text("Use a room number or entrance sign").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption)
            }.frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Color.indoorTeal).accessibilityIdentifier("scanStartingSign")
    }

    @ViewBuilder private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.session.needsPosition {
                Label("Where are you now?", systemImage: "location.slash").font(.headline)
                Text("Set your starting point to continue.").font(.subheadline).foregroundStyle(.secondary)
            } else if store.session.route != nil {
                HStack {
                    SmallTag(text: store.session.arrived ? "Arrived" : store.preferences.avoidStairs ? "Step-free" : "Stairs allowed", symbol: store.session.arrived ? "checkmark" : "figure.roll")
                    Spacer()

                }
                if store.session.arrived {
                    Text("You’ve arrived").font(.title2.weight(.semibold))
                    Text(store.session.destinationID.flatMap(store.building.node)?.label ?? "Destination").foregroundStyle(.secondary)
                } else {
                    Text(store.session.isGuiding ? store.session.nextCheckpoint?.label ?? "" : "Via \(store.connector)")
                        .font(.title2.weight(.semibold)).accessibilityIdentifier("routeHeadline")
                    if store.session.isGuiding {
                        Text(store.instruction).font(.subheadline).foregroundStyle(.secondary)
                        PrimaryButton(title: "I’m here", systemImage: "checkmark") {
                            if let next = store.session.nextCheckpoint { store.change { try $0.confirmCheckpoint(next.id) } }
                        }.accessibilityIdentifier("confirmNext")
                        HStack {
                            Button("Repeat", systemImage: "speaker.wave.2", action: store.repeatInstruction).disabled(!store.preferences.speech && !UIAccessibility.isVoiceOverRunning)
                            Spacer()
                            Button("Pause") { store.change { $0.stopGuidance() } }
                        }.font(.subheadline).frame(minHeight: 44)
                    } else {
                        Text("\(store.session.destinationID.flatMap(store.building.node)?.label ?? "Destination")")
                            .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("routeCost")
                        PrimaryButton(title: "Start", systemImage: "location.north.fill") { store.change { $0.startGuidance() } }
                            .accessibilityIdentifier("startGuidance")
                    }
                }
                if let delta = store.session.routeDelta, delta != 0 {
                    Label("\(delta > 0 ? "+" : "")\(delta.formatted()) demo units · route updated", systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(Color.indoorTeal).accessibilityIdentifier("routeDelta")
                }
                Button("I’m not sure where I am") { store.change { $0.forgetPosition() } }
                    .font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
            } else {
                IconTile(symbol: "signpost.right.and.left")
                Text("No route available").font(.title2.weight(.semibold)).accessibilityIdentifier("noRoute")
                Text("No route is available with these closures and preferences.")
                    .font(.subheadline).foregroundStyle(.secondary)
                PrimaryButton(title: "Review barriers", systemImage: "flag") { reportPresented = true }
            }
        }
    }
}

struct DestinationPicker: View {
    let building: Building
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        NavigationStack {
            List {
                ForEach(building.destinations(matching: query)) { node in
                    Button { selection = node.id; dismiss() } label: {
                        HStack(spacing: 14) {
                            IconTile(symbol: node.kind == "elevator" ? "arrow.up.arrow.down" : node.kind == "room" ? "door.left.hand.closed" : "mappin")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(node.label).font(.headline).foregroundStyle(.primary)
                                Text("Level \(node.floor)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == node.id { Image(systemName: "checkmark").foregroundStyle(Color.indoorTeal) }
                        }.padding(.vertical, 4)
                    }
                }
                if building.destinations(matching: query).isEmpty { Text("No matching places").foregroundStyle(.secondary) }
            }.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Room, entrance or lift")
                .navigationTitle("Choose destination").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
