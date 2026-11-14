import Foundation

/// An explicitly aligned, same-floor collection. Every path remains captured evidence.
public struct BuildingNetwork: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var floor: String
    public var revision = 1
    public var segments: [Segment]
    public var links: [Link] = []
    public struct Segment: Codable {
        public let scanID: UUID
        public let routeID: UUID
        public let alignment: ScanAlignment
        public init(scanID: UUID, routeID: UUID, alignment: ScanAlignment) {
            self.scanID = scanID; self.routeID = routeID; self.alignment = alignment
        }
    }
    public struct Link: Codable {
        public let first: UUID, second: UUID
        public let firstIndex: Int, secondIndex: Int
    }
    public init(name: String, floor: String, route: HallwayRoute) {
        self.name = name; self.floor = floor
        segments = [Segment(scanID: route.scanID, routeID: route.id, alignment: .identity)]
    }
    public mutating func extend(base: HallwayRoute, new: HallwayRoute, baseA: SpatialPoint, baseB: SpatialPoint,
                                newA: SpatialPoint, newB: SpatialPoint, confirmedFloor: String) throws {
        guard !base.hasLevelChange, !new.hasLevelChange, confirmedFloor == floor, !floor.isEmpty,
              let parent = segments.first(where: { $0.routeID == base.id }),
              !segments.contains(where: { $0.scanID == new.scanID }) else { throw MapError.invalid("Choose a new recording on the same confirmed floor.") }
        let transform = try ScanAlignment.fit(liveA: newA, liveB: newB,
                                              savedA: parent.alignment.apply(baseA), savedB: parent.alignment.apply(baseB))
        guard let i = base.path.indices.min(by: { base.path[$0].horizontalDistance(to: baseA) < base.path[$1].horizontalDistance(to: baseA) }),
              let j = new.path.indices.min(by: { new.path[$0].horizontalDistance(to: newA) < new.path[$1].horizontalDistance(to: newA) }),
              base.path[i].horizontalDistance(to: baseA) <= 0.35,
              new.path[j].horizontalDistance(to: newA) <= 0.35,
              parent.alignment.apply(base.path[i]).distance(to: transform.apply(new.path[j])) <= 0.5 else {
            throw MapError.invalid("The shared landmark must be on both walked paths. No connecting corridor was assumed.")
        }
        segments.append(Segment(scanID: new.scanID, routeID: new.id, alignment: transform))
        links.append(Link(first: base.id, second: new.id, firstIndex: i, secondIndex: j)); revision += 1
    }
    public struct PlannedPath { public let points: [SpatialPoint]; public let routeIDs: Set<UUID> }
    public func path(from start: UUID, to end: UUID, routes: [UUID: HallwayRoute], blocked: Set<UUID> = []) throws -> PlannedPath {
        guard segments.count <= 32, segments.count > 0, links.count <= 64, Set(segments.map(\.scanID)).count == segments.count,
              Set(segments.map(\.routeID)).count == segments.count else { throw MapError.invalid("Invalid building collection.") }
        var points: [String: SpatialPoint] = [:], adjacency: [String: [(String, Float)]] = [:]
        func key(_ id: UUID, _ i: Int) -> String { "\(id):\(i)" }
        func connect(_ a: String, _ b: String) throws {
            guard let p = points[a], let q = points[b], p.isFinite, q.isFinite else { throw MapError.invalid("Missing connection geometry.") }
            let d = p.distance(to: q)
            adjacency[a, default: []].append((b,d)); adjacency[b, default: []].append((a,d))
        }
        for segment in segments where !blocked.contains(segment.routeID) {
            guard let route = routes[segment.routeID], !route.hasLevelChange, route.scanID == segment.scanID, route.path.count >= 2, route.path.count <= 20000, points.count + route.path.count <= 40000, segment.alignment.yaw.isFinite, segment.alignment.translation.isFinite else { throw MapError.invalid("A building recording is missing or changed.") }
            for (i,p) in route.path.enumerated() { points[key(route.id,i)] = segment.alignment.apply(p) }
            for i in 1..<route.path.count { try connect(key(route.id,i-1),key(route.id,i)) }
        }
        for link in links where !blocked.contains(link.first) && !blocked.contains(link.second) {
            let a = key(link.first,link.firstIndex), b = key(link.second,link.secondIndex)
            guard let p = points[a], let q = points[b], p.distance(to: q) <= 0.5 else { throw MapError.invalid("A shared landmark no longer aligns.") }
            try connect(a,b)
        }
        guard let endRoute = routes[end] else { throw MapError.invalid("Unknown destination.") }
        let source = key(start,0), goal = key(end,endRoute.path.count-1)
        guard points[source] != nil, points[goal] != nil else { throw MapError.invalid("Starting route or destination is closed.") }
        var costs = [source: Float(0)], previous: [String:String] = [:], pending: Set<String> = [source], visited = Set<String>()
        while let current = pending.min(by: { costs[$0,default:.infinity] < costs[$1,default:.infinity] }) {
            pending.remove(current)
            if current == goal { break }; visited.insert(current)
            for (next,d) in adjacency[current,default:[]] where !visited.contains(next) {
                let cost = costs[current,default:.infinity]+d
                if cost < costs[next,default:.infinity] { costs[next] = cost; previous[next] = current; pending.insert(next) }
            }
        }
        guard costs[goal] != nil else { throw MapError.invalid("No verified connected route is available.") }
        var nodes = [goal], cursor = goal
        while cursor != source { guard let p = previous[cursor] else { throw MapError.invalid("Broken path.") }; nodes.append(p); cursor = p }
        let ordered = nodes.reversed().compactMap { points[$0] }
        var result: [SpatialPoint] = []
        for point in ordered where result.last.map({ $0.horizontalDistance(to: point) > 0.01 }) ?? true { result.append(point) }
        return PlannedPath(points: result, routeIDs: Set(nodes.compactMap { UUID(uuidString: String($0.prefix(36))) }))
    }
}
