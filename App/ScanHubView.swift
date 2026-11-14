import SwiftUI
import IndoorbilityCore

struct ScanHubView: View {
    @ObservedObject var store: AppStore
    @StateObject private var library = ScanLibrary()
    @State private var signPresented = false
    @State private var pendingDelete: ScanDraft?
    @State private var deletionError: String?
    var body: some View {
        List {
            Section {
                NavigationLink { RememberRouteView(settings: store) } label: {
                    row("Record route", subtitle: "Choose a building, start and destination", symbol: "record.circle")
                }.accessibilityIdentifier("recordRoute")
            }
            Section {
                DisclosureGroup("Map tools") {
                    NavigationLink("Connect building areas") { BuildingCollectionsView(library: library, settings: store) }
                    NavigationLink("Import or share") { MapTransferView(library: library, drafts: []) }
                    Button { signPresented = true } label: {
                        Label("Read closure sign", systemImage: "text.viewfinder")
                    }.accessibilityIdentifier("readSign")
                    NavigationLink { SpatialCaptureView(library: library) } label: {
                        Label("Scan a space", systemImage: "cube.transparent")
                    }.accessibilityIdentifier("newSpatialScan")
                }
            }
            Section {
                if library.scans.isEmpty {
                    Text("No routes yet").foregroundStyle(.secondary)
                    Text("Record a walk between two familiar places.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(library.scans) { draft in
                    NavigationLink { ScanDetailView(library: library, settings: store, draft: draft) } label: {
                        row(recordTitle(draft), subtitle: draft.name + " · " + draft.createdAt.formatted(date: .abbreviated, time: .omitted), symbol: "map")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = draft } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)
                    }
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = draft } label: { Label("Delete recording", systemImage: "trash") }
                    }
                    .accessibilityAction(named: "Delete recording") { pendingDelete = draft }
                }
            } header: { Text("Saved routes") } footer: { Text("Swipe left or hold a recording to delete it.") }
            if let error = library.error { Text(error).foregroundStyle(.red) }
            if let deletionError { Text(deletionError).foregroundStyle(.red) }
        }.navigationTitle("Routes").navigationBarTitleDisplayMode(.inline)
            .onAppear { library.reload() }
            .confirmationDialog("Delete this recording?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                if let draft = pendingDelete {
                    Button("Delete recording", role: .destructive) {
                        do { try withAnimation { try library.delete(draft) }; deletionError = nil }
                        catch { deletionError = "Could not delete recording: " + error.localizedDescription }
                        pendingDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("Removes this route, its 3D scan and saved position map from this iPhone. Other recordings stay saved.")
            }
            .sheet(isPresented: $signPresented) { SignScanView(store: store) }
    }
    private func recordTitle(_ draft: ScanDraft) -> String {
        if let route = try? library.hallway(draft) { return route.entrance.label + " → " + route.room.label }
        return "Mapped area"
    }
    private func row(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Color.indoorTeal).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 8)
    }
}

struct ScanDetailView: View {
    @ObservedObject var library: ScanLibrary
    @ObservedObject var settings: AppStore
    let draft: ScanDraft
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(draft.name).font(.largeTitle.bold())
                if let route = try? library.hallway(draft) {
                    Text(route.entrance.label + " → " + route.room.label).font(.headline)
                    SmallTag(text: library.visitorReady(route) ? "Saved route" : "Ready to publish", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    if library.visitorReady(route) {
                        NavigationLink("Start directions") {
                            HallwayLaunchView(route: route, draft: draft, library: library, settings: settings)
                        }.buttonStyle(ForestButtonStyle())
                    }
                } else { SmallTag(text: "Saved scan", symbol: "square.3.layers.3d") }
                SavedScanPreview(file: library.directory(draft.id).appending(path: "mesh.json"))
                DisclosureGroup("Recorded path") {
                    TraceView(samples: draft.samples, landmarks: draft.landmarks)
                }
                if library.requiresVolunteerReview(draft.id), let route = try? library.hallway(draft) {
                    NavigationLink("Preview & publish") { VolunteerReviewView(library: library, settings: settings, draft: draft, route: route) }
                }
                NavigationLink { HallwaySetupView(library: library, settings: settings, draft: draft) } label: {
                    Label("Hallway directions", systemImage: "arrow.turn.up.right").padding(18).frame(maxWidth: .infinity)
                }.buttonStyle(ForestButtonStyle())
                NavigationLink("Share this map") { MapTransferView(library: library, drafts: [draft]) }
                DisclosureGroup("Scan details") {
                    LabeledContent("Recorded travel", value: "\(draft.recordedDistance.formatted(.number.precision(.fractionLength(1)))) m")
                    LabeledContent("Mesh vertices", value: draft.meshVertexCount.formatted())
                    LabeledContent("Mesh triangles", value: draft.meshTriangleCount.formatted())
                    LabeledContent("Landmarks", value: draft.landmarks.count.formatted())
                }
                NavigationLink { SpatialCaptureView(library: library, draft: draft) } label: { Label("Locate me in this space", systemImage: "location.fill").padding(18).frame(maxWidth: .infinity) }
                Button("Delete saved scan", role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
                if let error { Text(error).foregroundStyle(.red) }
                Text("Captured surfaces and route. Unscanned areas stay unknown.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.background(Color.indoorBackground).swipeLeftToGoBack().navigationTitle("Saved space").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this scan and its spatial map?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete scan", role: .destructive) { do { try library.delete(draft); dismiss() } catch { self.error = error.localizedDescription } }
            }
    }
}
