import Testing
@testable import DedockCore
import Foundation

@Suite struct IntervalSetTests {
    @Test func normalisesOverlappingAndTouchingIntervals() {
        let set = IntervalSet([Interval(10, 20), Interval(0, 5), Interval(5, 8), Interval(15, 30), Interval(40, 40)])
        #expect(set.intervals == [Interval(0, 8), Interval(10, 30)])
    }

    @Test func subtractingSplitsAnInterval() {
        let set = IntervalSet(Interval(0, 100)).subtracting(Interval(40, 60))
        #expect(set.intervals == [Interval(0, 40), Interval(60, 100)])
    }

    @Test func subtractingEverythingLeavesEmpty() {
        let set = IntervalSet(Interval(10, 20)).subtracting(Interval(0, 100))
        #expect(set.isEmpty)
    }

    @Test func subtractingDisjointIsIdentity() {
        let set = IntervalSet(Interval(10, 20))
        #expect(set.subtracting(Interval(30, 40)) == set)
        #expect(set.subtracting(Interval(20, 30)) == set) // half-open: touching does not cut
    }

    @Test func intersection() {
        let a = IntervalSet([Interval(0, 10), Interval(20, 30)])
        let b = IntervalSet(Interval(5, 25))
        #expect(a.intersection(b).intervals == [Interval(5, 10), Interval(20, 25)])
    }

    @Test func totalLength() {
        #expect(IntervalSet([Interval(0, 10), Interval(20, 25)]).totalLength == 15)
    }
}

@Suite struct PointerSampleTests {
    /// Deltas are y-up (PointerHub flips NSEvent.deltaY once).
    @Test(arguments: [
        (ScreenEdge.left, CGVector(dx: -5, dy: 0), CGFloat(5)),
        (.left, CGVector(dx: 5, dy: 0), -5),
        (.right, CGVector(dx: 5, dy: 0), 5),
        (.bottom, CGVector(dx: 0, dy: -5), 5),
        (.top, CGVector(dx: 0, dy: 5), 5),
        (.top, CGVector(dx: 0, dy: -5), -5),
    ])
    func pushTowardEdge(edge: ScreenEdge, delta: CGVector, expected: CGFloat) {
        let s = PointerSample(location: .zero, delta: delta, timestamp: .zero)
        #expect(s.push(toward: edge) == expected)
    }
}

@Suite struct ScreenEdgeTests {
    @Test func axesAndOpposites() {
        #expect(ScreenEdge.left.orientation == .vertical)
        #expect(ScreenEdge.top.orientation == .horizontal)
        for e in ScreenEdge.allCases { #expect(e.opposite.opposite == e) }
    }

    @Test(arguments: ScreenEdge.allCases)
    func stripLiesOnTheEdge(edge: ScreenEdge) {
        let f = CGRect(x: 100, y: 50, width: 800, height: 600)
        let line = edge.line(of: f)
        let r = edge.strip(of: f, along: Interval(line.lower + 10, line.upper - 10), thickness: 3)
        #expect(f.contains(r))
        switch edge {
        case .left: #expect(r.minX == f.minX)
        case .right: #expect(r.maxX == f.maxX)
        case .bottom: #expect(r.minY == f.minY)
        case .top: #expect(r.maxY == f.maxY)
        }
    }

    @Test func flipIsItsOwnInverse() {
        let r = CGRect(x: 10, y: 20, width: 30, height: 40)
        #expect(r.flippedVertically(primaryHeight: 1080) == CGRect(x: 10, y: 1020, width: 30, height: 40))
        #expect(r.flippedVertically(primaryHeight: 1080).flippedVertically(primaryHeight: 1080) == r)
    }

    @Test func hotCornerMask() {
        let m: HotCornerMask = [.topLeft, .bottomRight]
        #expect(m.contains(ScreenCorner.topLeft))
        #expect(!m.contains(ScreenCorner.topRight))
        #expect(HotCornerMask.all.contains(ScreenCorner.bottomLeft))
    }

    @Test func durationSeconds() {
        #expect(Duration.milliseconds(1500).seconds == 1.5)
        #expect(Duration.seconds(0.12) == .milliseconds(120))
    }
}
