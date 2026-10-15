import AppKit
import DedockCore
import Diagnostics

/// The DD-933 click-through gate (architecture §6.7), in two layers:
/// 1. coarse: pass-through whenever the dock is hidden or hiding;
/// 2. fine: while interactive, `ignoresMouseEvents = !hitRegion.contains(pointer)` per sample,
///    because returning `nil` from `hitTest` drops a click instead of passing it on.
@MainActor public final class ClickThroughGate: ClickThroughGating {
    private weak var panel: NSPanel?
    private let edge: ScreenEdge
    private var interactive = false
    private var hitRegion: [CGRect] = []
    private var lastIgnores: Bool?
    /// A reorder drag keeps the panel receiving mouse events wherever the pointer goes.
    public var dragInFlight = false {
        didSet { if dragInFlight { apply(ignores: false) } else { pointerMoved(NSEvent.mouseLocation) } }
    }

    public init(panel: NSPanel, edge: ScreenEdge) {
        self.panel = panel
        self.edge = edge
        apply(ignores: true)
    }

    public func setInteractive(_ on: Bool) {
        interactive = on
        if on { pointerMoved(NSEvent.mouseLocation) } else { apply(ignores: true) }
    }

    public func updateHitRegion(_ rects: [CGRect]) {
        hitRegion = rects
        if interactive { pointerMoved(NSEvent.mouseLocation) }
    }

    public func pointerMoved(_ location: CGPoint) {
        guard interactive, !dragInFlight else { return }
        apply(ignores: !hitRegion.contains { $0.contains(location) })
    }

    /// True when a point is inside the interactive region (for the content view's `hitTest`).
    public func accepts(_ location: CGPoint) -> Bool {
        interactive && hitRegion.contains { $0.contains(location) }
    }

    private func apply(ignores: Bool) {
        guard ignores != lastIgnores else { return }
        lastIgnores = ignores
        panel?.ignoresMouseEvents = ignores
        DedockLog.event(.reveal, "gate.mouse", ["edge": edge.rawValue, "ignores": ignores])
    }
}
