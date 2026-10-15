import DedockCore
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
        let length: CGFloat = 48 * 13 + 16
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
        let length: CGFloat = 48 * 5 + 16
        #expect(f.span == Interval(540 - length / 2, 540 + length / 2))
    }

    @Test func hugeDockSpanIsClampedToTheEdge() throws {
        let prefs = NativeDockPreferences(orientation: .bottom, tileSize: 128, persistentAppCount: 40)
        let f = try #require(NativeDockPreferences.footprint(prefs: prefs, display: display))
        #expect(f.span == Interval(0, 1920))
    }
}
