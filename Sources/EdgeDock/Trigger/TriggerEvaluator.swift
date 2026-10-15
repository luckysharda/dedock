import CoreGraphics
import DedockCore
import Foundation

/// Turns pointer samples into `RevealMachine` events for one dock instance
/// (system-design §5.3).
///
/// It reports *changes* (zone entered or left, pointer region changed) plus push-through and
/// shared-band speed signals. Deciding what they mean in each state is the machine's job.
/// The per-sample path compares against a few cached rects and does not allocate.
public struct TriggerEvaluator: Sendable {
    public private(set) var zones: [HotZone]
    /// The dock's fully shown frame (AppKit global). `nil` until the dock is laid out.
    public private(set) var dockFrame: CGRect?
    public var parameters: EdgeTriggerParameters

    private var currentZone: HotZone?
    private var region: RevealMachine.PointerRegion = .away
    private var pushAccumulated: CGFloat = 0
    private var pushFired = false
    /// Recent samples in the current shared band, for the speed check.
    private var recent: [(time: TimeInterval, point: CGPoint)] = []

    public init(zones: [HotZone] = [], dockFrame: CGRect? = nil, parameters: EdgeTriggerParameters = .init()) {
        self.zones = zones
        self.dockFrame = dockFrame
        self.parameters = parameters
        recent.reserveCapacity(16)
    }

    /// Replace the zones and dock frame (on configuration or display change). Membership is
    /// re-derived on the next sample.
    public mutating func update(zones: [HotZone], dockFrame: CGRect?) {
        self.zones = zones
        self.dockFrame = dockFrame
    }

    public mutating func evaluate(_ sample: PointerSample) -> [RevealMachine.Event] {
        var events: [RevealMachine.Event] = []
        let point = sample.location

        // A held button (window-tiling drags on macOS 15+, text selection) never arms a zone.
        // Content-drag reveal (DD-932) is a separate path.
        let zone = sample.buttonsDown && currentZone == nil ? nil : zones.first { $0.contains(point) }

        if zone != currentZone {
            if currentZone != nil { events.append(.leftZone) }
            if let zone {
                events.append(.enteredZone(zone.kind))
                pushAccumulated = 0
                pushFired = false
                recent.removeAll(keepingCapacity: true)
            }
            currentZone = zone
        }

        if let zone {
            switch zone.kind {
            case .wall:
                if let threshold = parameters.pushThroughDistance, !pushFired {
                    pushAccumulated = max(0, pushAccumulated + sample.push(toward: zone.edge))
                    if pushAccumulated >= threshold {
                        pushFired = true
                        events.append(.pushThrough)
                    }
                }
            case .shared:
                if isMovingFast(sample) { events.append(.restartDwell) }
            }
        }

        let newRegion = classify(point, inZone: zone != nil)
        if newRegion != region {
            region = newRegion
            events.append(.pointer(newRegion))
        }
        return events
    }

    private func classify(_ point: CGPoint, inZone: Bool) -> RevealMachine.PointerRegion {
        if inZone { return .onDock }
        guard let frame = dockFrame else { return .away }
        if Self.containsInclusive(frame, point) { return .onDock }
        let outset = frame.insetBy(dx: -parameters.hideHysteresis, dy: -parameters.hideHysteresis)
        return Self.containsInclusive(outset, point) ? .nearDock : .away
    }

    private mutating func isMovingFast(_ sample: PointerSample) -> Bool {
        let window = parameters.sharedSpeedWindow
        recent.removeAll { sample.timestamp - $0.time > window }
        defer {
            if recent.count == 16 { recent.removeFirst() }
            recent.append((sample.timestamp, sample.location))
        }
        guard let oldest = recent.first else { return false }
        let dt = sample.timestamp - oldest.time
        guard dt > 0 else { return false }
        let distance = hypot(sample.location.x - oldest.point.x, sample.location.y - oldest.point.y)
        return distance / dt > parameters.sharedMaxSpeed
    }

    static func containsInclusive(_ rect: CGRect, _ p: CGPoint) -> Bool {
        p.x >= rect.minX && p.x <= rect.maxX && p.y >= rect.minY && p.y <= rect.maxY
    }
}
