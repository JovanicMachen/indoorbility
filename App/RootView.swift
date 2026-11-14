import SwiftUI

struct RootView: View {
    @ObservedObject var store: AppStore
    @AppStorage("highContrast") private var highContrast = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { PlacesHomeView(store: store) }
                .tabItem { Label("Home", systemImage: "location.north.line") }.tag(0)
            NavigationStack { ScanHubView(store: store) }
                .tabItem { Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(1)
            NavigationStack { SettingsView(store: store) }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .preferredColorScheme(.light)
        .tint(highContrast ? .primary : .indoorTeal)
        .onChange(of: phase) { _, value in if value != .active { store.stopSpeech() } }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in store.stopSpeech() }
        .alert("Unable to save this change", isPresented: Binding(
            get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
}
