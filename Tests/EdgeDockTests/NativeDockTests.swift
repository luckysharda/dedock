import AppKit
import DedockCore
import DedockTestSupport
import Foundation
import Testing
@testable import EdgeDock

@Suite struct NativeDockPreferencesTests {
    @Test func defaultsWhenEmpty() {
        let p = NativeDockPreferences.parse([:])
        #expect(p.orientation == .bottom)
        #expect(!p.autohide)
        #expect(p.tileSize == 48)
        #expect(p.hotCorners == .all) // unknown corners keep the larger exclusion
    }

    @Test func parsesTypicalValues() {
        let p = NativeDockPreferences.parse([
            "orientation": "left", "autohide": true, "tilesize": NSNumber(value: 64),
            "persistent-apps": [1, 2, 3], "persistent-others": [1],
            "wvous-tl-corner": NSNumber(value: 0), "wvous-tr-corner": NSNumber(value: 1),
            "wvous-bl-corner": NSNumber(value: 2), "wvous-br-corner": NSNumber(value: 14),
        ])
        #expect(p.orientation == .left)
        #expect(p.autohide)
        #expect(p.tileSize == 64)
        #expect(p.persistentAppCount == 3)
        #expect(p.persistentOtherCount == 1)
        #expect(p.hotCorners == [.bottomLeft, .bottomRight])
    }

    @Test func autohideAsNumberAndUnknownOrientation() {
        let p = NativeDockPreferences.parse(["autohide": NSNumber(value: 1), "orientation": "top"])
        #expect(p.autohide)
        #expect(p.orientation == .bottom)
    }

    @Test(arguments: [(ScreenEdge.bottom, ScreenEdge.left), (.right, .left), (.left, .right)])
    func recommendedEdge(native: ScreenEdge, expected: ScreenEdge) {
        #expect(NativeDockPreferences.recommendedEdge(nativeDock: native) == expected)
    }

    let display = DisplaySnapshot.make(
        identity: DisplayIdentity(uuid: "M"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 70, width: 1920, height: 985), isMain: true)

    @Test func visibleBottomDockFootprint() throws {
        let prefs = NativeDockPreferences(orientation: .bottom, autohide: false, tileSize: 48,
                                          persistentAppCount: 10, persistentOtherCount: 2)
        let f = try #require(NativeDockPreferences.footprint(prefs: prefs, display: display))
        #expect(f.edge == .bottom)
        #expect(f.thickness == 70)
        let length: CGFloat = 48 * (13 + 2) + 16      // + one tile of margin each side (T27(4))
        #expect(f.span == Interval(960 - length / 2, 960 + length / 2))
        #expect(!f.autohide)
    }

    @Test func autohiddenDockThicknessFromTileSize() throws {
        let hidden = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "M"), frame: display.frame,
                                          visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        let prefs = NativeDockPreferences(orientation: .bottom, autohide: true, tileSize: 48, persistentAppCount: 5)
        let f = try #require(NativeDockPreferences.footprint(prefs: prefs, display: hidden))
        #expect(f.thickness == 64)
        #expect(f.autohide)
    }

    @Test func sideDockFootprintIsAlongY() throws {
        let side = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "M"), frame: display.frame,
                                        visibleFrame: CGRect(x: 0, y: 0, width: 1856, height: 1055))
        let prefs = NativeDockPreferences(orientation: .right, tileSize: 48, persistentAppCount: 4)
        let f = try #require(NativeDockPreferences.footprint(prefs: prefs, display: side))
        #expect(f.edge == .right)
        #expect(f.thickness == 64)
        let length: CGFloat = 48 * (5 + 2) + 16
        #expect(f.span == Interval(540 - length / 2, 540 + length / 2))
    }

    @Test func hugeDockSpanIsClampedToTheEdge() throws {
        let prefs = NativeDockPreferences(orientation: .bottom, tileSize: 128, persistentAppCount: 40)
        let f = try #require(NativeDockPreferences.footprint(prefs: prefs, display: display))
        #expect(f.span == Interval(0, 1920))
    }
}


/// T27: health and recovery (macOS only).
@Suite @MainActor struct HealthRecoveryTests {
    final class FakeWindow {
        var visible = true
        var onSpace = false
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        var behaviors: [NSWindow.CollectionBehavior] = []
        var rebuilds = 0
        /// Becomes on-Space after this many behaviour flips (nil = never).
        var fixAfterFlips: Int?
        var window: SpaceMembershipRepair.Window {
            .init(isVisible: { self.visible }, isOnActiveSpace: { self.onSpace }, behavior: { self.behavior },
                  setBehavior: { b in
                      self.behavior = b
                      self.behaviors.append(b)
                      if let n = self.fixAfterFlips, self.behaviors.count >= n { self.onSpace = true }
                  },
                  rebuild: { self.rebuilds += 1 })
        }
    }

    func settle(_ clock: ManualClock, _ repair: SpaceMembershipRepair) async {
        for _ in 0..<40 {
            for _ in 0..<50 where clock.pendingCount == 0 && repair.isRepairing { await Task.yield() }
            guard repair.isRepairing else { return }
            clock.advance(by: SpaceMembershipRepair.turn)
            for _ in 0..<20 { await Task.yield() }
        }
    }

    @Test func onTheActiveSpaceNothingHappens() async {
        let w = FakeWindow()
        w.onSpace = true
        let clock = ManualClock()
        let repair = SpaceMembershipRepair(window: w.window, clock: clock, edge: "left")
        repair.check(reason: "space")
        #expect(!repair.isRepairing && w.behaviors.isEmpty)
        w.onSpace = false
        w.visible = false                              // ordered out: nothing to repair
        repair.check(reason: "space")
        #expect(!repair.isRepairing)
    }

    @Test func aFlipAndRestoreReattachesThePanel() async {
        let w = FakeWindow()
        w.fixAfterFlips = 2                            // fixed by the first flip-and-restore
        let clock = ManualClock()
        let repair = SpaceMembershipRepair(window: w.window, clock: clock, edge: "left")
        let original = w.behavior
        repair.check(reason: "fullscreenExit")
        await settle(clock, repair)
        #expect(w.onSpace)
        #expect(w.behaviors.count == 2 && w.behaviors[0] != original && w.behaviors[1] == original)
        #expect(w.behavior == original)                // always restored
        #expect(w.rebuilds == 0)
    }

    @Test func threeFailedAttemptsRebuildThePanel() async {
        let w = FakeWindow()                           // never comes back by itself
        let clock = ManualClock()
        let repair = SpaceMembershipRepair(window: w.window, clock: clock, edge: "left")
        repair.check(reason: "wake")
        await settle(clock, repair)
        #expect(w.behaviors.count == 2 * SpaceMembershipRepair.attempts)
        #expect(w.rebuilds == 1)
        #expect(!repair.isRepairing)
    }

    @Test func aDockRelaunchIsReportedEvenWithUnchangedPreferences() {
        var changes = 0, relaunches = 0
        let reader = DockPreferencesReader { _ in changes += 1 }
        reader.onRelaunch = { relaunches += 1 }
        reader.dockRelaunched()
        #expect(relaunches == 1)
        #expect(changes == 0)                          // the preferences did not change
        reader.invalidate()
    }
}
