import Foundation

public struct SpatialPoint: Codable, Equatable, Sendable {
    public let x: Float
    public let y: Float
    public let z: Float
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func distance(to other: SpatialPoint) -> Float {
        sqrt(pow(x - other.x, 2) + pow(y - other.y, 2) + pow(z - other.z, 2))
    }
}

public struct ScanSample: Codable, Equatable {
    public let position: SpatialPoint
    public let segment: Int
    public init(position: SpatialPoint, segment: Int) { self.position = position; self.segment = segment }
}

public struct ScanLandmark: Codable, Identifiable, Equatable {
    public let id: UUID
    public let label: String
    public let kind: String
    public let position: SpatialPoint
    public init(id: UUID = UUID(), label: String, kind: String, position: SpatialPoint) {
        self.id = id; self.label = label; self.kind = kind; self.position = position
    }
}

public struct ScanDraft: Codable, Identifiable, Equatable {
    public let version: Int
    public let id: UUID
    public let name: String
    public let createdAt: Date
    public let usesLiDAR: Bool
    public let hasWorldMap: Bool
    public let samples: [ScanSample]
    public let landmarks: [ScanLandmark]
    public let meshVertexCount: Int
    public let meshTriangleCount: Int
    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), usesLiDAR: Bool, hasWorldMap: Bool,
                samples: [ScanSample], landmarks: [ScanLandmark], meshVertexCount: Int, meshTriangleCount: Int) {
        version = 1; self.id = id; self.name = name; self.createdAt = createdAt; self.usesLiDAR = usesLiDAR
        self.hasWorldMap = hasWorldMap; self.samples = samples; self.landmarks = landmarks
        self.meshVertexCount = meshVertexCount; self.meshTriangleCount = meshTriangleCount
    }
    public var recordedDistance: Float {
        zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            total + (pair.0.segment == pair.1.segment ? pair.0.position.distance(to: pair.1.position) : 0)
        }
    }
    public func validate() throws {
        guard version == 1, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              meshVertexCount >= 0, meshTriangleCount >= 0,
              samples.allSatisfy({ $0.position.isFinite && $0.segment >= 0 }),
              landmarks.allSatisfy({ $0.position.isFinite && !$0.label.isEmpty }),
              Set(landmarks.map(\.id)).count == landmarks.count else {
            throw MapError.invalid("This saved scan has invalid spatial data.")
        }
    }
}
