import DedockCore
import Foundation
import Testing
@testable import DisplayTopology

@Suite struct DisplaySnapshotDerivationTests {
    let id = DisplayIdentity(uuid: "A")

    @Test func menuBarShown() {
        let s = DisplaySnapshot.make(identity: id, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        #expect(s.menuBarHeight == 25)
        #expect(!s.menuBarAutoHides)
        #expect(s.notch == nil)
    }

    @Test func menuBarAutoHiddenUsesStatusBarThickness() {
        let s = DisplaySnapshot.make(identity: id, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), statusBarThickness: 24)
        #expect(s.menuBarAutoHides)
        #expect(s.menuBarHeight == 24)
    }

    @Test func notchedDisplay() throws {
        // 14" MacBook Pro: 1512 × 982, safe area 32, auxiliary areas either side of a 200 pt notch.
        let s = DisplaySnapshot.make(
            identity: id, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            safeAreaTop: 32, statusBarThickness: 24,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRight: CGRect(x: 856, y: 950, width: 656, height: 32),
            isBuiltin: true)
        #expect(s.menuBarHeight == 33)
        let notch = try #require(s.notch)
        #expect(notch == CGRect(x: 656, y: 950, width: 200, height: 32))
    }

    @Test func notchedDisplayWithAutoHidingMenuBarUsesSafeArea() {
        let s = DisplaySnapshot.make(
            identity: id, frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32, statusBarThickness: 24)
        #expect(s.menuBarHeight == 32)
    }
}

@Suite struct DisplayLayoutTests {
    let builtin = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "B"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                       visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055), isBuiltin: true, isMain: true)
    let external = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "E"), frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
                                        visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1415))

    @Test func displayContainingPointIncludesMaxEdges() {
        let layout = DisplayLayout(displays: [builtin, external])
        #expect(layout.display(containing: CGPoint(x: 0, y: 0))?.identity.uuid == "B")
        #expect(layout.display(containing: CGPoint(x: 1919.5, y: 500))?.identity.uuid == "B")
        #expect(layout.display(containing: CGPoint(x: 1920, y: 500))?.identity.uuid == "E")
        // Far right edge and top edge of the external (where a clamped cursor can sit).
        #expect(layout.display(containing: CGPoint(x: 4480, y: 1440))?.identity.uuid == "E")
        // Top of the built-in display.
        #expect(layout.display(containing: CGPoint(x: 100, y: 1080))?.identity.uuid == "B")
        #expect(layout.display(containing: CGPoint(x: 100, y: 1300)) == nil)
    }

    @Test func mainAndBuiltin() {
        let layout = DisplayLayout(displays: [builtin, external])
        #expect(layout.main?.identity.uuid == "B")
        #expect(layout.builtin?.identity.uuid == "B")
        #expect(layout.primaryHeight == 1080)
    }

    @Test(arguments: [
        (CGRect(x: 0, y: 0, width: 100, height: 50), CGRect(x: 0, y: 1030, width: 100, height: 50)),
        (CGRect(x: 1920, y: 1000, width: 200, height: 440), CGRect(x: 1920, y: -360, width: 200, height: 440)),
    ])
    func appKitToCoreGraphicsFlipRoundTrips(appKit: CGRect, cg: CGRect) {
        #expect(appKit.flippedVertically(primaryHeight: 1080) == cg)
        #expect(cg.flippedVertically(primaryHeight: 1080) == appKit)
    }

    @Test func pointFlip() {
        #expect(CGPoint(x: 5, y: 1080).flippedVertically(primaryHeight: 1080) == CGPoint(x: 5, y: 0))
    }
}

@MainActor @Suite struct DisplayTopologyObservationTests {

    @Test func refreshNotifiesOnlyOnChangeAndBumpsGeneration() {
        let a = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "A"), frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 575), isMain: true)
        nonisolated(unsafe) var list = [a]
        let topology = DisplayTopology(reader: { list })
        var seen: [UInt64] = []
        let token = topology.observe { seen.append($0.generation) }
        topology.refreshNow()
        #expect(seen.isEmpty)
        let b = DisplaySnapshot.make(identity: DisplayIdentity(uuid: "B"), frame: CGRect(x: 800, y: 0, width: 800, height: 600),
                                     visibleFrame: CGRect(x: 800, y: 0, width: 800, height: 575))
        list = [a, b]
        topology.refreshNow()
        #expect(seen == [2])
        #expect(topology.layout.displays.count == 2)
        token.cancel()
        list = [a]
        topology.refreshNow()
        #expect(seen == [2])
        topology.invalidate()
    }
}
