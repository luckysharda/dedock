import DedockCore
import Foundation
import Testing
@testable import EdgeDock

// Expected values built from integer-literal arithmetic are wrapped in CGFloat(...): with
// swift-testing's #expect, `cgFloat == 1080 - 24 - 6` evaluates false even when equal.
@Suite struct LayoutEngineTests {
    /// 1920×1080 at 1×, menu bar 24, native Dock 75 at the bottom → visibleFrame y 75…1056 (height 981, odd).
    let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 0, y: 75, width: 1920, height: 981),
                            menuBarHeight: 24, menuBarAutoHides: false, isMain: true, backingScale: 1)
    let m = DockMetrics(thickness: 68, padding: 6, gap: 8, separatorLength: 10, edgeGap: 6, labelLane: 180, shadowMargin: 12)
    let tiles = (1...4).map { TileSpec(id: TileID("t\($0)")) }

    func layout(_ edge: ScreenEdge, _ a: DockAlignment = .center, tiles: [TileSpec]? = nil, inset: CGFloat = 0,
                display: DisplaySnapshot? = nil) -> DockLayout {
        LayoutEngine.layout(tiles ?? self.tiles, PlacementInput(display: display ?? d, edge: edge, alignment: a, nativeDockInset: inset), m)
    }

    @Test func tileGrammar() {
        let l = layout(.left)
        #expect(m.tileThickness == 56)
        // 4 × 56 + 3 × 8 + 2 × 6 = 260
        #expect(l.capsuleFrame.size == CGSize(width: 68, height: 260))
        for f in l.tileFrames.values { #expect(f.size == CGSize(width: 56, height: 56)) }
        #expect(l.scale == 1)
    }

    @Test(arguments: ScreenEdge.allCases)
    func capsuleSitsEdgeGapFromItsEdgeAndIsPixelAligned(edge: ScreenEdge) {
        let l = layout(edge)
        let c = l.capsuleFrame
        switch edge {
        case .left: #expect(c.minX == 6)
        case .right: #expect(c.maxX == 1914)
        case .bottom: #expect(c.minY == 6)
        case .top: #expect(c.maxY == CGFloat(1080 - 24 - 6))
        }
        for r in [l.capsuleFrame, l.panelFrame] + Array(l.tileFrames.values) {
            #expect(r.minX == r.minX.rounded() && r.minY == r.minY.rounded(), "\(r) not on whole pixels")
        }
    }

    @Test(arguments: [(DockAlignment.start, CGFloat(1056 - 8)), (.end, CGFloat(75 + 8))])
    func sideAlignmentStartIsTheTop(alignment: DockAlignment, anchor: CGFloat) {
        let c = layout(.left, alignment).capsuleFrame
        if alignment == .start { #expect(c.maxY == anchor) } else { #expect(c.minY == anchor) }
    }

    @Test func centreIsCentredWithinTheVisibleFrame() {
        let c = layout(.right).capsuleFrame
        #expect(abs(c.midY - (75 + 981 / 2)) <= 0.5)
        let b = layout(.bottom).capsuleFrame
        #expect(b.midX == 960)
    }

    @Test(arguments: [DockAlignment.start, .end])
    func horizontalAlignment(alignment: DockAlignment) {
        let c = layout(.bottom, alignment).capsuleFrame
        if alignment == .start { #expect(c.minX == CGFloat(8)) } else { #expect(c.maxX == CGFloat(1920 - 8)) }
    }

    @Test func sideTilesRunTopToBottomInOrder() {
        let l = layout(.left)
        let ys = tiles.map { l.tileFrames[$0.id]!.midY }
        #expect(ys == ys.sorted(by: >))
        let b = layout(.bottom)
        let xs = tiles.map { b.tileFrames[$0.id]!.midX }
        #expect(xs == xs.sorted())
    }

    @Test func tilesAreInsideTheCapsuleAndCapsuleInsidePanel() {
        for edge in ScreenEdge.allCases {
            let l = layout(edge)
            for f in l.tileFrames.values { #expect(l.capsuleFrame.contains(f)) }
            #expect(l.panelFrame.contains(l.capsuleFrame))
            #expect(d.frame.contains(l.panelFrame))
        }
    }

    @Test func sidePanelStartsAtTheScreenEdgeAndAvoidsTheMenuBar() {
        let l = layout(.left, .start)
        #expect(l.panelFrame.minX == 0)
        #expect(l.panelFrame.maxY <= 1080 - 24)
        let r = layout(.right)
        #expect(r.panelFrame.maxX == 1920)
        #expect(r.panelFrame.minX == r.capsuleFrame.minX - 180 - 12)
    }

    @Test(arguments: ScreenEdge.allCases)
    func hiddenOffsetPointsOutward(edge: ScreenEdge) {
        let o = layout(edge).hiddenOffset
        let travel: CGFloat = 68 + 6 + 12   // T + edge inset + shadow reach
        #expect(o.dx == edge.outward.dx * travel && o.dy == edge.outward.dy * travel)
    }

    @Test func indicatorsFaceTheCentre() {
        #expect(layout(.left).indicatorSide == .right)
        #expect(layout(.bottom).indicatorSide == .top)
    }

    @Test func bottomDockSitsAboveAVisibleNativeDock() {
        let c = layout(.bottom, inset: 75).capsuleFrame
        #expect(c.minY == CGFloat(75 + 6))
    }

    @Test func overflowShrinksToFitThenStopsAtMinimumScale() {
        let many = (1...20).map { TileSpec(id: TileID("t\($0)")) }
        let l = layout(.left, tiles: many)
        #expect(l.scale < 1 && l.scale >= 0.6)
        #expect(l.capsuleFrame.height <= 981 - 16 + 1)
        let lots = (1...60).map { TileSpec(id: TileID("t\($0)")) }
        #expect(layout(.left, tiles: lots).scale == 0.6)
    }

    @Test func separatorsAreShort() {
        let withSep = [TileSpec(id: "a"), TileSpec(id: "s", shape: .separator), TileSpec(id: "b")]
        let l = layout(.left, tiles: withSep)
        #expect(l.tileFrames["s"]!.height == 10)
        let expected: CGFloat = 56 + 10 + 56 + 16 + 12
        #expect(l.capsuleFrame.height == expected)
    }

    @Test func appCellsUseTheirOwnLength() {
        var cells = m
        cells.appCellLength = 54
        let l = LayoutEngine.layout(tiles, PlacementInput(display: d, edge: .left), cells)
        for f in l.tileFrames.values { #expect(f.size == CGSize(width: 56, height: 54)) }
        let expected: CGFloat = 4 * 54 + 3 * 8 + 12
        #expect(l.capsuleFrame.height == expected)
    }

    @Test func emptyDockStillHasACapsule() {
        let l = layout(.left, tiles: [])
        #expect(l.capsuleFrame.height == CGFloat(56 + 12))
        #expect(l.tileFrames.isEmpty)
    }

    @Test func contentSpanMatchesTheCapsuleAlongTheEdge() {
        let l = layout(.left)
        #expect(l.contentSpan == Interval(l.capsuleFrame.minY, l.capsuleFrame.maxY))
    }

    @Test func layoutIsPure() {
        #expect(layout(.right, .end) == layout(.right, .end))
    }

    @Test func retinaAlignsToHalfPoints() {
        let retina = DisplaySnapshot(identity: DisplayIdentity(uuid: "r"), frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                     visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945.25),
                                     menuBarHeight: 36.75, menuBarAutoHides: false, backingScale: 2)
        let c = layout(.left, display: retina).capsuleFrame
        #expect((c.minY * 2) == (c.minY * 2).rounded())
    }

    @Test func insertionIndexFollowsThePointer() {
        let l = layout(.left)
        let order = tiles.map(\.id)
        let f = { (id: String) in l.tileFrames[TileID(id)]! }
        // Dragging t1 below t3's middle on a side dock → index 2 among the others (t2, t3 | t4).
        #expect(LayoutEngine.insertionIndex(for: CGPoint(x: 30, y: f("t3").midY - 1), in: l, order: order, moving: "t1") == 2)
        #expect(LayoutEngine.insertionIndex(for: CGPoint(x: 30, y: f("t1").maxY + 50), in: l, order: order, moving: "t4") == 0)
        let b = layout(.bottom)
        let g = { (id: String) in b.tileFrames[TileID(id)]! }
        #expect(LayoutEngine.insertionIndex(for: CGPoint(x: g("t4").maxX + 20, y: 30), in: b, order: order, moving: "t1") == 3)
    }
}
