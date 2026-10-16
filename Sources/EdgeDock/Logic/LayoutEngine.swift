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
    /// Splits the dock into separate capsules ("islands", SP3) with `islandGap` between them.
    case separator
    /// Half a cell of empty glass inside a capsule (SP3).
    case spacer
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
    /// Clear space between two islands (SP3 Islands, design.md §7.2a).
    public var islandGap: CGFloat = 8

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
    /// A visible native Dock on the same edge (left, right or bottom): the dock sits on its
    /// inner side and slides out from there (the Dock's thickness here; REG-070).
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
    /// The whole dock along the edge, every island included. It is still ONE dock for the trigger
    /// zone, hysteresis and click-through region (SP3).
    public let capsuleFrame: CGRect
    /// The capsules actually drawn: one per run of tiles between separators (SP3 Islands). Equal
    /// to `[capsuleFrame]` without separators.
    public let islands: [CGRect]
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

        // Only a separator with content on both sides (since the previous break) splits the
        // dock; leading, trailing and doubled separators collapse to zero length and stay in
        // the data, so the union never includes invisible glass. A spacer counts as content,
        // so a spacer-only island is allowed.
        var effective: Set<TileID> = []
        var sawContent = false
        for (i, tile) in tiles.enumerated() {
            if tile.shape == .separator {
                let contentAfter = tiles[(i + 1)...].contains { $0.shape != .separator }
                if sawContent, contentAfter { effective.insert(tile.id); sawContent = false }
            } else {
                sawContent = true
            }
        }
        let laid = tiles.filter { $0.shape != .separator || effective.contains($0.id) }

        func length(_ shape: TileShape, _ scale: CGFloat) -> CGFloat {
            switch shape {
            case .square(let units): CGFloat(units.rawValue) * t * scale
            case .app: (m.appCellLength ?? t) * scale
            // An island break: the end padding of one island, the gap, the start padding of the
            // next, minus the tile gaps already on either side of the cell.
            case .separator: max(1, 2 * m.padding + m.islandGap - 2 * m.gap * scale)
            case .spacer: (m.appCellLength ?? t) * scale / 2
            }
        }
        func contentLength(_ scale: CGFloat) -> CGFloat {
            guard !laid.isEmpty else { return t * scale + 2 * m.padding }
            let sum = laid.reduce(0) { $0 + length($1.shape, scale) }
            return sum + CGFloat(laid.count - 1) * m.gap * scale + 2 * m.padding
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

        // Cross-axis: distance from the screen edge, or from a visible native Dock's inner edge.
        let f = d.frame
        let inset = edge == .top ? 0 : placement.nativeDockInset
        let capsule: CGRect = switch edge {
        case .left: CGRect(x: f.minX + inset + m.edgeGap, y: span.lower, width: capsuleThickness, height: span.length)
        case .right: CGRect(x: f.maxX - inset - m.edgeGap - capsuleThickness, y: span.lower, width: capsuleThickness, height: span.length)
        case .bottom: CGRect(x: span.lower, y: f.minY + inset + m.edgeGap, width: span.length, height: capsuleThickness)
        case .top: CGRect(x: span.lower, y: f.maxY - d.menuBarHeight - m.edgeGap - capsuleThickness, width: span.length, height: capsuleThickness)
        }

        // Tiles in reading order: top → bottom on side docks, leading → trailing otherwise.
        var frames: [TileID: CGRect] = [:]
        var cursor: CGFloat = edge.isVertical ? capsule.maxY - m.padding : capsule.minX + m.padding
        let tileT = t * scale
        for tile in tiles {
            guard tile.shape != .separator || effective.contains(tile.id) else {
                // Collapsed: a zero-length frame where it sits, no gap.
                frames[tile.id] = edge.isVertical
                    ? CGRect(x: capsule.midX, y: cursor, width: 0, height: 0)
                    : CGRect(x: cursor, y: capsule.midY, width: 0, height: 0)
                continue
            }
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

        // Islands: each run of tiles between separators gets its own capsule (padding at both ends).
        var islands: [CGRect] = []
        var run: [CGRect] = []
        func closeRun() {
            guard let first = run.first, let last = run.last else { return }
            let r: CGRect = edge.isVertical
                ? CGRect(x: capsule.minX, y: last.minY - m.padding, width: capsule.width,
                         height: first.maxY - last.minY + 2 * m.padding)
                : CGRect(x: first.minX - m.padding, y: capsule.minY, width: last.maxX - first.minX + 2 * m.padding,
                         height: capsule.height)
            islands.append(aligned(r.intersection(capsule)))
            run.removeAll()
        }
        for tile in tiles {
            if tile.shape == .separator {
                if effective.contains(tile.id) { closeRun() }
            } else if let r = frames[tile.id] {
                run.append(r)
            }
        }
        closeRun()
        if islands.isEmpty || effective.isEmpty { islands = [capsule] }

        // Panel: from the true screen edge (or the native Dock's inner edge) through the capsule,
        // plus the label lane and shadow margin toward the centre; never into the menu bar.
        let inward = m.labelLane + m.shadowMargin
        let alongPad = m.shadowMargin
        var panel: CGRect = switch edge {
        case .left:
            CGRect(x: f.minX + inset, y: capsule.minY - alongPad, width: capsule.maxX - (f.minX + inset) + inward,
                   height: capsule.height + 2 * alongPad)
        case .right:
            CGRect(x: capsule.minX - inward, y: capsule.minY - alongPad, width: (f.maxX - inset) - capsule.minX + inward,
                   height: capsule.height + 2 * alongPad)
        case .bottom:
            CGRect(x: capsule.minX - alongPad, y: f.minY + inset, width: capsule.width + 2 * alongPad,
                   height: capsule.maxY - (f.minY + inset) + inward)
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
            panelFrame: panel, capsuleFrame: capsule, islands: islands, tileFrames: frames, order: tiles.map(\.id),
            indicatorSide: edge.opposite, hiddenOffset: CGVector(dx: o.dx * travel, dy: o.dy * travel),
            scale: scale, contentSpan: edge.isVertical ? Interval(capsule.minY, capsule.maxY) : Interval(capsule.minX, capsule.maxX),
            edge: edge)
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
