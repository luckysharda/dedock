import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif
import DedockCore

// Pure (architecture rule D5): Foundation, CoreGraphics and DedockCore only.

public enum SegmentKind: String, Sendable, Hashable, Codable {
    /// The cursor stops at this edge: contact arms (dwell or push-through).
    case wall
    /// The edge borders another display, so the cursor crosses over (DD-931).
    case shared
}

public enum SharedEdgePolicy: String, Codable, Sendable, CaseIterable {
    /// 300 ms in the band while slower than 300 pt/s (default).
    case slowDwell
    /// Contact with the band while ⌥ is held.
    case modifier
    /// Shared segments never trigger.
    case wallOnly
}

/// Trigger tuning for one dock (architecture §6.4; defaults settled by dedock-e9, 2026-10-15).
public struct TriggerParameters: Sendable, Hashable {
    public enum SpanMode: String, Sendable, Codable, CaseIterable { case content, wholeEdge }

    /// Wall zone thickness from the physical edge (`frame`, not `visibleFrame`). 1–20 pt.
    public var thickness: CGFloat = 3
    public var spanMode: SpanMode = .content
    /// Zone extension past each end of the dock content.
    public var spanPadding: CGFloat = 40
    /// Corner exclusion when that corner has a Hot Corner action. 0–96 pt.
    public var cornerExclusion: CGFloat = 24
    /// Corner exclusion when that corner's Hot Corner is off.
    public var cornerExclusionWithoutHotCorner: CGFloat = 8
    /// Band on an edge segment shared with another display. 4–24 pt.
    public var sharedBand: CGFloat = 8
    public var sharedPolicy: SharedEdgePolicy = .slowDwell
    /// Capsule outset inside which the pointer still counts as on the dock. 0–40 pt.
    public var hysteresis: CGFloat = 16
    /// Accumulated push toward the edge that reveals before the dwell ends; `nil` = off.
    public var pushThrough: CGFloat? = 40
    /// Shared band: the dwell restarts while the pointer moves faster than this (pt/s) …
    public var sharedMaxSpeed: CGFloat = 300
    /// … over this trailing window.
    public var sharedSpeedWindow: Duration = .milliseconds(50)
    /// A sample on the neighbouring display this soon after entering the band was a crossing.
    public var crossingGuard: Duration = .milliseconds(80)
    /// Unthrottled sampling band around zones and the capsule (architecture §6.3).
    public var nearBand: CGFloat = 96

    public init() {}
}

/// One rect of the invisible strip that arms a dock.
public struct HotZone: Sendable, Hashable {
    /// Stable within one geometry build: `z-<index>`.
    public let id: String
    /// AppKit global, already clipped.
    public let rect: CGRect
    public let kind: SegmentKind

    public init(id: String, rect: CGRect, kind: SegmentKind) {
        self.id = id
        self.rect = rect
        self.kind = kind
    }

    /// Inclusive containment: `NSEvent.mouseLocation` can sit exactly on the far edge
    /// (`x == frame.maxX` at the right edge), which `CGRect.contains` excludes.
    public func contains(_ p: CGPoint) -> Bool {
        p.x >= rect.minX && p.x <= rect.maxX && p.y >= rect.minY && p.y <= rect.maxY
    }
}

/// The native Dock's footprint on one edge of one display.
public struct NativeDockFootprint: Sendable, Hashable {
    public let edge: ScreenEdge
    /// Span along the edge axis (global).
    public let span: Interval
    public let thickness: CGFloat
    public let autohide: Bool

    public init(edge: ScreenEdge, span: Interval, thickness: CGFloat, autohide: Bool) {
        self.edge = edge
        self.span = span
        self.thickness = thickness
        self.autohide = autohide
    }
}

/// Everything zones depend on, so equality means "no rebuild".
public struct EdgeEnvironment: Sendable, Hashable {
    public let layout: DisplayLayout
    public let display: DisplayIdentity
    public let edge: ScreenEdge
    /// Capsule extent along the edge axis, in global coordinates.
    public let contentSpan: Interval?
    public let nativeDock: NativeDockFootprint?
    public let hotCorners: HotCornerMask
    /// Top edge only: status-item rects on this display (AppKit global).
    public let statusItemRects: [CGRect]

    public init(
        layout: DisplayLayout, display: DisplayIdentity, edge: ScreenEdge, contentSpan: Interval?,
        nativeDock: NativeDockFootprint? = nil, hotCorners: HotCornerMask = .all, statusItemRects: [CGRect] = []
    ) {
        self.layout = layout
        self.display = display
        self.edge = edge
        self.contentSpan = contentSpan
        self.nativeDock = nativeDock
        self.hotCorners = hotCorners
        self.statusItemRects = statusItemRects
    }
}

public enum EdgeGeometry {
    /// Builds the hot zones for one dock (architecture §6.4, system-design §5.2). Run on
    /// configuration or display change only, never per sample.
    public static func zones(_ env: EdgeEnvironment, _ p: TriggerParameters) -> [HotZone] {
        guard let display = env.layout.display(env.display) else { return [] }
        let edge = env.edge
        let line = edge.line(of: display.frame)

        var span = IntervalSet(line)
        if p.spanMode == .content, let content = env.contentSpan {
            span = span.intersection(IntervalSet(Interval(content.lower - p.spanPadding, content.upper + p.spanPadding)))
        }

        let (lowerCorner, upperCorner) = edge.corners
        let lowerCut = env.hotCorners.contains(lowerCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        let upperCut = env.hotCorners.contains(upperCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        span = span
            .subtracting(Interval(line.lower, line.lower + lowerCut))
            .subtracting(Interval(line.upper - upperCut, line.upper))

        switch edge {
        case .left, .right:
            span = span.subtracting(Interval(line.upper - display.menuBarHeight, line.upper))
        case .top:
            if let notch = display.notch { span = span.subtracting(Interval(notch.minX, notch.maxX)) }
            for item in env.statusItemRects { span = span.subtracting(Interval(item.minX, item.maxX)) }
        case .bottom:
            break
        }

        if let dock = env.nativeDock, dock.edge == edge {
            span = span.subtracting(dock.span)
        }

        let neighbours = IntervalSet(sharedSegments(of: display, edge: edge, in: env.layout))
        let wall = span.subtracting(neighbours)
        let shared = p.sharedPolicy == .wallOnly ? IntervalSet() : span.intersection(neighbours)

        var zones: [HotZone] = []
        for segment in wall.intervals {
            zones.append(HotZone(id: "z-\(zones.count)",
                                 rect: edge.strip(of: display.frame, along: segment, thickness: p.thickness),
                                 kind: .wall))
        }
        for segment in shared.intervals {
            zones.append(HotZone(id: "z-\(zones.count)",
                                 rect: edge.strip(of: display.frame, along: segment, thickness: p.sharedBand),
                                 kind: .shared))
        }
        return zones
    }

    /// Parts of `display`'s edge that touch another display within 1 pt, along the edge axis.
    public static func sharedSegments(of display: DisplaySnapshot, edge: ScreenEdge,
                                      in layout: DisplayLayout) -> [Interval] {
        let d = display.frame
        var shared = IntervalSet()
        for other in layout.displays where other.identity != display.identity {
            let n = other.frame
            let touches = switch edge {
            case .left: abs(n.maxX - d.minX) <= 1
            case .right: abs(n.minX - d.maxX) <= 1
            case .bottom: abs(n.maxY - d.minY) <= 1
            case .top: abs(n.minY - d.maxY) <= 1
            }
            if touches { shared = shared.union(IntervalSet(edge.line(of: n))) }
        }
        return shared.intersection(IntervalSet(edge.line(of: d))).intervals
    }

    /// The unthrottled sampling region: zones and capsule, outset by `band`.
    public static func nearRegion(zones: [HotZone], capsule: CGRect?, band: CGFloat = 96) -> CGRect {
        var rect = zones.reduce(CGRect.null) { $0.union($1.rect) }
        if let capsule { rect = rect.union(capsule) }
        return rect.isNull ? .null : rect.insetBy(dx: -band, dy: -band)
    }
}
