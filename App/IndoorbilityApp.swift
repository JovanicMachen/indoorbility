import SwiftUI
import IndoorbilityCore

@main
struct IndoorbilityApp: App {
    init() {
        // Registration supplies defaults without overwriting a user's saved off switches.
        UserDefaults.standard.register(defaults: [
            "depthAdvisories": true,
            "floorAlerts": true,
            "phoneCoaching": true,
            "guidanceCues": true,
            "directionalSound": false,
            // Indoor directions read "30 ft"; a user who switched to metres keeps metres.
            "guidanceFeet": true
        ])
    }
    var body: some Scene {
        WindowGroup { LaunchView() }
    }
}

private struct LaunchView: View {
    @State private var store: AppStore?
    @State private var failure: String?
    @State private var confirmRecovery = false
    var body: some View {
        Group {
            if let store { RootView(store: store) }
            else if let failure {
                ContentUnavailableView {
                    Label("Unable to open your map", systemImage: "exclamationmark.folder")
                } description: {
                    Text(failure + "\nSaved reports have not been overwritten.")
                } actions: {
                    Button("Try again", action: load).buttonStyle(.borderedProminent)
                    Button("Start fresh with a backup") { confirmRecovery = true }
                }
            } else { ProgressView("Opening Indoorbility…") }
        }.task { if store == nil { load() } }
        .alert("Start a fresh demo?", isPresented: $confirmRecovery) {
            Button("Back up and start fresh") {
                do { try AppStore.recoverSavedState(); load() }
                catch { failure = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The original saved file will be kept as a backup in this app’s storage. Its reports will not apply to the new demo.")
        }
    }
    private func load() {
        do { store = try AppStore(); failure = nil }
        catch { failure = error.localizedDescription }
    }
}
