import CoreGraphics
import Testing
@testable import DedockCore

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

@Suite struct ScreenInfoTests {
    @Test func menuBarHeightWhenShown() {
        let s = ScreenInfo(id: "a", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                           visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 945))
        #expect(s.menuBarHeight == 37)
    }

    @Test func menuBarHeightWhenAutoHiddenOnNotchedDisplay() {
        let s = ScreenInfo(id: "a", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                           safeAreaTop: 32, statusBarThickness: 24)
        #expect(s.menuBarHeight == 32)
    }

    @Test func menuBarHeightWhenAutoHiddenWithoutNotch() {
        let s = ScreenInfo(id: "a", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), statusBarThickness: 24)
        #expect(s.menuBarHeight == 24)
    }
}

@Suite struct PointerSampleTests {
    @Test(arguments: [
        (ScreenEdge.left, CGVector(dx: -5, dy: 0), CGFloat(5)),
        (.left, CGVector(dx: 5, dy: 0), -5),
        (.right, CGVector(dx: 5, dy: 0), 5),
        (.bottom, CGVector(dx: 0, dy: 5), 5), // NSEvent dy > 0 = downward
        (.bottom, CGVector(dx: 0, dy: -5), -5),
    ])
    func pushTowardEdge(edge: ScreenEdge, delta: CGVector, expected: CGFloat) {
        let s = PointerSample(location: .zero, delta: delta, timestamp: 0)
        #expect(s.push(toward: edge) == expected)
    }
}
