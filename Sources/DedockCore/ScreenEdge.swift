import CoreGraphics

/// The screen edge a dock instance lives on (DD-902). The top edge is not offered in v1,
/// but callers should switch exhaustively so adding it later is a compile error, not a bug.
public enum ScreenEdge: String, Codable, Sendable, CaseIterable {
    case left, right, bottom

    /// Side docks are laid out vertically; the bottom dock horizontally (DD-903).
    public var isVertical: Bool { self != .bottom }

    /// Unit vector pointing from the screen centre toward this edge, in AppKit global
    /// coordinates (y grows upward).
    public var outwardNormal: CGVector {
        switch self {
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        case .bottom: CGVector(dx: 0, dy: -1)
        }
    }
}

/// A display corner, used for Hot Corner exclusions.
public enum ScreenCorner: String, Codable, Sendable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

extension ScreenEdge {
    /// The two corners at the ends of this edge, ordered (lower end, upper end) along the edge axis.
    /// For side edges the axis is y (bottom → top); for the bottom edge it is x (left → right).
    public var corners: (lower: ScreenCorner, upper: ScreenCorner) {
        switch self {
        case .left: (.bottomLeft, .topLeft)
        case .right: (.bottomRight, .topRight)
        case .bottom: (.bottomLeft, .bottomRight)
        }
    }
}
