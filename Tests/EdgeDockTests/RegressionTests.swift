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

    /// REG-066: the top zone was empty on a plain display. Any status-level window touching the
    /// menu bar counted as a status item, including a tall overlay across the centre, which
    /// removed the dock's whole content span. Only item-sized windows count now, and when items
    /// really do cover the span the zone falls back to the nearest free stretch, then to ⌥.
    @Test("REG-066: the top zone ignores non-item windows and falls back when items cover it")
    func reg066() throws {
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056),
                                menuBarHeight: 24, menuBarAutoHides: false)
        func window(_ x: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowRecord {
            WindowRecord(ownerPID: 42, layer: StatusItemGeometry.statusLayer, alpha: 1, bounds: CGRect(x: x, y: 0, width: w, height: h))
        }
        // An item is kept; a full-width backdrop and a tall overlay over the centre are not.
        let found = StatusItemGeometry.classify([window(1700, 30, 24), window(0, 1920, 24), window(700, 520, 156)],
                                                display: d, primaryHeight: 1080)
        #expect(found.items == [CGRect(x: 1700, y: 1056, width: 30, height: 24)])
        #expect(found.rejected == 2)

        let p = TriggerParameters()
        let content = Interval(CGFloat(832), CGFloat(1088))      // the default seed's capsule
        func derive(_ items: [CGRect]) -> ZoneDerivation {
            EdgeGeometry.derive(EdgeEnvironment(layout: DisplayLayout(displays: [d]), display: d.identity, edge: .top,
                                                contentSpan: content, statusItemRects: items), p)
        }
        func spans(_ z: ZoneDerivation) -> [Interval] { z.zones.map { Interval($0.rect.minX, $0.rect.maxX) } }

        // Primary: the content span ± 40, with the real items elsewhere on the bar.
        let primary = derive(found.items)
        #expect(primary.rule == .primary)
        #expect(spans(primary) == [Interval(CGFloat(792), CGFloat(1128))])
        #expect(primary.zones.allSatisfy { !$0.requiresOption })

        // Items over the centre: the nearest free stretch ≥ 80 pt (left gap 170 pt away, right 190).
        let centre = (0..<12).map { CGRect(x: CGFloat(790 + 30 * $0), y: 1056, width: 30, height: 24) }
        let nearest = derive(centre)
        #expect(nearest.rule == .nearestFree)
        #expect(spans(nearest) == [Interval(p.cornerExclusion, CGFloat(790))])

        // A bar with no free stretch ≥ 80 pt: ⌥ on contact over the content span.
        let crowded = stride(from: CGFloat(0), to: 1920, by: 70).map { CGRect(x: $0 + 10, y: 1056, width: 60, height: 24) }
        let option = derive(crowded)
        #expect(option.rule == .optionOnly)
        #expect(spans(option) == [Interval(CGFloat(792), CGFloat(1128))])
        #expect(option.zones.allSatisfy { $0.requiresOption })

        // The evaluator honours it: contact without ⌥ does nothing, with ⌥ it arms.
        var e = TriggerEvaluator(parameters: p)
        let at = CGPoint(x: 960, y: 1079)
        let plain = e.evaluate(PointerSample(location: at, timestamp: .zero), zones: option.zones, capsule: nil,
                               edge: .top, onDockDisplay: true)
        #expect(!plain.contains(.zoneEntered(.wall)))
        let withOption = e.evaluate(PointerSample(location: at, timestamp: .milliseconds(20), modifiers: [.option]),
                                    zones: option.zones, capsule: nil, edge: .top, onDockDisplay: true)
        #expect(withOption.contains(.zoneEntered(.wall)))
    }

    /// REG-067: on the top edge (and beside the native Dock) the shown capsule does not touch its
    /// zone, so the pointer travelling from the zone to the dock was outside zone ∪ capsule ± 16;
    /// a pause over 400 ms there hid the dock. The reveal corridor counts that path as inside
    /// until the pointer first reaches the capsule.
    @Test("REG-067: the path from the zone to the capsule stays inside until the first visit")
    func reg067() {
        func inside(_ events: [RevealEvent]) -> Bool? {
            events.compactMap { if case .pointerInside(let on) = $0 { on } else { nil } }.last
        }
        func sample(_ x: CGFloat, _ y: CGFloat, _ ms: Int) -> PointerSample {
            PointerSample(location: CGPoint(x: x, y: y), timestamp: .milliseconds(ms))
        }

        // Top (AppKit, 1080 high): zone y 1077–1080 over x 792–1128; capsule below the menu bar.
        let top = HotZone(id: "z-0", rect: CGRect(x: 792, y: 1077, width: 336, height: 3), kind: .wall)
        let topCapsule = CGRect(x: 832, y: 964, width: 256, height: 78)    // capsule ± 16 reaches y 1058
        var e = TriggerEvaluator()
        func step(_ x: CGFloat, _ y: CGFloat, _ ms: Int, _ cap: CGRect, _ zones: [HotZone], _ edge: ScreenEdge) -> [RevealEvent] {
            e.evaluate(sample(x, y, ms), zones: zones, capsule: cap, edge: edge, onDockDisplay: true)
        }
        #expect(inside(step(960, 1079, 0, topCapsule, [top], .top)) == true)        // zone entered
        let gap = step(960, 1068, 20, topCapsule, [top], .top)                     // the menu-bar band
        #expect(gap.contains(.zoneLeft))
        #expect(inside(gap) == nil)                                                // still inside: no hide armed
        #expect(inside(step(960, 1068, 900, topCapsule, [top], .top)) == nil)      // a long pause changes nothing
        #expect(inside(step(960, 1000, 950, topCapsule, [top], .top)) == nil)      // reaches the dock
        #expect(inside(step(960, 1068, 1000, topCapsule, [top], .top)) == false)   // visited: the band is outside now
        // A new zone entry starts a new corridor.
        #expect(inside(step(960, 1079, 1100, topCapsule, [top], .top)) == true)
        #expect(inside(step(960, 1068, 1120, topCapsule, [top], .top)) == nil)

        // Bottom beside the native Dock (footprint 424–1496): zone strips at the sides, capsule above.
        let strip = HotZone(id: "z-0", rect: CGRect(x: 24, y: 0, width: 400, height: 6), kind: .wall)
        let bottomCapsule = CGRect(x: 832, y: 86, width: 256, height: 78)
        e = TriggerEvaluator()
        #expect(inside(step(300, 3, 0, bottomCapsule, [strip], .bottom)) == true)
        #expect(inside(step(600, 60, 30, bottomCapsule, [strip], .bottom)) == nil)  // the diagonal midpoint
        let hull = TriggerEvaluator.corridorHull(entry: CGPoint(x: 300, y: 3), zone: strip.rect, capsule: bottomCapsule,
                                                 hysteresis: TriggerParameters().hysteresis, edge: .bottom)
        #expect(!TriggerEvaluator.convexContains(hull, CGPoint(x: 700, y: 3)))      // the Dock's own edge
        #expect(!TriggerEvaluator.convexContains(hull, CGPoint(x: 960, y: 3)))
        #expect(TriggerEvaluator.convexContains(hull, CGPoint(x: 600, y: 60)))

        // Left beside a visible native Dock (REG-070, T31): the Dock covers y 300–780 at the edge
        // (70 pt deep), the zone is the edge below it, the capsule sits on the Dock's inner side.
        let sideStrip = HotZone(id: "z-0", rect: CGRect(x: 0, y: 24, width: 3, height: 276), kind: .wall)
        let besideCapsule = CGRect(x: 78, y: 410, width: 78, height: 280)
        e = TriggerEvaluator()
        #expect(inside(step(1, 200, 0, besideCapsule, [sideStrip], .left)) == true)
        #expect(inside(step(40, 300, 30, besideCapsule, [sideStrip], .left)) == nil)   // the gap midpoint: inside
        let sideHull = TriggerEvaluator.corridorHull(entry: CGPoint(x: 1, y: 200), zone: sideStrip.rect, capsule: besideCapsule,
                                                     hysteresis: TriggerParameters().hysteresis, edge: .left)
        #expect(TriggerEvaluator.convexContains(sideHull, CGPoint(x: 40, y: 300)))
        #expect(!TriggerEvaluator.convexContains(sideHull, CGPoint(x: 3, y: 540)))      // the Dock's own edge strip
        #expect(!TriggerEvaluator.convexContains(sideHull, CGPoint(x: 35, y: 700)))

        // Left: capsule ± 16 already overlaps the zone; the path never goes outside (unchanged).
        let left = HotZone(id: "z-0", rect: CGRect(x: 0, y: 400, width: 3, height: 300), kind: .wall)
        let leftCapsule = CGRect(x: 8, y: 410, width: 78, height: 280)
        e = TriggerEvaluator()
        var events: [RevealEvent] = []
        for (i, x) in [CGFloat(1), 4, 10, 30, 60].enumerated() { events += step(x, 550, i * 20, leftCapsule, [left], .left) }
        #expect(!events.contains(.pointerInside(false)))
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

    /// REG-070: with the native Dock visible on the left or right edge and the Edge Dock on that
    /// edge, the capsule sat over the native Dock: the visible-Dock inset was applied only on
    /// the bottom edge. The dock now sits on the Dock's inner side on every edge it can share,
    /// and slides out from there (the panel starts at that side, so the hidden capsule is clipped).
    @Test("REG-070: beside a visible native Dock on the same side edge, the dock sits on its inner side",
          arguments: [ScreenEdge.left, .right, .bottom])
    func reg070(edge: ScreenEdge) {
        let f = CGRect(x: 0, y: 0, width: 1920, height: 1080), dock: CGFloat = 70
        let d = DisplaySnapshot(identity: DisplayIdentity(uuid: "d"), frame: f, visibleFrame: f,
                                menuBarHeight: 24, menuBarAutoHides: false, backingScale: 1)
        let m = DockMetrics(thickness: 68, padding: 6, gap: 8, separatorLength: 10, edgeGap: 8, labelLane: 180, shadowMargin: 12)
        let tiles = (1...4).map { TileSpec(id: TileID("t\($0)")) }
        let l = LayoutEngine.layout(tiles, PlacementInput(display: d, edge: edge, nativeDockInset: dock), m)
        let c = l.capsuleFrame, p = l.panelFrame
        // The native Dock's strip on that edge, which the capsule must stay clear of.
        let native: CGRect = switch edge {
        case .left: CGRect(x: 0, y: 0, width: dock, height: 1080)
        case .right: CGRect(x: 1920 - dock, y: 0, width: dock, height: 1080)
        default: CGRect(x: 0, y: 0, width: 1920, height: dock)
        }
        #expect(!c.intersects(native), "capsule \(c) over the native Dock \(native)")
        switch edge {
        case .left: #expect(c.minX == CGFloat(70 + 8) && p.minX == CGFloat(70))
        case .right: #expect(c.maxX == CGFloat(1920 - 70 - 8) && p.maxX == CGFloat(1920 - 70))
        default: #expect(c.minY == CGFloat(70 + 8) && p.minY == CGFloat(70))
        }
        // Hidden, the capsule is entirely outside the panel (clipped at the Dock's inner side).
        let hidden = c.offsetBy(dx: l.hiddenOffset.dx, dy: l.hiddenOffset.dy)
        #expect(!hidden.intersects(p), "hidden capsule \(hidden) still inside the panel \(p)")
    }
}
