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
    /// Contact counts only while ⌥ is held (the top edge's last-resort rule, REG-066).
    public let requiresOption: Bool

    public init(id: String, rect: CGRect, kind: SegmentKind, requiresOption: Bool = false) {
        self.id = id
        self.rect = rect
        self.kind = kind
        self.requiresOption = requiresOption
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

/// Which rule produced a dock's zones (logged as `zones.computed rule=`).
public enum ZoneRule: String, Sendable, Hashable {
    /// Content span (or whole edge) minus the usual exclusions.
    case primary
    /// Whole edge on either side of the native Dock (REG-065).
    case besideNativeDock
    /// Top edge: the nearest free stretch of the menu bar ≥ 80 pt (REG-066).
    case nearestFree
    /// Top edge with no free stretch: reveal only with ⌥ held on contact (REG-066).
    case optionOnly
}

/// The zones for one dock and how they were derived, counts and spans only.
public struct ZoneDerivation: Sendable, Equatable {
    public let zones: [HotZone]
    public let rule: ZoneRule
    /// The span before exclusions (content ± padding, or the whole edge).
    public let candidate: Interval?
    /// Status items subtracted (top edge).
    public let statusItems: Int
    public let notch: Bool
    /// The native Dock's span, when subtracted.
    public let nativeDock: Interval?
}

public enum EdgeGeometry {
    /// True when the native Dock shares this dock's edge: the zone then spans the whole edge
    /// minus the Dock's footprint and the corners, whatever the span mode (REG-065).
    public static func triggersBesideNativeDock(_ env: EdgeEnvironment) -> Bool {
        env.nativeDock?.edge == env.edge
    }

    /// Below this total length the top edge's primary zone is too small to find (REG-066).
    public static let minimumTopZone: CGFloat = 80

    /// Builds the hot zones for one dock (architecture §6.4, system-design §5.2). Run on
    /// configuration or display change only, never per sample.
    public static func zones(_ env: EdgeEnvironment, _ p: TriggerParameters) -> [HotZone] {
        derive(env, p).zones
    }

    /// The zones and how they were derived (`zones.computed`, so E2E can explain an empty zone).
    public static func derive(_ env: EdgeEnvironment, _ p: TriggerParameters) -> ZoneDerivation {
        guard let display = env.layout.display(env.display) else {
            return ZoneDerivation(zones: [], rule: .primary, candidate: nil, statusItems: 0, notch: false, nativeDock: nil)
        }
        let edge = env.edge
        let line = edge.line(of: display.frame)
        let besideDock = triggersBesideNativeDock(env)

        // Beside the native Dock on the same edge (shown or auto-hidden) the trigger is the whole
        // edge on either side of the Dock: content ± padding usually lies under the Dock and left
        // no zone at all (REG-065). Derived here, never stored; the spanMode setting is untouched.
        var candidate = line
        if p.spanMode == .content, !besideDock, let content = env.contentSpan {
            candidate = Interval(max(line.lower, content.lower - p.spanPadding), min(line.upper, content.upper + p.spanPadding))
        }

        let (lowerCorner, upperCorner) = edge.corners
        let lowerCut = env.hotCorners.contains(lowerCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        let upperCut = env.hotCorners.contains(upperCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        // Everything on this edge that must never trigger: corners, the menu-bar band on side
        // edges, the notch and status items on the top edge, the native Dock's span.
        var blocked = IntervalSet([Interval(line.lower, line.lower + lowerCut), Interval(line.upper - upperCut, line.upper)])
        switch edge {
        case .left, .right:
            blocked = blocked.union(IntervalSet(Interval(line.upper - display.menuBarHeight, line.upper)))
        case .top:
            if let notch = display.notch { blocked = blocked.union(IntervalSet(Interval(notch.minX, notch.maxX))) }
            for item in env.statusItemRects { blocked = blocked.union(IntervalSet(Interval(item.minX, item.maxX))) }
        case .bottom:
            break
        }
        let dockSpan = besideDock ? env.nativeDock?.span : nil
        if let dockSpan { blocked = blocked.union(IntervalSet(dockSpan)) }

        var span = IntervalSet(candidate).subtracting(blocked)
        var rule: ZoneRule = besideDock ? .besideNativeDock : .primary
        var requiresOption = false
        if edge == .top, span.totalLength < minimumTopZone {
            // Status items cover the dock's span: the nearest free stretch of the menu bar of at
            // least 80 pt, closest to the dock's centre; with none, ⌥ on contact (e9's top rule).
            let centre = candidate.midpoint
            let free = IntervalSet(line).subtracting(blocked).intervals.filter { $0.length >= minimumTopZone }
            if let nearest = free.min(by: { distance($0, centre) < distance($1, centre) }) {
                span = IntervalSet(nearest)
                rule = .nearestFree
            } else {
                span = IntervalSet(candidate).subtracting(IntervalSet([
                    Interval(line.lower, line.lower + lowerCut), Interval(line.upper - upperCut, line.upper),
                ]))
                rule = .optionOnly
                requiresOption = true
            }
        }

        let neighbours = IntervalSet(sharedSegments(of: display, edge: edge, in: env.layout))
        let wall = span.subtracting(neighbours)
        let shared = p.sharedPolicy == .wallOnly ? IntervalSet() : span.intersection(neighbours)

        var zones: [HotZone] = []
        for segment in wall.intervals {
            zones.append(HotZone(id: "z-\(zones.count)",
                                 rect: edge.strip(of: display.frame, along: segment, thickness: p.thickness),
                                 kind: .wall, requiresOption: requiresOption))
        }
        for segment in shared.intervals {
            zones.append(HotZone(id: "z-\(zones.count)",
                                 rect: edge.strip(of: display.frame, along: segment, thickness: p.sharedBand),
                                 kind: .shared, requiresOption: requiresOption))
        }
        return ZoneDerivation(zones: zones, rule: rule, candidate: candidate,
                              statusItems: edge == .top ? env.statusItemRects.count : 0,
                              notch: edge == .top && display.notch != nil, nativeDock: dockSpan)
    }

    /// Distance from `x` to the interval (0 inside it).
    private static func distance(_ i: Interval, _ x: CGFloat) -> CGFloat {
        x < i.lower ? i.lower - x : (x > i.upper ? x - i.upper : 0)
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
