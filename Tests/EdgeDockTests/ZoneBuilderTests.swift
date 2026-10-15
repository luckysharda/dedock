import CoreGraphics
import DedockCore
import Testing
@testable import EdgeDock

@Suite struct ZoneBuilderTests {
    /// 1920×1080, menu bar 24 pt shown.
    let single = ScreenInfo(id: "main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1056))

    @Test func leftDockZoneFollowsContentPlusPadding() throws {
        let zones = ZoneBuilder().zones(edge: .left, display: single, screens: [single],
                                        contentSpan: Interval(300, 700))
        let zone = try #require(zones.first)
        #expect(zones.count == 1)
        #expect(zone.kind == .wall)
        #expect(zone.rect == CGRect(x: 0, y: 260, width: 3, height: 480))
    }

    @Test func rightDockZoneSitsAtMaxX() throws {
        let zones = ZoneBuilder().zones(edge: .right, display: single, screens: [single],
                                        contentSpan: Interval(300, 700))
        #expect(try #require(zones.first).rect == CGRect(x: 1917, y: 260, width: 3, height: 480))
    }

    @Test func rightZoneContainsThePointerAtTheExactEdge() throws {
        let zone = try #require(ZoneBuilder().zones(edge: .right, display: single, screens: [single],
                                                    contentSpan: Interval(300, 700)).first)
        #expect(zone.contains(CGPoint(x: 1920, y: 500)))
        #expect(zone.contains(CGPoint(x: 1919.5, y: 500)))
        #expect(!zone.contains(CGPoint(x: 1916, y: 500)))
    }

    @Test func wholeEdgeExcludesCornersAndMenuBar() throws {
        var params = EdgeTriggerParameters()
        params.spanMode = .wholeEdge
        let zones = ZoneBuilder(parameters: params).zones(edge: .left, display: single, screens: [single],
                                                          contentSpan: nil)
        // Bottom corner 24 pt; top: max(corner 24, menu bar 24) = 24.
        #expect(try #require(zones.first).rect == CGRect(x: 0, y: 24, width: 3, height: 1080 - 48))
    }

    @Test func menuBarTallerThanCornerWinsOnSideEdges() throws {
        let notched = ScreenInfo(id: "mbp", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                 visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945))
        let zones = ZoneBuilder().zones(edge: .right, display: notched, screens: [notched], contentSpan: nil)
        let rect = try #require(zones.first).rect
        #expect(rect.minY == 24)
        #expect(rect.maxY == CGFloat(945)) // 982 − menu bar 37
    }

    @Test func bottomEdgeIgnoresMenuBar() throws {
        var params = EdgeTriggerParameters()
        params.spanMode = .wholeEdge
        let zones = ZoneBuilder(parameters: params).zones(edge: .bottom, display: single, screens: [single],
                                                          contentSpan: nil)
        #expect(try #require(zones.first).rect == CGRect(x: 24, y: 0, width: 1920 - 48, height: 3))
    }

    @Test func disabledHotCornerShrinksExclusionTo8pt() throws {
        var params = EdgeTriggerParameters()
        params.spanMode = .wholeEdge
        let zones = ZoneBuilder(parameters: params).zones(
            edge: .bottom, display: single, screens: [single], contentSpan: nil,
            hotCorners: [.bottomRight])
        #expect(try #require(zones.first).rect == CGRect(x: 8, y: 0, width: 1920 - 8 - 24, height: 3))
    }

    @Test func contentSpanIsClippedToTheDisplay() throws {
        let zones = ZoneBuilder().zones(edge: .left, display: single, screens: [single],
                                        contentSpan: Interval(-100, 2000))
        #expect(try #require(zones.first).rect == CGRect(x: 0, y: 24, width: 3, height: 1080 - 48))
    }

    /// system-design §5.4 example: a 1920×1080 built-in at x 0…1920 with a 2560×1440 external
    /// at x 1920…4480, bottoms aligned. The external's left edge is shared for y 0…1080 and a
    /// wall for y 1080…1440.
    @Test func sharedEdgeSplitMatchesSpecExample() {
        let builtin = ScreenInfo(id: "builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let external = ScreenInfo(id: "ext", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440),
                                  visibleFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1416))
        var params = EdgeTriggerParameters()
        params.spanMode = .wholeEdge

        let shared = ZoneBuilder.sharedSegments(edge: .left, display: external, screens: [builtin, external])
        #expect(shared.intervals == [Interval(0, 1080)])

        let zones = ZoneBuilder(parameters: params).zones(edge: .left, display: external,
                                                          screens: [builtin, external], contentSpan: nil)
        let wall = zones.filter { $0.kind == .wall }.map(\.rect)
        let band = zones.filter { $0.kind == .shared }.map(\.rect)
        // Wall: 1080…1440 minus top corner/menu bar (24) → 1080…1416, 3 pt thick.
        #expect(wall == [CGRect(x: 1920, y: 1080, width: 3, height: 336)])
        // Shared: 0…1080 minus bottom corner (24) → 24…1080, 8 pt thick.
        #expect(band == [CGRect(x: 1920, y: 24, width: 8, height: 1056)])
    }

    @Test func outerEdgesOfASideBySidePairAreWalls() {
        let builtin = ScreenInfo(id: "builtin", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let external = ScreenInfo(id: "ext", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        let left = ZoneBuilder().zones(edge: .left, display: builtin, screens: [builtin, external], contentSpan: nil)
        let right = ZoneBuilder().zones(edge: .right, display: external, screens: [builtin, external], contentSpan: nil)
        #expect(left.allSatisfy { $0.kind == .wall })
        #expect(right.allSatisfy { $0.kind == .wall })
    }

    @Test func neighbourWithinOnePointCountsAsShared() {
        let a = ScreenInfo(id: "a", frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = ScreenInfo(id: "b", frame: CGRect(x: 1000.5, y: 0, width: 1000, height: 800))
        let shared = ZoneBuilder.sharedSegments(edge: .right, display: a, screens: [a, b])
        #expect(shared.intervals == [Interval(0, 800)])
    }

    @Test func nativeDockFootprintIsExcluded() {
        var params = EdgeTriggerParameters()
        params.spanMode = .wholeEdge
        let zones = ZoneBuilder(parameters: params).zones(
            edge: .bottom, display: single, screens: [single], contentSpan: nil,
            nativeDockFootprint: Interval(600, 1300))
        #expect(zones.map(\.rect) == [
            CGRect(x: 24, y: 0, width: 576, height: 3),
            CGRect(x: 1300, y: 0, width: 1920 - 24 - 1300, height: 3),
        ])
    }

    @Test func fullyCoveredEdgeHasNoZones() {
        let zones = ZoneBuilder().zones(edge: .left, display: single, screens: [single],
                                        contentSpan: Interval(500, 600), nativeDockFootprint: Interval(0, 1080))
        #expect(zones.isEmpty)
    }

    @Test func thicknessFollowsParameters() throws {
        var params = EdgeTriggerParameters()
        params.triggerThickness = 6
        let zones = ZoneBuilder(parameters: params).zones(edge: .right, display: single, screens: [single],
                                                          contentSpan: Interval(300, 700))
        #expect(try #require(zones.first).rect.minX == 1914)
    }

    /// Property: on random side-by-side layouts, every wall zone lies on an edge segment
    /// that touches no other display, and every zone lies on its own display's edge.
    @Test func randomLayoutsNeverPutWallZonesOnSharedSegments() {
        var rng = SplitMix64(seed: 0xDED0C)
        for _ in 0..<300 {
            let w1 = CGFloat(Int.random(in: 800...3000, using: &rng))
            let h1 = CGFloat(Int.random(in: 600...2000, using: &rng))
            let w2 = CGFloat(Int.random(in: 800...3000, using: &rng))
            let h2 = CGFloat(Int.random(in: 600...2000, using: &rng))
            let dy = CGFloat(Int.random(in: -800...800, using: &rng))
            let a = ScreenInfo(id: "a", frame: CGRect(x: 0, y: 0, width: w1, height: h1))
            let b = ScreenInfo(id: "b", frame: CGRect(x: w1, y: dy, width: w2, height: h2))
            for (display, edge) in [(a, ScreenEdge.right), (b, .left), (a, .left), (b, .right)] {
                let zones = ZoneBuilder().zones(edge: edge, display: display, screens: [a, b], contentSpan: nil)
                let other = display.id == "a" ? b : a
                for zone in zones {
                    #expect(display.frame.insetBy(dx: -0.01, dy: -0.01).contains(zone.rect))
                    let otherSpan = Interval(other.frame.minY, other.frame.maxY)
                    let zoneSpan = Interval(zone.rect.minY, zone.rect.maxY)
                    let touches = (edge == .right && display.id == "a") || (edge == .left && display.id == "b")
                    if zone.kind == .wall && touches {
                        #expect(zoneSpan.intersection(otherSpan) == nil)
                    }
                    if zone.kind == .shared {
                        #expect(touches)
                    }
                }
            }
        }
    }
}

/// Deterministic RNG for property tests.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
