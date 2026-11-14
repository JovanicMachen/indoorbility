import Foundation

public enum SignLocationMatcher {
    /// Returns candidates only. A recognized label is not proof of physical location.
    public static func candidates(in text: String, building: Building) -> [Checkpoint] {
        func normalized(_ value: String) -> String {
            value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        let recognized = " " + normalized(text) + " "
        return building.nodes.filter { node in
            // Floor-specific labels must include the floor; "Lift A" alone is ambiguous.
            let label = " " + normalized(node.label) + " "
            return recognized.contains(label)
        }
    }
}
