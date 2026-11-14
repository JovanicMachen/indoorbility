import SwiftUI
import IndoorbilityCore

/// A schematic of the supplied graph, not an invented architectural floor plan.
struct FloorDiagram: View {
    let building: Building
    let route: Route?
    let blocked: Set<String>
    let checkpoint: String?
    let floor: Int
    var body: some View {
        Canvas { context, size in
            func point(_ node: Checkpoint) -> CGPoint {
                // Per-floor bounds keep each level legible instead of leaving half the canvas empty.
                let nodes = building.nodes.filter { $0.floor == floor }
                let minX = nodes.map(\.x).min() ?? 0, maxX = nodes.map(\.x).max() ?? 1
                return CGPoint(x: 45 + (node.x - minX) / max(1, maxX - minX) * (size.width - 90),
                               y: 55 + (node.y - 60) / 130 * (size.height - 110))
            }
            for x in stride(from: 14.0, to: size.width, by: 18) {
                for y in stride(from: 12.0, to: size.height, by: 18) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.secondary.opacity(0.15)))
                }
            }
            for edge in building.edges {
                guard let a = building.node(edge.from), let b = building.node(edge.to), a.floor == floor, b.floor == floor else { continue }
                var line = Path(); line.move(to: point(a)); line.addLine(to: point(b))
                context.stroke(line, with: .color(.secondary.opacity(0.12)), style: .init(lineWidth: 26, lineCap: .round, lineJoin: .round))
                context.stroke(line, with: .color(.indoorCard), style: .init(lineWidth: 22, lineCap: .round, lineJoin: .round))
            }
            // Overlay route strokes after every corridor so intersections stay continuous.
            for edge in building.edges {
                guard let a = building.node(edge.from), let b = building.node(edge.to), a.floor == floor, b.floor == floor else { continue }
                var line = Path(); line.move(to: point(a)); line.addLine(to: point(b))
                if route?.edgeIDs.contains(edge.id) == true {
                    context.stroke(line, with: .color(.indoorTeal), style: .init(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if blocked.contains(edge.id) {
                    context.stroke(line, with: .color(.orange), style: .init(lineWidth: 3, dash: [3, 5]))
                }
            }
            for node in building.nodes where node.floor == floor {
                let p = point(node)
                if node.kind == "junction" { continue }
                let closed = building.edges.contains { $0.kind == .elevator && ($0.from == node.id || $0.to == node.id) && blocked.contains($0.id) }
                let current = node.id == checkpoint
                let color: Color = closed ? .orange : .indoorTeal
                let box = CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)
                context.fill(Path(roundedRect: box, cornerRadius: 12), with: .color(current ? .indoorForest : .indoorCard))
                context.stroke(Path(roundedRect: box, cornerRadius: 12), with: .color(color.opacity(0.3)), lineWidth: 1)
                let symbol = closed ? "exclamationmark" : current ? "location.fill" : node.kind == "elevator" ? "arrow.up.arrow.down" : node.kind == "stairs" ? "stairs" : node.kind == "room" ? "door.left.hand.closed" : "arrow.down.right.and.arrow.up.left"
                var icon = context.resolve(Image(systemName: symbol))
                icon.shading = .color(current ? Color.indoorLime : color)
                context.draw(icon, at: p)
                let label = node.label.replacingOccurrences(of: " - Level \(floor)", with: "")
                let labelY = node.kind == "stairs" ? p.y - 35 : p.y + 32
                context.draw(Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.indoorInk), at: CGPoint(x: p.x, y: labelY))
                if current {
                    context.draw(Text("YOU").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(.indoorTeal), at: CGPoint(x: p.x, y: p.y - 29))
                }
            }
        }.accessibilityHidden(true)
    }
}
