import CoreGraphics
import DedockCore

/// One rectangle of the invisible edge strip that arms a dock (architecture §7.5).
public struct HotZone: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The cursor stops at this edge: plain contact arms (dwell or push-through).
        case wall
        /// The edge borders another display, so the cursor crosses over: needs a slow dwell (DD-931).
        case shared
    }

    public var edge: ScreenEdge
    public var displayID: String
    /// AppKit global coordinates, already corner-, menu-bar-, neighbour- and native-Dock-clipped.
    public var rect: CGRect
    public var kind: Kind

    public init(edge: ScreenEdge, displayID: String, rect: CGRect, kind: Kind) {
        self.edge = edge
        self.displayID = displayID
        self.rect = rect
        self.kind = kind
    }

    /// Inclusive containment. `NSEvent.mouseLocation` can report the far edge coordinate
    /// itself (e.g. `x == frame.maxX` at the right edge), which `CGRect.contains` excludes.
    public func contains(_ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}
