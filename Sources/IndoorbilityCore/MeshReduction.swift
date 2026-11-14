import Foundation

/// Preview/export-only vertex clustering. Never use reduced surfaces for routing or depth alerts.
public enum MeshReduction {
    public struct Result { public let vertices: [SpatialPoint]; public let triangles: [UInt32] }
    public static func reduce(vertices: [SpatialPoint], triangles: [UInt32], cell: Float = 0.04) throws -> Result {
        guard cell.isFinite, cell >= 0.01, cell <= 0.2, vertices.count <= 500000, triangles.count <= 3000000,
              triangles.count % 3 == 0, vertices.allSatisfy({ $0.isFinite && abs($0.x) < 100000 && abs($0.y) < 100000 && abs($0.z) < 100000 }),
              triangles.allSatisfy({ Int($0) < vertices.count }) else { throw MapError.invalid("Invalid or oversized mesh.") }
        struct Cell: Hashable { let x: Int, y: Int, z: Int }
        var cells: [Cell: UInt32] = [:], mapped: [UInt32] = [], output: [SpatialPoint] = []
        for p in vertices {
            let key = Cell(x: Int(floor(p.x/cell)), y: Int(floor(p.y/cell)), z: Int(floor(p.z/cell)))
            if let index = cells[key] { mapped.append(index) }
            else { let index = UInt32(output.count); cells[key] = index; mapped.append(index); output.append(p) }
        }
        var indices: [UInt32] = []
        struct Face: Hashable { let a: UInt32, b: UInt32, c: UInt32 }
        var seen = Set<Face>()
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let a = mapped[Int(triangles[i])], b = mapped[Int(triangles[i+1])], c = mapped[Int(triangles[i+2])]
            guard a != b, b != c, a != c else { continue }
            let sorted = [a,b,c].sorted()
            if seen.insert(Face(a: sorted[0], b: sorted[1], c: sorted[2])).inserted { indices += [a,b,c] }
        }
        return Result(vertices: output, triangles: indices)
    }
}
