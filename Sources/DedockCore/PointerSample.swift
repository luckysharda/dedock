import CoreGraphics
import Foundation

/// One pointer event as seen by edge sensing (architecture §6).
public struct PointerSample: Sendable, Equatable {
    /// AppKit global coordinates (bottom-left origin).
    public var location: CGPoint
    /// Raw `NSEvent.deltaX` / `deltaY`. These keep arriving while the cursor is clamped at a
    /// physical edge. Note the NSEvent convention: **`dy` is positive when moving down**.
    public var delta: CGVector
    /// Event timestamp in seconds (monotonic).
    public var timestamp: TimeInterval
    public var buttonsDown: Bool

    public init(location: CGPoint, delta: CGVector = .zero, timestamp: TimeInterval, buttonsDown: Bool = false) {
        self.location = location
        self.delta = delta
        self.timestamp = timestamp
        self.buttonsDown = buttonsDown
    }

    /// The component of `delta` that pushes toward `edge` (positive = toward it).
    public func push(toward edge: ScreenEdge) -> CGFloat {
        switch edge {
        case .left: -delta.dx
        case .right: delta.dx
        case .bottom: delta.dy // NSEvent dy > 0 means downward
        }
    }
}
