import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif
import DedockCore

/// Turns pointer samples into reveal events for one dock (architecture §6.4, system-design §5.3).
///
/// It reports changes (zone entered or left, inside or outside the dock, button held) plus
/// push-through, shared-band speed and crossing signals. What they mean per phase is the
/// machine's job. No clock, no references; the per-sample path does not allocate.
public struct TriggerEvaluator: Sendable {
    public var parameters: TriggerParameters

    private var currentZone: HotZone?
    private var inside = false
    private var buttonHeld = false
    private var pushAccumulated: CGFloat = 0
    private var pushFired = false
    private var bandEnteredAt: Duration?
    /// Ring of recent samples in a shared band, for the speed window.
    private var recent: [(time: Duration, point: CGPoint)] = []
    /// The reveal corridor (REG-067): where the pointer entered the zone, and the convex hull
    /// of that entry segment and the capsule ± hysteresis. On the top edge (and beside the
    /// native Dock) the capsule does not touch its zone, so the path between them counts as
    /// inside until the pointer first reaches the capsule.
    private var entry: (point: CGPoint, zone: CGRect)?
    private var corridor: [CGPoint] = []
    private var corridorCapsule: CGRect?

    /// Half the entry segment's length along the edge.
    public static let corridorHalfWidth: CGFloat = 24

    public init(parameters: TriggerParameters = .init()) {
        self.parameters = parameters
        recent.reserveCapacity(8)
    }

    /// The accumulated push toward the edge since the current zone was entered (for `edge.push`).
    public var accumulatedPush: CGFloat { pushAccumulated }
    public var zone: HotZone? { currentZone }

    /// - Parameters:
    ///   - zones: the dock's current zones (rebuilt elsewhere on configuration change).
    ///   - capsule: the capsule frame at its shown position, or `nil` before layout.
    ///   - onDockDisplay: whether the sample lies on the dock's display.
    public mutating func evaluate(_ s: PointerSample, zones: [HotZone], capsule: CGRect?,
                                  edge: ScreenEdge, onDockDisplay: Bool) -> [RevealEvent] {
        var events: [RevealEvent] = []

        var released = false
        if s.buttonsDown != buttonHeld {
            buttonHeld = s.buttonsDown
            released = !buttonHeld
            events.append(.buttonHeld(buttonHeld))
        }

        if !onDockDisplay, let entered = bandEnteredAt, s.timestamp - entered <= parameters.crossingGuard {
            events.append(.crossedToNeighbour)
            bandEnteredAt = nil
        }

        // A held button (window-tiling drags on macOS 15+) never arms a zone. Leaving still counts.
        var hit = zones.first { $0.contains(s.location) }
        if buttonHeld && currentZone == nil { hit = nil }
        if let z = hit, z.kind == .shared, parameters.sharedPolicy == .modifier, !s.modifiers.contains(.option) {
            hit = nil
        }
        // The top edge's last-resort zone counts only while ⌥ is held (REG-066).
        if let z = hit, z.requiresOption, !s.modifiers.contains(.option) { hit = nil }

        if hit?.id != currentZone?.id || hit?.kind != currentZone?.kind {
            if currentZone != nil { events.append(.zoneLeft) }
            if let z = hit {
                events.append(.zoneEntered(z.kind))
                entry = (s.location, z.rect)    // a fresh corridor from this entry point
                corridorCapsule = nil
                pushAccumulated = 0
                pushFired = false
                recent.removeAll(keepingCapacity: true)
                bandEnteredAt = z.kind == .shared ? s.timestamp : nil
            } else {
                bandEnteredAt = nil
            }
            currentZone = hit
        } else if released, let z = hit {
            // A press while arming disarmed the dock; releasing it still inside the zone re-arms
            // without having to leave and come back (REG-034).
            events.append(.zoneEntered(z.kind))
            pushAccumulated = 0
            pushFired = false
        }

        // The entry sample's delta is travel toward the edge, not push: count from the next one.
        let justEntered = hit != nil && events.contains(.zoneEntered(hit!.kind))
        if let z = hit {
            switch z.kind {
            case .wall:
                if let threshold = parameters.pushThrough, !pushFired, !justEntered {
                    pushAccumulated = max(0, pushAccumulated + s.push(toward: edge))
                    if pushAccumulated >= threshold {
                        pushFired = true
                        events.append(.pushThrough)
                    }
                }
            case .shared:
                if parameters.sharedPolicy == .slowDwell, isMovingFast(s) { events.append(.sharedSpeedExceeded) }
            }
        }

        let inCapsule = capsule.map { Self.contains($0.insetBy(dx: -parameters.hysteresis, dy: -parameters.hysteresis), s.location) } ?? false
        if inCapsule { dropCorridor() }          // visited: from now on zone ∪ capsule only
        let nowInside = hit != nil || inCapsule || inCorridor(s.location, capsule: capsule, edge: edge)
        if nowInside != inside {
            inside = nowInside
            events.append(.pointerInside(nowInside))
        }
        return events
    }

    /// Ends the corridor (the dock is hidden again, or the capsule was reached). An explicit
    /// reveal never gets one: it already waits for the first visit (S-13).
    public mutating func dropCorridor() {
        entry = nil
        corridor.removeAll(keepingCapacity: true)
        corridorCapsule = nil
    }

    /// Whether `p` lies in the corridor; the hull is rebuilt only when the capsule's frame
    /// changes (a relayout), never per sample.
    private mutating func inCorridor(_ p: CGPoint, capsule: CGRect?, edge: ScreenEdge) -> Bool {
        guard let entry, let capsule else { return false }
        if corridorCapsule != capsule {
            corridorCapsule = capsule
            corridor = Self.corridorHull(entry: entry.point, zone: entry.zone, capsule: capsule,
                                         hysteresis: parameters.hysteresis, edge: edge)
        }
        return Self.convexContains(corridor, p)
    }

    /// The convex hull of the entry segment (entry ± `corridorHalfWidth` along the edge,
    /// clamped to the zone, at the zone's full depth) and the capsule outset by `hysteresis`.
    public static func corridorHull(entry e: CGPoint, zone z: CGRect, capsule: CGRect, hysteresis h: CGFloat,
                                    edge: ScreenEdge) -> [CGPoint] {
        let w = corridorHalfWidth
        let segment: CGRect = edge.isVertical
            ? CGRect(x: z.minX, y: max(z.minY, e.y - w), width: z.width, height: min(z.maxY, e.y + w) - max(z.minY, e.y - w))
            : CGRect(x: max(z.minX, e.x - w), y: z.minY, width: min(z.maxX, e.x + w) - max(z.minX, e.x - w), height: z.height)
        let c = capsule.insetBy(dx: -h, dy: -h)
        var points = [segment, c].flatMap { r in
            [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
        }
        // Andrew's monotone chain, counter-clockwise.
        points.sort { ($0.x, $0.y) < ($1.x, $1.y) }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in points {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in points.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// Point in a counter-clockwise convex polygon, edges included.
    static func convexContains(_ hull: [CGPoint], _ p: CGPoint) -> Bool {
        guard hull.count >= 3 else { return false }
        for i in hull.indices {
            let a = hull[i], b = hull[(i + 1) % hull.count]
            if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0 { return false }
        }
        return true
    }

    /// Forget membership (after a geometry rebuild the next sample re-derives it).
    /// Returns the events that clearing implies (`zoneLeft`, `pointerInside(false)`), so the
    /// machine never keeps a stale "inside" (PR #7 review item 3). The next sample re-derives
    /// membership against the new zones.
    @discardableResult
    public mutating func reset() -> [RevealEvent] {
        var events: [RevealEvent] = []
        if currentZone != nil { events.append(.zoneLeft) }
        if inside { events.append(.pointerInside(false)) }
        currentZone = nil
        inside = false
        pushAccumulated = 0
        pushFired = false
        bandEnteredAt = nil
        recent.removeAll(keepingCapacity: true)
        return events
    }

    /// Speed from position and timestamp across the trailing window. Global monitors receive
    /// moves coalesced to the display rate (measured by the E2E lane: 60 Hz), so a 50 ms window
    /// holds about three samples; per-event deltas would be wrong.
    private mutating func isMovingFast(_ s: PointerSample) -> Bool {
        let window = parameters.sharedSpeedWindow
        recent.removeAll { s.timestamp - $0.time > window }
        defer {
            if recent.count == 8 { recent.removeFirst() }
            recent.append((s.timestamp, s.location))
        }
        guard let oldest = recent.first else { return false }
        let dt = (s.timestamp - oldest.time).seconds
        guard dt > 0 else { return false }
        let distance = hypot(s.location.x - oldest.point.x, s.location.y - oldest.point.y)
        return distance / dt > parameters.sharedMaxSpeed
    }

    static func contains(_ r: CGRect, _ p: CGPoint) -> Bool {
        p.x >= r.minX && p.x <= r.maxX && p.y >= r.minY && p.y <= r.maxY
    }
}
