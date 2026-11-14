import SwiftUI
import SceneKit
import IndoorbilityCore

// Attach to this view's own window so tab bars, sheets and bottom controls cannot clip the halo.
struct VoiceEdgeGlow: View {
    let active: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        WindowVoiceGlow(active: active && phase == .active, reduceMotion: reduceMotion)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WindowVoiceGlow: UIViewRepresentable {
    let active: Bool
    let reduceMotion: Bool
    func makeUIView(context: Context) -> GlowAttachment { GlowAttachment() }
    func updateUIView(_ view: GlowAttachment, context: Context) {
        view.host.rootView = AnyView(VoiceGlowRenderer(active: active, reduceMotion: reduceMotion))
        view.attach()
    }
    static func dismantleUIView(_ view: GlowAttachment, coordinator: ()) { view.host.view.removeFromSuperview() }
}

private final class GlowAttachment: UIView {
    let host = UIHostingController(rootView: AnyView(VoiceGlowRenderer(active: false)))
    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        host.safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func didMoveToWindow() { super.didMoveToWindow(); attach() }
    func attach() {
        guard let window else { host.view.removeFromSuperview(); return }
        if host.view.superview !== window {
            host.view.removeFromSuperview()
            host.view.frame = window.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            window.addSubview(host.view)
        }
        window.bringSubviewToFront(host.view)
    }
}

/// Listening feedback only: never implies tracking quality or arrival.
private struct VoiceGlowRenderer: View {
    let active: Bool
    var reduceMotion = false
    private var visible: Bool { active }
    private let orange = Color(red: 1, green: 0.39, blue: 0.08)
    private let amber = Color(red: 1, green: 0.69, blue: 0.30)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !visible || reduceMotion)) { context in
            let wave = reduceMotion ? 0.5 : (sin(context.date.timeIntervalSinceReferenceDate * .pi / 1.6) + 1) / 2
            let gradient = LinearGradient(colors: [amber, orange, .indoorPeach, orange, amber],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)
            ZStack {
                // Broad ambient light plus a crisp inner rim, leaving the camera unobscured.
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 10 + 3 * wave)
                    .blur(radius: 20).opacity(0.38 + 0.10 * wave)
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 4 + wave)
                    .blur(radius: 7).opacity(0.65)
                RoundedRectangle(cornerRadius: 46, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 1.3).opacity(0.45)
            }.padding(2)
        }
        .ignoresSafeArea()
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: visible)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct HoldToTalk: View {
    @ObservedObject var voice: VoiceCommandInput
    var before: () -> Void = {}
    var onUnrecognized: () -> Void = {}
    var haptics = false
    var diameter: CGFloat = 90
    var result: (String) -> Void
    @AppStorage("tapToTalk") private var tapMode = false
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var phase
    @State private var held = false
    @State private var starting: Task<Void, Never>?
    private var tapping: Bool { tapMode || voiceOver }
    var body: some View {
        VStack(spacing: 8) {
            Button { if tapping { toggle() } } label: {
                Image(systemName: voice.listening ? "waveform" : "mic.fill")
                    .font(.system(size: 32, weight: .medium)).foregroundStyle(.white)
                    .frame(width: diameter, height: diameter)
                    .background(LinearGradient(colors: [.indoorTeal, Color(red: 0.53, green: 0.29, blue: 0.43)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .overlay(Circle().stroke(Color.indoorPeach.opacity(0.6), lineWidth: 2))
                    .background(Circle().fill(Color.indoorPeach.opacity(voice.listening ? 0.4 : 0.16)).padding(-12))
                    .shadow(color: Color.indoorPeach.opacity(voice.listening ? 0.65 : 0.25), radius: voice.listening ? 28 : 15)
                    .animation(.easeInOut(duration: 0.3), value: voice.listening)
            }.buttonStyle(.plain)
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                    guard !tapping, !held, !voice.busy else { return }
                    held = true; begin()
                }.onEnded { _ in
                    guard !tapping else { return }; held = false
                    if voice.listening { voice.finish(); if haptics { UISelectionFeedbackGenerator().selectionChanged() } }
                    else if voice.status != "Finishing…" { starting?.cancel(); voice.cancel() }
                })
                .accessibilityLabel(voice.listening ? "Finish speaking" : "Speak to Indoorbility")
                .accessibilityIdentifier("holdToTalk")
            Text(voice.listening ? "Listening…" : voice.busy ? "Understanding…" : tapping ? "Tap to speak" : "Hold to speak")
                .font(.callout.weight(.medium))
        }
        .onChange(of: voice.status) { _, status in
            if status == VoiceCommandInput.notUnderstood { onUnrecognized() }
        }
        .onDisappear { starting?.cancel(); voice.cancel() }
        .onChange(of: phase) { _, value in if value != .active { starting?.cancel(); held = false; voice.cancel() } }
    }
    private func begin() {
        before()
        starting = Task { await voice.start(onResult: result) }
    }
    private func toggle() {
        if voice.listening { voice.finish(); if haptics { UISelectionFeedbackGenerator().selectionChanged() } } else if voice.busy { voice.cancel() } else { begin() }
    }
}

struct GuidancePreferencesView: View {
    @ObservedObject var store: AppStore
    @AppStorage("tapToTalk") private var tap = false
    @AppStorage("depthAdvisories") private var awareness = true
    @AppStorage("floorAlerts") private var floorAlerts = true
    @AppStorage("phoneCoaching") private var phoneCoaching = true
    @AppStorage("depthWideRegion") private var wide = false
    @AppStorage("highContrast") private var highContrast = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Guidance") {
                    Toggle("Spoken directions", isOn: Binding(get: { store.preferences.speech }, set: { store.setPreference(\.speech, $0) }))
                    Toggle("Vibration", isOn: Binding(get: { store.preferences.haptics }, set: { store.setPreference(\.haptics, $0) }))
                    Toggle("Avoid stairs", isOn: Binding(get: { store.preferences.avoidStairs }, set: { store.setPreference(\.avoidStairs, $0) }))
                }
                Section("Display & controls") {
                    Toggle("Simpler instructions", isOn: Binding(get: { store.preferences.reducedInformation }, set: { store.setPreference(\.reducedInformation, $0) }))
                    Toggle("Higher contrast", isOn: $highContrast)
                    Toggle("Tap to speak", isOn: $tap)
                }
                Section {
                    DisclosureGroup("Sound & voice") {
                        NavigationSoundSettings(store: store)
                        Button("Preview voice") { store.speak("Your next turn is on the left.") }
                            .disabled(!store.preferences.speech || store.allSoundMuted)
                            .accessibilityIdentifier("previewNarration")
                        Button("Stop speaking", action: store.stopSpeech)
                    }
                    DisclosureGroup("Camera alerts") {
                        Toggle("Phone-position tips", isOn: $phoneCoaching)
                        Toggle("Possible obstacles", isOn: $awareness)
                        Toggle("Possible drop-offs", isOn: $floorAlerts).disabled(!SpatialSession.supportsLiDAR)
                        Text("Experimental alerts can miss hazards; silence does not mean the path is clear.").font(.footnote).foregroundStyle(.secondary)
                        DisclosureGroup("Sensing options") { Toggle("Wider sensing area", isOn: $wide) }
                    }
                }
            }.navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
                .scrollContentBackground(.hidden).background(Color.indoorBackground)
                .toolbar { Button("Done") { dismiss() } }

        }
    }
}

/// Two independent presentation choices. Neither changes routes, camera tracking or arrival rules.
struct NavigationAccessibilitySheet: View {
    @ObservedObject var store: AppStore
    @AppStorage("depthAdvisories") private var awareness = true
    @AppStorage("floorAlerts") private var floorAlerts = true
    @AppStorage("phoneCoaching") private var phoneCoaching = true
    @AppStorage("guidanceFeet") private var feet = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: Binding(
                        get: { store.preferences.speech && !store.allSoundMuted },
                        set: { enabled in
                            store.setPreference(\.speech, enabled)
                            // The mute gate also prevents forced agent replies or VoiceOver announcements
                            // from restarting app narration after this switch is turned off.
                            store.allSoundMuted = !enabled
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Voice guidance")
                                Text("Blind or low vision").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "speaker.wave.2") }
                    }.accessibilityHint("Spoken directions. Turning this off mutes app audio; your system VoiceOver remains available.")
                        .accessibilityIdentifier("navigationVoiceGuidance")
                    Toggle(isOn: Binding(
                        get: { store.preferences.reducedInformation && store.preferences.haptics },
                        set: { enabled in
                            store.setPreference(\.reducedInformation, enabled)
                            store.setPreference(\.haptics, enabled)
                        }
                    )) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Visual alerts")
                                Text("Deaf or hard of hearing").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "eye") }
                    }.accessibilityHint("Larger instructions and vibration. Written directions remain visible when off.")
                        .accessibilityIdentifier("navigationVisualAlerts")
                } footer: {
                    Text("Written directions stay visible with either option off.")
                }
                Section("During navigation") {
                    Toggle("Distances in feet", isOn: $feet)
                    Toggle("Phone-position coaching", isOn: $phoneCoaching)
                    Toggle("People & obstacle alerts", isOn: $awareness)
                    Toggle("Possible step-down alerts", isOn: $floorAlerts).disabled(!SpatialSession.supportsLiDAR)
                    Text("Experimental alerts may miss hazards; silence does not mean the path is clear.").font(.footnote)
                    if !SpatialSession.supportsLiDAR { Text("Person detection is available; surface distances and furniture mapping require LiDAR.").font(.footnote) }
                }
            }.navigationTitle("Accessibility").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { dismiss() } }
                .tint(Color.indoorTeal)
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

/// A screen-fixed instruction, never a claim of world-space alignment.
struct DirectionBadge: View {
    let instruction: String
    let reliable: Bool
    var proximity: ApproachFeedback.Trend = .steady
    var distanceText: String? = nil
    private var glow: Color {
        guard reliable else { return .clear }
        return proximity == .closer ? .red : proximity == .farther ? .blue : .clear
    }
    private var symbol: String {
        guard reliable else { return "pause.fill" }
        let text = instruction.lowercased()
        if text.contains("turn around") || text.contains("u-turn") { return "arrow.uturn.down" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        return "arrow.up"
    }
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 64, weight: .bold))
                .shadow(color: glow.opacity(0.4), radius: 16)
                .accessibilityHidden(true)
            Text(reliable ? instruction : "Guidance paused")
                .font(.headline).multilineTextAlignment(.center)
            if reliable, let distanceText { Text(distanceText).font(.subheadline).monospacedDigit() }
            if reliable, proximity != .steady {
                Text(proximity == .closer ? "Getting closer" : "Moving farther")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Color.indoorTeal).padding(18)
        .frame(maxWidth: 310)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal).accessibilityElement(children: .combine)
        .accessibilityIdentifier("liveDirectionBadge")
    }
}

/// Recognize horizontal intent before competing with scrolling or result-card taps.
private struct PageBackSwipe: UIViewRepresentable {
    var enabled: Bool
    var action: () -> Void
    func makeUIView(context: Context) -> BackSwipeView { BackSwipeView() }
    func updateUIView(_ view: BackSwipeView, context: Context) {
        view.action = action; view.enabled = enabled
    }
    static func dismantleUIView(_ view: BackSwipeView, coordinator: ()) { view.detach() }
}
private final class BackSwipeView: UIView, UIGestureRecognizerDelegate {
    var action: (() -> Void)?
    var enabled = true
    private weak var attachedWindow: UIWindow?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
    override func didMoveToWindow() {
        super.didMoveToWindow()
        detach()
        guard let window else { return }
        pan.delegate = self; pan.cancelsTouchesInView = true
        window.addGestureRecognizer(pan); attachedWindow = window
    }
    func detach() { attachedWindow?.removeGestureRecognizer(pan); attachedWindow = nil }
    private func owner(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard enabled, !UIAccessibility.isVoiceOverRunning, let window, let touched = touch.view,
              convert(bounds, to: window).contains(touch.location(in: window)),
              let ownController = owner(of: self), owner(of: touched) === ownController else { return false }
        var view: UIView? = touched
        while let current = view {
            if current is UISlider || current is UISwitch || current is SCNView { return false }
            view = current.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other.view is UIScrollView
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: window)
        return velocity.x < -abs(velocity.y) * 2
    }
    @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        let offset = recognizer.translation(in: window)
        if offset.x < -90 && abs(offset.x) > abs(offset.y) * 2 { action?() }
    }
}
struct SwipeLeftBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @State private var active = true
    var action: (() -> Void)?
    func body(content: Content) -> some View {
        content.background(PageBackSwipe(enabled: active && (action != nil || isPresented)) {
            if let action { action() } else { dismiss() }
        })
        .onAppear { active = true }
        .onDisappear { active = false }
    }
}
extension View {
    func swipeLeftToGoBack(action: (() -> Void)? = nil) -> some View {
        modifier(SwipeLeftBackModifier(action: action))
    }
}
