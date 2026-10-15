import CoreGraphics
import DedockCore

/// Builds the hot zones for one dock instance (system-design §5.2).
///
/// Run on configuration or display change only, never per pointer sample.
public struct ZoneBuilder: Sendable {
    public var parameters: EdgeTriggerParameters

    public init(parameters: EdgeTriggerParameters = .init()) {
        self.parameters = parameters
    }

    /// - Parameters:
    ///   - edge: The dock's edge.
    ///   - display: The display the dock lives on.
    ///   - screens: Every connected display (including `display`), used to find shared edges.
    ///   - contentSpan: The dock's content extent along the edge axis (y for side docks, x for
    ///     the bottom dock), in global coordinates. Ignored in `.wholeEdge` mode; when `nil`
    ///     the whole edge is used.
    ///   - hotCorners: Corners that have a Hot Corner action. Unknown state should pass all
    ///     corners, which keeps the larger exclusion.
    ///   - nativeDockFootprint: The native Dock's span along this edge of this display, if it
    ///     sits here (system-design §5.5: the zone excludes the native Dock's span).
    public func zones(
        edge: ScreenEdge,
        display: ScreenInfo,
        screens: [ScreenInfo],
        contentSpan: Interval?,
        hotCorners: Set<ScreenCorner> = Set(ScreenCorner.allCases),
        nativeDockFootprint: Interval? = nil
    ) -> [HotZone] {
        let p = parameters
        let line = Self.edgeLine(edge, of: display.frame)

        var span = IntervalSet(line)
        if p.spanMode == .dockLength, let content = contentSpan {
            let padded = Interval(content.lower - p.spanPadding, content.upper + p.spanPadding)
            span = span.intersection(IntervalSet(padded))
        }

        let (lowerCorner, upperCorner) = edge.corners
        let lowerCut = hotCorners.contains(lowerCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        let upperCut = hotCorners.contains(upperCorner) ? p.cornerExclusion : p.cornerExclusionWithoutHotCorner
        span = span
            .subtracting(Interval(line.lower, line.lower + lowerCut))
            .subtracting(Interval(line.upper - upperCut, line.upper))

        if edge.isVertical {
            span = span.subtracting(Interval(line.upper - display.menuBarHeight, line.upper))
        }

        let neighbours = Self.sharedSegments(edge: edge, display: display, screens: screens)
        var shared = span.intersection(neighbours)
        var wall = span.subtracting(neighbours)

        if let dock = nativeDockFootprint {
            wall = wall.subtracting(dock)
            shared = shared.subtracting(dock)
        }

        let wallZones = wall.intervals.map {
            HotZone(edge: edge, displayID: display.id,
                    rect: Self.rect(edge, frame: display.frame, along: $0, thickness: p.triggerThickness),
                    kind: .wall)
        }
        let sharedZones = shared.intervals.map {
            HotZone(edge: edge, displayID: display.id,
                    rect: Self.rect(edge, frame: display.frame, along: $0, thickness: p.sharedBandThickness),
                    kind: .shared)
        }
        return wallZones + sharedZones
    }

    /// The full edge of `frame` on `edge`, as an interval along the edge axis.
    public static func edgeLine(_ edge: ScreenEdge, of frame: CGRect) -> Interval {
        edge.isVertical ? Interval(frame.minY, frame.maxY) : Interval(frame.minX, frame.maxX)
    }

    /// Parts of `display`'s edge that touch another display (within 1 pt), along the edge axis.
    public static func sharedSegments(edge: ScreenEdge, display: ScreenInfo, screens: [ScreenInfo]) -> IntervalSet {
        let d = display.frame
        var shared = IntervalSet()
        for other in screens where other.id != display.id {
            let n = other.frame
            let touches: Bool
            switch edge {
            case .left: touches = abs(n.maxX - d.minX) <= 1
            case .right: touches = abs(n.minX - d.maxX) <= 1
            case .bottom: touches = abs(n.maxY - d.minY) <= 1
            }
            guard touches else { continue }
            shared = shared.union(IntervalSet(edgeLine(edge, of: n)))
        }
        return shared.intersection(IntervalSet(edgeLine(edge, of: d)))
    }

    /// The strip of `thickness` inward from `edge`, covering `along` on the edge axis.
    static func rect(_ edge: ScreenEdge, frame: CGRect, along: Interval, thickness: CGFloat) -> CGRect {
        switch edge {
        case .left:
            CGRect(x: frame.minX, y: along.lower, width: thickness, height: along.length)
        case .right:
            CGRect(x: frame.maxX - thickness, y: along.lower, width: thickness, height: along.length)
        case .bottom:
            CGRect(x: along.lower, y: frame.minY, width: along.length, height: thickness)
        }
    }
}
