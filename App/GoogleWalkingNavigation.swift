import SwiftUI
import CoreLocation
import GoogleMaps
import GoogleNavigation

/// A single Google session for the outdoor part of a journey. Indoor coordinates
/// and localization remain entirely separate from this session.
@MainActor final class GoogleWalkingNavigation: NSObject, ObservableObject, GMSNavigatorListener {
    @Published private(set) var session: GMSNavigationSession?
    @Published private(set) var instruction = ""
    @Published private(set) var distanceToTurn: Double?
    @Published private(set) var distanceToDestination: Double?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var active = false
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = 0
    private var deadline: Task<Void, Never>?
    private var lastCallbackTime = -Double.infinity
    private static var configured = false

    static var hasKey: Bool {
        guard let url = Bundle.main.url(forResource: "MapsConfig", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = values["GoogleNavigationAPIKey"] as? String else { return false }
        return !key.isEmpty && !key.hasPrefix("YOUR_")
    }

    func start(destination: CLLocationCoordinate2D, title: String) {
        guard !loading, !active else { return }
        guard let url = Bundle.main.url(forResource: "MapsConfig", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = values["GoogleNavigationAPIKey"] as? String,
              !key.isEmpty, !key.hasPrefix("YOUR_") else {
            error = "Google navigation is not configured."; return
        }
        guard let waypoint = GMSNavigationWaypoint(location: destination, title: title) else {
            error = "Destination is unavailable."; return
        }
        if !Self.configured {
            guard GMSServices.provideAPIKey(key) else { error = "Google navigation could not start."; return }
            Self.configured = true
        }
        generation += 1
        let request = generation
        loading = true; error = nil
        let options = GMSNavigationTermsAndConditionsOptions(companyName: "Indoorbility")
        GMSNavigationServices.showTermsAndConditionsDialogIfNeeded(with: options) { [weak self] accepted in
            guard let self, self.generation == request else { return }
            guard accepted, let session = GMSNavigationServices.createNavigationSession(),
                  let navigator = session.navigator else {
                self.loading = false; self.error = "Google navigation could not start."; return
            }
            self.session = session
            session.travelMode = .walking
            navigator.add(self)
            navigator.voiceGuidance = .silent
            session.isStarted = true
            self.armDeadline(for: request, message: "Google route request timed out.")
            navigator.setDestinations([waypoint]) { [weak self] status in
                guard let self, self.generation == request else { return }
                self.loading = false
                guard status == .OK else {
                    self.fail("Google route unavailable (status \(status.rawValue))."); return
                }
                self.active = true
                navigator.isGuidanceActive = true
                if self.lastUpdate == nil { self.armDeadline(for: request, message: "Google guidance did not start.") }
            }
        }
    }

    @objc(navigator:didUpdateNavInfo:)
    nonisolated func navigator(_ navigator: GMSNavigator, didUpdate navInfo: GMSNavigationNavInfo) {
        // Only immutable values cross to the UI actor; no SDK object is moved
        // between executors or used to mutate published state off-main.
        let identity = ObjectIdentifier(navigator), captured = ProcessInfo.processInfo.systemUptime
        let text = navInfo.navState == .enroute ? navInfo.currentStep?.fullInstructionText : nil
        let turn = navInfo.distanceToCurrentStepMeters, destination = navInfo.distanceToFinalDestinationMeters
        let received = Date()
        Task { @MainActor [weak self] in
            guard let self, let current = self.session?.navigator, ObjectIdentifier(current) == identity,
                  captured >= self.lastCallbackTime else { return }
            self.lastCallbackTime = captured
            guard let text else {
                self.instruction = ""; self.distanceToTurn = nil; self.distanceToDestination = nil; self.lastUpdate = nil; return
            }
            self.deadline?.cancel(); self.deadline = nil
            self.lastUpdate = received
            self.instruction = text
            self.distanceToTurn = turn.isFinite ? max(0, turn) : nil
            self.distanceToDestination = destination.isFinite ? max(0, destination) : nil
        }
    }

    private func armDeadline(for request: Int, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, let self, self.generation == request else { return }
            self.fail(message)
        }
    }
    private func fail(_ message: String) {
        generation += 1; loading = false; stopSession(); error = message
    }
    func stop() { generation += 1; loading = false; stopSession(); error = nil }
    private func stopSession() {
        deadline?.cancel(); deadline = nil
        session?.navigator?.isGuidanceActive = false
        session?.navigator?.remove(self)
        session?.isStarted = false
        session = nil; active = false; instruction = ""; distanceToTurn = nil; distanceToDestination = nil; lastUpdate = nil
        // Also reject queued snapshots from a stopped session, even if an SDK
        // navigator object address is later reused by a new session.
        lastCallbackTime = ProcessInfo.processInfo.systemUptime
    }
}

struct GoogleWalkingMap: UIViewRepresentable {
    let session: GMSNavigationSession
    func makeUIView(context: Context) -> GMSMapView {
        let map = GMSMapView(options: GMSMapViewOptions())
        _ = map.enableNavigation(with: session)
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = true
        return map
    }
    func updateUIView(_ map: GMSMapView, context: Context) {}
}
