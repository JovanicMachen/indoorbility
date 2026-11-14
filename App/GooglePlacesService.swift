import SwiftUI
import IndoorbilityCore

struct GooglePlace: Decodable, Identifiable {
    struct Coordinate: Decodable { let latitude: Double; let longitude: Double }
    let location: Coordinate?
    struct DisplayName: Decodable { let text: String }
    struct Attribution: Decodable { let provider: String?; let providerUri: String? }
    let id: String
    let displayName: DisplayName?
    let formattedAddress: String?
    let googleMapsUri: String?
    let attributions: [Attribution]?
}

@MainActor final class GooglePlacesService: ObservableObject {
    @Published var results: [GooglePlace] = []
    @Published var error: String?
    @Published var loading = false
    private var generation = UUID()
    private let session = URLSession(configuration: .ephemeral)
    static var configured: Bool { key != nil }
    private static var key: String? {
        guard let url = Bundle.main.url(forResource: "MapsConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let config = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let key = config["GooglePlacesAPIKey"], !key.isEmpty else { return nil }
        return key
    }
    func cancel() { generation = UUID(); loading = false; results = []; error = nil }
    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        guard let key = Self.key else { error = "Google Places is not configured. Native destination search remains available."; return }
        let token = UUID(); generation = token; loading = true; error = nil; results = []
        do {
            var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
            request.setValue(Bundle.main.bundleIdentifier ?? "com.indoorbility.app", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
            request.setValue("places.id,places.displayName,places.formattedAddress,places.googleMapsUri,places.attributions,places.location", forHTTPHeaderField: "X-Goog-FieldMask")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["textQuery": query, "pageSize": 8])
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw MapError.invalid("Google discovery is unavailable. Check Places API access, billing and key restrictions in your Google project.")
            }
            struct Response: Decodable { let places: [GooglePlace]? }
            let responseData = try JSONDecoder().decode(Response.self, from: data)
            guard generation == token else { return }; results = responseData.places ?? []
        } catch { if generation == token { self.error = error.localizedDescription } }
        if generation == token { loading = false }
    }
}

/// Google content is kept off Apple's map and is not persisted into the indoor graph.
struct GoogleDiscoveryView: View {
    @ObservedObject var settings: AppStore
    @StateObject private var service = GooglePlacesService()
    @State private var query = ""
    var body: some View {
        List {
            Section {
                TextField("Building or place", text: $query).submitLabel(.search).onSubmit { search() }
                Button("Search Google Places", action: search).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.loading)
                if service.loading { ProgressView("Searching…") }
                if let error = service.error { Text(error).foregroundStyle(.secondary) }
            }
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section {
                    NavigationLink("Find outdoor directions for this search") { NativeDestinationSearchView(query: query, settings: settings) }
                } footer: { Text("Searches your original words with Apple Maps. Google result locations are not transferred to Apple's map.") }
            }
            Section {
                ForEach(service.results) { place in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.displayName?.text ?? "Place").font(.headline)
                        if let address = place.formattedAddress { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                        Text("Place information · Google Maps").font(.caption)
                        ForEach(Array((place.attributions ?? []).enumerated()), id: \.offset) { _, attribution in
                            if let name = attribution.provider { Text(name).font(.caption) }
                        }
                    }.padding(.vertical, 6)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Google Maps").font(.system(size: 16, weight: .medium))
                    Text("Place discovery only. Room locations and indoor accessibility come from your reviewed maps.")
                    Link("Google Maps terms", destination: URL(string: "https://www.google.com/help/terms_maps/")!)
                    Link("Google privacy policy", destination: URL(string: "https://policies.google.com/privacy")!)
                }
            }
        }.navigationTitle("Discover buildings").navigationBarTitleDisplayMode(.inline)
    }
    private func search() { Task { await service.search(query) } }
}
