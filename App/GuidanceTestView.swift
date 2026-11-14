import SwiftUI
import IndoorbilityCore

/// Synthetic inputs into the production follower and guidance/sound pipeline. No AR hardware claims.
struct GuidanceTestView: View {
    @ObservedObject var store: AppStore
    @State private var follower: HallwayFollower?
    @State private var delivery = GuidanceDelivery()
    @State private var time: Double = 0
    @State private var index = 0
    @State private var note = "No simulation running."
    @State private var path: [SpatialPoint] = []
    @State private var draft: ScanDraft?
    var body: some View {
        Form {
            Section { Text("SIMULATED positions and surface events. No camera, LiDAR, or physical accuracy is tested here.").font(.headline) }
            Section("Instruction") {
                Text(follower.map { LiveGuidance.message($0, feet: UserDefaults.standard.bool(forKey: "guidanceFeet")).text } ?? "Start the test.")
                    .font(.title2).accessibilityIdentifier("testGuidanceInstruction")
                Text(note)
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(store.audio.journeyLoopPlaying ? "Travel loop: Playing" : "Travel loop: Stopped")
                        .font(.caption).accessibilityIdentifier("testJourneyLoopState")
                }
                Button("Start Test", action: start)
                Button("Advance position", action: advance).disabled(follower == nil)
                Button("Simulate tracking loss") { follower?.invalidate(); deliver() }
                Button("Recover at simulated landmark") {
                    guard let p = follower?.position ?? path.dropFirst(index).first else { return }
                    settle(p)
                    do { try follower?.recover(using: .identity, livePosition: p); deliver() } catch { note = error.localizedDescription }
                }
                Button("Simulate possible surface") { note = "Simulated: Possible surface ahead. Check your surroundings."; store.speak(note); store.cue(.attention) }
                Button("Simulate destination change") {
                    guard let draft, let current = follower, let target = draft.landmarks.last else { return }
                    do { follower = try current.changingDestination(to: target, on: current.route, draft: draft); store.stopSpeech(); delivery.reset(); store.cue(.changed); deliver() } catch { note = error.localizedDescription }
                }
                Button("Confirm simulated room label") { do { try follower?.confirmArrival(); deliver() } catch { note = error.localizedDescription } }
            }
            Section("Production sound controls") {
                NavigationSoundSettings(store: store)
                Button("Repeat instruction") { if let follower { store.speak(LiveGuidance.message(follower).text) } }
                ForEach(GuidanceCue.allCases, id: \.rawValue) { cue in Button("Play \(cue.rawValue) cue") { store.cue(cue) } }
                Text("Last requested speech: \(store.lastNarration)")
                Text("Last played cue: \(store.audio.lastCue)")
            }
        }.navigationTitle("Test navigation").onDisappear { store.stopSpeech() }
    }
    private func start() {
        path = (0...100).map { SpatialPoint(x: Float($0), y: 0, z: 0) }
            + (1...30).map { SpatialPoint(x: 100, y: 0, z: -Float($0)) }
            + (1...20).map { SpatialPoint(x: 100+Float($0), y: 0, z: -30) }
        let marks = [ScanLandmark(label: "Test entrance", kind: "entrance", position: path[0]), ScanLandmark(label: "Test Room 106", kind: "room", position: path.last!), ScanLandmark(label: "Test Room 105", kind: "room", position: path[path.count-6])]
        let data = ScanDraft(name: "SIMULATION", usesLiDAR: true, hasWorldMap: true, samples: path.map { ScanSample(position: $0, segment: 0) }, landmarks: marks, meshVertexCount: 30, meshTriangleCount: 10)
        do {
            let route = try HallwayRoute.make(draft: data, entranceID: marks[0].id, roomID: marks[1].id, reviewed: true)
            draft = data; follower = HallwayFollower(route: route); time = 0; index = 0; delivery.reset()
            settle(path[0]); try follower?.confirmEntrance(); note = "Simulation started; no live sensor evidence."; deliver()
        } catch { note = error.localizedDescription }
    }
    private func settle(_ p: SpatialPoint) {
        for _ in 0...25 { time += 0.1; follower?.update(position: p, heading: 0, time: time, trackingNormal: true) }
    }
    private func advance() {
        guard index < path.count-1 else { if let p = path.last { settle(p); deliver() }; return }
        // Feed intermediate poses at walking speed, never teleport the follower.
        let target = min(path.count-1, index < 80 ? index+10 : index+1)
        while index < target {
            let a = path[index], b = path[index+1]
            for step in 1...10 {
                time += 0.1
                let t = Float(step)/10
                follower?.update(position: SpatialPoint(x: a.x+(b.x-a.x)*t, y: 0, z: a.z+(b.z-a.z)*t), heading: atan2(b.z-a.z,b.x-a.x), time: time, trackingNormal: true)
                deliver()
            }
            index += 1
        }
    }
    private func deliver() {
        guard let follower else { return }
        let message = LiveGuidance.message(follower, feet: UserDefaults.standard.bool(forKey: "guidanceFeet"))
        if delivery.consume(message, listening: false) { store.speak(message.text); if let cue = message.cue { store.cue(cue) } }
        store.updateJourneySound(active: follower.stable && follower.state == .guiding)
    }
}
