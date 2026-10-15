import DedockCore
import Foundation
import Testing
@testable import EdgeDock

@Suite struct FullscreenDetectionTests {
    /// CG coordinates: main 1920×1080 at the origin; an external 2560×1440 to its right, tops aligned.
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let me: Int32 = 100

    func w(_ r: CGRect, pid: Int32 = 200, layer: Int = 0, alpha: Double = 1) -> WindowRecord {
        WindowRecord(ownerPID: pid, layer: layer, alpha: alpha, bounds: r)
    }

    @Test func fullDisplayWindowCounts() {
        #expect(FullscreenDetection.isFullscreen([w(main)], displayFrameCG: main, ownPID: me))
    }

    @Test func maximisedWindowBelowTheMenuBarDoesNot() {
        let maximised = CGRect(x: 0, y: 25, width: 1920, height: 1055)
        #expect(!FullscreenDetection.isFullscreen([w(maximised)], displayFrameCG: main, ownPID: me))
    }

    @Test func onePointRoundingIsTolerated() {
        let almost = CGRect(x: 0.5, y: 0, width: 1919.5, height: 1080)
        #expect(FullscreenDetection.isFullscreen([w(almost)], displayFrameCG: main, ownPID: me))
    }

    @Test func ignoresOwnWindowsOtherLayersAndInvisibleOverlays() {
        #expect(!FullscreenDetection.isFullscreen([w(main, pid: me)], displayFrameCG: main, ownPID: me))
        #expect(!FullscreenDetection.isFullscreen([w(main, layer: 25)], displayFrameCG: main, ownPID: me))
        #expect(!FullscreenDetection.isFullscreen([w(main, alpha: 0)], displayFrameCG: main, ownPID: me))
    }

    @Test func perDisplayStatesUseAppKitToCGConversion() {
        // AppKit: main at origin; external to the right, bottoms aligned (its CG y is 1080 − 1440 = −360).
        let a = DisplaySnapshot(identity: DisplayIdentity(uuid: "a"), frame: main, visibleFrame: main,
                                menuBarHeight: 24, menuBarAutoHides: false, isMain: true)
        let b = DisplaySnapshot(identity: DisplayIdentity(uuid: "b"), frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
                                visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), menuBarHeight: 24, menuBarAutoHides: false)
        let layout = DisplayLayout(displays: [a, b])
        let onB = w(CGRect(x: 1920, y: -360, width: 2560, height: 1440))
        let states = FullscreenDetection.states([onB], layout: layout, ownPID: me)
        #expect(states[a.identity] == false)
        #expect(states[b.identity] == true)
    }
}

@Suite struct StatusItemGeometryTests {
    @Test func keepsStatusLayerWindowsInThisDisplaysMenuBar() {
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "a"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056), menuBarHeight: 24, menuBarAutoHides: false)
        let item = WindowRecord(ownerPID: 1, layer: 25, alpha: 1, bounds: CGRect(x: 1700, y: 0, width: 30, height: 24))   // CG, top
        let normal = WindowRecord(ownerPID: 1, layer: 0, alpha: 1, bounds: CGRect(x: 1700, y: 0, width: 30, height: 24))
        let lowStatus = WindowRecord(ownerPID: 1, layer: 25, alpha: 1, bounds: CGRect(x: 10, y: 500, width: 30, height: 24))
        let rects = StatusItemGeometry.rects([item, normal, lowStatus], display: d, primaryHeight: 1080)
        #expect(rects == [CGRect(x: 1700, y: 1056, width: 30, height: 24)])
    }
}
