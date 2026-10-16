import AppKit
import DedockCore
import Diagnostics
import DisplayTopology
import EventTapKit
import SettingsStore

/// Creates and removes one coordinator per enabled dock, fans pointer samples out to them and
/// implements `EdgeDockControlling` (architecture §6.1).
@MainActor public final class EdgeDockManager: EdgeDockControlling, PointerSampleSink {
    public private(set) var coordinators: [DockID: EdgeDockCoordinator] = [:]

    private let settings: SettingsModel
    private let topology: DisplayTopology
    private let hub: PointerHub
    private let running = RunningAppsMonitor()
    private let icons = IconCache()
    private let clock: any Clock<Duration>
    private let env = DedockEnvironment.current
    private let geometryWriter: GeometryWriter
    private var dockPrefs: DockPreferencesReader!
    private var fullscreen: FullscreenProbe!
    private var topologyToken: ObservationToken?
    private var settingsObserver: UUID?
    private var accessibilityObserver: (any NSObjectProtocol)?
    /// A Space change can bring another desktop picture: LG4 re-reads it (T37).
    private var spaceObserver: (any NSObjectProtocol)?
    private var appearanceObservation: NSKeyValueObservation?
    /// The document as of the last settings notification (for `settings.changed`).
    private var lastDocument: DedockDocument
    private var edgeReadyLogged = false
    /// Set once edge sensing is live (end of init), independent of any pointer activity.
    public private(set) var edgeReadyMs: Int?
    /// Set at the first zone arming after launch.
    public private(set) var firstArmMs: Int?
    private let launchTime = ProcessInfo.processInfo.systemUptime - EdgeDockManager.processAge()
    private var geometryWritePending = false
    private var debugCommands: DebugCommandListener?
    /// Set by the app to open the Settings window (debug command `openSettings`).
    public var onOpenSettings: (() -> Void)?

    /// The outer `sync` reason while a bookmark fill re-enters `sync` through the observer (REG-059).
    private var fillingReason: String?
    /// The reason of the last `docks.sync` line (for the REG-059 guard).
    private(set) var lastSyncReason: String?

    /// - Parameter notices: launch notices, released once edge sensing is live (REG-057).
    public init(settings: SettingsModel, topology: DisplayTopology, hub: PointerHub,
                clock: any Clock<Duration> = ContinuousClock(), dataDirectory: URL, notices: LaunchNotices? = nil) {
        self.settings = settings
        lastDocument = settings.document
        self.topology = topology
        self.hub = hub
        self.clock = clock
        geometryWriter = GeometryWriter(dataDirectory: dataDirectory)
        dockPrefs = DockPreferencesReader { [weak self] _ in self?.sync(reason: "dockPrefs") }
        fullscreen = FullscreenProbe(clock: clock, layout: { [weak topology] in topology?.layout ?? DisplayLayout(displays: []) })
        topologyToken = topology.observe { [weak self] _ in
            self?.sync(reason: "displays")
            self?.fullscreen.check()
        }
        settingsObserver = settings.addObserver { [weak self] _ in
            self?.logSettingChanges()
            self?.sync(reason: "settings")
        }
        // Only top-edge zones avoid status items; side and bottom docks are left alone.
        fullscreen.onStatusItemsChange = { [weak self] in self?.sync(reason: "statusItems", updating: { $0.config.edge == .top }) }
        fullscreen.onChange = { [weak self] changed in
            guard let self else { return }
            for c in self.coordinators.values {
                if let on = changed[c.display.identity] { c.controller.send(.fullscreenChanged(on)) }
            }
        }
        running.onChange = { [weak self] in
            guard let self else { return }
            for c in self.coordinators.values { c.refreshRunning() }
            self.scheduleGeometryWrite()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.sync(reason: "reduceMotion") } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.coordinators.values.forEach { $0.refreshBackground() } } }
        // Light / Dark switches re-derive the tokens: label colours follow the system appearance.
        appearanceObservation = NSApp?.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.sync(reason: "appearance") }
        }
        hub.addSink(self)
        debugCommands = DebugCommandListener { [weak self] in self?.perform($0) }
        sync(reason: "launch")
        // Edge sensing is live: zones built, panels parked, monitors installed.
        edgeReadyMs = msSinceProcessStart()
        DedockLog.event(.launch, "launch.edgeReady", ["ms": edgeReadyMs!, "docks": coordinators.count])
        // Only now may a notice take the screen: the docks are already live behind it.
        notices?.docksAreLive()
    }

    private func msSinceProcessStart() -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - launchTime) * 1000).rounded())
    }

    /// Reduce Motion as the docks use it (the override, else the system setting).
    public var reducesMotion: Bool { reduceMotion }

    private var reduceMotion: Bool {
        settings.document.app.reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var surroundings: DockSurroundings {
        DockSurroundings(layout: topology.layout, nativeDock: dockPrefs.current, reduceMotion: reduceMotion,
                         reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
                         statusItems: fullscreen.statusItems, statusItemsRejected: fullscreen.statusItemsRejected,
                         fullscreen: fullscreen.states)
    }

    /// Folder tiles saved with only a path (hand-written seeds, older files) get their bookmark
    /// on the first save (evaluation.md §7.5, REG-031). Returns nil when nothing is missing.
    static func fillingBookmarks(_ doc: DedockDocument) -> DedockDocument? {
        var next = doc
        var changed = false
        for p in next.profiles.indices {
            for i in next.profiles[p].items.indices {
                let item = next.profiles[p].items[i]
                guard item.kind == .folder, item.bookmark == nil, let path = item.path,
                      FileManager.default.fileExists(atPath: path),
                      let data = try? URL(fileURLWithPath: path, isDirectory: true).bookmarkData() else { continue }
                next.profiles[p].items[i].bookmark = data
                changed = true
            }
        }
        return changed ? next : nil
    }

    /// Reconcile coordinators with the settings document and display layout.
    /// - Parameter updating: which existing docks to update; new and removed docks are always handled.
    func sync(reason outer: String, updating: (EdgeDockCoordinator) -> Bool = { _ in true }) {
        if let filled = Self.fillingBookmarks(settings.document) {
            // Re-enters sync through the observer, then saves. The nested pass logs the outer
            // reason, so the first launch still reads `reason=launch` (REG-059).
            fillingReason = outer
            settings.update { $0 = filled }
            fillingReason = nil
            return
        }
        let reason = fillingReason ?? outer
        let doc = settings.document
        let s = surroundings
        var keep: Set<DockID> = []
        for config in doc.docks where config.enabled {
            guard let display = resolveDisplay(config.display, in: s.layout) else { continue }
            keep.insert(config.id)
            let profile = doc.profile(config.profileID)
            if let existing = coordinators[config.id] {
                guard updating(existing) else { continue }
                existing.update(config: config, profile: profile, display: display, surroundings: s)
            } else {
                let c = EdgeDockCoordinator(config: config, profile: profile, display: display, surroundings: s,
                                            running: running, icons: icons, clock: clock)
                c.onChange = { [weak self] in self?.dockChanged() }
                c.onArmed = { [weak self] in self?.logEdgeReady() }
                c.onRemoveTile = { [weak self] tile in self?.remove(tile: tile, from: config.profileID) }
                c.onDragOut = { [weak self, weak c] tile, point in
                    guard let self, let c else { return }
                    self.askToRemove(tile, from: config.profileID, coordinator: c, at: point)
                }
                c.onReorder = { [weak self] order in self?.reorder(order, in: config.profileID) }
                c.onPin = { [weak self] urls, index in self?.pin(urls, at: index, in: config.profileID) }
                coordinators[config.id] = c
            }
        }
        for (id, c) in coordinators where !keep.contains(id) {
            c.teardown()
            coordinators[id] = nil
        }
        // Pointer monitors run only while at least one dock is enabled (architecture §6.3, REG-032).
        if coordinators.isEmpty {
            if hub.isRunning { hub.stop() }
        } else if !hub.isRunning {
            hub.start()
        }
        lastSyncReason = reason
        DedockLog.event(.app, "docks.sync", ["reason": reason, "docks": coordinators.count])
        dockChanged()
    }

    /// M1 binding: main display (or a specific one), falling back to the built-in display.
    private func resolveDisplay(_ binding: DisplayBinding, in layout: DisplayLayout) -> DisplaySnapshot? {
        switch binding.role {
        case .main:
            return layout.main
        case .identity:
            if let uuid = binding.identity, let d = layout.displays.first(where: { $0.identity.uuid == uuid }) { return d }
            return binding.fallbackToBuiltin ? (layout.builtin ?? layout.main) : nil
        }
    }

    private func dockChanged() {
        hub.nearRegions = coordinators.values.map(\.nearRegion).filter { !$0.isNull }
        scheduleGeometryWrite()
    }

    private func scheduleGeometryWrite() {
        guard env.e2e, !geometryWritePending else { return }
        geometryWritePending = true
        // Coalesce bursts (a transition and a layout pass in the same turn) into one write.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.geometryWritePending = false
                self.writeGeometry()
            }
        }
    }

    public func writeGeometry() {
        let docks = coordinators.values.sorted { $0.id.rawValue < $1.id.rawValue }.map { c in
            let tokens = c.model.tokens
            return DockGeometrySnapshot(id: c.id, display: c.display, edge: c.config.edge,
                                        mode: c.config.mode == .pinned ? .pinned : .reveal, phase: c.phase,
                                        layout: c.layout, zones: c.zones, tiles: c.tiles,
                                        style: tokens.style.rawValue,
                                        material: tokens.systemGlassTint != nil ? "glass" : Self.materialName(tokens.blurMaterial),
                                        liquidTint: c.config.appearance.style == .liquidGlass ? c.liquid.applied.rawValue : nil,
                                        showDwellMs: Self.ms(c.config.revealConfig(reduceMotion: reduceMotion).showDwell),
                                        zoneRule: c.derivation?.rule.rawValue ?? "primary", nativeDock: c.nativeDockFootprint)
        }
        geometryWriter.write(layout: topology.layout, docks: docks)
    }

    /// `settings.changed` lines (E2E contract) for the keys the harness tracks, between two documents.
    static func settingChanges(from old: DedockDocument, to new: DedockDocument) -> [(key: String, value: String, scenario: String)] {
        let before = Dictionary(old.docks.map { ($0.id, $0.appearance.style) }, uniquingKeysWith: { a, _ in a })
        return new.docks.compactMap { dock in
            guard let was = before[dock.id], was != dock.appearance.style else { return nil }
            return ("dd.dock.style", dock.appearance.style.rawValue, dock.scenario)
        }
    }

    private func logSettingChanges() {
        let doc = settings.document
        for change in Self.settingChanges(from: lastDocument, to: doc) {
            DedockLog.event(.settings, "settings.changed", ["key": change.key, "value": change.value, "scenario": change.scenario])
        }
        lastDocument = doc
    }

    static func ms(_ d: Duration) -> Int {
        Int(d.components.seconds) * 1000 + Int(d.components.attoseconds / 1_000_000_000_000_000)
    }

    /// Settings' note when the first dock's top-edge trigger had to fall back (REG-066).
    public var triggerHint: String? {
        switch coordinators.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }).first?.derivation?.rule {
        case .nearestFree?: "Reveal from the free part of the menu bar near the centre"
        case .optionOnly?: "Hold ⌥ at the top edge to reveal"
        default: nil
        }
    }

    /// GEOM's `material` value: the blur material's name, or `solid` under Reduce Transparency.
    static func materialName(_ m: NSVisualEffectView.Material?) -> String {
        switch m {
        case nil: "solid"
        case .hudWindow?: "hudWindow"
        case .popover?: "popover"
        default: "other"
        }
    }

    /// The first zone arming after launch (includes however long the user took to get there).
    private func logEdgeReady() {
        guard !edgeReadyLogged else { return }
        edgeReadyLogged = true
        firstArmMs = msSinceProcessStart()
        DedockLog.event(.launch, "launch.firstArm", ["ms": firstArmMs!])
    }

    /// Persist a reorder at once; it survives relaunch (T15 item 5).
    private func reorder(_ order: [TileID], in profile: ProfileID) {
        settings.update { doc in
            guard let i = doc.profiles.firstIndex(where: { $0.id == profile }) else { return }
            let items = doc.profiles[i].items
            let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let reordered = order.compactMap { byID[$0] }
            // Keep anything the drag did not know about (added meanwhile) at the end.
            doc.profiles[i].items = reordered + items.filter { !order.contains($0.id) }
        }
        Task { await settings.flush() }
    }

    /// Pin dropped apps or folders at `index` (duplicates of an existing app are skipped).
    private func pin(_ urls: [URL], at index: Int, in profile: ProfileID) {
        settings.update { doc in
            guard let i = doc.profiles.firstIndex(where: { $0.id == profile }) else { return }
            var items = doc.profiles[i].items
            var at = min(max(0, index), items.count)
            for url in urls {
                let item = Self.tileItem(for: url)
                if let b = item.bundleID, items.contains(where: { $0.bundleID == b }) { continue }
                if item.kind == .folder, items.contains(where: { $0.kind == .folder && $0.path == item.path }) { continue }
                items.insert(item, at: at)
                at += 1
                DedockLog.event(.tiles, "tile.pin", ["id": item.id.rawValue, "kind": item.kind.rawValue, "at": at - 1])
            }
            doc.profiles[i].items = items
        }
        Task { await settings.flush() }
    }

    static func tileItem(for url: URL) -> TileItem {
        TileActions.pinKind(url) == .app ? .app(at: url) : .folder(at: url)
    }

    // MARK: Drag-out removal (evaluation row 43, design §2.3a)

    /// The question being asked, if any (one at a time).
    private(set) var pendingRemoval: RemovalConfirmation?
    private var removalPanel: RemoveConfirmPanel?
    /// Puts the question on screen. Replaced in tests; the default is `RemoveConfirmPanel`.
    var presentRemoval: (_ name: String, _ confirmation: RemovalConfirmation, _ c: EdgeDockCoordinator, _ drop: CGPoint) -> Void = { _, _, _, _ in }
    private var presentRemovalDefault = true

    /// One question at a time: a second drag-out while one is open is ignored (that tile has
    /// already sprung back, so nothing is lost; drag it out again after answering).
    func askToRemove(_ tile: TileID, from profile: ProfileID, coordinator c: EdgeDockCoordinator, at drop: CGPoint) {
        guard pendingRemoval == nil,
              let item = settings.document.profile(profile)?.items.first(where: { $0.id == tile }) else { return }
        let name = item.displayName
            ?? (item.kind == .separator ? "Separator" : item.path.map { FileManager.default.displayName(atPath: $0) } ?? "this tile")
        // The dock stays shown while the question is open.
        c.controller.send(.hold(.popoverOpen, true))
        let confirmation = RemovalConfirmation(tile: tile, clock: clock) { [weak self, weak c] result in
            guard let self else { return }
            c?.controller.send(.hold(.popoverOpen, false))
            self.removalPanel?.close()
            self.removalPanel = nil
            self.pendingRemoval = nil
            DedockLog.event(.tiles, "tile.removeConfirm", ["id": tile.rawValue, "result": result.rawValue])
            if result == .remove {
                self.remove(tile: tile, from: profile)
                Task { await self.settings.flush() }
            }
        }
        pendingRemoval = confirmation
        if presentRemovalDefault {
            // P2: the dock's own style (and LG4 tint), beside the slot the tile sprang back to.
            let icon = c.tiles.first { $0.id == tile }.flatMap { c.model.icons.icon(for: $0) }
            let panel = RemoveConfirmPanel(name: name, icon: icon, tokens: c.model.tokens, confirmation: confirmation)
            removalPanel = panel
            let slot = c.layout.tileFrames[tile].map { CGPoint(x: $0.midX, y: $0.midY) } ?? drop
            panel.show(capsule: c.capsuleFrame, slot: slot, edge: c.config.edge, visible: c.display.visibleFrame,
                       reduceMotion: reduceMotion)
        } else {
            presentRemoval(name, confirmation, c, drop)
            confirmation.start()
        }
    }

    /// Tests answer the question themselves instead of the panel.
    func replaceRemovalPresenter(_ present: @escaping (_ name: String, _ confirmation: RemovalConfirmation, _ c: EdgeDockCoordinator, _ drop: CGPoint) -> Void) {
        presentRemoval = present
        presentRemovalDefault = false
    }

    private func remove(tile: TileID, from profile: ProfileID) {
        settings.update { doc in
            guard let i = doc.profiles.firstIndex(where: { $0.id == profile }) else { return }
            doc.profiles[i].items.removeAll { $0.id == tile }
        }
    }

    /// E2E debug commands (debug bundle + DEDOCK_E2E=1 only).
    func perform(_ command: DebugCommand) {
        switch command {
        case .setEdge(let edge):
            settings.update { doc in
                guard !doc.docks.isEmpty else { return }
                doc.docks[0].edge = edge
                doc.docks[0].scenario = "custom"
            }
        case .rebuildZones:
            for c in coordinators.values { c.forceRebuildZones(surroundings) }
        case .reveal:
            reveal(dock: nil)
        case .hide:
            hide(dock: nil, animated: true)
        case .openSettings:
            onOpenSettings?()
        }
    }

    // MARK: PointerSampleSink

    public func pointer(_ sample: PointerSample) {
        for c in coordinators.values { c.pointer(sample) }
    }

    // MARK: EdgeDockControlling

    private func targets(_ dock: DockID?) -> [EdgeDockCoordinator] {
        if let dock { return coordinators[dock].map { [$0] } ?? [] }
        let p = NSEvent.mouseLocation
        let onPointer = coordinators.values.filter { $0.display.frame.contains(p) }
        return onPointer.isEmpty ? Array(coordinators.values) : onPointer
    }

    public func reveal(dock: DockID?) {
        for c in targets(dock) { c.controller.send(.command(.reveal)) }
    }

    public func hide(dock: DockID?, animated: Bool) {
        for c in targets(dock) {
            if animated {
                c.controller.send(.command(.hide(explicit: true)))
            } else {
                c.controller.send([.suppression(.disabled, true), .suppression(.disabled, false)])
            }
        }
    }

    public func setHold(_ token: HoldOpenToken, _ on: Bool, dock: DockID?) {
        let all = dock.map { coordinators[$0].map { [$0] } ?? [] } ?? Array(coordinators.values)
        for c in all { c.controller.send(.hold(token, on)) }
    }

    public var isHeldOpen: Bool {
        coordinators.values.contains { $0.controller.machine.holds.contains(.pinnedByUser) }
    }

    /// Process age at the time the manager starts, from `kinfo_proc` (for `launch.edgeReady`).
    private static func processAge() -> TimeInterval {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1e6
        return max(0, Date().timeIntervalSince1970 - started)
    }
}
