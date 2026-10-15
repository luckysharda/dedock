import AppKit
import DedockCore
import DesignSystem
import Diagnostics
import SwiftUI

/// The Edge Dock window: placed once at its fully shown frame; only the content slides.
@MainActor public final class EdgeDockPanel: FloatingPanel {
    /// Above normal windows, `.floating`, the native Dock (20) and the system Apps panel (23);
    /// below menu-bar menus and pop-up menus (101). One constant, so it can move if the
    /// overlay check (DD-901 item 5) says so.
    public static let restingLevel = NSWindow.Level.mainMenu

    public let root: DockRootView

    public init(frame: CGRect, model: DockViewModel) {
        root = DockRootView(frame: CGRect(origin: .zero, size: frame.size), model: model)
        super.init(contentRect: frame)
        level = Self.restingLevel
        contentView = root
        ignoresMouseEvents = true
    }

    /// Move to a new fixed frame after a relayout (never during a slide).
    public func place(_ frame: CGRect) {
        setFrame(frame, display: false)
    }
}

/// Root view: owns the sliding container and turns clicks on tiles into actions.
@MainActor public final class DockRootView: NSView {
    /// The layer-backed view whose `sublayerTransform` slides (or whose opacity fades).
    public let container: NSView
    let model: DockViewModel
    /// The Dark Glass capsule, under the tiles and inside the sliding container.
    let capsule = CapsuleView(frame: .zero)
    private let hosting: NSHostingView<DockContentView>
    /// Where point-based accessibility hit tests go: the SwiftUI content, which owns the tile
    /// elements. A seam for the REG-054 guard.
    var accessibilityContent: NSView
    /// Screen-space hit test, supplied by the gate.
    var accepts: ((CGPoint) -> Bool)?
    var onTileClick: ((TileID) -> Void)?
    var onTileRightClick: ((TileID, NSEvent) -> Void)?
    /// Reorder drag (DD-975), in screen coordinates.
    var onDragBegan: ((TileID, CGPoint) -> Void)?
    var onDragMoved: ((CGPoint) -> Void)?
    var onDragEnded: ((CGPoint) -> Void)?
    /// Whether a plain (no ⌘) drag reorders ("Drag to rearrange").
    var plainDragReorders: () -> Bool = { false }

    private var downPoint: CGPoint?
    private var downWithCommand = false
    private var dragging = false
    private static let dragThreshold: CGFloat = 3

    init(frame: CGRect, model: DockViewModel) {
        self.model = model
        container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        hosting = NSHostingView(rootView: DockContentView(model: model))
        accessibilityContent = hosting
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        container.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(capsule)
        container.addSubview(hosting)
        addSubview(container)
    }

    /// Re-applies the capsule's frame and material from the model (after layout or token changes).
    func applyCapsule() {
        capsule.apply(frame: model.capsule, tokens: model.tokens)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard let window else { return nil }
        let screen = window.convertPoint(toScreen: convert(point, to: nil))
        return (accepts?(screen) ?? false) ? self : nil
    }

    /// `hitTest` returns this view so it can route clicks, and AppKit's default accessibility hit
    /// test follows it, so VoiceOver mouse-follow and hover speech found the window instead of
    /// the tile buttons (REG-054). Point-based assistive hit tests go to the SwiftUI content.
    override public func accessibilityHitTest(_ point: NSPoint) -> Any? {
        accessibilityContent.accessibilityHitTest(point) ?? super.accessibilityHitTest(point)
    }

    override public func mouseDown(with event: NSEvent) {
        model.pressedTile = tile(at: event)
        DedockLog.debug(.tiles, "mouse.down", ["tile": model.pressedTile?.rawValue ?? "-", "cmd": event.modifierFlags.contains(.command)])
        downPoint = screenPoint(event)
        downWithCommand = event.modifierFlags.contains(.command)
        dragging = false
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let start = downPoint, let id = model.pressedTile, model.tiles.first(where: { $0.id == id })?.kind != .separator
        else { return }
        let p = screenPoint(event)
        if !dragging {
            guard downWithCommand || plainDragReorders(),
                  hypot(p.x - start.x, p.y - start.y) >= Self.dragThreshold else { return }
            dragging = true
            DedockLog.debug(.tiles, "mouse.dragBegan", ["tile": id.rawValue])
            onDragBegan?(id, p)
        }
        onDragMoved?(p)
    }

    override public func mouseUp(with event: NSEvent) {
        defer {
            model.pressedTile = nil
            downPoint = nil
            dragging = false
        }
        if dragging {
            onDragEnded?(screenPoint(event))
            return
        }
        guard let id = tile(at: event), id == model.pressedTile else { return }
        onTileClick?(id)
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override public func rightMouseDown(with event: NSEvent) {
        guard let id = tile(at: event) else { return }
        onTileRightClick?(id, event)
    }

    private func tile(at event: NSEvent) -> TileID? {
        guard let window else { return nil }
        let screen = window.convertPoint(toScreen: event.locationInWindow)
        return model.tile(atScreen: screen)
    }
}
