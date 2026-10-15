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
    @Test("REG-021: observed apps are held and still alive across refreshes")
    func reg021() {
        let monitor = RunningAppsMonitor()
        monitor.refresh()
        monitor.refresh()
        for app in monitor.watchedApps {
            #expect(!app.isTerminated)
            #expect(app.activationPolicy != .regular)
        }
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
    func makeCoordinator(_ config: DockConfig, reduceMotion: Bool = false) -> (EdgeDockCoordinator, DockSurroundings, DisplaySnapshot) {
        let display = DisplaySnapshot(identity: DisplayIdentity(uuid: "reg"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                      visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056), menuBarHeight: 24,
                                      menuBarAutoHides: false, isMain: true, backingScale: 1)
        let s = DockSurroundings(layout: DisplayLayout(displays: [display]), nativeDock: NativeDockPreferences(),
                                 reduceMotion: reduceMotion)
        let profile = Profile(id: config.profileID, name: "p", items: [TileItem(id: "t1", kind: .app, bundleID: "com.apple.calculator")])
        let c = EdgeDockCoordinator(config: config, profile: profile, display: display, surroundings: s,
                                    running: RunningAppsMonitor(), icons: IconCache(), clock: ManualClock())
        return (c, s, display)
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

/// A pointer source that never delivers anything (no real pointer in tests).
@MainActor final class SilentPointerSource: PointerEventSource {
    func install(_ handler: @escaping @MainActor (PointerSample) -> Void) {}
    func uninstall() {}
    var currentLocation: CGPoint { .zero }
    var buttonsDown: Bool { false }
    var currentModifiers: ModifierSet { [] }
}
