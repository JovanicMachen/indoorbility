import XCTest
@testable import IndoorbilityCore

final class BuildingNetworkTests: XCTestCase {
    func point(_ x: Float, _ z: Float = 0) -> SpatialPoint { SpatialPoint(x: x,y: 0,z: z) }
    func route(_ positions: [SpatialPoint]) throws -> HallwayRoute {
        let a = ScanLandmark(label: "Start", kind: "entrance", position: positions.first!)
        let b = ScanLandmark(label: "Room", kind: "room", position: positions.last!)
        let scan = ScanDraft(name: "Test", usesLiDAR: true, hasWorldMap: true, samples: positions.map { ScanSample(position: $0, segment: 0) }, landmarks: [a,b], meshVertexCount: 0, meshTriangleCount: 0)
        return try .make(draft: scan, entranceID: a.id, roomID: b.id, reviewed: true)
    }
    func testConnectedMeasuredRouteAndClosure() throws {
        let a = try route((0...4).map { point(Float($0)) })
        let b = try route((10...16).map { point(Float($0)) })
        var network = BuildingNetwork(name: "Building", floor: "LL", route: a)
        try network.extend(base: a,new: b,baseA: point(2),baseB: point(4),newA: point(10),newB: point(12),confirmedFloor: "LL")
        let decoded = try JSONDecoder().decode(BuildingNetwork.self, from: JSONEncoder().encode(network))
        let result = try decoded.path(from: a.id,to: b.id,routes: [a.id:a,b.id:b])
        XCTAssertEqual(result.points.first,point(0));XCTAssertEqual(result.points.last,point(8))
        XCTAssertEqual(result.routeIDs,Set([a.id,b.id]))
        XCTAssertThrowsError(try decoded.path(from: a.id,to: b.id,routes: [a.id:a,b.id:b],blocked: [b.id]))
        XCTAssertThrowsError(try decoded.path(from: a.id,to: b.id,routes: [a.id:a]))
    }
    func testNoInventedConnectionOrFloor() throws {
        let a = try route((0...4).map { point(Float($0)) }), b = try route((10...14).map { point(Float($0)) })
        var network = BuildingNetwork(name: "Building",floor: "LL",route: a)
        XCTAssertThrowsError(try network.extend(base:a,new:b,baseA:point(2),baseB:point(4),newA:point(10),newB:point(12),confirmedFloor:"1"))
        XCTAssertThrowsError(try network.extend(base:a,new:b,baseA:point(2,3),baseB:point(4,3),newA:point(10),newB:point(12),confirmedFloor:"LL"))
        XCTAssertEqual(network.segments.count,1)
    }
    func testMeshReductionAndBounds() throws {
        let vertices = [point(0),point(0.01),point(1),point(0,1)]
        let result = try MeshReduction.reduce(vertices:vertices,triangles:[0,2,3,1,2,3,0,1,2])
        XCTAssertEqual(result.vertices.count,3);XCTAssertEqual(result.triangles.count,3)
        XCTAssertThrowsError(try MeshReduction.reduce(vertices:vertices,triangles:[0,2,99]))
        XCTAssertThrowsError(try MeshReduction.reduce(vertices:[point(.nan)],triangles:[]))
    }
}
