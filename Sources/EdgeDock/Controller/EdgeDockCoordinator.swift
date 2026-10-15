import AppKit
import DedockCore
import DesignSystem
import Diagnostics
import EventTapKit
import SettingsStore
import SwiftUI

/// Everything outside the dock that its geometry depends on.
public struct DockSurroundings: Sendable, Equatable {
    public var layout: DisplayLayout
    public var nativeDock: NativeDockPreferences
    public var reduceMotion: Bool
    /// Menu-bar status-item rects per display (AppKit global), from `FullscreenProbe` (REG-044).
    public var statusItems: [DisplayIdentity: [CGRect]] = [:]
    /// Displays showing a full-screen window, from `FullscreenProbe` (REG-045).
    public var fullscreen: [DisplayIdentity: Bool] = [:]
}

/// One enabled dock instance: layout, zones, panel, animator, gate and reveal controller
/// (architecture §6.1). Receives every pointer sample from the manager.
@MainActor public final class EdgeDockCoordinator: PointerSampleSink {
    public let id: DockID
    public private(set) var config: DockConfig
    public private(set) var display: DisplaySnapshot
    public private(set) var layout: DockLayout
    public private(set) var zones: [HotZone] = []
    public private(set) var tiles: [TileModel] = []

    public let model: DockViewModel
    let panel: EdgeDockPanel
    let animator: SlideAnimator
    let gate: ClickThroughGate
    public let controller: EdgeRevealController
    private var evaluator: TriggerEvaluator
    private let running: RunningAppsMonitor
    private let env = DedockEnvironment.current
    private var lastPush: CGFloat = 0
    private var environmentKey: EdgeEnvironment?
    /// Trigger parameters the current zones were built with.
    private var zoneParameters: TriggerParameters?
    private var reduceMotion: Bool

    /// Called when geometry or state changed (GEOM output, near regions).
    var onChange: (() -> Void)?
    /// Called once per zone entry that arms (for `launch.edgeReady`).
    var onArmed: (() -> Void)?
    /// Called when a tile asks to be removed (context menu).
    var onRemoveTile: ((TileID) -> Void)?
    /// Called with the new tile order after a reorder drop (DD-975).
    var onReorder: (([TileID]) -> Void)?
    /// Called with dropped app/folder URLs and the insertion index (DD-975 item 4).
    var onPin: (([URL], Int) -> Void)?

    /// A reorder drag: layout and order frozen at drag start, so live changes cannot corrupt it.
    private struct ReorderSession {
        let tile: TileID
        let frozen: DockLayout
        let order: [TileID]
        var index: Int
    }
    private var reorder: ReorderSession?
    /// The tile specs the current layout was built from.
    private var specs: [TileSpec] = []

    init(config: DockConfig, profile: Profile?, display: DisplaySnapshot, surroundings: DockSurroundings,
         running: RunningAppsMonitor, icons: IconCache, clock: any Clock<Duration>) {
        id = config.id
        self.config = config
        self.display = display
        self.running = running
        evaluator = TriggerEvaluator(parameters: config.triggerParameters(nativeDockEdge: surroundings.nativeDock.orientation))
        reduceMotion = surroundings.reduceMotion

        let tokens = config.tokens
        model = DockViewModel(tokens: tokens, icons: icons)
        tiles = Self.tileModels(profile, running: running)
        layout = Self.layout(config, tiles: profile?.items ?? [], display: display, surroundings: surroundings)
        specs = (profile?.items ?? []).map(\.tileSpec)

        panel = EdgeDockPanel(frame: layout.panelFrame, model: model)
        animator = SlideAnimator(container: panel.root.container, edge: config.edge,
                                 hiddenOffset: layout.hiddenOffset, reduceMotion: surroundings.reduceMotion)
        gate = ClickThroughGate(panel: panel, edge: config.edge)
        controller = EdgeRevealController(config: config.revealConfig(reduceMotion: surroundings.reduceMotion),
                                          clock: clock, animator: animator, gate: gate, edge: config.edge)

        model.apply(layout: layout, tiles: tiles)
        panel.root.applyCapsule()
        rebuildZones(surroundings)
        gate.updateHitRegion(hitRegion)
        // A dock created on a full-screen display starts with the longer dwell.
        if surroundings.fullscreen[display.identity] == true { controller.send(.fullscreenChanged(true)) }

        panel.root.accepts = { [weak self] p in self?.gate.accepts(p) ?? false }
        panel.root.onTileClick = { [weak self] id in self?.click(id) }
        model.activate = { [weak self] id in self?.click(id) }   // AXPress = click (REG-040)
        panel.root.onTileRightClick = { [weak self] id, event in self?.contextMenu(for: id, event: event) }
        panel.root.onDragBegan = { [weak self] id, p in self?.beginReorder(id, at: p) }
        panel.root.onDragMoved = { [weak self] p in self?.moveReorder(to: p) }
        panel.root.onDragEnded = { [weak self] p in self?.endReorder(at: p) }
        panel.root.plainDragReorders = { [weak self] in self?.config.appearance.dragToRearrange ?? false }
        panel.root.onDropHover = { [weak self] on in
            guard let self else { return }
            self.gate.dragInFlight = on
            self.controller.send(.hold(.dragging, on))
        }
        panel.root.onDropURLs = { [weak self] urls, p in
            guard let self else { return }
            let order = self.tiles.map(\.id)
            let index = LayoutEngine.insertionIndex(for: p, in: self.layout, order: order, moving: TileID("__drop__"))
            self.onPin?(urls, index)
        }
        controller.onOrder = { [weak self] on in
            guard let self else { return }
            if on { self.panel.orderFrontRegardless() } else { self.panel.orderOut(nil) }
        }
        controller.onTransition = { [weak self] t in
            guard let self else { return }
            if case .arming = t.to { self.onArmed?() }
            if t.to == .hidden || t.to == .hiding { self.model.hoveredTile = nil }
            self.onChange?()
        }
        panel.orderFrontRegardless()
        logLayout(reason: "create")
    }

    public var phase: RevealPhase { controller.phase }
    public var capsuleFrame: CGRect { layout.capsuleFrame }

    /// Rects where the hub delivers every event unthrottled.
    public var nearRegion: CGRect { EdgeGeometry.nearRegion(zones: zones, capsule: layout.capsuleFrame) }

    private var hitRegion: [CGRect] { [layout.capsuleFrame] }

    // MARK: Updates

    /// Apply a new configuration, profile or surroundings. Re-lays out only when an input changed.
    func update(config new: DockConfig, profile: Profile?, display newDisplay: DisplaySnapshot, surroundings: DockSurroundings) {
        let oldConfig = config
        let movedDisplay = newDisplay.identity != display.identity
        config = new
        display = newDisplay
        tiles = Self.tileModels(profile, running: running)
        let newLayout = Self.layout(new, tiles: profile?.items ?? [], display: newDisplay, surroundings: surroundings)
        let newSpecs = (profile?.items ?? []).map(\.tileSpec)
        model.tokens = new.tokens
        let geometryChanged = newLayout != layout || oldConfig.edge != new.edge
        // The drag's frozen layout and order no longer match the dock (REG-048).
        if geometryChanged || newSpecs != specs { cancelReorder(reason: "relayout") }
        specs = newSpecs
        // The flag belongs to the display, not the dock: take the new display's (REG-045).
        if movedDisplay { controller.send(.fullscreenChanged(surroundings.fullscreen[newDisplay.identity] ?? false)) }
        if geometryChanged {
            layout = newLayout
            panel.place(layout.panelFrame)
            gate.updateHitRegion(hitRegion)
            logLayout(reason: "update")
        }
        // Reduce Motion switches the animator between slide and fade; update it on either change.
        if geometryChanged || reduceMotion != surroundings.reduceMotion {
            reduceMotion = surroundings.reduceMotion
            animator.update(edge: new.edge, hiddenOffset: layout.hiddenOffset, reduceMotion: reduceMotion)
        }
        model.apply(layout: layout, tiles: tiles)
        panel.root.applyCapsule()
        evaluator.parameters = new.triggerParameters(nativeDockEdge: surroundings.nativeDock.orientation)
        rebuildZones(surroundings)
        controller.reconfigure(new.revealConfig(reduceMotion: surroundings.reduceMotion))
        onChange?()
    }

    /// Running state changed: only the tile models change, never the geometry.
    func refreshRunning() {
        let changes = Self.indicatorChanges(tiles) { [running] in running.state(for: $0) }
        guard !changes.isEmpty else { return }
        for change in changes {
            tiles[change.index].running = change.state
            DedockLog.event(.tiles, "tile.indicator", ["bundle": tiles[change.index].bundleID ?? "-", "state": change.state.rawValue])
        }
        model.tiles = tiles
    }

    /// Indicator changes for the dock's own app tiles only; other running apps never appear
    /// here (and so never reach the log).
    static func indicatorChanges(_ tiles: [TileModel], state: (String?) -> TileModel.Running)
        -> [(index: Int, state: TileModel.Running)] {
        tiles.indices.compactMap { i in
            guard tiles[i].kind == .app else { return nil }
            let s = state(tiles[i].bundleID)
            return s == tiles[i].running ? nil : (i, s)
        }
    }

    func teardown() {
        controller.invalidate()
        panel.orderOut(nil)
        panel.close()
    }

    /// Rebuilds the zones even if nothing changed (E2E debug command `rebuildZones`).
    func forceRebuildZones(_ s: DockSurroundings) {
        environmentKey = nil
        rebuildZones(s)
        onChange?()
    }

    private func rebuildZones(_ s: DockSurroundings) {
        let footprint = s.nativeDock.orientation == config.edge
            ? NativeDockPreferences.footprint(prefs: s.nativeDock, display: display) : nil
        // Status items come from the probe, refreshed as they change (REG-044).
        let items = config.edge == .top ? s.statusItems[display.identity] ?? [] : []
        let env = EdgeEnvironment(layout: s.layout, display: display.identity, edge: config.edge,
                                  contentSpan: layout.contentSpan, nativeDock: footprint,
                                  hotCorners: s.nativeDock.hotCorners, statusItemRects: items)
        let parameters = config.triggerParameters(nativeDockEdge: s.nativeDock.orientation)
        guard env != environmentKey || parameters != zoneParameters else { return }
        environmentKey = env
        zoneParameters = parameters
        zones = EdgeGeometry.zones(env, parameters)
        // Tell the machine what the reset cleared; the next pointer sample re-derives it.
        controller.send(evaluator.reset())
    }

    // MARK: PointerSampleSink

    public func pointer(_ s: PointerSample) {
        let before = evaluator.zone
        let onDisplay = display.frame.insetBy(dx: -0.5, dy: -0.5).contains(s.location)
        let events = evaluator.evaluate(s, zones: zones, capsule: layout.capsuleFrame, edge: config.edge, onDockDisplay: onDisplay)
        logZoneChange(from: before, to: evaluator.zone, at: s)
        if env.e2e, case .arming = controller.phase, evaluator.accumulatedPush != lastPush {
            lastPush = evaluator.accumulatedPush
            DedockLog.debug(.edge, "edge.push", ["edge": config.edge.rawValue, "acc": DedockLog.pt(Double(lastPush))])
        }
        if env.edgeTrace {
            DedockLog.debug(.edge, "edge.trace", [
                "x": DedockLog.pt(Double(s.location.x)), "y": DedockLog.pt(Double(s.location.y)),
                "zone": evaluator.zone?.id ?? "-", "state": controller.phase.name, "src": s.isSynthetic ? "synthetic" : "real",
            ])
        }
        controller.send(events)
        gate.pointerMoved(s.location)
        updateHover(s.location)
    }

    private func updateHover(_ p: CGPoint) {
        let hover: TileID? = switch controller.phase {
        case .shown, .armingHide: model.tile(atScreen: p)
        default: nil
        }
        if hover != model.hoveredTile { model.hoveredTile = hover }
    }

    private func logZoneChange(from old: HotZone?, to new: HotZone?, at s: PointerSample) {
        guard old?.id != new?.id else { return }
        let x = DedockLog.pt(Double(s.location.x)), y = DedockLog.pt(Double(s.location.y))
        if let old { DedockLog.event(.edge, "edge.zoneExit", ["edge": config.edge.rawValue, "zone": old.id, "x": x, "y": y]) }
        if let new {
            lastPush = 0
            DedockLog.event(.edge, "edge.zoneEnter", ["edge": config.edge.rawValue, "zone": new.id, "kind": new.kind.rawValue, "x": x, "y": y])
        }
    }

    // MARK: Tiles

    private func click(_ id: TileID) {
        guard let tile = tiles.first(where: { $0.id == id }) else { return }
        TileActions.activate(tile)
        // A launch from a tile hides the dock with the re-arm cooldown (DD-912 / T6 item 7).
        if config.mode == .reveal { controller.send(.command(.hide(explicit: true))) }
    }

    private func contextMenu(for id: TileID, event: NSEvent) {
        guard let tile = tiles.first(where: { $0.id == id }) else { return }
        // "Open" takes the same path as a click: explicit hide and re-arm cooldown (REG-033).
        let menu = TileMenu(tile: tile, open: { [weak self] in self?.click(id) },
                            remove: { [weak self] in self?.onRemoveTile?(id) })
        controller.send(.hold(.menuOpen, true))
        menu.popUp(from: panel.root, event: event)
        controller.send(.hold(.menuOpen, false))
    }

    // MARK: Reorder (DD-975, T15)

    private func beginReorder(_ id: TileID, at p: CGPoint) {
        let order = tiles.map(\.id)
        guard let index = order.firstIndex(of: id) else { return }
        reorder = ReorderSession(tile: id, frozen: layout, order: order, index: index)
        gate.dragInFlight = true
        controller.send(.hold(.dragging, true))
        model.hoveredTile = nil
        model.draggedTile = id
        moveReorder(to: p)
    }

    private func moveReorder(to p: CGPoint) {
        guard var session = reorder, let frame = session.frozen.tileFrames[session.tile] else { return }
        // The dragged tile follows the pointer along the dock axis, clamped to the capsule.
        let o = layout.panelFrame.origin
        let c = session.frozen.capsuleFrame
        let centre: CGPoint = config.edge.isVertical
            ? CGPoint(x: frame.midX, y: min(c.maxY - frame.height / 2, max(c.minY + frame.height / 2, p.y)))
            : CGPoint(x: min(c.maxX - frame.width / 2, max(c.minX + frame.width / 2, p.x)), y: frame.midY)
        model.dragCentre = CGPoint(x: centre.x - o.x, y: centre.y - o.y)

        let index = LayoutEngine.insertionIndex(for: p, in: session.frozen, order: session.order, moving: session.tile)
        guard index != session.index else { return }
        session.index = index
        reorder = session
        let preview = Self.reordered(session.order, moving: session.tile, to: index)
        let byID = Dictionary(specs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let previewSpecs = preview.compactMap { byID[$0] }
        let previewLayout = LayoutEngine.layout(previewSpecs, PlacementInput(display: display, edge: config.edge, alignment: config.dockAlignment,
                                                                      nativeDockInset: layoutInset), config.tokens.metrics)
        let frames = previewLayout.tileFrames.mapValues { $0.offsetBy(dx: -o.x, dy: -o.y) }
        // Neighbours part with a 0.2 s critically damped spring; instant under Reduce Motion.
        if reduceMotion {
            model.tileFrames = frames
        } else {
            withAnimation(.spring(duration: 0.2, bounce: 0)) { model.tileFrames = frames }
        }
    }

    private func endReorder(at p: CGPoint) {
        guard let session = reorder else { return }
        endDrag()
        // Dropping outside the capsule (plus hysteresis) cancels in M1.
        let hysteresis = config.triggerParameters.hysteresis
        let inside = session.frozen.capsuleFrame.insetBy(dx: -hysteresis, dy: -hysteresis).contains(p)
        let from = session.order.firstIndex(of: session.tile) ?? 0
        guard inside, session.index != from else {
            model.apply(layout: layout, tiles: tiles)
            return
        }
        let order = Self.reordered(session.order, moving: session.tile, to: session.index)
        DedockLog.event(.tiles, "tile.reorder", ["id": session.tile.rawValue, "from": from, "to": session.index])
        onReorder?(order)
    }

    /// A relayout during the drag ends it without a reorder; the tiles snap to the new layout.
    private func cancelReorder(reason: String) {
        guard let session = reorder else { return }
        endDrag()
        DedockLog.event(.tiles, "tile.reorderCancelled", ["id": session.tile.rawValue, "reason": reason])
    }

    private func endDrag() {
        reorder = nil
        model.draggedTile = nil
        gate.dragInFlight = false
        controller.send(.hold(.dragging, false))
    }

    /// `order` with `moving` removed and reinserted at `index` among the others.
    static func reordered(_ order: [TileID], moving: TileID, to index: Int) -> [TileID] {
        var others = order.filter { $0 != moving }
        others.insert(moving, at: min(max(0, index), others.count))
        return others
    }

    private var layoutInset: CGFloat { max(0, layout.panelFrame.minY - display.frame.minY) * (config.edge == .bottom ? 1 : 0) }

    // MARK: Pure helpers

    static func tileModels(_ profile: Profile?, running: RunningAppsMonitor) -> [TileModel] {
        (profile?.items ?? []).map { item in
            var t = item.tileModel
            t.running = running.state(for: t.bundleID)
            switch t.kind {
            case .app: t.isMissing = TileActions.appURL(t) == nil
            case .folder: t.isMissing = !(t.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            case .separator: break
            }
            return t
        }
    }

    static func layout(_ config: DockConfig, tiles: [TileItem], display: DisplaySnapshot, surroundings s: DockSurroundings) -> DockLayout {
        // Bottom edge beside a visible native Dock: sit above it (visibleFrame.minY).
        let inset: CGFloat = (config.edge == .bottom && s.nativeDock.orientation == .bottom && !s.nativeDock.autohide)
            ? max(0, display.visibleFrame.minY - display.frame.minY) : 0
        let placement = PlacementInput(display: display, edge: config.edge, alignment: config.dockAlignment, nativeDockInset: inset)
        return LayoutEngine.layout(tiles.map(\.tileSpec), placement, config.tokens.metrics)
    }

    private func logLayout(reason: String) {
        DedockLog.event(.layout, "layout.pass", ["edge": config.edge.rawValue, "reason": reason, "tiles": tiles.count])
    }
}

/// Tile context menu (architecture §6.9). Holds `menuOpen` while tracking.
@MainActor final class TileMenu: NSObject {
    private let tile: TileModel
    private let openTile: () -> Void
    private let remove: () -> Void
    private let menu = NSMenu()

    init(tile: TileModel, open: @escaping () -> Void, remove: @escaping () -> Void) {
        self.tile = tile
        self.openTile = open
        self.remove = remove
        super.init()
        add("Open", #selector(TileMenu.open))
        if tile.url != nil || tile.bundleID != nil { add("Show in Finder", #selector(showInFinder)) }
        if tile.kind == .app, tile.running != .none {
            menu.addItem(.separator())
            add(tile.running == .hidden ? "Unhide" : "Hide", #selector(toggleHidden))
            add("Quit", #selector(quit))
        }
        menu.addItem(.separator())
        add("Remove from Dock", #selector(removeTile))
    }

    func popUp(from view: NSView, event: NSEvent) {
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func add(_ title: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }

    private var runningApps: [NSRunningApplication] {
        tile.bundleID.map { NSRunningApplication.runningApplications(withBundleIdentifier: $0) } ?? []
    }

    @objc func open() { openTile() }
    @objc private func showInFinder() {
        if let url = tile.url ?? TileActions.appURL(tile) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc private func toggleHidden() {
        for app in runningApps { if app.isHidden { app.unhide() } else { app.hide() } }
    }
    @objc private func quit() {
        let force = NSEvent.modifierFlags.contains(.option)
        for app in runningApps { if force { app.forceTerminate() } else { app.terminate() } }
    }
    @objc private func removeTile() { remove() }
}
