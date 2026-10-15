import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif

/// One pointer event as seen by edge sensing (architecture §6.2).
public struct PointerSample: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case monitor, menuTrackingTimer }

    /// AppKit global coordinates (bottom-left origin, y up).
    public var location: CGPoint
    /// Movement since the previous event, **normalised to AppKit y-up**. `PointerHub` flips
    /// `NSEvent.deltaY` (positive = down) once, so every consumer sees y-up deltas. Deltas keep
    /// arriving while the cursor is clamped at a physical edge.
    public var delta: CGVector
    /// Event time since boot.
    public var timestamp: Duration
    public var buttonsDown: Bool
    public var modifiers: ModifierSet
    public var source: Source
    /// Debug only: the event was posted by the E2E driver (eventSourceUserData 0xDED0C).
    public var isSynthetic: Bool

    public init(
        location: CGPoint, delta: CGVector = .zero, timestamp: Duration,
        buttonsDown: Bool = false, modifiers: ModifierSet = [], source: Source = .monitor,
        isSynthetic: Bool = false
    ) {
        self.location = location
        self.delta = delta
        self.timestamp = timestamp
        self.buttonsDown = buttonsDown
        self.modifiers = modifiers
        self.source = source
        self.isSynthetic = isSynthetic
    }

    /// The component of `delta` that pushes toward `edge` (positive = toward it).
    public func push(toward edge: ScreenEdge) -> CGFloat {
        let n = edge.outward
        return delta.dx * n.dx + delta.dy * n.dy
    }
}

/// Modifier keys relevant to edge sensing (the shared-edge modifier policy, DD-931).
public struct ModifierSet: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let option = ModifierSet(rawValue: 1 << 0)
    public static let command = ModifierSet(rawValue: 1 << 1)
    public static let control = ModifierSet(rawValue: 1 << 2)
    public static let shift = ModifierSet(rawValue: 1 << 3)
}

extension Duration {
    /// Seconds as a `Double`.
    public var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }
}
