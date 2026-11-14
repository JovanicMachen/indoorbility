import SwiftUI
import IndoorbilityCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @AppStorage("agentDeveloperMode") private var developer = false
    @State private var confirmReset = false
    @State private var controlsPresented = false
    @State private var accessibilityPresented = false
    @State private var cameraHelp = false
    var body: some View {
        Form {
            Section {
                Button("Camera help", systemImage: "camera") { cameraHelp = true }
                    .accessibilityIdentifier("cameraAssistance")
                Button { accessibilityPresented = true } label: {
                    Label("Accessibility & guidance", systemImage: "accessibility")
                }
                NavigationLink { AgentSettingsView(store: store).swipeLeftToGoBack() } label: {
                    Label("AI connection", systemImage: "bubble.left.and.bubble.right")
                }
            }
            Section("Your places") {
                NavigationLink { ScanHubView(store: store) } label: {
                    Label("Saved rooms & maps", systemImage: "square.stack.3d.up")
                }
                NavigationLink { RememberRouteView(settings: store) } label: {
                    Label("Record a route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
            }
            Section {
                NavigationLink("Advanced & testing") { advanced.swipeLeftToGoBack() }
                NavigationLink("Privacy & about") {
                    Form {
                        Section("Your data") {
                            Text("Scans and saved routes are stored on this phone. Sharing is optional.")
                            Text("Place search uses Apple or Google. The cloud assistant sends requests only when enabled.")
                            Text("Saved indoor routes work offline after your position is confirmed.")
                        }
                        Section("Indoorbility") {
                            Text("Find a place. Follow a saved route. Return with confidence.")
                            Text("Experimental navigation support; not a replacement for mobility aids or emergency guidance.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }.swipeLeftToGoBack().navigationTitle("Privacy & about").scrollContentBackground(.hidden).background(Color.indoorBackground)
                }
            }
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden).background(Color.indoorBackground)
        .tint(.indoorTeal)
        .sheet(isPresented: $accessibilityPresented) { GuidancePreferencesView(store: store) }
        .fullScreenCover(isPresented: $cameraHelp) { CameraAssistanceView(settings: store) }

    }
    private var advanced: some View {
        Form {
            Section("Controls") {
                Button("Voice & face controls", systemImage: "mic") { controlsPresented = true }
                    .accessibilityIdentifier("settingsCommands")
            }
            Section("Reference & discovery") {
                NavigationLink("Friend Center information") { FriendCenterView(store: store) }
                NavigationLink("Google place discovery") { GoogleDiscoveryView(settings: store) }
            }
            Section {
                Toggle("Developer tools", isOn: $developer)
                if developer { NavigationLink("Test navigation") { GuidanceTestView(store: store) } }
                NavigationLink("Demo building & reports") { BuildingView(store: store) }
                NavigationLink("Demo navigation") { NavigateView(store: store) }
                NavigationLink("Shopping demo") { ShoppingDemoView(settings: store, initialItems: []) }
            } header: { Text("Testing") } footer: { Text("Demos use sample locations.") }
            Section {
                Button("Reset demo", role: .destructive) { confirmReset = true }.accessibilityIdentifier("resetDemo")
            } footer: { Text("Resets reports and preferences. Saved scans are kept.") }
        }.navigationTitle("Advanced").scrollContentBackground(.hidden).background(Color.indoorBackground)
        .sheet(isPresented: $controlsPresented) { AccessibleControlView(store: store) }
        .confirmationDialog("Reset demo data and preferences?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset reports and preferences", role: .destructive) { store.change { $0.reset() } }
            Button("Cancel", role: .cancel) { }
        }
    }
}
