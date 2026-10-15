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
    private var topologyToken: ObservationToken?
    private var settingsObserver: UUID?
    private var accessibilityObserver: (any NSObjectProtocol)?
    private var edgeReadyLogged = false
    private let launchTime = ProcessInfo.processInfo.systemUptime - EdgeDockManager.processAge()
    private var geometryWritePending = false

    public init(settings: SettingsModel, topology: DisplayTopology, hub: PointerHub,
                clock: any Clock<Duration> = ContinuousClock(), dataDirectory: URL) {
        self.settings = settings
        self.topology = topology
        self.hub = hub
        self.clock = clock
        geometryWriter = GeometryWriter(dataDirectory: dataDirectory)
        dockPrefs = DockPreferencesReader { [weak self] _ in self?.sync(reason: "dockPrefs") }
        topologyToken = topology.observe { [weak self] _ in self?.sync(reason: "displays") }
        settingsObserver = settings.addObserver { [weak self] _ in self?.sync(reason: "settings") }
        running.onChange = { [weak self] in
            guard let self else { return }
            for c in self.coordinators.values { c.refreshRunning() }
            self.scheduleGeometryWrite()
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.sync(reason: "reduceMotion") } }
        hub.addSink(self)
        sync(reason: "launch")
        hub.start()
        // Edge sensing is live: zones built, panels parked, monitors installed.
        DedockLog.event(.launch, "launch.edgeReady", ["ms": msSinceProcessStart(), "docks": coordinators.count])
    }

    private func msSinceProcessStart() -> Int {
        Int(((ProcessInfo.processInfo.systemUptime - launchTime) * 1000).rounded())
    }

    private var reduceMotion: Bool {
        settings.document.app.reduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var surroundings: DockSurroundings {
        DockSurroundings(layout: topology.layout, nativeDock: dockPrefs.current, reduceMotion: reduceMotion)
    }

    /// Reconcile coordinators with the settings document and display layout.
    func sync(reason: String) {
        let doc = settings.document
        let s = surroundings
        var keep: Set<DockID> = []
        for config in doc.docks where config.enabled {
            guard let display = resolveDisplay(config.display, in: s.layout) else { continue }
            keep.insert(config.id)
            let profile = doc.profile(config.profileID)
            if let existing = coordinators[config.id] {
                existing.update(config: config, profile: profile, display: display, surroundings: s)
            } else {
                let c = EdgeDockCoordinator(config: config, profile: profile, display: display, surroundings: s,
                                            running: running, icons: icons, clock: clock)
                c.onChange = { [weak self] in self?.dockChanged() }
                c.onArmed = { [weak self] in self?.logEdgeReady() }
                c.onRemoveTile = { [weak self] tile in self?.remove(tile: tile, from: config.profileID) }
                coordinators[config.id] = c
            }
        }
        for (id, c) in coordinators where !keep.contains(id) {
            c.teardown()
            coordinators[id] = nil
        }
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
        let docks = coordinators.values.sorted { $0.id.rawValue < $1.id.rawValue }.map {
            DockGeometrySnapshot(id: $0.id, display: $0.display, edge: $0.config.edge,
                                 mode: $0.config.mode == .pinned ? .pinned : .reveal, phase: $0.phase,
                                 layout: $0.layout, zones: $0.zones, tiles: $0.tiles)
        }
        geometryWriter.write(layout: topology.layout, docks: docks)
    }

    /// The first zone arming after launch (includes however long the user took to get there).
    private func logEdgeReady() {
        guard !edgeReadyLogged else { return }
        edgeReadyLogged = true
        DedockLog.event(.launch, "launch.firstArm", ["ms": msSinceProcessStart()])
    }

    private func remove(tile: TileID, from profile: ProfileID) {
        settings.update { doc in
            guard let i = doc.profiles.firstIndex(where: { $0.id == profile }) else { return }
            doc.profiles[i].items.removeAll { $0.id == tile }
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
