import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DedockCore

// Pure (architecture rule D5). Same input → same output; table-tested (architecture §6.8).

public enum TileLength: Double, Codable, Sendable { case unit = 1.0, compact = 1.5, medium = 2.25, wide = 3.0, extraWide = 4.0 }

public enum TileShape: Sendable, Hashable {
    /// Widgets: `lengthUnits × t` along the dock axis.
    case square(TileLength)
    /// Apps and folders: a bare icon in a cell of `DockMetrics.appCellLength` along the axis.
    case app
    /// The divider between sections.
    case separator
}

public struct TileSpec: Sendable, Hashable, Identifiable {
    public let id: TileID
    public let shape: TileShape
    public init(id: TileID, shape: TileShape = .app) {
        self.id = id
        self.shape = shape
    }
}

public enum DockAlignment: String, Codable, Sendable, CaseIterable { case start, center, end }

/// Geometry metrics, supplied from DesignSystem tokens (dedock's own values; PLACEHOLDER until
/// the design gate).
public struct DockMetrics: Sendable, Hashable {
    /// `T`: dock thickness across the edge.
    public var thickness: CGFloat
    /// `p`: capsule padding.
    public var padding: CGFloat
    /// `g`: gap between tiles.
    public var gap: CGFloat
    public var separatorLength: CGFloat
    /// Length of an app or folder cell along the dock axis (defaults to `t`, a square cell).
    public var appCellLength: CGFloat?
    /// DD-925 distance from the edge, 0–48 pt.
    public var edgeGap: CGFloat
    /// Lane toward the screen centre for the instant tile label.
    public var labelLane: CGFloat
    /// Shadow reach around the capsule: panel margin and part of the hidden travel.
    public var shadowMargin: CGFloat
    /// Margin kept free at each end of the available length (design.md §7.1: max length =
    /// visible edge − 48 pt, i.e. 24 pt per end).
    public var endMargin: CGFloat = 8
    public var minimumScale: CGFloat = 0.6

    public var tileThickness: CGFloat { thickness - 2 * padding }

    public init(thickness: CGFloat, padding: CGFloat, gap: CGFloat, separatorLength: CGFloat,
                edgeGap: CGFloat, labelLane: CGFloat, shadowMargin: CGFloat) {
        self.thickness = thickness
        self.padding = padding
        self.gap = gap
        self.separatorLength = separatorLength
        self.edgeGap = edgeGap
        self.labelLane = labelLane
        self.shadowMargin = shadowMargin
    }
}

public struct PlacementInput: Sendable, Hashable {
    public let display: DisplaySnapshot
    public let edge: ScreenEdge
    public let alignment: DockAlignment
    /// Bottom edge with a visible native Dock: the dock sits above it (its thickness here).
    public let nativeDockInset: CGFloat

    public init(display: DisplaySnapshot, edge: ScreenEdge, alignment: DockAlignment = .center, nativeDockInset: CGFloat = 0) {
        self.display = display
        self.edge = edge
        self.alignment = alignment
        self.nativeDockInset = nativeDockInset
    }
}

public struct DockLayout: Sendable, Hashable {
    /// The fixed, fully shown panel frame (AppKit global). It never moves while revealing.
    public let panelFrame: CGRect
    public let capsuleFrame: CGRect
    /// At the shown position, AppKit global, in tile order.
    public let tileFrames: [TileID: CGRect]
    public let order: [TileID]
    /// Running indicators and labels face the screen centre.
    public let indicatorSide: ScreenEdge
    /// Translation that parks the content off-screen (along `edge.outward`).
    public let hiddenOffset: CGVector
    /// < 1 when the content had to shrink to fit.
    public let scale: CGFloat
    /// Capsule extent along the edge axis (feeds `EdgeEnvironment.contentSpan`).
    public let contentSpan: Interval
    public let edge: ScreenEdge
}

public enum LayoutEngine {
    public static func layout(_ tiles: [TileSpec], _ placement: PlacementInput, _ m: DockMetrics) -> DockLayout {
        let edge = placement.edge
        let d = placement.display
        let t = m.tileThickness

        // Available length along the edge.
        let available: Interval = switch edge {
        case .left, .right: Interval(d.visibleFrame.minY + m.endMargin, d.visibleFrame.maxY - m.endMargin)
        case .bottom, .top: Interval(d.visibleFrame.minX + m.endMargin, d.visibleFrame.maxX - m.endMargin)
        }

        func length(_ shape: TileShape, _ scale: CGFloat) -> CGFloat {
            switch shape {
            case .square(let units): CGFloat(units.rawValue) * t * scale
            case .app: (m.appCellLength ?? t) * scale
            case .separator: max(1, m.separatorLength * scale)
            }
        }
        func contentLength(_ scale: CGFloat) -> CGFloat {
            guard !tiles.isEmpty else { return t * scale + 2 * m.padding }
            let sum = tiles.reduce(0) { $0 + length($1.shape, scale) }
            return sum + CGFloat(tiles.count - 1) * m.gap * scale + 2 * m.padding
        }

        // Overflow: shrink uniformly down to minimumScale, then clip at the far end.
        var scale: CGFloat = 1
        let natural = contentLength(1)
        if natural > available.length {
            let fixed = 2 * m.padding
            scale = max(m.minimumScale, (available.length - fixed) / max(1, natural - fixed))
        }
        let capsuleLength = min(contentLength(scale), available.length)
        let capsuleThickness = m.thickness

        // Position along the edge.
        let start: CGFloat = switch (placement.alignment, edge.isVertical) {
        case (.center, _): available.midpoint - capsuleLength / 2
        // Side docks: "start" is the top, the first item in reading order.
        case (.start, true): available.upper - capsuleLength
        case (.end, true): available.lower
        case (.start, false): available.lower
        case (.end, false): available.upper - capsuleLength
        }
        // Device-pixel alignment: an odd visibleFrame (e.g. 975 pt) would otherwise put the dock on
        // half points and blur its edges on a 1× display.
        let scalePx = max(1, d.backingScale)
        func px(_ v: CGFloat) -> CGFloat { (v * scalePx).rounded() / scalePx }
        func aligned(_ r: CGRect) -> CGRect {
            let minX = px(r.minX), minY = px(r.minY)
            return CGRect(x: minX, y: minY, width: px(r.maxX) - minX, height: px(r.maxY) - minY)
        }
        let span = Interval(px(start), px(start) + px(capsuleLength))

        // Cross-axis: distance from the screen edge (or the native Dock's inner edge at the bottom).
        let f = d.frame
        let capsule: CGRect = switch edge {
        case .left: CGRect(x: f.minX + m.edgeGap, y: span.lower, width: capsuleThickness, height: span.length)
        case .right: CGRect(x: f.maxX - m.edgeGap - capsuleThickness, y: span.lower, width: capsuleThickness, height: span.length)
        case .bottom: CGRect(x: span.lower, y: f.minY + placement.nativeDockInset + m.edgeGap, width: span.length, height: capsuleThickness)
        case .top: CGRect(x: span.lower, y: f.maxY - d.menuBarHeight - m.edgeGap - capsuleThickness, width: span.length, height: capsuleThickness)
        }

        // Tiles in reading order: top → bottom on side docks, leading → trailing otherwise.
        var frames: [TileID: CGRect] = [:]
        var cursor: CGFloat = edge.isVertical ? capsule.maxY - m.padding : capsule.minX + m.padding
        let tileT = t * scale
        for tile in tiles {
            let l = length(tile.shape, scale)
            let cross = tile.shape == .separator ? tileT : tileT
            let r: CGRect
            if edge.isVertical {
                r = CGRect(x: capsule.midX - cross / 2, y: cursor - l, width: cross, height: l)
                cursor -= l + m.gap * scale
            } else {
                r = CGRect(x: cursor, y: capsule.midY - cross / 2, width: l, height: cross)
                cursor += l + m.gap * scale
            }
            frames[tile.id] = aligned(r)
        }

        // Panel: from the true screen edge (or the native Dock's inner edge) through the capsule,
        // plus the label lane and shadow margin toward the centre; never into the menu bar.
        let inward = m.labelLane + m.shadowMargin
        let alongPad = m.shadowMargin
        var panel: CGRect = switch edge {
        case .left: CGRect(x: f.minX, y: capsule.minY - alongPad, width: capsule.maxX - f.minX + inward, height: capsule.height + 2 * alongPad)
        case .right:
            CGRect(x: capsule.minX - inward, y: capsule.minY - alongPad, width: f.maxX - capsule.minX + inward, height: capsule.height + 2 * alongPad)
        case .bottom:
            CGRect(x: capsule.minX - alongPad, y: f.minY + placement.nativeDockInset, width: capsule.width + 2 * alongPad,
                   height: capsule.maxY - (f.minY + placement.nativeDockInset) + inward)
        case .top:
            CGRect(x: capsule.minX - alongPad, y: capsule.minY - inward, width: capsule.width + 2 * alongPad,
                   height: (f.maxY - d.menuBarHeight) - capsule.minY + inward)
        }
        panel = aligned(panel).intersection(f)
        if edge.isVertical {
            panel = panel.intersection(CGRect(x: f.minX, y: f.minY, width: f.width, height: f.height - d.menuBarHeight))
        }

        // Hidden offset = T + edge inset + shadow reach (design.md §4.2), so no shadow shows.
        let travel = m.thickness + m.edgeGap + max(8, m.shadowMargin)
        let o = edge.outward
        return DockLayout(
            panelFrame: panel, capsuleFrame: capsule, tileFrames: frames, order: tiles.map(\.id),
            indicatorSide: edge.opposite, hiddenOffset: CGVector(dx: o.dx * travel, dy: o.dy * travel),
            scale: scale, contentSpan: edge.isVertical ? Interval(capsule.minY, capsule.maxY) : Interval(capsule.minX, capsule.maxX),
            edge: edge)
    }

    /// design.md §4.3: a side dock re-centres only when its display's change moves it along the
    /// edge by `threshold` (4 pt) or more, or when its current position would overlap the newly
    /// reserved area (outside `visible`). Smaller moves keep the old layout, so a 1 pt
    /// `visibleFrame` change (an icon added to the native Dock) does not nudge the dock.
    public static func keepingPosition(old: DockLayout, new: DockLayout, visible: CGRect, threshold: CGFloat = 4) -> DockLayout {
        guard new.edge.isVertical, old.edge == new.edge, old.scale == new.scale, old.order == new.order,
              old.capsuleFrame.size == new.capsuleFrame.size, old.capsuleFrame.minX == new.capsuleFrame.minX else { return new }
        let shift = new.capsuleFrame.midY - old.capsuleFrame.midY
        guard shift != 0, abs(shift) < threshold else { return new }
        // Every tile must have moved by the same amount (a pure translation).
        for (id, r) in new.tileFrames {
            guard let o = old.tileFrames[id], o.size == r.size, abs((r.midY - o.midY) - shift) < 0.01 else { return new }
        }
        let fits = old.capsuleFrame.minY >= visible.minY && old.capsuleFrame.maxY <= visible.maxY
        return fits ? old : new
    }

    /// Insertion index for a reorder drag, from a layout frozen at drag start (DD-975).
    public static func insertionIndex(for point: CGPoint, in frozen: DockLayout, order: [TileID], moving: TileID) -> Int {
        let others = order.filter { $0 != moving }
        let along = frozen.edge.along(point)
        var index = 0
        for id in others {
            guard let r = frozen.tileFrames[id] else { continue }
            let mid = frozen.edge.isVertical ? r.midY : r.midX
            // Side docks run top → bottom (decreasing y); horizontal docks left → right.
            let before = frozen.edge.isVertical ? along > mid : along < mid
            if before { break }
            index += 1
        }
        return index
    }
}
