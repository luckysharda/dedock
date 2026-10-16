import DedockCore
import Foundation
import AppKit
import DedockTestSupport
import DisplayTopology
import EventTapKit
import SettingsStore
import Testing
@testable import EdgeDock

/// Regression guards for settings → dock mapping (macOS: the mapping lives in the AppKit module).
@Suite("Regression", .tags(.regression)) struct MappingRegressionTests {
    /// REG-035: hysteresis allowed 0–64 pt (spec 0–40) and dwell/delay values were not clamped
    /// to 0–5 s, so a hand-edited or seeded layout.json could set out-of-range timings.
    @Test("REG-035: trigger and timing values are clamped to their spec ranges")
    func reg035() {
        var d = DedockDocument.makeDefault().docks[0]
        d.reveal.hysteresisPt = 64
        d.reveal.showDwellMs = 99_000
        d.reveal.hideDelayMs = -5
        d.reveal.fullscreenDwellMs = 7000
        d.reveal.pushThroughPt = 1000
        let p = d.triggerParameters
        let c = d.revealConfig(reduceMotion: false)
        #expect(p.hysteresis == 40)
        #expect(p.pushThrough == 200)
        #expect(c.showDwell == .seconds(5))
        #expect(c.hideDelay == .zero)
        #expect(c.fullscreenDwell == .seconds(5))
        d.reveal.pushThroughPt = 2
        #expect(d.triggerParameters.pushThrough == 16)
        d.reveal.pushThroughPt = nil
        #expect(d.triggerParameters.pushThrough == nil)
    }
}

/// Regression guards for the dock manager and tile menu (macOS only).
@Suite("Regression", .tags(.regression), .serialized) @MainActor struct ManagerRegressionTests {
    /// REG-033: the context menu's "Open" launched the app directly, skipping the explicit hide
    /// and the re-arm cooldown that a click applies.
    @Test("REG-033: context-menu Open takes the click path")
    func reg033() {
        var opened = 0
        let menu = TileMenu(tile: TileModel(id: "a", kind: .app, name: "A", bundleID: "com.example.a"),
                            open: { opened += 1 }, remove: {})
        menu.open()
        #expect(opened == 1)
    }

    /// REG-032: the pointer monitors ran (and woke the app on every mouse move) with zero
    /// enabled docks.
    @Test("REG-032: pointer monitors run only while a dock is enabled", .enabled(if: NSScreen.main != nil))
    func reg032() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dedock-reg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        var doc = DedockDocument.makeDefault()
        doc.docks[0].enabled = false
        let clock = ManualClock()
        let settings = SettingsModel(file: LayoutFile(directory: dir), clock: clock, document: doc)
        let hub = PointerHub(source: QuietPointerSource(), clock: clock)
        let manager = EdgeDockManager(settings: settings, topology: DisplayTopology(clock: clock), hub: hub,
                                      clock: clock, dataDirectory: dir)
        #expect(!hub.isRunning)
        settings.update { $0.docks[0].enabled = true }
        #expect(hub.isRunning)
        settings.update { $0.docks[0].enabled = false }
        #expect(!hub.isRunning)
        #expect(manager.coordinators.isEmpty)
    }
}

/// A pointer source that never delivers anything (no real pointer in tests).
@MainActor final class QuietPointerSource: PointerEventSource {
    func install(_ handler: @escaping @MainActor (PointerSample) -> Void) {}
    func uninstall() {}
    var currentLocation: CGPoint { .zero }
    var buttonsDown: Bool { false }
    var currentModifiers: ModifierSet { [] }
}

@Suite("Regression", .tags(.regression)) @MainActor struct BookmarkRegressionTests {
    /// REG-031: folder tiles used the path only, ignoring the bookmark, and a tile seeded with a
    /// path never got its bookmark filled in.
    @Test("REG-031: folder tiles resolve the bookmark first and get one filled on save")
    func reg031() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dedock-reg031-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let original = root.appendingPathComponent("Original", isDirectory: true)
        try fm.createDirectory(at: original, withIntermediateDirectories: true)
        let bookmark = try original.bookmarkData()
        let moved = root.appendingPathComponent("Moved", isDirectory: true)
        try fm.moveItem(at: original, to: moved)

        // The path is stale; the bookmark follows the move.
        let item = TileItem(id: "f", kind: .folder, path: original.path, bookmark: bookmark)
        #expect(item.tileModel.url?.standardizedFileURL.resolvingSymlinksInPath().path
                == moved.standardizedFileURL.resolvingSymlinksInPath().path)

        // A path-only folder gets a bookmark; a document with nothing missing is left alone.
        var doc = DedockDocument.makeDefault()
        doc.profiles[0].items.append(TileItem(id: "p", kind: .folder, path: moved.path))
        let filled = try #require(EdgeDockManager.fillingBookmarks(doc))
        #expect(filled.profiles[0].items.last?.bookmark != nil)
        #expect(EdgeDockManager.fillingBookmarks(filled) == nil)
    }
}

extension MappingRegressionTests {
    /// REG-062: Scenario.apply stored edge-derived values (300 ms for Reveal at Top, 6 pt beside
    /// the native Dock) in layout.json. A later edge change only marked the dock Custom, so
    /// Top → Left kept a 300 ms dwell. The values are now derived from the edge at mapping time.
    @Test("REG-062: edge-derived dwell and trigger thickness follow the current edge")
    func reg062() {
        let base = DedockDocument.makeDefault().docks[0]
        var dock = Scenario.revealTop.apply(to: base)
        #expect(dock.revealConfig(reduceMotion: false).showDwell == .milliseconds(300))   // top: derived 300

        dock.edge = .left                       // status menu / EdgePicker / setEdge
        dock.markCustom()
        #expect(dock.revealConfig(reduceMotion: false).showDwell == .milliseconds(120))
        #expect(dock.triggerParameters(nativeDockEdge: .bottom).thickness == 3)

        // Beside the native Dock the zone is thicker, derived; moving away drops it again.
        var bottom = Scenario.revealBottom.apply(to: base)
        #expect(bottom.reveal.triggerThicknessPt == 3)                                    // stored default
        #expect(bottom.triggerParameters(nativeDockEdge: .bottom).thickness == 6)
        bottom.edge = .right
        #expect(bottom.triggerParameters(nativeDockEdge: .bottom).thickness == 3)
    }
}

@Suite @MainActor struct DockStyleMappingTests {
    /// The dock's `dd.dock.style` picks the capsule material; the system appearance only picks
    /// the label colours (design.md §7.1: the style is chosen apart from Light / Dark).
    @Test func styleAndAppearanceMapToTokens() {
        var config = DedockDocument.makeDefault().docks[0]
        #expect(config.tokens(lightAppearance: false, reduceTransparency: false).style == .darkGlass)
        config.appearance.style = .black
        #expect(config.tokens(lightAppearance: false, reduceTransparency: false).style == .black)
        config.appearance.style = .lightGlass
        let light = config.tokens(lightAppearance: false, reduceTransparency: false)
        #expect(light.style == .lightGlass)
        #expect(light.blurMaterial == .popover)
        #expect(config.tokens(lightAppearance: false, reduceTransparency: true).blurMaterial == nil)

        // Light / Dark changes the label, not the style.
        config.appearance.style = .darkGlass
        let dark = config.tokens(lightAppearance: false, reduceTransparency: false)
        let aqua = config.tokens(lightAppearance: true, reduceTransparency: false)
        #expect(aqua.style == .darkGlass)
        #expect(dark.labelText != aqua.labelText)
        #expect(dark.labelFill != aqua.labelFill)
    }

    /// A style change logs `settings.changed key=dd.dock.style value=<style>` (E2E contract).
    @Test func styleChangeIsReportedOnce() {
        let old = DedockDocument.makeDefault()
        var new = old
        #expect(EdgeDockManager.settingChanges(from: old, to: new).isEmpty)
        new.docks[0].appearance.style = .lightGlass
        let changes = EdgeDockManager.settingChanges(from: old, to: new)
        #expect(changes.count == 1)
        #expect(changes.first?.key == "dd.dock.style")
        #expect(changes.first?.value == "lightGlass")
        #expect(changes.first?.scenario == old.docks[0].scenario)
        new.docks[0].appearance.size = .l          // other keys are not reported here
        new.docks[0].appearance.style = old.docks[0].appearance.style
        #expect(EdgeDockManager.settingChanges(from: old, to: new).isEmpty)
    }

    @Test func geometryNamesTheCapsuleMaterial() {
        #expect(EdgeDockManager.materialName(.hudWindow) == "hudWindow")
        #expect(EdgeDockManager.materialName(.popover) == "popover")
        #expect(EdgeDockManager.materialName(nil) == "solid")
    }

    /// VoiceOver reads a window's AXTitle, so the borderless panel carries one too.
    @Test(.enabled(if: NSScreen.main != nil)) func panelIsTitledEdgeDock() {
        let model = DockViewModel(tokens: DedockDocument.makeDefault().docks[0].tokens, icons: IconCache())
        let panel = EdgeDockPanel(frame: CGRect(x: 0, y: 0, width: 78, height: 400), model: model)
        defer { panel.close() }
        #expect(panel.title == "Edge Dock")
    }
}

/// T38 display fallback and D2 Hello reveal (macOS only).
@Suite(.serialized) @MainActor struct DisplayFallbackTests {
    static func display(_ uuid: String, x: CGFloat, id: UInt32, main: Bool = false, builtin: Bool = false) -> DisplaySnapshot {
        DisplaySnapshot(identity: DisplayIdentity(uuid: uuid), displayID: id, frame: CGRect(x: x, y: 0, width: 1920, height: 1080),
                        visibleFrame: CGRect(x: x, y: 0, width: 1920, height: 1056), menuBarHeight: 24,
                        menuBarAutoHides: false, isBuiltin: builtin, isMain: main, backingScale: 1)
    }

    @Test func bindingFallsBackAndReturns() {
        let main = Self.display("M", x: 0, id: 1, main: true)
        let air = Self.display("AIR", x: 1920, id: 7)
        let bound = DisplayBinding(role: .identity, identity: "AIR", fallbackToBuiltin: true)
        #expect(EdgeDockManager.resolveDisplay(bound, in: DisplayLayout(displays: [main, air]))?.identity.uuid == "AIR")
        // Disconnected, and this Mac has no built-in display: the main display.
        #expect(EdgeDockManager.resolveDisplay(bound, in: DisplayLayout(displays: [main]))?.identity.uuid == "M")
        // With a built-in display, that one.
        let builtin = Self.display("BI", x: -1512, id: 3, builtin: true)
        #expect(EdgeDockManager.resolveDisplay(bound, in: DisplayLayout(displays: [main, builtin]))?.identity.uuid == "BI")
        // Reconnected: back on it.
        #expect(EdgeDockManager.resolveDisplay(bound, in: DisplayLayout(displays: [main, air]))?.identity.uuid == "AIR")
        // No fallback wanted: no dock.
        var strict = bound
        strict.fallbackToBuiltin = false
        #expect(EdgeDockManager.resolveDisplay(strict, in: DisplayLayout(displays: [main])) == nil)
        #expect(EdgeDockManager.resolveDisplay(DisplayBinding(role: .main), in: DisplayLayout(displays: [main, air]))?.identity.uuid == "M")
    }

    @Test func bindDisplayAcceptsOnlyMainOrANumber() {
        #expect(DebugCommand.parse("bindDisplay=main") == .bindDisplay(.main))
        #expect(DebugCommand.parse("bindDisplay=7") == .bindDisplay(.id(7)))
        #expect(DebugCommand.parse("bindDisplay=") == nil)
        #expect(DebugCommand.parse("bindDisplay=-1") == nil)
        #expect(DebugCommand.parse("bindDisplay=7x") == nil)
        #expect(DebugCommand.parse("bindDisplay=99999999999") == nil)    // beyond UInt32
        #expect(DebugCommand.parse("bindDisplay=١") == nil)              // non-ASCII digit
        #expect(DebugCommand.parse("bindDisplay") == nil)
    }

    func coordinator(clock: ManualClock) -> (EdgeDockCoordinator, DockSurroundings, DisplaySnapshot, DisplaySnapshot) {
        let config = DedockDocument.makeDefault().docks[0]
        let main = Self.display("M", x: 0, id: 1, main: true), air = Self.display("AIR", x: 1920, id: 7)
        let s = DockSurroundings(layout: DisplayLayout(displays: [main, air]), nativeDock: NativeDockPreferences(), reduceMotion: false)
        let profile = Profile(id: config.profileID, name: "p", items: [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")])
        let c = EdgeDockCoordinator(config: config, profile: profile, display: main, surroundings: s,
                                    running: RunningAppsMonitor(), icons: IconCache(), clock: clock)
        return (c, s, main, air)
    }

    func finishAnimation(_ c: EdgeDockCoordinator) {
        if let g = c.controller.machine.activeGeneration { c.controller.send(.animationFinished(generation: g)) }
    }

    func advance(_ clock: ManualClock, _ d: Duration) async {
        for _ in 0..<100 where clock.pendingCount == 0 { await Task.yield() }
        clock.advance(by: d)
        for _ in 0..<100 { await Task.yield() }
    }

    func move(_ c: EdgeDockCoordinator, to d: DisplaySnapshot, _ s: DockSurroundings) {
        c.update(config: c.config, profile: nil, display: d, surroundings: s)
    }

    /// D2: after a move, the display set settles 1 s, then one reveal, a 1.0 s hold, a hide.
    @Test(.enabled(if: NSScreen.main != nil)) func helloRevealOnTheNewDisplay() async {
        let clock = ManualClock()
        let (c, s, _, air) = coordinator(clock: clock)
        move(c, to: air, s)
        #expect(c.phase == .hidden)                       // waiting for the display set to settle
        await advance(clock, .milliseconds(1000))
        #expect(c.phase == .revealing)
        finishAnimation(c)
        await advance(clock, .milliseconds(900))
        #expect(c.phase == .shown)
        await advance(clock, .milliseconds(150))
        #expect(c.phase == .hiding)
        c.teardown()
    }

    /// D2: two moves 300 ms apart give one hello, 1 s after the second.
    @Test(.enabled(if: NSScreen.main != nil)) func flappingDisplaysGiveOneHello() async {
        let clock = ManualClock()
        let (c, s, main, air) = coordinator(clock: clock)
        move(c, to: air, s)
        await advance(clock, .milliseconds(300))
        move(c, to: main, s)
        await advance(clock, .milliseconds(700))
        #expect(c.phase == .hidden)                       // the first one was superseded
        await advance(clock, .milliseconds(300))
        #expect(c.phase == .revealing)
        c.teardown()
    }

    /// D2: at most one hello per 10 s.
    @Test(.enabled(if: NSScreen.main != nil)) func oneHelloPerTenSeconds() async {
        let clock = ManualClock()
        let (c, s, main, air) = coordinator(clock: clock)
        move(c, to: air, s)
        await advance(clock, .milliseconds(1000))
        finishAnimation(c)
        await advance(clock, .milliseconds(1000))         // hold over: hiding
        if let g = c.controller.machine.activeGeneration { c.controller.send(.animationFinished(generation: g)) }
        #expect(c.phase == .hidden)
        move(c, to: main, s)                              // 2 s after the first hello
        await advance(clock, .milliseconds(1000))
        #expect(c.helloSkipReason() == "rateLimit" && c.phase == .hidden)
        await advance(clock, .milliseconds(8000))         // > 10 s since the first
        move(c, to: air, s)
        await advance(clock, .milliseconds(1000))
        #expect(c.phase == .revealing)
        c.teardown()
    }

    /// D2: skipped while away, on a full-screen Space, in Pinned mode, or when already shown.
    @Test(.enabled(if: NSScreen.main != nil)) func helloSkips() async {
        let clock = ManualClock()
        var (c, s, main, air) = coordinator(clock: clock)
        c.helloAllowed = { false }                        // locked or screens asleep
        move(c, to: air, s)
        await advance(clock, .milliseconds(1100))
        #expect(c.phase == .hidden && c.helloSkipReason() == "away")
        c.teardown()

        (c, s, main, air) = coordinator(clock: ManualClock())
        s.fullscreen = [air.identity: true]
        #expect(c.helloSkipReason() == nil)
        c.update(config: c.config, profile: nil, display: air, surroundings: s)
        #expect(c.helloSkipReason() == "fullscreen")
        c.teardown()

        (c, s, main, air) = coordinator(clock: ManualClock())
        c.controller.send(.hold(.pinnedByUser, true))     // Keep Open
        #expect(c.helloSkipReason() == "shown")
        c.teardown()

        (c, s, main, air) = coordinator(clock: ManualClock())
        var pinned = c.config
        pinned.mode = .pinned
        c.update(config: pinned, profile: nil, display: main, surroundings: s)
        #expect(c.helloSkipReason() == "pinned")
        c.teardown()
    }

    /// D2: if the pointer is on the dock when the hold ends, it stays.
    @Test(.enabled(if: NSScreen.main != nil)) func helloKeepsTheDockWhenThePointerIsOnIt() async {
        let clock = ManualClock()
        let (c, s, _, air) = coordinator(clock: clock)
        move(c, to: air, s)
        await advance(clock, .milliseconds(1000))
        finishAnimation(c)
        let cap = c.capsuleFrame
        c.pointer(PointerSample(location: CGPoint(x: cap.midX, y: cap.midY), timestamp: .milliseconds(100)))
        await advance(clock, .milliseconds(1100))
        #expect(c.phase == .shown)
        c.teardown()
    }
}
