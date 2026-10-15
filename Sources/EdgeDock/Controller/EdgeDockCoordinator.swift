import AppKit
import DedockCore
import DesignSystem
import Diagnostics
import EventTapKit
import SettingsStore

/// Everything outside the dock that its geometry depends on.
public struct DockSurroundings: Sendable, Equatable {
    public var layout: DisplayLayout
    public var nativeDock: NativeDockPreferences
    public var reduceMotion: Bool
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

    init(config: DockConfig, profile: Profile?, display: DisplaySnapshot, surroundings: DockSurroundings,
         running: RunningAppsMonitor, icons: IconCache, clock: any Clock<Duration>) {
        id = config.id
        self.config = config
        self.display = display
        self.running = running
        evaluator = TriggerEvaluator(parameters: config.triggerParameters)
        reduceMotion = surroundings.reduceMotion

        let tokens = config.tokens
        model = DockViewModel(tokens: tokens, icons: icons)
        tiles = Self.tileModels(profile, running: running)
        layout = Self.layout(config, tiles: profile?.items ?? [], display: display, surroundings: surroundings)

        panel = EdgeDockPanel(frame: layout.panelFrame, model: model)
        animator = SlideAnimator(container: panel.root.container, edge: config.edge,
                                 hiddenOffset: layout.hiddenOffset, reduceMotion: surroundings.reduceMotion)
        gate = ClickThroughGate(panel: panel, edge: config.edge)
        controller = EdgeRevealController(config: config.revealConfig(reduceMotion: surroundings.reduceMotion),
                                          clock: clock, animator: animator, gate: gate, edge: config.edge)

        model.apply(layout: layout, tiles: tiles)
        rebuildZones(surroundings)
        gate.updateHitRegion(hitRegion)

        panel.root.accepts = { [weak self] p in self?.gate.accepts(p) ?? false }
        panel.root.onTileClick = { [weak self] id in self?.click(id) }
        panel.root.onTileRightClick = { [weak self] id, event in self?.contextMenu(for: id, event: event) }
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
        config = new
        display = newDisplay
        tiles = Self.tileModels(profile, running: running)
        let newLayout = Self.layout(new, tiles: profile?.items ?? [], display: newDisplay, surroundings: surroundings)
        model.tokens = new.tokens
        let geometryChanged = newLayout != layout || oldConfig.edge != new.edge
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
        evaluator.parameters = new.triggerParameters
        rebuildZones(surroundings)
        controller.reconfigure(new.revealConfig(reduceMotion: surroundings.reduceMotion))
        onChange?()
    }

    /// Running state changed: only the tile models change, never the geometry.
    func refreshRunning() {
        var changed = false
        for i in tiles.indices where tiles[i].kind == .app {
            let state = running.state(for: tiles[i].bundleID)
            guard state != tiles[i].running else { continue }
            tiles[i].running = state
            changed = true
            DedockLog.event(.tiles, "tile.indicator", ["bundle": tiles[i].bundleID ?? "-", "state": state.rawValue])
        }
        if changed { model.tiles = tiles }
    }

    func teardown() {
        controller.invalidate()
        panel.orderOut(nil)
        panel.close()
    }

    private func rebuildZones(_ s: DockSurroundings) {
        let footprint = s.nativeDock.orientation == config.edge
            ? NativeDockPreferences.footprint(prefs: s.nativeDock, display: display) : nil
        let env = EdgeEnvironment(layout: s.layout, display: display.identity, edge: config.edge,
                                  contentSpan: layout.contentSpan, nativeDock: footprint,
                                  hotCorners: s.nativeDock.hotCorners)
        let parameters = config.triggerParameters
        guard env != environmentKey || parameters != zoneParameters else { return }
        environmentKey = env
        zoneParameters = parameters
        zones = EdgeGeometry.zones(env, parameters)
        evaluator.reset()
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
        let menu = TileMenu(tile: tile) { [weak self] in self?.onRemoveTile?(id) }
        controller.send(.hold(.menuOpen, true))
        menu.popUp(from: panel.root, event: event)
        controller.send(.hold(.menuOpen, false))
    }

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
    private let remove: () -> Void
    private let menu = NSMenu()

    init(tile: TileModel, remove: @escaping () -> Void) {
        self.tile = tile
        self.remove = remove
        super.init()
        add("Open", #selector(open))
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

    @objc private func open() { TileActions.activate(tile) }
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
