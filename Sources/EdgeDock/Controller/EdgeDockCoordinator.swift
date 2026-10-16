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
    /// The system Reduce Transparency setting: Liquid Glass and the glass styles draw solid.
    public var reduceTransparency: Bool = false
    /// Menu-bar status-item rects per display (AppKit global), from `FullscreenProbe` (REG-044).
    public var statusItems: [DisplayIdentity: [CGRect]] = [:]
    /// Status-level windows rejected as not item-sized, per display (for `zones.computed`).
    public var statusItemsRejected: [DisplayIdentity: Int] = [:]
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
    /// Called when a reorder drag is dropped outside the dock, with the screen drop point; the
    /// manager asks before removing (evaluation row 43).
    var onDragOut: ((TileID, CGPoint) -> Void)?
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
    /// LG4 Adaptive (Liquid Glass): the tint and what it was read from (design.md §7.2a).
    private(set) var liquid = LiquidTintPolicy()
    /// Reduce Transparency, from the surroundings (like Reduce Motion).
    private var reduceTransparency: Bool
    /// Where LG4 readings come from (the desktop picture file); tests inject their own.
    private let background: BackgroundReader
    private var backgroundKey: WallpaperLuminance.Key?
    private var backgroundTask: Task<Void, Never>?

    init(config: DockConfig, profile: Profile?, display: DisplaySnapshot, surroundings: DockSurroundings,
         running: RunningAppsMonitor, icons: IconCache, clock: any Clock<Duration>, background: BackgroundReader = .wallpaper) {
        id = config.id
        self.config = config
        self.display = display
        self.running = running
        evaluator = TriggerEvaluator(parameters: config.triggerParameters(nativeDockEdge: surroundings.nativeDock.orientation))
        reduceMotion = surroundings.reduceMotion
        reduceTransparency = surroundings.reduceTransparency
        self.background = background

        let tokens = Self.tokens(config, liquid: .dark, reduceTransparency: surroundings.reduceTransparency)
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
            // Hidden again: the reveal corridor ends (REG-067); a new zone entry starts another.
            if t.to == .hidden { self.evaluator.dropCorridor() }
            // A reveal, or a snap straight to shown (Settings, suppression), applies a pending tint.
            if t.to == .revealing || (t.to == .shown && t.from != .revealing) { self.applyPendingTint() }
            if t.to == .hidden { self.refreshBackground() }    // a cheap key check; reads only on a change
            self.onChange?()
        }
        panel.orderFrontRegardless()
        logLayout(reason: "create")
        refreshBackground()
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
        reduceTransparency = surroundings.reduceTransparency
        model.tokens = Self.tokens(new, liquid: liquid.applied, reduceTransparency: reduceTransparency)
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
        refreshBackground()
        onChange?()
    }

    // MARK: LG4 Adaptive (Liquid Glass)

    /// Re-reads the wallpaper under the dock's edge when what it depends on changed (the picture,
    /// the display, the edge, the dock's depth); called at creation, on updates, when the dock
    /// has hidden, and by the manager on a Space change. Only for the Liquid Glass style.
    func refreshBackground() {
        guard config.appearance.style == .liquidGlass else {
            backgroundTask?.cancel()
            backgroundKey = nil
            return
        }
        // The strip's depth, in 16 pt steps: the size slider's live preview resizes the capsule
        // every frame, and the average barely moves with it.
        let c = layout.capsuleFrame
        let depth = (((config.edge.isVertical ? c.width : c.height) + model.tokens.edgeGap) / 16).rounded(.up) * 16
        guard let key = background.key(display, config.edge, depth) else {
            if backgroundKey != nil || !backgroundUnavailableLogged { logUnavailable() }
            backgroundKey = nil
            return
        }
        guard key != backgroundKey else { return }
        backgroundKey = key
        backgroundTask?.cancel()
        let read = background.read
        backgroundTask = Task { @MainActor [weak self] in
            let luminance = await read(key)
            guard !Task.isCancelled, let self, self.backgroundKey == key else { return }
            guard let luminance else { self.logUnavailable(); return }
            self.observeBackground(luminance: luminance)
        }
    }

    private var backgroundUnavailableLogged = false

    /// No reading: no desktop picture file, or one ImageIO cannot decode (some dynamic or
    /// aerial wallpapers). The tint stays as it is.
    private func logUnavailable() {
        backgroundUnavailableLogged = true
        DedockLog.event(.edge, "dock.tint.reading", ["unavailable": 1, "applied": liquid.applied.rawValue])
    }

    /// The tokens for a tint: appearance (label colours) live, Reduce Transparency from the
    /// surroundings.
    static func tokens(_ config: DockConfig, liquid: LiquidTint, reduceTransparency: Bool) -> DockTokens {
        config.tokens(lightAppearance: NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua,
                      reduceTransparency: reduceTransparency, liquid: liquid)
    }

    /// A background reading. The tint never changes while the dock is shown: the change waits
    /// for the next reveal. A Pinned dock is always shown, so it takes the change at once,
    /// cross-faded.
    func observeBackground(luminance: Double) {
        let before = liquid.pending
        liquid.observe(luminance: luminance)
        DedockLog.event(.edge, "dock.tint.reading", ["luminance": String(format: "%.2f", luminance),
                                                     "pending": liquid.pending.rawValue, "applied": liquid.applied.rawValue])
        if liquid.pending != before, config.mode == .pinned { applyPendingTint() }
    }

    /// The dock starts to reveal: a pending tint change applies now and cross-fades 0.3 s
    /// (instant under Reduce Motion).
    private func applyPendingTint() {
        guard let tint = liquid.reveal() else { return }
        DedockLog.event(.edge, "dock.tint", ["tint": tint.rawValue])
        if reduceMotion {
            model.tokens = Self.tokens(config, liquid: tint, reduceTransparency: reduceTransparency)
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {   // text and dots
                model.tokens = Self.tokens(config, liquid: tint, reduceTransparency: reduceTransparency)
            }
        }
        panel.root.applyCapsule(crossFade: !reduceMotion)
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
        refreshHoverState()    // the state line updates live
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
        backgroundTask?.cancel()
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
        let derived = EdgeGeometry.derive(env, parameters)
        zones = derived.zones
        derivation = derived
        nativeDockFootprint = footprint
        logZones(derived, rejected: s.statusItemsRejected[display.identity] ?? 0)
        // Tell the machine what the reset cleared; the next pointer sample re-derives it.
        controller.send(evaluator.reset())
    }

    /// How the current zones were derived, and the native Dock footprint they avoid (GEOM).
    private(set) var derivation: ZoneDerivation?
    private(set) var nativeDockFootprint: NativeDockFootprint?

    /// `zones.computed`: spans along the edge and counts only, never another app's details.
    private func logZones(_ d: ZoneDerivation, rejected: Int) {
        func span(_ i: Interval?) -> String { i.map { "\(Int($0.lower.rounded()))..\(Int($0.upper.rounded()))" } ?? "-" }
        DedockLog.event(.edge, "zones.computed", [
            "edge": config.edge.rawValue, "dock": id.rawValue, "rule": d.rule.rawValue, "span": span(d.candidate),
            "statusItems": d.statusItems, "statusRejected": rejected, "notch": d.notch, "nativeDock": span(d.nativeDock),
            "segments": d.zones.count,
        ])
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
        // Instant (motion.tile.label): set on the same sample, no timer.
        if hover != model.hoveredTile {
            model.hoveredTile = hover
            refreshHoverState()
        }
    }

    /// Reads the hovered app's window count for the H4 state line (only on hover or running
    /// changes, never per sample).
    var windowCounter: (String) -> Int = WindowCount.of
    private func refreshHoverState() {
        guard let id = model.hoveredTile, let i = tiles.firstIndex(where: { $0.id == id }),
              tiles[i].kind == .app, let bundle = tiles[i].bundleID else { return }
        let count: Int? = tiles[i].running == .none ? nil : windowCounter(bundle)
        guard tiles[i].windowCount != count else { return }
        tiles[i].windowCount = count
        model.tiles = tiles
    }

    /// Layout passes since creation (row 20: none while the pointer moves).
    private(set) var layoutPasses = 0

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
        let hysteresis = config.triggerParameters.hysteresis
        let inside = session.frozen.capsuleFrame.insetBy(dx: -hysteresis, dy: -hysteresis).contains(p)
        let from = session.order.firstIndex(of: session.tile) ?? 0
        guard inside, session.index != from else {
            // The tile springs back to its place; dropped outside, the manager asks whether to
            // remove it (row 43).
            if reduceMotion {
                model.apply(layout: layout, tiles: tiles)
            } else {
                withAnimation(.spring(duration: 0.2, bounce: 0)) { model.apply(layout: layout, tiles: tiles) }
            }
            if !inside { onDragOut?(session.tile, p) }
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

    /// The native Dock inset the current layout was built with (the panel starts at it).
    private var layoutInset: CGFloat {
        let p = layout.panelFrame, f = display.frame
        return switch config.edge {
        case .left: max(0, p.minX - f.minX)
        case .right: max(0, f.maxX - p.maxX)
        case .bottom: max(0, p.minY - f.minY)
        case .top: 0
        }
    }

    // MARK: Pure helpers

    static func tileModels(_ profile: Profile?, running: RunningAppsMonitor) -> [TileModel] {
        (profile?.items ?? []).map { item in
            var t = item.tileModel
            t.running = running.state(for: t.bundleID)
            switch t.kind {
            case .app: t.isMissing = TileActions.appURL(t) == nil
            case .folder: t.isMissing = !(t.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
            case .separator, .spacer: break
            }
            return t
        }
    }

    static func layout(_ config: DockConfig, tiles: [TileItem], display: DisplaySnapshot, surroundings s: DockSurroundings) -> DockLayout {
        // Beside a visible native Dock on the same edge: sit on its inner side, where macOS's
        // visibleFrame ends (REG-070: the left and right edges sat over the Dock).
        let inset: CGFloat = Self.nativeDockInset(edge: config.edge, display: display, nativeDock: s.nativeDock)
        let placement = PlacementInput(display: display, edge: config.edge, alignment: config.dockAlignment, nativeDockInset: inset)
        return LayoutEngine.layout(tiles.map(\.tileSpec), placement, config.tokens.metrics)
    }

    /// The visible native Dock's thickness on `edge`, from the `visibleFrame` gap macOS leaves
    /// for it; 0 when the Dock is on another edge or auto-hides.
    static func nativeDockInset(edge: ScreenEdge, display: DisplaySnapshot, nativeDock: NativeDockPreferences) -> CGFloat {
        guard nativeDock.orientation == edge, !nativeDock.autohide else { return 0 }
        let f = display.frame, v = display.visibleFrame
        return switch edge {
        case .left: max(0, v.minX - f.minX)
        case .right: max(0, f.maxX - v.maxX)
        case .bottom: max(0, v.minY - f.minY)
        case .top: 0
        }
    }

    private func logLayout(reason: String) {
        layoutPasses += 1
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
