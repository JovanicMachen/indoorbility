import Foundation

/// Describes confirmed app state only; never infers physical movement or obstacles.
public enum NavigationNarration {
    public static func update(from old: NavigationSession, to new: NavigationSession, instruction: String) -> String? {
        let reportsChanged = old.saved.reports != new.saved.reports
        let routeChanged = old.route?.nodeIDs != new.route?.nodeIDs
        let positionChanged = old.checkpointID != new.checkpointID
        let destinationChanged = old.destinationID != new.destinationID
        let routingChanged = old.saved.preferences.avoidStairs != new.saved.preferences.avoidStairs
        guard reportsChanged || routeChanged || positionChanged || destinationChanged || routingChanged || old.isGuiding != new.isGuiding else { return nil }
        if new.needsPosition { return "Starting point is not confirmed. Scan a known sign or choose your starting point before continuing." }
        if new.arrived { return "Arrival confirmed at \(new.destinationID.flatMap(new.building.node)?.label ?? "your destination"). Guidance has ended." }
        if new.destinationID != nil && new.route == nil {
            return "No route is available with the current closures and preferences. Review barriers or choose another destination."
        }
        if reportsChanged {
            return (new.updateMessage ?? "Closures updated.") + (new.route != nil ? " Route recalculated. " + instruction : "")
        }
        if new.isGuiding { return (old.isGuiding ? "" : "Guidance started. ") + instruction }
        if old.isGuiding { return "Guidance paused. Select Start when you are ready to continue." }
        if destinationChanged || routingChanged, new.route != nil {
            return "Route ready to \(new.destinationID.flatMap(new.building.node)?.label ?? "your destination"). Select Start for checkpoint instructions."
        }
        if positionChanged { return "Starting point confirmed: \(new.checkpointID.flatMap(new.building.node)?.label ?? "checkpoint")." }
        return new.updateMessage
    }
}
