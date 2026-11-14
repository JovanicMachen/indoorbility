import Foundation

/// Lossless compression of a derived positioning archive. The original map is
/// never overwritten. A changed source or damaged cache always forces a reload.
public enum CompressedNavigationArchive {
    private static let limit = 80 * 1024 * 1024
    private struct Envelope: Codable {
        let version: Int
        let source: CompactNavigationGeometry.Source
        let archiveSize: Int
        let compressed: Data
    }
    public static func load(at cache: URL, source: CompactNavigationGeometry.Source) -> Data? {
        guard let metadata = try? FileManager.default.attributesOfItem(atPath: cache.path),
              let size = metadata[.size] as? NSNumber, size.intValue <= limit,
              let data = try? Data(contentsOf: cache, options: .mappedIfSafe),
              let stored = try? PropertyListDecoder().decode(Envelope.self, from: data),
              stored.version == 1, stored.source == source,
              stored.archiveSize > 0, stored.archiveSize <= limit,
              let archive = try? (stored.compressed as NSData).decompressed(using: .lzfse) as Data,
              archive.count == stored.archiveSize else { return nil }
        return archive
    }
    public static func save(_ archive: Data, at cache: URL, sourceURL: URL, expected: CompactNavigationGeometry.Source) throws {
        guard !archive.isEmpty, archive.count <= limit,
              try CompactNavigationGeometry.Source.read(sourceURL) == expected else {
            throw MapError.invalid("The positioning map changed; its derived cache was discarded.")
        }
        let compressed = try (archive as NSData).compressed(using: .lzfse) as Data
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(Envelope(version: 1, source: expected, archiveSize: archive.count, compressed: compressed))
        guard data.count <= limit else { throw MapError.invalid("Positioning cache is too large.") }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cache, options: .atomic)
    }
}

/// Disposable display/surface-comparison data. Never used to establish position
/// or replace the recorded route or ARWorldMap.
public struct CompactNavigationGeometry: Codable, Sendable {
    public let points: [SpatialPoint]
    /// Flat x/z endpoint pairs for a bounded, low-detail wall outline.
    public let edges: [Float]
    public init(points: [SpatialPoint], edges: [Float]) { self.points = points; self.edges = edges }
    private var valid: Bool {
        points.count <= 50000 && edges.count <= 6000 && edges.count % 4 == 0 &&
        points.allSatisfy { $0.isFinite && abs($0.x) < 100000 && abs($0.y) < 100000 && abs($0.z) < 100000 } &&
        edges.allSatisfy { $0.isFinite && abs($0) < 100000 }
    }
    public struct Source: Codable, Equatable, Sendable {
        public let size: Int
        public let modified: Date
        public static func read(_ url: URL) throws -> Self {
            // URL resource values may retain cached metadata after a file rewrite.
            // Read fresh attributes so edits cannot reuse a stale derived cache.
            let metadata = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let bytes = metadata[.size] as? NSNumber, let modified = metadata[.modificationDate] as? Date else {
                throw MapError.invalid("Saved scan metadata is unavailable.")
            }
            return Self(size: bytes.intValue, modified: modified)
        }
    }
    private struct Envelope: Codable {
        let version: Int
        let source: Source
        let geometry: CompactNavigationGeometry
    }
    public static func load(at cache: URL, source: Source) -> Self? {
        guard let metadata = try? FileManager.default.attributesOfItem(atPath: cache.path),
              let size = metadata[.size] as? NSNumber, size.intValue <= 6*1024*1024,
              let data = try? Data(contentsOf: cache),
              let stored = try? PropertyListDecoder().decode(Envelope.self, from: data),
              stored.version == 1, stored.source == source, stored.geometry.valid else { return nil }
        return stored.geometry
    }
    public func save(at cache: URL, sourceURL: URL, expected: Source) throws {
        guard valid, try Source.read(sourceURL) == expected else {
            throw MapError.invalid("The source scan changed; the navigation cache was discarded.")
        }
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        let data = try encoder.encode(Envelope(version: 1, source: expected, geometry: self))
        guard data.count <= 6*1024*1024 else { throw MapError.invalid("Navigation cache is too large.") }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: cache, options: .atomic)
    }
}
