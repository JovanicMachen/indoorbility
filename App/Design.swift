import SwiftUI

extension Color {
    static let indoorTeal = Color(red: 0.44, green: 0.24, blue: 0.38)
    static let indoorPeach = Color(red: 1, green: 0.77, blue: 0.66)
    static let indoorBackground = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.09, green: 0.07, blue: 0.09, alpha: 1) : UIColor(red: 1, green: 0.973, blue: 0.953, alpha: 1) })
    static let indoorCard = Color(uiColor: .secondarySystemGroupedBackground)
    static let indoorInk = Color.primary
    static let indoorCameraCaption = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.79, green: 0.77, blue: 0.78, alpha: 1)
            : UIColor(red: 0.33, green: 0.30, blue: 0.32, alpha: 1)
    })
    static let indoorLime = Color.white
    static let indoorForest = indoorTeal

}

struct Panel<Content: View>: View {
    @AppStorage("highContrast") private var highContrast = false
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(highContrast ? 0.7 : 0.045)))
    }
}
struct Eyebrow: View {
    var text: String
    var body: some View { Text(text).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
}
struct DemoBadge: View {
    var body: some View {
        Text("Demo").font(.caption2.weight(.medium))
            .padding(.horizontal, 9).padding(.vertical, 5).background(Color.primary.opacity(0.055), in: Capsule())
            .accessibilityLabel("Demo building").accessibilityIdentifier("demoBadge")
    }
}
struct PrimaryButton: View {
    var title: String
    var systemImage: String = "arrow.up.right"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) { Text(title); Spacer(minLength: 8); Image(systemName: systemImage) }
                .font(.headline).padding(.horizontal, 18).padding(.vertical, 14)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(ForestButtonStyle())
    }
}
struct ForestButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(enabled ? Color.indoorLime : .secondary)
            .background(enabled ? Color.indoorForest : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
struct IconTile: View {
    var symbol: String
    var dark = false
    var body: some View {
        Image(systemName: symbol).font(.system(size: 21, weight: .medium))
            .frame(width: 48, height: 48).foregroundStyle(dark ? Color.indoorLime : .indoorTeal)
            .background(dark ? Color.white.opacity(0.09) : Color.indoorTeal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }
}
struct SmallTag: View {
    var text: String
    var symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 7)
            .foregroundStyle(Color.indoorTeal).background(Color.indoorTeal.opacity(0.07), in: Capsule())
    }
}

/// Fixed-height hint; never changes the search field or announces individual letters.
struct DestinationTypingHint: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var phase
    @State private var text = "Find a building"
    @State private var cursor = true
    private let phrases = ["Find a room", "Explore Washington, DC", "Find a café", "Discover Princeton", "Find your next stop"]
    private var animate: Bool { active && !reduceMotion && !voiceOver && phase == .active }
    var body: some View {
        Text(animate ? text : "Search destinations")
            .overlay(alignment: .trailing) {
                if animate {
                    Rectangle().fill(Color.indoorTeal)
                        .frame(width: 1.5, height: 20)
                        .offset(x: 2)
                        .opacity(cursor ? 1 : 0)
                        .accessibilityHidden(true)
                }
            }
            .font(.body).multilineTextAlignment(.center).frame(minHeight: 26)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Search for a building, room or place")
            .task(id: animate) {
                guard animate else { return }
                var index = 0
                text = phrases[index]; cursor = true
                do {
                    while !Task.isCancelled {
                        for _ in 0..<4 {
                            try await Task.sleep(for: .milliseconds(350))
                            cursor.toggle()
                        }
                        cursor = true
                        while !text.isEmpty {
                            try await Task.sleep(for: .milliseconds(45))
                            text.removeLast()
                        }
                        try await Task.sleep(for: .milliseconds(180))
                        index = (index + 1) % phrases.count
                        for character in phrases[index] {
                            try await Task.sleep(for: .milliseconds(85))
                            text.append(character)
                        }
                    }
                } catch { /* SwiftUI cancels when editing, backgrounded or dismissed. */ }
            }
    }
}

/// A quiet instruction card over the live camera. Content scrolls at large text sizes.
struct ScanInstructionPanel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("highContrast") private var highContrast = false
    @ViewBuilder var content: Content
    var body: some View {
        ViewThatFits(in: .vertical) {
            contents
            ScrollView { contents }
        }
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.indoorBackground.opacity(reduceTransparency || highContrast ? 1 : 0.7))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Color.indoorTeal.opacity(highContrast ? 0.65 : 0.18)))
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
    private var contents: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
    }
}

struct ScanInstructionHeading: View {
    var status: String
    var title: String
    var instruction: String
    var active = true
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                MappingDash(active: active)
                Text(status)
            }.font(.subheadline.weight(.medium)).foregroundStyle(Color.indoorTeal)
            Text(title).font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(instruction).font(.body).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
        }.multilineTextAlignment(.leading)
    }
}

/// A small rising dash indicates activity, never a percentage of mapped coverage.
struct MappingDash: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !active || reduceMotion)) { context in
            let progress = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            Text("−").font(.system(size: 24, weight: .semibold, design: .rounded))
                .offset(y: active && !reduceMotion ? 7 - progress * 14 : 0)
                .opacity(active && !reduceMotion ? 0.25 + sin(progress * .pi) * 0.75 : 0.7)
                .frame(width: 24, height: 28).clipped()
        }.accessibilityHidden(true)
    }
}

/// Decorative landscape, never a representation of mapped or navigable geometry.
struct DestinationBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color.indoorPeach.opacity(0.45), Color.indoorTeal.opacity(0.10), Color.indoorBackground], startPoint: .topTrailing, endPoint: .bottomLeading)
                Canvas { context, size in
                    for index in 0..<5 {
                        let y = size.height * (0.22 + Double(index) * 0.13)
                        var curve = Path()
                        curve.move(to: CGPoint(x: -20, y: y))
                        curve.addCurve(to: CGPoint(x: size.width + 20, y: y + 50),
                                       control1: CGPoint(x: size.width * 0.3, y: y - 100),
                                       control2: CGPoint(x: size.width * 0.65, y: y + 140))
                        context.stroke(curve, with: .color(Color.indoorTeal.opacity(0.07)), lineWidth: 1)
                    }
                }
            }
            .frame(height: min(420, proxy.size.height * 0.52))
            .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
            .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .padding(.horizontal, 12).padding(.top, 8)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Lightweight, decorative Home-only snowfall. No interaction or navigation work.
struct HomeHolidayBackdrop: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || phase != .active)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                // Fixed seeds keep the flakes stable across ordinary UI updates.
                for index in 0..<36 {
                    let seed = Double(index)
                    let column = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
                    let period = 15 + Double(index % 7) * 2
                    let progress = (time / period + seed * 0.137).truncatingRemainder(dividingBy: 1)
                    let x = column * size.width + sin(time * 0.35 + seed) * 9
                    let y = progress * (size.height + 24) - 12
                    let radius = 1.5 + Double(index % 3) * 0.65
                    let flake = Path(ellipseIn: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
                    context.fill(flake, with: .color(.white.opacity(0.75)))
                    context.stroke(flake, with: .color(Color.indoorTeal.opacity(0.13)), lineWidth: 0.6)
                }
                // Quiet Christmas decals stay at the edges, behind the controls.
                let trees: [CGPoint] = [CGPoint(x: 30, y: size.height * 0.36),
                                        CGPoint(x: size.width - 28, y: size.height * 0.74)]
                for point in trees {
                    var pine = Path()
                    for tier in 0..<3 {
                        let top = point.y - 23 + CGFloat(tier) * 10
                        let halfWidth = CGFloat(9 + tier * 5)
                        pine.move(to: CGPoint(x: point.x, y: top))
                        pine.addLine(to: CGPoint(x: point.x + halfWidth, y: top + 20))
                        pine.addLine(to: CGPoint(x: point.x - halfWidth, y: top + 20))
                        pine.closeSubpath()
                    }
                    pine.addRect(CGRect(x: point.x - 2.5, y: point.y + 17, width: 5, height: 8))
                    context.fill(pine, with: .color(Color(red: 0.24, green: 0.39, blue: 0.30).opacity(0.12)))
                    context.draw(Text(Image(systemName: "star.fill")).font(.system(size: 8))
                        .foregroundColor(Color(red: 0.68, green: 0.47, blue: 0.23).opacity(0.24)),
                                 at: CGPoint(x: point.x, y: point.y - 26))
                }
                let stars: [CGPoint] = [CGPoint(x: 45, y: 45), CGPoint(x: size.width - 42, y: 80),
                                        CGPoint(x: size.width - 30, y: size.height * 0.48)]
                for point in stars {
                    context.draw(Text(Image(systemName: "sparkle")).font(.system(size: 20))
                        .foregroundColor(Color(red: 0.68, green: 0.47, blue: 0.23).opacity(0.22)), at: point)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true).clipped()
    }
}
