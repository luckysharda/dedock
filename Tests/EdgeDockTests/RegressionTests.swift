import DedockCore
import Foundation
import Testing
@testable import EdgeDock

/// Unit-level regression guards for the pure Edge Dock logic. Runs on macOS and Linux.
@Suite("Regression", .tags(.regression)) struct LogicRegressionTests {
    /// REG-013: an odd visibleFrame height (e.g. 975 pt) put the capsule and panel on half
    /// points, blurring their edges on 1× displays.
    @Test("REG-013: odd visibleFrame keeps the dock on whole device pixels", arguments: ScreenEdge.allCases)
    func reg013(edge: ScreenEdge) {
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 0, y: 75, width: 1920, height: 975),
                                menuBarHeight: 30, menuBarAutoHides: false, backingScale: 1)
        let m = DockMetrics(thickness: 68, padding: 6, gap: 8, separatorLength: 10, edgeGap: 6, labelLane: 180, shadowMargin: 12)
        let tiles = (1...3).map { TileSpec(id: TileID("t\($0)")) }
        let l = LayoutEngine.layout(tiles, PlacementInput(display: d, edge: edge), m)
        for r in [l.capsuleFrame, l.panelFrame] + Array(l.tileFrames.values) {
            #expect(r.minX == r.minX.rounded() && r.minY == r.minY.rounded(), "\(r)")
            #expect(r.maxX == r.maxX.rounded() && r.maxY == r.maxY.rounded(), "\(r)")
        }
    }

    /// REG-020: a fast approach carried a big delta on the zone-entry sample, which counted
    /// as push-through and revealed with no dwell.
    @Test("REG-020: the entry sample's travel delta is not push-through")
    func reg020() {
        var e = TriggerEvaluator()
        let zone = HotZone(id: "z-0", rect: CGRect(x: 0, y: 0, width: 3, height: 500), kind: .wall)
        let entry = e.evaluate(PointerSample(location: CGPoint(x: 1, y: 200), delta: CGVector(dx: -400, dy: 0), timestamp: .zero),
                               zones: [zone], capsule: nil, edge: .left, onDockDisplay: true)
        #expect(entry.contains(.zoneEntered(.wall)))
        #expect(!entry.contains(.pushThrough))
    }

    /// REG-065: in content-span mode the bottom zone was content ± padding minus the native
    /// Dock's span. A typical Dock is wider than the content, so no zone was left and Reveal at
    /// Bottom could not trigger. Beside the native Dock the zone is the whole edge on either side.
    @Test("REG-065: beside the native Dock the trigger spans the edge on both sides of it",
          arguments: [CGFloat(328), CGFloat(840), CGFloat(1352)])
    func reg065(dockLength: CGFloat) throws {
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 0, y: 78, width: 1920, height: 978),
                                menuBarHeight: 24, menuBarAutoHides: false)
        let dock = Interval(CGFloat(960) - dockLength / 2, CGFloat(960) + dockLength / 2)
        let p = TriggerParameters()
        for autohide in [false, true] {
            let native = NativeDockFootprint(edge: .bottom, span: dock, thickness: 78, autohide: autohide)
            for content in [CGFloat(300), CGFloat(600), CGFloat(1200)] {
                let env = EdgeEnvironment(layout: DisplayLayout(displays: [d]), display: d.identity, edge: .bottom,
                                          contentSpan: Interval(CGFloat(960) - content / 2, CGFloat(960) + content / 2),
                                          nativeDock: native)
                let spans = EdgeGeometry.zones(env, p).map { Interval($0.rect.minX, $0.rect.maxX) }
                #expect(spans == [Interval(p.cornerExclusion, dock.lower), Interval(dock.upper, CGFloat(1920) - p.cornerExclusion)],
                        "dock \(dockLength) content \(content) autohide \(autohide)")
            }
        }

        // A dock on a side edge, with the native Dock at the bottom, keeps its content span.
        let side = EdgeEnvironment(layout: DisplayLayout(displays: [d]), display: d.identity, edge: .left,
                                   contentSpan: Interval(CGFloat(400), CGFloat(700)), nativeDock: nil)
        let zone = try #require(EdgeGeometry.zones(side, p).first)
        #expect(zone.rect.minY == CGFloat(400) - p.spanPadding && zone.rect.maxY == CGFloat(700) + p.spanPadding)
    }

    /// REG-023: integer-literal arithmetic in test arguments compiled on macOS but not on Linux
    /// (no implicit Int → CGFloat there), and with swift-testing `#expect(cgFloat == 1080 - 48)`
    /// reads false even when equal: the macro type-checks the bare right-hand side on its own.
    /// Expected values are typed explicitly; this guard fails if the wrapper is dropped.
    @Test("REG-023: computed CGFloat geometry matches explicitly typed expectations",
          arguments: [(ScreenEdge.left, CGFloat(1080 - 48)), (.top, CGFloat(1920 - 48))])
    func reg023(edge: ScreenEdge, length: CGFloat) throws {
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056),
                                menuBarHeight: 24, menuBarAutoHides: false)
        var p = TriggerParameters()
        p.spanMode = .wholeEdge
        let env = EdgeEnvironment(layout: DisplayLayout(displays: [d]), display: d.identity, edge: edge, contentSpan: nil)
        let zone = try #require(EdgeGeometry.zones(env, p).first)
        let computed = edge.isVertical ? zone.rect.height : zone.rect.width
        #expect(computed == length)
        if edge == .left { #expect(computed == CGFloat(1080 - 48)) } else { #expect(computed == CGFloat(1920 - 48)) }
    }
}
