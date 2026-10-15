import CoreGraphics
import DedockCore
import Testing
@testable import EdgeDock

@Suite struct TriggerEvaluatorTests {
    let wall = HotZone(edge: .left, displayID: "d", rect: CGRect(x: 0, y: 260, width: 3, height: 480), kind: .wall)
    let band = HotZone(edge: .left, displayID: "d", rect: CGRect(x: 0, y: 0, width: 8, height: 260), kind: .shared)
    let dock = CGRect(x: 6, y: 300, width: 76, height: 400)

    func sample(_ x: CGFloat, _ y: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0, t: Double = 0, buttons: Bool = false) -> PointerSample {
        PointerSample(location: CGPoint(x: x, y: y), delta: CGVector(dx: dx, dy: dy), timestamp: t, buttonsDown: buttons)
    }

    @Test func enteringAndLeavingTheZone() {
        var ev = TriggerEvaluator(zones: [wall], dockFrame: dock)
        #expect(ev.evaluate(sample(500, 500)) == [])
        #expect(ev.evaluate(sample(1, 500)) == [.enteredZone(.wall), .pointer(.onDock)])
        #expect(ev.evaluate(sample(0, 510)) == [])                                // still inside: no relayout, no events
        #expect(ev.evaluate(sample(10, 510)) == [.leftZone])                      // inside dock frame, still onDock
        #expect(ev.evaluate(sample(90, 510)) == [.pointer(.nearDock)])            // within 16 pt of maxX 82
        #expect(ev.evaluate(sample(120, 510)) == [.pointer(.away)])
    }

    @Test func pushThroughFiresOnceAfter40ptTowardTheEdge() {
        var ev = TriggerEvaluator(zones: [wall], dockFrame: dock)
        _ = ev.evaluate(sample(0, 500))
        var fired = 0
        for _ in 0..<20 {
            fired += ev.evaluate(sample(0, 500, dx: -5)).filter { $0 == .pushThrough }.count
        }
        #expect(fired == 1)
    }

    @Test func pushAwayFromTheEdgeDoesNotCount() {
        var ev = TriggerEvaluator(zones: [wall])
        _ = ev.evaluate(sample(0, 500))
        _ = ev.evaluate(sample(0, 500, dx: -30))
        _ = ev.evaluate(sample(1, 500, dx: 20))   // moving away subtracts
        #expect(!ev.evaluate(sample(0, 500, dx: -25)).contains(.pushThrough))
        #expect(ev.evaluate(sample(0, 500, dx: -10)).contains(.pushThrough))
    }

    @Test func pushResetsOnReentry() {
        var ev = TriggerEvaluator(zones: [wall])
        _ = ev.evaluate(sample(0, 500))
        _ = ev.evaluate(sample(0, 500, dx: -35))
        _ = ev.evaluate(sample(200, 500))
        _ = ev.evaluate(sample(0, 500))
        #expect(!ev.evaluate(sample(0, 500, dx: -35)).contains(.pushThrough))
    }

    @Test func pushThroughCanBeTurnedOff() {
        var params = EdgeTriggerParameters()
        params.pushThroughDistance = nil
        var ev = TriggerEvaluator(zones: [wall], parameters: params)
        _ = ev.evaluate(sample(0, 500))
        #expect(!ev.evaluate(sample(0, 500, dx: -500)).contains(.pushThrough))
    }

    @Test func heldButtonNeverArms() {
        var ev = TriggerEvaluator(zones: [wall])
        #expect(!ev.evaluate(sample(0, 500, buttons: true)).contains(.enteredZone(.wall)))
        #expect(ev.evaluate(sample(0, 501)).contains(.enteredZone(.wall)))
    }

    @Test func fastMovementInSharedBandRestartsDwell() {
        var ev = TriggerEvaluator(zones: [band])
        #expect(ev.evaluate(sample(2, 100, t: 0.000)) == [.enteredZone(.shared), .pointer(.onDock)])
        // 30 pt in 20 ms = 1500 pt/s > 300 pt/s
        #expect(ev.evaluate(sample(2, 130, t: 0.020)).contains(.restartDwell))
    }

    @Test func slowMovementInSharedBandKeepsDwell() {
        var ev = TriggerEvaluator(zones: [band])
        _ = ev.evaluate(sample(2, 100, t: 0.000))
        // 2 pt in 20 ms = 100 pt/s
        #expect(!ev.evaluate(sample(2, 102, t: 0.020)).contains(.restartDwell))
    }

    @Test func movingFromSharedBandToWallReportsLeaveThenEnter() {
        var ev = TriggerEvaluator(zones: [wall, band])
        _ = ev.evaluate(sample(1, 200))
        #expect(ev.evaluate(sample(1, 300)) == [.leftZone, .enteredZone(.wall)])
    }

    @Test func withoutDockFrameOnlyZonesCount() {
        var ev = TriggerEvaluator(zones: [wall])
        _ = ev.evaluate(sample(1, 500))
        #expect(ev.evaluate(sample(10, 500)) == [.leftZone, .pointer(.away)])
    }
}
