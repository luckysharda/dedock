import AppKit
import DedockCore

/// NSEvent global + local mouse monitors. Global monitors for mouse events need no TCC grant;
/// they are passive, so they never swallow a click on the edge pixels (architecture §6.3).
@MainActor public final class NSEventPointerSource: PointerEventSource {
    /// `eventSourceUserData` the E2E pointer driver stamps on its events.
    public nonisolated static let syntheticTag: Int64 = 0xDED0C

    private static let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public func install(_ handler: @escaping @MainActor (PointerSample) -> Void) {
        uninstall()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { event in
            let sample = Self.sample(from: event)
            MainActor.assumeIsolated { handler(sample) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { event in
            let sample = Self.sample(from: event)
            MainActor.assumeIsolated { handler(sample) }
            return event
        }
    }

    public func uninstall() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    public var currentLocation: CGPoint { NSEvent.mouseLocation }
    public var buttonsDown: Bool { NSEvent.pressedMouseButtons != 0 }
    public var currentModifiers: ModifierSet { Self.modifiers(NSEvent.modifierFlags) }

    nonisolated static func sample(from event: NSEvent) -> PointerSample {
        var synthetic = false
        #if DEBUG
        synthetic = event.cgEvent?.getIntegerValueField(.eventSourceUserData) == syntheticTag
        #endif
        return PointerSample(
            // `NSEvent.mouseLocation`, not `event.locationInWindow`: global monitor events carry
            // no window, and the class property is in AppKit global coordinates.
            location: NSEvent.mouseLocation,
            // NSEvent.deltaY is positive when moving down; flip once to AppKit y-up.
            delta: CGVector(dx: event.deltaX, dy: -event.deltaY),
            timestamp: .nanoseconds(Int64((event.timestamp * 1e9).rounded())),
            buttonsDown: NSEvent.pressedMouseButtons != 0,
            modifiers: modifiers(event.modifierFlags),
            source: .monitor,
            isSynthetic: synthetic)
    }

    nonisolated static func modifiers(_ flags: NSEvent.ModifierFlags) -> ModifierSet {
        var set: ModifierSet = []
        if flags.contains(.option) { set.insert(.option) }
        if flags.contains(.command) { set.insert(.command) }
        if flags.contains(.control) { set.insert(.control) }
        if flags.contains(.shift) { set.insert(.shift) }
        return set
    }
}
