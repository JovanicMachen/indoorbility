import XCTest
@testable import IndoorbilityCore

final class NavigationGeometryCacheTests: XCTestCase {
    func testLosslessPositioningArchiveCompressionAndInvalidation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("world.arworldmap"), cache = directory.appendingPathComponent("cache/world.plist")
        // Synthetic repetitive bytes exercise compression only, not AR accuracy.
        let original = Data(repeating: 42, count: 1024 * 1024)
        try original.write(to: source)
        let stamp = try CompactNavigationGeometry.Source.read(source)
        try CompressedNavigationArchive.save(original, at: cache, sourceURL: source, expected: stamp)
        XCTAssertEqual(CompressedNavigationArchive.load(at: cache, source: stamp), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertLessThan(try Data(contentsOf: cache).count, original.count / 10)
        try Data("changed positioning source".utf8).write(to: source)
        XCTAssertNil(CompressedNavigationArchive.load(at: cache, source: try .read(source)))
        XCTAssertThrowsError(try CompressedNavigationArchive.save(original, at: cache, sourceURL: source, expected: stamp))
        try Data("damaged cache".utf8).write(to: cache)
        XCTAssertNil(CompressedNavigationArchive.load(at: cache, source: stamp))
    }
    func testCompactCachePreservesMeasuredPointsAndDoesNotRewriteSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("mesh.json"), cache = directory.appendingPathComponent("cache/navigation.plist")
        let original = Data("synthetic source fixture, not a real scan".utf8)
        try original.write(to: source)
        let stamp = try CompactNavigationGeometry.Source.read(source)
        let geometry = CompactNavigationGeometry(points: [.init(x: 1.234567, y: -0.456789, z: 9.876543)], edges: [1.25, 2.5, 3.75, 4])
        try geometry.save(at: cache, sourceURL: source, expected: stamp)
        let decoded = try XCTUnwrap(CompactNavigationGeometry.load(at: cache, source: stamp))
        XCTAssertEqual(decoded.points, geometry.points)
        XCTAssertEqual(decoded.edges, geometry.edges)
        XCTAssertEqual(try Data(contentsOf: source), original)
        try Data("changed source fixture".utf8).write(to: source)
        XCTAssertNil(CompactNavigationGeometry.load(at: cache, source: try .read(source)))
        XCTAssertThrowsError(try geometry.save(at: cache, sourceURL: source, expected: stamp))
    }
    func testCorruptCacheAndInvalidGeometryAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("mesh.json"), cache = directory.appendingPathComponent("navigation.plist")
        try Data("synthetic".utf8).write(to: source)
        let stamp = try CompactNavigationGeometry.Source.read(source)
        try Data("not a property list".utf8).write(to: cache)
        XCTAssertNil(CompactNavigationGeometry.load(at: cache, source: stamp))
        for geometry in [CompactNavigationGeometry(points: [.init(x: .nan, y: 0, z: 0)], edges: []),
                         CompactNavigationGeometry(points: [], edges: [0, 1, 2]),
                         CompactNavigationGeometry(points: [], edges: Array(repeating: 0, count: 6004))] {
            XCTAssertThrowsError(try geometry.save(at: cache, sourceURL: source, expected: stamp))
        }
    }
}
