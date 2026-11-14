import Foundation

public enum MapError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

public struct Floor: Codable, Identifiable, Equatable {
    public let id: Int
    public let label: String
}

public struct Checkpoint: Codable, Identifiable, Equatable {
    public let id: String
    public let label: String
    public let floor: Int
    public let kind: String
    public let x: Double
    public let y: Double
}

public struct Connection: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case hallway, elevator, stairs }
    public let id: String
    public let from: String
    public let to: String
    public let distance: Double
    public let kind: Kind
    public var verified: Bool
    public var blocked: Bool
}

public struct Building: Codable, Equatable {
    public let schemaVersion: Int
    public let buildingID: String
    public let name: String
    public let description: String
    public var floors: [Floor]
    public var nodes: [Checkpoint]
    public var edges: [Connection]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", buildingID = "building_id"
        case name, description, floors, nodes, edges
    }

    public static func load(_ data: Data) throws -> Building {
        let building = try JSONDecoder().decode(Building.self, from: data)
        try building.validate()
        return building
    }

    public static func demo() throws -> Building {
        guard let url = Bundle.module.url(forResource: "demo_building", withExtension: "json") else {
            throw MapError.invalid("The demo map is missing. Reinstall Indoorbility.")
        }
        return try load(Data(contentsOf: url))
    }

    public func validate() throws {
        guard schemaVersion == 1 else { throw MapError.invalid("This map version is not supported.") }
        guard !nodes.isEmpty, !floors.isEmpty,
              Set(nodes.map(\.id)).count == nodes.count,
              Set(edges.map(\.id)).count == edges.count,
              Set(floors.map(\.id)).count == floors.count else {
            throw MapError.invalid("The map has missing data or duplicate identifiers.")
        }
        let floorIDs = Set(floors.map(\.id))
        let nodeIDs = Set(nodes.map(\.id))
        guard nodes.allSatisfy({ !$0.id.isEmpty && !$0.label.isEmpty && floorIDs.contains($0.floor) && $0.x.isFinite && $0.y.isFinite }) else {
            throw MapError.invalid("A checkpoint has an invalid floor or position.")
        }
        guard edges.allSatisfy({ !$0.id.isEmpty && nodeIDs.contains($0.from) && nodeIDs.contains($0.to) && $0.from != $0.to && $0.distance.isFinite && $0.distance > 0 }) else {
            throw MapError.invalid("A connection has invalid endpoints or cost.")
        }
    }

    public func node(_ id: String) -> Checkpoint? { nodes.first { $0.id == id } }
    public func edgeLabel(_ id: String) -> String {
        guard let edge = edges.first(where: { $0.id == id }) else { return "Unknown connection" }
        if edge.kind == .elevator {
            return node(edge.from)?.label.components(separatedBy: " - ").first ?? "Lift"
        }
        return "\(node(edge.from)?.label ?? edge.from) → \(node(edge.to)?.label ?? edge.to)"
    }

    public func destinations(matching query: String) -> [Checkpoint] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let destinations = nodes.filter { $0.kind != "junction" }
        if query.isEmpty { return destinations }
        return destinations.filter { $0.label.localizedCaseInsensitiveContains(query) }
    }
}
