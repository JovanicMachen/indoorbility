import SwiftUI
import VisionKit
import IndoorbilityCore

struct FriendCenterView: View {
    @ObservedObject var store: AppStore
    @AppStorage("agentDeveloperMode") private var developer = false
    @State private var readSign = false
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        List {
            Section("Friend Center · Princeton") {
                NavigationLink {
                    NativeDestinationSearchView(query: "Friend Center for Engineering Education Princeton University", settings: store)
                } label: {
                    Label("Directions to the building", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                Text("Known rooms · indoor route not ready").font(.headline)
                Text(FriendCenter.routeStatus)
                Text("Levels: " + FriendCenter.levels.joined(separator: ", "))
            }
            Section("Level LL") {
                ForEach(FriendCenter.rooms) { room in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Room \(room.id)").font(.headline)
                        Text(room.approach)
                        Text("Published door information: 83 cm opening, outward swing, effort needed to open; written, tactile and Braille signage. Current access needs checking.").font(.footnote)
                        NavigationLink("Record a route to this room") { RememberRouteView(settings: store, knownRoom: room) }
                        Link("Room accessibility source", destination: room.source)
                    }
                }
            }
            Section("Entrances and access") {
                ForEach(FriendCenter.buildingFacts, id: \.self) { Text($0) }
                Link("Building accessibility source", destination: FriendCenter.source)
                Link("Official campus map", destination: URL(string: "https://facilities.princeton.edu/maps")!)
                Text("Source review: \(FriendCenter.reviewedOn). These facts do not establish your current location, an open route or permission to enter.").font(.footnote)
            }
            if developer {
                Section("Friend Center field test") {
                    Button("Check room sign with camera") { text = ""; error = nil; readSign = true }
                    NavigationLink("Capture measured hallway and landmarks") { ScanHubView(store: store) }
                    Text("Mapper setup only: use an authorized LL plan or survey. Mark the elevator exit and the specific 006/008 doors; review the measured paths before enabling navigation. Visitors will use the prepared map.")
                    Text("Sign recognition identifies text only. It cannot align a floor plan or verify arrival by itself.")
                }
            }
        }
        .navigationTitle("Friend Center")
        .sheet(isPresented: $readSign) {
            NavigationStack {
                VStack {
                    if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                        LiveSignCamera(text: $text, error: $error)
                    } else { Text("Live text scanning is unavailable on this device.") }
                    Text(text.isEmpty ? "Point at a room sign." : text).padding()
                    let matches = FriendCenter.recognizedRooms(in: text)
                    Text(matches.isEmpty ? "No known room number detected." : "Text matches: " + matches.map { "Room " + $0.id }.joined(separator: ", "))
                    Text("Text evidence only · position remains unverified").font(.footnote).padding()
                    if let error { Text(error).foregroundStyle(.red) }
                }.navigationTitle("Room sign check").toolbar { Button("Done") { readSign = false } }
            }
        }
    }
}
