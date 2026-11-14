import Foundation

/// Bounded, local-only timing samples. Durations are measurements, not accuracy claims.
public struct TimingWindow {
    private var values: [Double] = []
    private var cursor = 0
    public init() {}
    public mutating func record(_ value: Double) {
        guard value.isFinite, value >= 0 else { return }
        if values.count < 300 { values.append(value) }
        else { values[cursor] = value; cursor = (cursor+1)%300 }
    }
    public var count: Int { values.count }
    public var mean: Double? { values.isEmpty ? nil : values.reduce(0,+)/Double(values.count) }
    public var p95: Double? { values.isEmpty ? nil : values.sorted()[min(values.count-1, Int(Double(values.count-1)*0.95))] }
}

public enum MapPositionConfidence: String {
    case unverified = "Map position unverified"
    case savedMap = "Saved map matched; confirm landmark"
    case confirmed = "Landmark-confirmed position"
    case uncertain = "Position uncertain"
}

/// Sparse measured-surface comparison, never a clearance or localization proof.
public struct SurfaceReference: Sendable {
    private struct Cell: Hashable, Sendable { let x: Int; let y: Int; let z: Int }
    private var cells: [Cell: SpatialPoint] = [:]
    private static func cell(_ p: SpatialPoint) -> Cell {
        Cell(x: Int(floor(p.x/0.25)), y: Int(floor(p.y/0.25)), z: Int(floor(p.z/0.25)))
    }
    public init(points: [SpatialPoint]) {
        for p in points where p.isFinite && abs(p.x) < 10000 && abs(p.y) < 10000 && abs(p.z) < 10000 {
            cells[Self.cell(p)] = p
            if cells.count >= 50000 { break }
        }
    }
    public var count: Int { cells.count }
    public enum Agreement: String { case unknown, consistent, discrepancy }
    public func compare(points: [SpatialPoint]) -> Agreement {
        guard cells.count >= 20 else { return .unknown }
        var compared = 0, different = 0
        for p in points.prefix(96) where p.isFinite && abs(p.x) < 10000 && abs(p.y) < 10000 && abs(p.z) < 10000 {
            let c = Self.cell(p)
            var nearest = Float.infinity
            for x in -4...4 { for y in -4...4 { for z in -4...4 {
                if let q = cells[Cell(x: c.x+x, y: c.y+y, z: c.z+z)] { nearest = min(nearest, p.distance(to: q)) }
            } } }
            // Unscanned / distant surfaces remain unknown, never declared discrepant or clear.
            if nearest <= 1 { compared += 1; if nearest > 0.45 { different += 1 } }
        }
        guard compared >= 20 else { return .unknown }
        return Double(different)/Double(compared) > 0.6 ? .discrepancy : .consistent
    }
}
public struct SurfaceAgreementFilter {
    private var count = 0
    private var last: Double?
    public init() {}
    public mutating func update(_ evidence: SurfaceReference.Agreement, time: Double) -> Bool {
        guard time.isFinite, last.map({ time > $0 }) ?? true else { return false }
        if let last, time-last > 2 { count = 0 }
        last = time
        count = evidence == .discrepancy ? count+1 : 0
        return count >= 3
    }
}
