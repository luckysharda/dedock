import DedockCore
import Foundation
import AppKit
import DedockTestSupport
import DesignSystem
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

/// T25 rolled-in M1 rows 10, 20 and 27 (macOS only).
@Suite(.serialized) @MainActor struct T25RowTests {
    /// Row 10: the label sits toward the screen centre on every edge, beside its tile.
    @Test func labelLaneFacesTheScreenCentre() {
        let t = DockTokens.capsule()
        let tile = CGRect(x: 100, y: 300, width: 62, height: 54)
        let left = DockViewModel.labelLane(for: tile, capsule: CGRect(x: 92, y: 100, width: 78, height: 400), edge: .left, tokens: t)
        #expect(left.minX == CGFloat(170 + 10) && abs(left.midY - tile.midY) < 0.5)
        let right = DockViewModel.labelLane(for: tile, capsule: CGRect(x: 92, y: 100, width: 78, height: 400), edge: .right, tokens: t)
        #expect(right.maxX == CGFloat(92 - 10))
        let bottom = DockViewModel.labelLane(for: tile, capsule: CGRect(x: 0, y: 0, width: 400, height: 78), edge: .bottom, tokens: t)
        #expect(bottom.minY == CGFloat(78 + 10) && abs(bottom.midX - tile.midX) < 0.5)
        let top = DockViewModel.labelLane(for: tile, capsule: CGRect(x: 0, y: 500, width: 400, height: 78), edge: .top, tokens: t)
        #expect(top.maxY == CGFloat(500 - 10))
    }

    /// Row 10 (H4): the name, then the state.
    @Test func labelSaysNameAndState() {
        var app = TileModel(id: "a", kind: .app, name: "Calculator", bundleID: "com.apple.calculator")
        let idle = TileLabelContent(app)
        #expect(idle.name == "Calculator" && idle.state == "Not running" && !idle.running)
        app.running = .running
        app.windowCount = 2
        #expect(TileLabelContent(app).state == "Running \u{00B7} 2 windows" && TileLabelContent(app).running)
        app.windowCount = 1
        #expect(TileLabelContent(app).state == "Running \u{00B7} 1 window")
        app.running = .hidden
        app.windowCount = nil
        #expect(TileLabelContent(app).state == "Hidden" && !TileLabelContent(app).running)
        #expect(TileLabelContent(TileModel(id: "f", kind: .folder, name: "Downloads")).state == "Folder")
        #expect(TileLabelContent(TileModel(id: "s", kind: .separator, name: "")).state == nil)
    }

    func shownCoordinator(_ items: [TileItem]) -> (EdgeDockCoordinator, DockSurroundings, DisplaySnapshot) {
        let config = DedockDocument.makeDefault().docks[0]
        let made = AppRegressionTests().makeCoordinator(config, items: items)
        let c = made.0
        c.controller.send(.command(.reveal))
        if let g = c.controller.machine.activeGeneration { c.controller.send(.animationFinished(generation: g)) }
        return made
    }

    /// Row 10: the label appears on the same sample the pointer reaches a tile (no delay), and its
    /// state line carries the window count.
    @Test(.enabled(if: NSScreen.main != nil)) func hoverIsInstantWithLiveState() throws {
        let (c, _, _) = shownCoordinator([TileItem(id: "fin", kind: .app, bundleID: "com.apple.finder")])
        #expect(c.phase == .shown)
        c.windowCounter = { _ in 3 }
        let f = try #require(c.layout.tileFrames["fin"])
        c.pointer(PointerSample(location: CGPoint(x: f.midX, y: f.midY), timestamp: .milliseconds(10)))
        #expect(c.model.hoveredTile == "fin")
        let tile = try #require(c.model.tiles.first)
        #expect(TileLabelContent(tile).state == "Running \u{00B7} 3 windows")   // Finder always runs
        c.teardown()
    }

    /// Row 20: moving the pointer through the zone and over the shown dock never relayouts.
    @Test(.enabled(if: NSScreen.main != nil)) func noRelayoutWhileThePointerMoves() {
        let (c, _, _) = shownCoordinator([TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator"),
                                          TileItem(id: "t2", kind: .app, bundleID: "com.apple.TextEdit")])
        let passes = c.layoutPasses
        let cap = c.capsuleFrame
        for i in 0..<200 {
            let y = cap.minY + CGFloat(i % 50) * cap.height / 50
            let x = i < 100 ? CGFloat(1) : cap.midX
            c.pointer(PointerSample(location: CGPoint(x: x, y: y), timestamp: .milliseconds(i * 8)))
        }
        #expect(c.layoutPasses == passes)
        c.teardown()
    }

    /// Row 27: each stop scales tiles, gaps and padding together.
    @Test func sizeStopsScaleTheWholeDock() {
        let expected: [(DockTokens.Size, CGFloat)] = [(.s, 48), (.m, 62), (.l, 76), (.xl, 92)]
        for (size, tile) in expected {
            let t = DockTokens.capsule(size)
            #expect(t.tileThickness == tile)
            #expect(abs(t.padding - 8 * tile / 62) < 0.001 && abs(t.gap - 8 * tile / 62) < 0.001)
        }
        #expect(DockTokens.Size.nearest(toTile: 70) == .l)
        #expect(DockTokens.Size.nearest(toTile: 54) == .s)
        #expect(DockTokens.capsule(tile: 200).tileThickness == 92)       // clamped to the range
    }

    /// Row 27: while the slider is dragged the dock follows (a relayout per change), and the
    /// editing hold keeps it shown.
    @Test(.enabled(if: NSScreen.main != nil)) func sizePreviewRelayoutsUnderTheEditingHold() {
        var config = DedockDocument.makeDefault().docks[0]
        let (c, s, d) = shownCoordinator([TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")])
        c.controller.send(.hold(.editing, true))
        let before = c.capsuleFrame
        config.appearance.liveTilePt = 85
        c.update(config: config, profile: Profile(id: config.profileID, name: "p", items: [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")]),
                 display: d, surroundings: s)
        #expect(c.capsuleFrame != before)
        #expect(c.model.tokens.tileThickness == 85)
        #expect(c.phase == .shown)
        c.teardown()
    }
}

/// T25(5): the M1 criteria values, pinned (evaluation rows 23, 24, 26, 28, 34).
@Suite(.serialized) @MainActor struct M1PinTests {
    /// Row 23: the hide delay defaults to 400 ms.
    @Test func hideDelayDefaultsTo400ms() {
        #expect(RevealSettings().hideDelayMs == 400)
        #expect(DedockDocument.makeDefault().docks[0].revealConfig(reduceMotion: false).hideDelay == .milliseconds(400))
    }

    /// Rows 24 and 26: the zone thickness is clamped to 1–20 pt and the edge inset to 0–48 pt.
    @Test func zoneAndInsetClamps() {
        var d = DedockDocument.makeDefault().docks[0]
        d.reveal.triggerThicknessPt = 0
        #expect(d.triggerParameters.thickness == 1)
        d.reveal.triggerThicknessPt = 50
        #expect(d.triggerParameters.thickness == 20)
        d.placement.edgeGapPt = -5
        #expect(d.tokens(lightAppearance: false, reduceTransparency: false).edgeGap == 0)
        d.placement.edgeGapPt = 100
        #expect(d.tokens(lightAppearance: false, reduceTransparency: false).edgeGap == 48)
    }

    /// Row 34: the popoverOpen and pinnedByUser holds keep the dock shown when the pointer leaves.
    @Test(arguments: [HoldOpenToken.popoverOpen, .pinnedByUser])
    func holdsKeepTheDockShown(token: HoldOpenToken) {
        var m = RevealStateMachine()
        _ = m.handle(.zoneEntered(.wall), progress: 0)
        _ = m.handle(.timerFired(.dwell), progress: 0)
        _ = m.handle(.animationFinished(generation: m.activeGeneration!), progress: 1)
        _ = m.handle(.hold(token, true), progress: 1)
        _ = m.handle(.zoneLeft, progress: 1)
        let effects = m.handle(.pointerInside(false), progress: 1)
        #expect(m.phase == .shown)
        #expect(!effects.contains { if case .startTimer(.hide, _) = $0 { true } else { false } })
        _ = m.handle(.hold(token, false), progress: 1)
        #expect(m.phase == .armingHide)                  // released: the normal hide starts
    }

    /// Row 28: the panel stays at its fixed frame; only its content moves when revealing.
    @Test(.enabled(if: NSScreen.main != nil)) func panelFrameIsFixedWhileRevealing() {
        let config = DedockDocument.makeDefault().docks[0]
        let (c, _, _) = AppRegressionTests().makeCoordinator(config)
        let frame = c.panel.frame
        #expect(frame == c.layout.panelFrame)
        c.controller.send(.command(.reveal))
        #expect(c.panel.frame == frame)
        if let g = c.controller.machine.activeGeneration { c.controller.send(.animationFinished(generation: g)) }
        #expect(c.panel.frame == frame)
        c.controller.send(.command(.hide(explicit: true)))
        #expect(c.panel.frame == frame)
        c.teardown()
    }
}

/// T26 separators and spacers, SP3 Islands: separate capsules that behave as one dock (macOS).
@Suite(.serialized) @MainActor struct IslandTests {
    @Test func fillersAreHiddenFromAccessibility() {
        #expect(TileAccessibilitySpec(TileModel(id: "s", kind: .separator, name: "")).hidden)
        #expect(TileAccessibilitySpec(TileModel(id: "p", kind: .spacer, name: "")).hidden)
        #expect(TileModel(id: "p", kind: .spacer, name: "").isFiller)
        #expect(TileItem(id: "p", kind: .spacer).tileSpec.shape == .spacer)
        #expect(TileItem(id: "p", kind: .spacer).tileModel.kind == .spacer)
    }

    @Test(.enabled(if: NSScreen.main != nil)) func islandsDrawSeparatelyButActAsOneDock() throws {
        let config = DedockDocument.makeDefault().docks[0]
        let items = [TileItem(id: "a", kind: .app, bundleID: "com.apple.calculator"),
                     TileItem(id: "s", kind: .separator),
                     TileItem(id: "b", kind: .app, bundleID: "com.apple.TextEdit")]
        let (c, _, _) = AppRegressionTests().makeCoordinator(config, items: items)
        #expect(c.layout.islands.count == 2)
        #expect(c.panel.root.capsules.count == 2)                          // two capsules drawn
        // The gap between the islands: inside the one dock, but no tile there.
        let sep = try #require(c.layout.tileFrames["s"])
        let gap = CGPoint(x: sep.midX, y: sep.midY)
        #expect(c.capsuleFrame.contains(gap))
        #expect(c.model.tile(atScreen: gap) == nil)
        c.controller.send(.command(.reveal))
        if let g = c.controller.machine.activeGeneration { c.controller.send(.animationFinished(generation: g)) }
        #expect(c.gate.accepts(gap))                                       // one click-through region
        c.teardown()
    }
}
