import AppKit
import DedockCore
import DedockTestSupport
import DisplayTopology
import EventTapKit
import Foundation
import SettingsStore
import Testing
@testable import EdgeDock

/// Regression guards for the AppKit side of the Edge Dock. macOS only (excluded on Linux).
@Suite("Regression", .tags(.regression), .serialized) @MainActor struct AppRegressionTests {
    /// REG-014: tile.indicator was logged for every running app (leaking the user's app list),
    /// not just the dock's tiles.
    @Test("REG-014: indicator changes cover only the dock's own app tiles")
    func reg014() {
        let tiles = [
            TileModel(id: "a", kind: .app, name: "A", bundleID: "com.example.a"),
            TileModel(id: "f", kind: .folder, name: "F"),
            TileModel(id: "s", kind: .separator, name: ""),
        ]
        var asked: [String?] = []
        let changes = EdgeDockCoordinator.indicatorChanges(tiles) { id in
            asked.append(id)
            return .running
        }
        #expect(changes.map(\.index) == [0])
        #expect(asked == ["com.example.a"])   // never asked about any other app
    }

    /// REG-021: KVO observations outlived the NSRunningApplication objects they observed
    /// ("deallocated while observers are still registered"); the monitor now holds them.
    /// NSWorkspace caches its NSRunningApplication instances, so real apps cannot show the
    /// difference: the guard drives the monitor's holder with an object nothing else retains.
    @Test("REG-021: an observed object is held for as long as it is observed")
    func reg021() {
        let kept = KeptObservations<Int, KVOProbe>()
        let fired = Counter()
        weak var probe: KVOProbe?
        autoreleasepool {
            let p = KVOProbe()
            probe = p
            kept.insert(p, for: 1, observation: p.observe(\.value) { _, _ in fired.value += 1 })
        }
        #expect(probe != nil)           // held while observed
        #expect(kept.contains(1))
        probe?.value = 1
        #expect(fired.value == 1)       // and the observation is still live
        kept.removeAll { _ in true }
        #expect(probe == nil)           // released once the observation is invalidated
        #expect(!kept.contains(1))
    }

    /// REG-019: one-shot reveal timers slept with the default tolerance and fired ~26 ms late.
    @Test("REG-019: reveal timers sleep with zero tolerance")
    func reg019() async {
        let clock = ManualClock()
        let controller = EdgeRevealController(config: RevealConfig(), clock: clock, animator: FakeAnimator(),
                                              gate: FakeGate(), edge: .left)
        controller.send(.zoneEntered(.wall))
        for _ in 0..<100 where clock.pendingCount == 0 { await Task.yield() }
        #expect(clock.pendingCount == 1)
        #expect(clock.tolerances.last == .some(.zero))
        controller.invalidate()
    }

    /// REG-018: launch.edgeReady fired at the first arming, so it measured how long the user
    /// took to reach the edge rather than when edge sensing went live.
    @Test("REG-018: edge readiness is recorded at sensing-live, before any pointer activity",
          .enabled(if: NSScreen.main != nil))
    func reg018() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-reg-\(UUID().uuidString)")
        let clock = ManualClock()
        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: .makeDefault())
        let hub = PointerHub(source: SilentPointerSource(), clock: clock)
        let manager = EdgeDockManager(settings: settings, topology: DisplayTopology(clock: clock), hub: hub,
                                      clock: clock, dataDirectory: dir)
        #expect(manager.edgeReadyMs != nil)
        #expect(manager.firstArmMs == nil)
        for c in manager.coordinators.values { c.teardown() }
    }
}

extension AppRegressionTests {
    static let regDisplay = DisplaySnapshot(identity: DisplayIdentity(uuid: "reg"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056), menuBarHeight: 24,
                                            menuBarAutoHides: false, isMain: true, backingScale: 1)
    static let otherDisplay = DisplaySnapshot(identity: DisplayIdentity(uuid: "other"), frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                                              visibleFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1056), menuBarHeight: 24,
                                              menuBarAutoHides: false, isMain: false, backingScale: 1)

    func makeCoordinator(_ config: DockConfig, reduceMotion: Bool = false,
                         items: [TileItem] = [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")])
        -> (EdgeDockCoordinator, DockSurroundings, DisplaySnapshot) {
        let display = Self.regDisplay
        let s = DockSurroundings(layout: DisplayLayout(displays: [display]), nativeDock: NativeDockPreferences(),
                                 reduceMotion: reduceMotion)
        let profile = Profile(id: config.profileID, name: "p", items: items)
        let c = EdgeDockCoordinator(config: config, profile: profile, display: display, surroundings: s,
                                    running: RunningAppsMonitor(), icons: IconCache(), clock: ManualClock())
        return (c, s, display)
    }

    /// REG-044: the top-edge zone read the status items once, when the zones were built, so a
    /// status item added later (an app launched) could still trigger the dock.
    @Test("REG-044: top-edge zones follow the status items in the surroundings", .enabled(if: NSScreen.main != nil))
    func reg044() {
        var config = DedockDocument.makeDefault().docks[0]
        config.edge = .top
        config.reveal.spanMode = .wholeEdge
        var (c, s, d) = makeCoordinator(config)
        let first = CGRect(x: 700, y: 1056, width: 30, height: 24)
        let second = CGRect(x: 1100, y: 1056, width: 30, height: 24)
        func clear(_ item: CGRect) -> Bool { c.zones.allSatisfy { $0.rect.maxX <= item.minX || $0.rect.minX >= item.maxX } }
        #expect(!clear(first) && !clear(second))   // nothing excluded yet

        s.statusItems = [d.identity: [first]]
        c.update(config: config, profile: nil, display: d, surroundings: s)
        #expect(clear(first))
        #expect(!clear(second))

        s.statusItems = [d.identity: [second]]
        c.update(config: config, profile: nil, display: d, surroundings: s)
        #expect(clear(second))
        #expect(!clear(first))
        c.teardown()
    }

    /// REG-044 (source): the probe re-reads status items on every check (Space change, app
    /// activation, launch, quit) and reports a change once.
    @Test("REG-044: the probe re-reads status items and reports changes once")
    func reg044Probe() {
        let d = Self.regDisplay
        let windows = WindowFeed([])
        let probe = FullscreenProbe(clock: ManualClock(), layout: { DisplayLayout(displays: [d]) }, windows: { windows.records })
        let changes = Counter()
        probe.onStatusItemsChange = { changes.value += 1 }
        #expect(probe.statusItems[d.identity, default: []].isEmpty)

        // A status item 30 pt wide at x 1500, in CoreGraphics coordinates (top-left origin).
        windows.records = [WindowRecord(ownerPID: 42, layer: StatusItemGeometry.statusLayer, alpha: 1,
                                        bounds: CGRect(x: 1500, y: 0, width: 30, height: 24))]
        probe.check()
        #expect(probe.statusItems[d.identity] == [CGRect(x: 1500, y: 1056, width: 30, height: 24)])
        #expect(changes.value == 1)
        probe.check()
        #expect(changes.value == 1)
        probe.invalidate()
    }

    /// REG-045: a dock that moved to another display kept the first display's full-screen
    /// flag (and so the wrong dwell) until that display's state happened to change.
    @Test("REG-045: moving a dock to another display takes that display's full-screen state",
          .enabled(if: NSScreen.main != nil))
    func reg045() {
        let config = DedockDocument.makeDefault().docks[0]
        var (c, s, d) = makeCoordinator(config)
        let other = Self.otherDisplay
        s.layout = DisplayLayout(displays: [d, other])
        s.fullscreen = [other.identity: true]
        #expect(c.controller.machine.isFullscreen == false)
        c.update(config: config, profile: nil, display: other, surroundings: s)
        #expect(c.controller.machine.isFullscreen == true)
        c.update(config: config, profile: nil, display: d, surroundings: s)
        #expect(c.controller.machine.isFullscreen == false)
        c.teardown()
    }

    /// REG-046: when the reading after the confirmation hold differed from the candidate, the
    /// probe dropped it and waited for another notification that might never come.
    @Test("REG-046: a reading that moves during the hold is re-checked, not dropped")
    func reg046() async {
        let a = Self.regDisplay, b = Self.otherDisplay
        let full = { (x: CGFloat) in WindowRecord(ownerPID: 42, layer: 0, alpha: 1, bounds: CGRect(x: x, y: 0, width: 1920, height: 1080)) }
        let windows = WindowFeed([])
        let clock = ManualClock()
        let probe = FullscreenProbe(clock: clock, layout: { DisplayLayout(displays: [a, b]) }, windows: { windows.records })
        var reported: [[DisplayIdentity: Bool]] = []
        probe.onChange = { reported.append($0) }

        windows.records = [full(0)]                  // candidate: A full screen
        probe.check()
        windows.records = [full(0), full(1920)]      // during the hold B goes full screen too
        await advance(clock, by: .milliseconds(120))
        await advance(clock, by: .milliseconds(120)) // the re-check confirms the new reading
        #expect(probe.states == [a.identity: true, b.identity: true])
        #expect(reported == [[a.identity: true, b.identity: true]])
        probe.invalidate()
    }

    /// REG-047: drop-to-pin accepted any directory and any item named `.app`: packages such as
    /// `.rtfd`, a plain file called `X.app` and an empty `X.app` folder all became tiles.
    @Test("REG-047: only real application bundles and plain folders are pinnable")
    func reg047() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dedock-reg047-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let real = root.appendingPathComponent("Real.app")
        try fm.createDirectory(at: real.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.example.reg047", "CFBundlePackageType": "APPL",
                                   "CFBundleExecutable": "Real", "CFBundleName": "Real"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: real.appendingPathComponent("Contents/Info.plist"))
        try Data().write(to: real.appendingPathComponent("Contents/MacOS/Real"))
        let fakeFile = root.appendingPathComponent("Fake.app")
        try Data("not an app".utf8).write(to: fakeFile)
        let emptyApp = root.appendingPathComponent("Empty.app")
        try fm.createDirectory(at: emptyApp, withIntermediateDirectories: true)
        let rtfd = root.appendingPathComponent("Notes.rtfd")
        try fm.createDirectory(at: rtfd, withIntermediateDirectories: true)
        try Data("{\\rtf1}".utf8).write(to: rtfd.appendingPathComponent("TXT.rtf"))
        let folder = root.appendingPathComponent("Plain")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = root.appendingPathComponent("doc.txt")
        try Data("x".utf8).write(to: document)

        #expect(TileActions.pinKind(real) == .app)
        #expect(TileActions.pinKind(folder) == .folder)
        #expect(TileActions.pinKind(fakeFile) == nil)
        #expect(TileActions.pinKind(emptyApp) == nil)
        #expect(TileActions.pinKind(rtfd) == nil)
        #expect(TileActions.pinKind(document) == nil)
        #expect(TileActions.pinKind(root.appendingPathComponent("missing")) == nil)
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        if fm.fileExists(atPath: calculator.path) { #expect(TileActions.pinKind(calculator) == .app) }
    }

    /// REG-048: a relayout during a reorder drag (a display change, a settings change) left the
    /// drag on its frozen layout, and the drop wrote an order computed against stale geometry.
    @Test("REG-048: a relayout mid-drag cancels the reorder", .enabled(if: NSScreen.main != nil))
    func reg048() throws {
        let config = DedockDocument.makeDefault().docks[0]
        let items = [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator"),
                     TileItem(id: "t2", kind: .app, bundleID: "com.apple.TextEdit")]
        var (c, s, d) = makeCoordinator(config, items: items)
        var reorders: [[TileID]] = []
        c.onReorder = { reorders.append($0) }
        let t1 = try #require(c.layout.tileFrames["t1"]), t2 = try #require(c.layout.tileFrames["t2"])
        let target = CGPoint(x: t2.midX, y: t2.minY + 1)

        c.panel.root.onDragBegan?("t1", CGPoint(x: t1.midX, y: t1.midY))
        c.panel.root.onDragMoved?(target)
        #expect(c.model.draggedTile == "t1")

        // The display shrinks under the drag: a real relayout.
        let smaller = DisplaySnapshot(identity: d.identity, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876), menuBarHeight: 24,
                                      menuBarAutoHides: false, isMain: true, backingScale: 1)
        s.layout = DisplayLayout(displays: [smaller])
        c.update(config: config, profile: Profile(id: config.profileID, name: "p", items: items), display: smaller, surroundings: s)
        #expect(c.model.draggedTile == nil)
        #expect(c.gate.dragInFlight == false)
        #expect(!c.controller.machine.holds.contains(.dragging))

        c.panel.root.onDragEnded?(target)
        #expect(reorders.isEmpty)
        c.teardown()
    }

    /// REG-057: with a corrupt layout.json the recovery alert ran modally before the display
    /// topology and the manager existed: no dock and no `launch.edgeReady` until a click. The
    /// app now posts notices to `LaunchNotices`, which the manager releases once the docks are
    /// live, onto a later main-queue turn. (The app posting rather than presenting is visible in
    /// AppDelegate; this guard pins the hold and the release.)
    @Test("REG-057: launch notices wait for live docks and never show inside setup",
          .enabled(if: NSScreen.main != nil))
    func reg057() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-reg057-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let clock = ManualClock()
        var scheduled: [@MainActor () -> Void] = []
        var shown: [LaunchNotices.Notice] = []
        let notices = LaunchNotices(present: { shown.append($0) }, schedule: { scheduled.append($0) })
        notices.post(.recovered(movedTo: "layout.corrupt.json", fromBackup: false))
        notices.post(.readOnly)
        #expect(scheduled.isEmpty)                      // held: no dock stack yet

        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: .makeDefault())
        let manager = EdgeDockManager(settings: settings, topology: DisplayTopology(clock: clock),
                                      hub: PointerHub(source: SilentPointerSource(), clock: clock),
                                      clock: clock, dataDirectory: dir, notices: notices)
        #expect(manager.edgeReadyMs != nil)
        #expect(shown.isEmpty)                          // never presented inside setup
        #expect(scheduled.count == 2)                   // released after edgeReady, in order
        for work in scheduled { work() }
        #expect(shown == [.recovered(movedTo: "layout.corrupt.json", fromBackup: false), .readOnly])

        notices.post(.readOnly)                         // later notices go straight to the queue
        #expect(scheduled.count == 3)
        for c in manager.coordinators.values { c.teardown() }

        // The notice itself is never modal: `NSAlert.runModal` froze the pointer monitors and the
        // reveal timers until OK. `show()` returns at once with no modal session, and OK closes it.
        var closed: [LaunchNoticePanel] = []
        let notice = LaunchNoticePanel(.recovered(movedTo: "layout.corrupt.json", fromBackup: false)) { closed.append($0) }
        notice.show()
        #expect(notice.panel.isVisible)
        #expect(NSApplication.shared.modalWindow == nil)
        #expect(!notice.panel.isKeyWindow)              // keystrokes stay with the user's app
        #expect(notice.panel.styleMask.contains(.nonactivatingPanel))
        #expect(notice.panel.title == "Your Edge Dock layout was damaged")
        notice.dismiss()
        #expect(!notice.panel.isVisible)
        #expect(closed.count == 1 && closed.first === notice)
    }

    /// REG-058: the REG-046 re-hold had no limit, so a full-display window that keeps flapping
    /// turned the probe into a 120 ms poller. It now stops after `maxReholds` and waits for the
    /// next notification.
    @Test("REG-058: a flapping reading stops re-holding after the cap")
    func reg058() async {
        let a = Self.regDisplay, b = Self.otherDisplay
        let full = { (x: CGFloat) in WindowRecord(ownerPID: 42, layer: 0, alpha: 1, bounds: CGRect(x: x, y: 0, width: 1920, height: 1080)) }
        let reads = Counter()
        let clock = ManualClock()
        // Every read differs from the one before it, and none matches the settled state.
        let probe = FullscreenProbe(clock: clock, layout: { DisplayLayout(displays: [a, b]) }, windows: {
            reads.value += 1
            return reads.value == 1 ? [] : (reads.value % 2 == 0 ? [full(0)] : [full(0), full(1920)])
        })
        var reported = 0
        probe.onChange = { _ in reported += 1 }
        probe.check()
        for _ in 0..<12 { await advance(clock, by: .milliseconds(120)) }
        // The first hold plus `maxReholds` re-holds, two reads each, after the initial read.
        #expect(reads.value == 1 + 2 * (1 + FullscreenProbe.maxReholds))
        #expect(clock.pendingCount == 0)                // no hold left running
        #expect(reported == 0)
        #expect(probe.states == [a.identity: false, b.identity: false])
        probe.check()                                   // a notification starts a fresh cycle
        await advance(clock, by: .milliseconds(120))
        #expect(reads.value > 1 + 2 * (1 + FullscreenProbe.maxReholds))
        probe.invalidate()
    }

    /// REG-059: when folder bookmarks were filled on the first launch, the fill re-entered sync
    /// through the settings observer and the first `docks.sync` line said `reason=settings`,
    /// never `reason=launch`.
    @Test("REG-059: the first sync after a bookmark fill still reports reason=launch",
          .enabled(if: NSScreen.main != nil))
    func reg059() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-reg059-\(UUID().uuidString)")
        let folder = dir.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var doc = DedockDocument.makeDefault()
        doc.profiles[0].items.append(TileItem(id: "fold", kind: .folder, path: folder.path))
        #expect(EdgeDockManager.fillingBookmarks(doc) != nil)   // the launch sync will fill it
        let clock = ManualClock()
        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: doc)
        let manager = EdgeDockManager(settings: settings, topology: DisplayTopology(clock: clock),
                                      hub: PointerHub(source: SilentPointerSource(), clock: clock),
                                      clock: clock, dataDirectory: dir)
        #expect(manager.lastSyncReason == "launch")
        #expect(settings.document.profiles[0].items.last?.bookmark != nil)
        for c in manager.coordinators.values { c.teardown() }
    }

    func advance(_ clock: ManualClock, by d: Duration) async {
        for _ in 0..<100 where clock.pendingCount == 0 { await Task.yield() }
        clock.advance(by: d)
        for _ in 0..<100 { await Task.yield() }
    }

    /// REG-024: zones were not rebuilt when only trigger settings changed (thickness, corners).
    @Test("REG-024: a trigger-only settings change rebuilds the zones", .enabled(if: NSScreen.main != nil))
    func reg024() {
        var config = DedockDocument.makeDefault().docks[0]
        let (c, s, d) = makeCoordinator(config)
        #expect(c.zones.first?.rect.width == 3)
        config.reveal.triggerThicknessPt = 8
        c.update(config: config, profile: Profile(id: config.profileID, name: "p"), display: d, surroundings: s)
        #expect(c.zones.first?.rect.width == 8)
        c.teardown()
    }

    /// REG-025: turning Reduce Motion on (or off) while running did not reach the animator,
    /// which kept sliding (or kept fading).
    @Test("REG-025: a live Reduce Motion toggle switches the animator", .enabled(if: NSScreen.main != nil))
    func reg025() {
        let config = DedockDocument.makeDefault().docks[0]
        var (c, s, d) = makeCoordinator(config, reduceMotion: false)
        #expect(c.animator.reduceMotion == false)
        s.reduceMotion = true
        c.update(config: config, profile: nil, display: d, surroundings: s)
        #expect(c.animator.reduceMotion == true)
        s.reduceMotion = false
        c.update(config: config, profile: nil, display: d, surroundings: s)
        #expect(c.animator.reduceMotion == false)
        c.teardown()
    }
}

/// A KVO-observable object that nothing but its observer holds (REG-021).
final class KVOProbe: NSObject {
    @objc dynamic var value = 0
}

final class Counter: @unchecked Sendable {
    var value = 0
}

/// The on-screen window list a `FullscreenProbe` reads, set by the test.
@MainActor final class WindowFeed {
    var records: [WindowRecord]
    init(_ records: [WindowRecord]) { self.records = records }
}

/// A pointer source that never delivers anything (no real pointer in tests).
@MainActor final class SilentPointerSource: PointerEventSource {
    func install(_ handler: @escaping @MainActor (PointerSample) -> Void) {}
    func uninstall() {}
    var currentLocation: CGPoint { .zero }
    var buttonsDown: Bool { false }
    var currentModifiers: ModifierSet { [] }
}
