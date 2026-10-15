import AppKit
import DedockCore
import DesignSystem
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
    }

    override public func mouseUp(with event: NSEvent) {
        defer { model.pressedTile = nil }
        guard let id = tile(at: event), id == model.pressedTile else { return }
        onTileClick?(id)
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
