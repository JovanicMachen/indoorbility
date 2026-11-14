import Foundation

/// Require repeated fresh evidence; never interpret missing detections as a clear path.
public struct ObjectAlertFilter {
    private var candidate: String?
    private var count = 0
    private var lastSample = -Double.infinity
    private var lastAlert = -Double.infinity
    public init() {}
    public mutating func update(kind: String?, capturedAt: Double, now: Double, reliable: Bool) -> Bool {
        guard reliable, capturedAt.isFinite, now.isFinite, now >= capturedAt,
              now - capturedAt <= 1, capturedAt > lastSample else {
            candidate = nil; count = 0; return false
        }
        if capturedAt - lastSample > 2 { candidate = nil; count = 0 }
        lastSample = capturedAt
        guard let kind else { candidate = nil; count = 0; return false }
        count = candidate == kind ? count + 1 : 1; candidate = kind
        guard count >= 2, now - lastAlert >= 8 else { return false }
        lastAlert = now; return true
    }
}
