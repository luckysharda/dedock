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

        if s.buttonsDown != buttonHeld {
            buttonHeld = s.buttonsDown
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

        if hit?.id != currentZone?.id || hit?.kind != currentZone?.kind {
            if currentZone != nil { events.append(.zoneLeft) }
            if let z = hit {
                events.append(.zoneEntered(z.kind))
                pushAccumulated = 0
                pushFired = false
                recent.removeAll(keepingCapacity: true)
                bandEnteredAt = z.kind == .shared ? s.timestamp : nil
            } else {
                bandEnteredAt = nil
            }
            currentZone = hit
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

        let nowInside = hit != nil || capsule.map { Self.contains($0.insetBy(dx: -parameters.hysteresis, dy: -parameters.hysteresis), s.location) } ?? false
        if nowInside != inside {
            inside = nowInside
            events.append(.pointerInside(nowInside))
        }
        return events
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
