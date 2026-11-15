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
    var compact = false
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
                OrnamentMicButton(listening: voice.listening, diameter: diameter, showTree: !compact)
            }.buttonStyle(.plain)
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                    guard !tapping, !held, !voice.busy else { return }
                    held = true; begin()
                }.onEnded { _ in
                    guard !tapping else { return }; held = false
                    if voice.listening { voice.finish(); if haptics { AppHaptics.shared.selection() } }
                    else if voice.status != "Finishing…" { starting?.cancel(); voice.cancel() }
                })
                .accessibilityLabel(voice.listening ? "Finish speaking" : "Speak to Indoorbility")
                .accessibilityIdentifier("holdToTalk")
            Text(voice.listening ? "Listening…" : voice.busy ? "Understanding…" : tapping ? "Tap to speak" : "Hold to speak")
                .font(compact ? .caption : .callout.weight(.medium))
        }
        .onChange(of: voice.status) { _, status in
            if status == VoiceCommandInput.notUnderstood { onUnrecognized() }
        }
        .onDisappear { starting?.cancel(); voice.cancel() }
        .onChange(of: phase) { _, value in if value != .active { starting?.cancel(); held = false; voice.cancel() } }
    }
    private func begin() {
        if haptics { AppHaptics.shared.tap(0.6) } // Felt confirmation that listening started.
        before()
        starting = Task { await voice.start(automaticallyFinish: tapping, onResult: result) }
    }
    private func toggle() {
        if voice.listening { voice.finish(); if haptics { AppHaptics.shared.selection() } } else if voice.busy { voice.cancel() } else { begin() }
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
/// Shared camera layout for outdoor GPS and saved indoor routes.
struct CameraGuidancePanel<Content: View>: View {
    var maxHeight: CGFloat = 300
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            content.frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.indoorPeach.opacity(0.16), in: RoundedRectangle(cornerRadius: 18))
                .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: maxHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
    }
}

struct CameraGuidanceActions<Microphone: View>: View {
    var showingMap: Bool
    var repeatGuidance: () -> Void
    var toggleMap: () -> Void
    @ViewBuilder var microphone: Microphone
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Repeat guidance", action: repeatGuidance)
                .font(.subheadline).frame(minHeight: 44)
                .accessibilityIdentifier("repeatCameraGuidance")
            Spacer(minLength: 0)
            microphone
            Button(action: toggleMap) {
                Label(showingMap ? "Camera" : "Map", systemImage: showingMap ? "camera" : "map")
                    .labelStyle(.iconOnly).font(.title3).frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(showingMap ? "Camera" : "Map")
                .accessibilityIdentifier("toggleNavigationMap")
        }.foregroundStyle(Color.indoorTeal)
    }
}

struct CameraReadSignButton: View {
    var busy = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Group {
                if busy { ProgressView() }
                else { Image(systemName: "text.viewfinder").font(.title2) }
            }.frame(width: 48, height: 48)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6)))
        }.buttonStyle(.plain).foregroundStyle(Color.indoorInk)
            .accessibilityLabel("Read a sign").accessibilityIdentifier("readNavigationSign")
            .disabled(busy)
    }
}

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
        LiveGuidance.symbol(for: instruction, reliable: reliable)
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
    private func sharesScreen(_ touched: UIViewController?, with owner: UIViewController) -> Bool {
        // Result cards and scroll content can be sibling hosting controllers.
        // Compare their containment roots, while presented sheets keep a separate
        // root and must handle their own back gesture.
        guard var touchedRoot = touched else { return false }
        while let parent = touchedRoot.parent { touchedRoot = parent }
        var ownerRoot = owner
        while let parent = ownerRoot.parent { ownerRoot = parent }
        return touchedRoot === ownerRoot
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard enabled, !UIAccessibility.isVoiceOverRunning, window != nil, let touched = touch.view,
              let ownController = owner(of: self),
              sharesScreen(owner(of: touched), with: ownController) else { return false }
        var view: UIView? = touched
        while let current = view {
            if current is UISlider || current is UISwitch || current is SCNView { return false }
            view = current.superview
        }
        return true
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other is UIPanGestureRecognizer || other.view is UIScrollView
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
        // A result's tap must wait until the horizontal back pan has failed.
        // Vertical scroll pans still begin normally when our direction check fails.
        !(other is UIPanGestureRecognizer)
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
    var enabled = true
    var action: (() -> Void)?
    func body(content: Content) -> some View {
        content.background(PageBackSwipe(enabled: enabled && active && (action != nil || isPresented)) {
            if let action { action() } else { dismiss() }
        })
        .onAppear { active = true }
        .onDisappear { active = false }
    }
}
extension View {
    func swipeLeftToGoBack(enabled: Bool = true, action: (() -> Void)? = nil) -> some View {
        modifier(SwipeLeftBackModifier(enabled: enabled, action: action))
    }
}


/// The speak button as a Christmas ornament hanging in front of a small tree.
/// Purely decorative styling; the button, gestures and labels are unchanged.
struct OrnamentMicButton: View {
    var listening: Bool
    var diameter: CGFloat
    var showTree = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swing = false
    private let gold = Color(red: 0.86, green: 0.67, blue: 0.32)
    private let berry = Color(red: 0.62, green: 0.20, blue: 0.33)
    var body: some View {
        // The tree sits behind without changing the button's layout size.
        bauble
            .rotationEffect(.degrees(listening && !reduceMotion ? (swing ? 6 : -6) : 0), anchor: .top)
            .animation(listening && !reduceMotion ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: swing)
            .background {
                if showTree {
                    ChristmasTree(gold: gold)
                        .frame(width: diameter * 1.6, height: diameter * 1.6)
                        .offset(y: -diameter * 0.12)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Circle())
        .onChange(of: listening) { _, value in swing = value }
    }
    private var bauble: some View {
        VStack(spacing: -diameter * 0.04) {
            // Hanging loop and gold cap.
            Circle().stroke(gold, lineWidth: max(1.5, diameter * 0.025))
                .frame(width: diameter * 0.14, height: diameter * 0.14)
            RoundedRectangle(cornerRadius: diameter * 0.04)
                .fill(LinearGradient(colors: [gold.opacity(0.85), gold, gold.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                .frame(width: diameter * 0.3, height: diameter * 0.13)
                .zIndex(1)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.78, green: 0.42, blue: 0.58), .indoorTeal, berry.opacity(0.95)],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 2, endRadius: diameter * 0.62))
                // Festive band of tiny dots.
                OrnamentBand().stroke(Color.indoorPeach.opacity(0.75), style: StrokeStyle(lineWidth: max(1, diameter * 0.02), lineCap: .round, dash: [0.1, diameter * 0.07]))
                    .padding(diameter * 0.04)
                // Glossy highlight.
                Ellipse().fill(.white.opacity(0.35))
                    .frame(width: diameter * 0.32, height: diameter * 0.16)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -diameter * 0.2, y: -diameter * 0.24)
                Image(systemName: listening ? "waveform" : "mic.fill")
                    .font(.system(size: max(16, diameter * 0.32), weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.variableColor.iterative, isActive: listening && !reduceMotion)
            }
            .frame(width: diameter, height: diameter)
            .overlay(Circle().stroke(gold.opacity(0.55), lineWidth: max(1, diameter * 0.018)))
            .shadow(color: Color.indoorPeach.opacity(listening ? 0.8 : 0.3), radius: listening ? diameter * 0.25 : diameter * 0.1)
        }
    }
}

private struct OrnamentBand: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let y = rect.midY + rect.height * 0.18
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: y))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: y),
                       control: CGPoint(x: rect.midX, y: y + rect.height * 0.16))
        return p
    }
}

private struct ChristmasTree: View {
    var gold: Color
    private let pine = Color(red: 0.30, green: 0.50, blue: 0.38)
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            var tree = Path()
            for tier in 0..<3 {
                let t = CGFloat(tier)
                let top = h * (0.06 + t * 0.2)
                let half = w * (0.24 + t * 0.12)
                tree.move(to: CGPoint(x: w/2, y: top))
                tree.addQuadCurve(to: CGPoint(x: w/2 + half, y: top + h * 0.34), control: CGPoint(x: w/2 + half * 0.45, y: top + h * 0.22))
                tree.addQuadCurve(to: CGPoint(x: w/2 - half, y: top + h * 0.34), control: CGPoint(x: w/2, y: top + h * 0.38))
                tree.addQuadCurve(to: CGPoint(x: w/2, y: top), control: CGPoint(x: w/2 - half * 0.45, y: top + h * 0.22))
            }
            context.fill(tree, with: .color(pine.opacity(0.28)))
            // Tiny lights on the outer branches.
            let lights: [(CGFloat, CGFloat)] = [(0.36, 0.32), (0.66, 0.36), (0.26, 0.58), (0.76, 0.6), (0.2, 0.8), (0.82, 0.82)]
            for (i, l) in lights.enumerated() {
                let r = w * 0.025
                context.fill(Path(ellipseIn: CGRect(x: w*l.0 - r, y: h*l.1 - r, width: r*2, height: r*2)),
                             with: .color((i % 2 == 0 ? gold : Color.indoorPeach).opacity(0.75)))
            }
            context.draw(Text(Image(systemName: "star.fill")).font(.system(size: w * 0.12)).foregroundColor(gold),
                         at: CGPoint(x: w/2, y: h * 0.05))
        }
        .accessibilityHidden(true)
    }
}

/// Snow flurries that drift down from the top edge and fade away by the
/// middle of the screen. Decorative only: never takes touches, hidden from
/// VoiceOver, and still with Reduce Motion.
struct TopSnowfall: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || phase != .active)) { timeline in
                Canvas { context, size in
                    let time = reduceMotion ? 40 : timeline.date.timeIntervalSinceReferenceDate
                    for index in 0..<40 {
                        let seed = Double(index)
                        let column = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
                        let period = 7 + Double(index % 5) * 1.8
                        let progress = (time / period + seed * 0.173).truncatingRemainder(dividingBy: 1)
                        let x = column * size.width + sin(time * 0.7 + seed) * 14
                        let y = progress * size.height
                        // Full strength near the top, gone by halfway down the screen.
                        let fade = progress < 0.35 ? 1 : max(0, 1 - (progress - 0.35) / 0.65)
                        let flakeSize = 8 + Double(index % 4) * 3
                        var flake = context
                        flake.opacity = 0.9 * fade * fade
                        flake.translateBy(x: x, y: y)
                        flake.rotate(by: .radians(time * 0.6 + seed))
                        flake.draw(Text(Image(systemName: "snowflake")).font(.system(size: flakeSize, weight: .semibold))
                            .foregroundColor(Color(red: 0.30, green: 0.55, blue: 0.96)), at: .zero)
                    }
                }
            }
            .frame(height: proxy.size.height * 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
