import DedockCore
import Foundation
import Testing
@testable import EdgeDock

func display(_ id: String, _ frame: CGRect, menuBar: CGFloat = 24, autoHide: Bool = false,
             notch: CGRect? = nil, main: Bool = false) -> DisplaySnapshot {
    DisplaySnapshot(identity: DisplayIdentity(uuid: id), frame: frame,
                    visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - (autoHide ? 0 : menuBar)),
                    menuBarHeight: menuBar, menuBarAutoHides: autoHide, notch: notch, isMain: main)
}

func env(_ edge: ScreenEdge, _ d: DisplaySnapshot, _ all: [DisplaySnapshot]? = nil, content: Interval? = nil,
         dock: NativeDockFootprint? = nil, corners: HotCornerMask = .all, items: [CGRect] = []) -> EdgeEnvironment {
    EdgeEnvironment(layout: DisplayLayout(displays: all ?? [d]), display: d.identity, edge: edge, contentSpan: content,
                    nativeDock: dock, hotCorners: corners, statusItemRects: items)
}

@Suite struct EdgeGeometryTests {
    let single = display("main", CGRect(x: 0, y: 0, width: 1920, height: 1080), main: true)
    var whole: TriggerParameters { var p = TriggerParameters(); p.spanMode = .wholeEdge; return p }

    @Test func leftZoneFollowsContentPlusPadding() throws {
        let zones = EdgeGeometry.zones(env(.left, single, content: Interval(300, 700)), .init())
        #expect(zones.count == 1)
        let z = try #require(zones.first)
        #expect(z.kind == .wall)
        #expect(z.id == "z-0")
        #expect(z.rect == CGRect(x: 0, y: 260, width: 3, height: 480))
    }

    @Test func rightZoneSitsAtMaxXAndContainsTheExactEdge() throws {
        let z = try #require(EdgeGeometry.zones(env(.right, single, content: Interval(300, 700)), .init()).first)
        #expect(z.rect == CGRect(x: 1917, y: 260, width: 3, height: 480))
        #expect(z.contains(CGPoint(x: 1920, y: 500)))
        #expect(!z.contains(CGPoint(x: 1916, y: 500)))
    }

    @Test func wholeEdgeExcludesCornersAndMenuBar() throws {
        let z = try #require(EdgeGeometry.zones(env(.left, single), whole).first)
        #expect(z.rect == CGRect(x: 0, y: 24, width: 3, height: 1080 - 48))
    }

    @Test func tallMenuBarWinsOverCornerOnSideEdges() throws {
        let mbp = display("mbp", CGRect(x: 0, y: 0, width: 1512, height: 982), menuBar: 37)
        let r = try #require(EdgeGeometry.zones(env(.right, mbp), whole).first).rect
        #expect(r.minY == CGFloat(24))
        #expect(r.maxY == CGFloat(945))
    }

    @Test func bottomIgnoresMenuBar() throws {
        let z = try #require(EdgeGeometry.zones(env(.bottom, single), whole).first)
        #expect(z.rect == CGRect(x: 24, y: 0, width: 1920 - 48, height: 3))
    }

    @Test func topZoneSitsInTheMenuBarAndSkipsNotchAndStatusItems() {
        let notch = CGRect(x: 660, y: 950, width: 200, height: 32)
        let mbp = display("mbp", CGRect(x: 0, y: 0, width: 1512, height: 982), menuBar: 37, notch: notch)
        let item = CGRect(x: 1300, y: 950, width: 30, height: 24)
        let zones = EdgeGeometry.zones(env(.top, mbp, items: [item]), whole)
        #expect(zones.map(\.rect) == [
            CGRect(x: 24, y: 979, width: 636, height: 3),
            CGRect(x: 860, y: 979, width: 440, height: 3),
            CGRect(x: 1330, y: 979, width: 1512 - 24 - 1330, height: 3),
        ])
    }

    @Test func disabledHotCornerShrinksExclusion() throws {
        let z = try #require(EdgeGeometry.zones(env(.bottom, single, corners: [.bottomRight]), whole).first)
        #expect(z.rect == CGRect(x: 8, y: 0, width: 1920 - 8 - 24, height: 3))
    }

    @Test func contentSpanIsClippedToTheDisplay() throws {
        let z = try #require(EdgeGeometry.zones(env(.left, single, content: Interval(-100, 2000)), .init()).first)
        #expect(z.rect == CGRect(x: 0, y: 24, width: 3, height: 1080 - 48))
    }

    /// system-design §5.4: 1920×1080 at x 0…1920 beside 2560×1440 at x 1920…4480, bottoms aligned.
    @Test func sharedEdgeSplitMatchesSpecExample() {
        let builtin = display("b", CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let ext = display("e", CGRect(x: 1920, y: 0, width: 2560, height: 1440))
        let layout = [builtin, ext]
        #expect(EdgeGeometry.sharedSegments(of: ext, edge: .left, in: DisplayLayout(displays: layout)) == [Interval(0, 1080)])
        let zones = EdgeGeometry.zones(env(.left, ext, layout), whole)
        #expect(zones.filter { $0.kind == .wall }.map(\.rect) == [CGRect(x: 1920, y: 1080, width: 3, height: 336)])
        #expect(zones.filter { $0.kind == .shared }.map(\.rect) == [CGRect(x: 1920, y: 24, width: 8, height: 1056)])
    }

    @Test func wallOnlyPolicyDropsSharedBands() {
        let a = display("a", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = display("b", CGRect(x: 1000, y: 0, width: 1000, height: 800))
        var p = whole
        p.sharedPolicy = .wallOnly
        #expect(EdgeGeometry.zones(env(.right, a, [a, b]), p).isEmpty)
    }

    @Test func neighbourWithinOnePointCountsAsShared() {
        let a = display("a", CGRect(x: 0, y: 0, width: 1000, height: 800))
        let b = display("b", CGRect(x: 1000.5, y: 0, width: 1000, height: 800))
        #expect(EdgeGeometry.sharedSegments(of: a, edge: .right, in: DisplayLayout(displays: [a, b])) == [Interval(0, 800)])
    }

    @Test func stackedDisplaysShareBottomAndTop() {
        let lower = display("l", CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let upper = display("u", CGRect(x: 200, y: 1080, width: 1440, height: 900))
        let layout = DisplayLayout(displays: [lower, upper])
        #expect(EdgeGeometry.sharedSegments(of: upper, edge: .bottom, in: layout) == [Interval(200, 1640)])
        #expect(EdgeGeometry.sharedSegments(of: lower, edge: .top, in: layout) == [Interval(200, 1640)])
    }

    @Test func nativeDockSpanIsExcluded() {
        let dock = NativeDockFootprint(edge: .bottom, span: Interval(600, 1300), thickness: 70, autohide: false)
        let zones = EdgeGeometry.zones(env(.bottom, single, dock: dock), whole)
        #expect(zones.map(\.rect) == [CGRect(x: 24, y: 0, width: 576, height: 3),
                                      CGRect(x: 1300, y: 0, width: 1920 - 24 - 1300, height: 3)])
    }

    @Test func nativeDockOnAnotherEdgeIsIgnored() {
        let dock = NativeDockFootprint(edge: .bottom, span: Interval(0, 1920), thickness: 70, autohide: false)
        #expect(!EdgeGeometry.zones(env(.left, single, dock: dock), whole).isEmpty)
    }

    @Test func unknownDisplayHasNoZones() {
        let other = display("other", CGRect(x: 0, y: 0, width: 10, height: 10))
        let e = EdgeEnvironment(layout: DisplayLayout(displays: [single]), display: other.identity, edge: .left, contentSpan: nil)
        #expect(EdgeGeometry.zones(e, .init()).isEmpty)
    }

    @Test func nearRegionOutsetsZonesAndCapsule() {
        let z = HotZone(id: "z-0", rect: CGRect(x: 0, y: 100, width: 3, height: 100), kind: .wall)
        let r = EdgeGeometry.nearRegion(zones: [z], capsule: CGRect(x: 6, y: 120, width: 60, height: 60))
        #expect(r == CGRect(x: -96, y: 4, width: 66 + 192, height: 100 + 192))
        #expect(EdgeGeometry.nearRegion(zones: [], capsule: nil).isNull)
    }

    /// Property: on random side-by-side layouts every zone lies on its display; wall zones never
    /// overlap the neighbour's span on a touching edge; shared zones only exist on touching edges.
    @Test(arguments: ScreenEdge.allCases)
    func randomLayoutsKeepWallAndSharedApart(edge: ScreenEdge) {
        var rng = SplitMix64(seed: 0xDED0C &+ UInt64(edge.hashValue & 0xff))
        for _ in 0..<200 {
            let w1 = CGFloat(Int.random(in: 800...3000, using: &rng)), h1 = CGFloat(Int.random(in: 600...2000, using: &rng))
            let w2 = CGFloat(Int.random(in: 800...3000, using: &rng)), h2 = CGFloat(Int.random(in: 600...2000, using: &rng))
            let off = CGFloat(Int.random(in: -800...800, using: &rng))
            let a = display("a", CGRect(x: 0, y: 0, width: w1, height: h1))
            // b touches a's `edge`.
            let bFrame: CGRect = switch edge {
            case .right: CGRect(x: w1, y: off, width: w2, height: h2)
            case .left: CGRect(x: -w2, y: off, width: w2, height: h2)
            case .top: CGRect(x: off, y: h1, width: w2, height: h2)
            case .bottom: CGRect(x: off, y: -h2, width: w2, height: h2)
            }
            let b = display("b", bFrame)
            let zones = EdgeGeometry.zones(env(edge, a, [a, b]), whole)
            let neighbour = edge.line(of: b.frame)
            for z in zones {
                #expect(a.frame.insetBy(dx: -0.01, dy: -0.01).contains(z.rect))
                let along = edge.isVertical ? Interval(z.rect.minY, z.rect.maxY) : Interval(z.rect.minX, z.rect.maxX)
                switch z.kind {
                case .wall: #expect(along.intersection(neighbour) == nil)
                case .shared: #expect(along.intersection(neighbour) == along)
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
