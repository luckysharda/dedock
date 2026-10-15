import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif

/// The screen edge a dock instance lives on (DD-902). `top` sits below the menu bar and is
/// optional (DD-1141, pulled into M1 by user decision).
public enum ScreenEdge: String, Codable, Sendable, CaseIterable {
    case left, right, bottom, top

    /// Side docks are laid out vertically; bottom and top docks horizontally (DD-903).
    public var orientation: DockOrientation { self == .left || self == .right ? .vertical : .horizontal }
    public var isVertical: Bool { orientation == .vertical }

    /// Unit vector from the screen centre toward this edge, in AppKit global coordinates (y up).
    public var outward: CGVector {
        switch self {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .bottom: CGVector(dx: 0, dy: -1)
        case .top: CGVector(dx: 0, dy: 1)
        }
    }

    public var opposite: ScreenEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .bottom: .top
        case .top: .bottom
        }
    }

    /// The two corners at the ends of this edge, ordered (lower, upper) along the edge axis:
    /// y (bottom → top) for side edges, x (left → right) for bottom and top.
    public var corners: (lower: ScreenCorner, upper: ScreenCorner) {
        switch self {
        case .left: (.bottomLeft, .topLeft)
        case .right: (.bottomRight, .topRight)
        case .bottom: (.bottomLeft, .bottomRight)
        case .top: (.topLeft, .topRight)
        }
    }
}

public enum DockOrientation: Sendable, Hashable { case horizontal, vertical }

/// A display corner, for Hot Corner exclusions.
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Corners whose Hot Corner has an action (`com.apple.dock wvous-*-corner` > 1).
public struct HotCornerMask: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let topLeft = HotCornerMask(rawValue: 1 << 0)
    public static let topRight = HotCornerMask(rawValue: 1 << 1)
    public static let bottomLeft = HotCornerMask(rawValue: 1 << 2)
    public static let bottomRight = HotCornerMask(rawValue: 1 << 3)
    /// Unknown state: keep the larger exclusion everywhere.
    public static let all: HotCornerMask = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    public init(_ corner: ScreenCorner) {
        switch corner {
        case .topLeft: self = .topLeft
        case .topRight: self = .topRight
        case .bottomLeft: self = .bottomLeft
        case .bottomRight: self = .bottomRight
        }
    }

    public func contains(_ corner: ScreenCorner) -> Bool { contains(HotCornerMask(corner)) }
}

extension CGRect {
    /// Converts between AppKit global (bottom-left origin, y up) and CoreGraphics global
    /// (top-left origin of the primary display, y down). The conversion is its own inverse.
    /// - Parameter primaryHeight: height of the primary display (`NSScreen.screens[0].frame.height`).
    public func flippedVertically(primaryHeight: CGFloat) -> CGRect {
        CGRect(x: minX, y: primaryHeight - maxY, width: width, height: height)
    }
}

extension CGPoint {
    public func flippedVertically(primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: x, y: primaryHeight - y)
    }
}

extension ScreenEdge {
    /// The full edge of `frame` on this side, as an interval along the edge axis.
    public func line(of frame: CGRect) -> Interval {
        isVertical ? Interval(frame.minY, frame.maxY) : Interval(frame.minX, frame.maxX)
    }

    /// The coordinate along the edge axis of `point` (y for side edges, x otherwise).
    public func along(_ point: CGPoint) -> CGFloat { isVertical ? point.y : point.x }

    /// The strip of `thickness` inward from this edge of `frame`, covering `span` along the edge.
    public func strip(of frame: CGRect, along span: Interval, thickness: CGFloat) -> CGRect {
        switch self {
        case .left: CGRect(x: frame.minX, y: span.lower, width: thickness, height: span.length)
        case .right: CGRect(x: frame.maxX - thickness, y: span.lower, width: thickness, height: span.length)
        case .bottom: CGRect(x: span.lower, y: frame.minY, width: span.length, height: thickness)
        case .top: CGRect(x: span.lower, y: frame.maxY - thickness, width: span.length, height: thickness)
        }
    }
}
