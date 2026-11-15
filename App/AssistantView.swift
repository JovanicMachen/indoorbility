import SwiftUI
import IndoorbilityCore

struct AssistantView: View {
    @ObservedObject var store: AppStore
    @StateObject private var library = ScanLibrary()
    @StateObject private var memory = JourneyLibrary()
    @StateObject private var voice = VoiceCommandInput()
    @StateObject private var helper = DestinationAgentHost()
    @FocusState private var requestFocused: Bool
    @State private var request = ""
    @State private var response = ""
    @State private var destination: IndoorJourneyTarget?
    @State private var shopping: [String]?
    @State private var showShopping = false
    @State private var cameraHelp = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little help,\nwhen you need it.").font(.largeTitle.weight(.semibold)).foregroundStyle(Color.indoorTeal)
                    Text("Ask about a place, your route, or a general question.").foregroundStyle(.secondary)
                }.padding(.top, 20)
                Panel {
                    TextField("What would you like to know?", text: $request, axis: .vertical)
                        .focused($requestFocused).lineLimit(2...5).accessibilityIdentifier("assistantRequest")
                    HStack {
                        Button("Use camera", systemImage: "camera") { cameraHelp = true }
                            .frame(minHeight: 48).accessibilityIdentifier("cameraAssistance")
                        Spacer()
                        Button("Ask", action: plan).buttonStyle(.borderedProminent)
                            .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || helper.agent.busy)
                            .accessibilityIdentifier("assistantPlan")
                    }
                }
                AgentActivityView(agent: helper.agent)
                if !response.isEmpty {
                    Panel { Text(response).textSelection(.enabled).accessibilityIdentifier("assistantResponse") }
                }
                if voice.busy { Text(voice.status).font(.footnote).foregroundStyle(.secondary) }
            }.padding(24)
        }.scrollDismissesKeyboard(.interactively)
            .background(Color.indoorBackground).navigationTitle("Help")
            .safeAreaInset(edge: .bottom) { if !requestFocused { HoldToTalk(voice: voice, before: { store.stopSpeech() }, onUnrecognized: { store.speak(VoiceCommandInput.notUnderstood) }, haptics: store.preferences.haptics, result: { text in request = text; plan() }).padding().frame(maxWidth: .infinity).background(Color.indoorBackground) } }
            .overlay { VoiceEdgeGlow(active: voice.listening) }
            .onAppear {
                library.reload(); memory.refresh(from: library)
                helper.catalog = memory.preferredDestinations; helper.preferences = store.preferences
                helper.fallback = { _ in localPlan() }
                helper.speak = { response = $0; store.speak($0, force: true, userRequested: true) }
                helper.acknowledge = { store.speak(VoiceResponseTiming.acknowledgment, priority: .ambient) }
                helper.requestCamera = { cameraHelp = true }
                helper.found = { place in
                    UserDefaults.standard.set(place.room + " " + place.building, forKey: "pendingDestinationQuery")
                    store.selectedTab = 0
                }
            }
            .onDisappear { helper.agent.cancel(); helper.found = { _ in }; helper.fallback = { _ in }; helper.speak = { _ in }; helper.acknowledge = {}; helper.requestCamera = nil }
            .fullScreenCover(isPresented: $cameraHelp) { CameraAssistanceView(settings: store) }
            .sheet(item: $destination) { target in NavigationStack { DestinationJourneyView(target: target, settings: store) } }
            .sheet(isPresented: $showShopping) { NavigationStack { ShoppingDemoView(settings: store, initialItems: shopping ?? [], hardAvoidStairs: LocalNavigationAgent.constraints(for: request, base: store.preferences).avoidStairs) } }
    }
    private func plan() {
        requestFocused = false
        if request.lowercased().hasPrefix("buy ") { localPlan(); return }
        helper.preferences = store.preferences; helper.agent.submit(request, model: helper)
    }
    private func localPlan() {
        let question = request.lowercased()
        if question.contains("what") && (question.contains("front") || question.contains("ahead")) {
            cameraHelp = true; response = "Opening the camera. Ask when you’re ready."; store.speak(response); return
        }
        if question.contains("where am i") {
            response = "Open a saved route on Home to confirm your indoor position."; store.speak(response); return
        }
        if question.contains("stairs") && !question.contains("room") {
            response = store.preferences.avoidStairs ? "Avoid stairs is on. Only verified step-free indoor connections can be used." : "Avoid stairs is off. You can turn it on in Accessibility."; store.speak(response); return
        }
        switch LocalNavigationAgent.interpret(request, destinations: memory.destinations) {
        case .destination(let id):
            do {
                guard let place = memory.destinations.first(where: { $0.id == id }), let draft = library.scans.first(where: { $0.id == place.scanID }),
                      let route = try library.hallway(draft), route.id == id else { throw MapError.invalid("The mapped destination could not be found.") }
                let state = try library.navigationStore(route)
                _ = try VerifiedNavigationTools.calculateRoute(in: route.building, start: "entrance", destination: "room", preferences: LocalNavigationAgent.constraints(for: request, base: store.preferences), blocked: state.blockedEdges)
                UserDefaults.standard.set(place.room + " " + place.building, forKey: "pendingDestinationQuery")
                store.selectedTab = 0
                response = "Confirm this destination on Home before guidance starts."
            } catch { response = error.localizedDescription }
        case .shopping(let items): shopping = items; showShopping = true; response = "Opening a fictional store demonstration. Unknown products will remain unlocated."
        case .ambiguous: response = "More than one building has that room. Include the building name."
        case .unknown: response = "I couldn’t find a saved route. Search on Home or record one first."
        }
        store.speak(response)
    }
}

struct ShoppingDemoView: View {
    @ObservedObject var settings: AppStore
    let initialItems: [String]
    var hardAvoidStairs = false
    @AppStorage("shoppingDemoMemory") private var savedTrip = Data()
    private struct Trip: Codable { var items: [String]; var current: String; var completed: [String]; var blocked: Set<String> }
    @StateObject private var shoppingAgent = ShoppingAgentHost()
    @State private var agentRequest = ""
    @State private var items: [String] = []
    @State private var current = "entrance"
    @State private var input = ""
    @State private var plan: ShoppingPlan?
    @State private var error: String?
    @State private var blocked = Set<String>()
    @State private var completed: [String] = []
    @Environment(\.dismiss) private var dismiss
    private var building: Building? { try? ShoppingRoutePlanner.retailDemo() }
    var body: some View {
        List {
            Section {
                Label("Fictional store simulation", systemImage: "cart").font(.headline)
                Text("Product locations are sample data. Checkoffs simulate movement; camera tracking is not used here.").font(.footnote)
                TextEditor(text: $input).frame(minHeight: 70).accessibilityLabel("Add or paste shopping items")
                Button("Add items") {
                    items += input.replacingOccurrences(of: " and ", with: ",").components(separatedBy: CharacterSet(charactersIn: ",\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
                    input = ""; replan()
                }
            }
            Section("Shopping assistant") {
                TextField("Add shampoo, then optimize my route", text: $agentRequest)
                Button("Ask assistant") { shoppingAgent.agent.submit(agentRequest, model: shoppingAgent) }
                    .disabled(agentRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shoppingAgent.agent.busy)
                if let response = shoppingAgent.voiceResponse { Text(response) }
                Text("Uses this fictional store's graph. No live retailer data.").font(.caption)
                if UserDefaults.standard.bool(forKey: "agentDeveloperMode") {
                    NavigationLink("Agent timeline") { AgentTimelineView(agent: shoppingAgent.agent) }
                }
            }
            Section("Your list") {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack { Text(item); Spacer(); Button("Remove") { items.remove(at: index); replan() }.buttonStyle(.borderless) }
                }
            }
            if let plan, let building {
                Section("Next stop") {
                    Text(building.node(plan.stops.first ?? "checkout")?.label ?? "Checkout").font(.title2.bold())
                    if current == "checkout", plan.stops == ["checkout"] { Text(plan.unknownItems.isEmpty ? "Demo shopping trip complete" : "Checkout reached. Unlocated items remain on your list.") }
                    else {
                        Button(plan.stops.first == "checkout" ? "Confirm checkout (demo)" : "Collected (demo)") {
                            guard let next = plan.stops.first else { return }
                            current = next
                            let collected = items.filter { ShoppingRoutePlanner.demoProducts[$0] == next }
                            completed += collected; items.removeAll { collected.contains($0) }; replan()
                        }.buttonStyle(.borderedProminent)
                        if let next = plan.stops.first, next != "checkout" {
                            Button("Skip this item") { items.removeAll { ShoppingRoutePlanner.demoProducts[$0] == next }; replan() }
                        }
                    }
                    Text("Optimized route: \(plan.stops.compactMap { building.node($0)?.label }.joined(separator: " → "))").font(.subheadline)
                    Text("\(plan.cost.formatted()) demo distance units").font(.caption)
                    if !plan.unknownItems.isEmpty { Text("Location unknown: \(plan.unknownItems.joined(separator: ", ")). These items are excluded from routing.").foregroundStyle(.orange) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            Section("Demo disruption") {
                Toggle("Dairy aisle closed", isOn: Binding(get: { blocked.contains("dairy") }, set: { if $0 { blocked.insert("dairy") } else { blocked.remove("dairy") }; replan() }))
                Text("This toggle simulates a confirmed closure and recalculates the remaining stops.").font(.caption)
            }
            if !completed.isEmpty { Section("Collected") { Text(completed.joined(separator: ", ")) } }
        }.navigationTitle("Shopping demo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                if initialItems.isEmpty, let saved = try? JSONDecoder().decode(Trip.self, from: savedTrip), building?.node(saved.current) != nil {
                    items = saved.items; current = saved.current; completed = saved.completed; blocked = saved.blocked
                } else { items = initialItems.isEmpty ? ["milk","cereal","paper towels","shampoo"] : initialItems }
                replan()
                shoppingAgent.read = { (items, completed, current, blocked, hardAvoidStairs || settings.preferences.avoidStairs) }
                shoppingAgent.add = { item in if !items.contains(item) { items.append(item) }; replan() }
                shoppingAgent.speak = { settings.speak($0, force: true) }
            }
            .onDisappear { shoppingAgent.agent.cancel() }
    }
    private func replan() {
        if let data = try? JSONEncoder().encode(Trip(items: items, current: current, completed: completed, blocked: blocked)) { savedTrip = data }
        do {
            guard let building else { throw MapError.invalid("Retail demo unavailable.") }
            plan = try ShoppingRoutePlanner.plan(items: items, catalog: ShoppingRoutePlanner.demoProducts, in: building, from: current, checkout: "checkout", avoidStairs: hardAvoidStairs || settings.preferences.avoidStairs, blocked: blocked)
            error = nil
            if let next = plan?.stops.first { settings.speak("Demo next stop: \(building.node(next)?.label ?? next).") }
        } catch { plan = nil; self.error = error.localizedDescription; settings.speak(error.localizedDescription) }
    }
}
