import DedockCore
import Foundation
import Testing
@testable import EdgeDock

@Suite struct TriggerEvaluatorTests {
    let wall = HotZone(id: "z-0", rect: CGRect(x: 0, y: 260, width: 3, height: 480), kind: .wall)
    let band = HotZone(id: "z-1", rect: CGRect(x: 0, y: 24, width: 8, height: 236), kind: .shared)
    let capsule = CGRect(x: 6, y: 300, width: 76, height: 400)

    func s(_ x: CGFloat, _ y: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0, ms: Int = 0,
           buttons: Bool = false, mods: ModifierSet = []) -> PointerSample {
        PointerSample(location: CGPoint(x: x, y: y), delta: CGVector(dx: dx, dy: dy),
                      timestamp: .milliseconds(ms), buttonsDown: buttons, modifiers: mods)
    }

    func eval(_ e: inout TriggerEvaluator, _ sample: PointerSample, zones: [HotZone]? = nil,
              capsule: CGRect? = nil, on: Bool = true) -> [RevealEvent] {
        e.evaluate(sample, zones: zones ?? [wall], capsule: capsule, edge: .left, onDockDisplay: on)
    }

    @Test func enterLeaveAndHysteresis() {
        var e = TriggerEvaluator()
        #expect(eval(&e, s(500, 500), capsule: capsule) == [])
        #expect(eval(&e, s(1, 500), capsule: capsule) == [.zoneEntered(.wall), .pointerInside(true)])
        #expect(eval(&e, s(0, 510), capsule: capsule) == [])          // stable zone: no events
        #expect(eval(&e, s(10, 510), capsule: capsule) == [.zoneLeft]) // on the capsule, still inside
        #expect(eval(&e, s(95, 510), capsule: capsule) == [])          // within 16 pt of maxX 82
        #expect(eval(&e, s(120, 510), capsule: capsule) == [.pointerInside(false)])
    }

    @Test func pushThroughFiresOnceAfter40pt() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(0, 500))
        var fired = 0
        for _ in 0..<20 { fired += eval(&e, s(0, 500, dx: -5)).filter { $0 == .pushThrough }.count }
        #expect(fired == 1)
    }

    /// Coalesced moves (one event per display frame) carry summed deltas; the accumulator must
    /// sum deltas, not count events.
    /// A fast approach carries a big delta on the entry sample; that is travel, not push.
    @Test func entrySampleDeltaDoesNotCountAsPush() {
        var e = TriggerEvaluator()
        #expect(!eval(&e, s(0, 500, dx: -60)).contains(.pushThrough))
        #expect(eval(&e, s(0, 500, dx: -40)).contains(.pushThrough))
    }

    @Test func pushThroughWithCoalescedDeltas() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(0, 500))
        #expect(!eval(&e, s(0, 500, dx: -25)).contains(.pushThrough))
        #expect(eval(&e, s(0, 500, dx: -15)).contains(.pushThrough))
    }

    @Test func pushAwaySubtractsAndReentryResets() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(0, 500))
        _ = eval(&e, s(0, 500, dx: -30))
        _ = eval(&e, s(1, 500, dx: 20))
        #expect(!eval(&e, s(0, 500, dx: -25)).contains(.pushThrough))
        _ = eval(&e, s(200, 500))
        _ = eval(&e, s(0, 500))
        #expect(!eval(&e, s(0, 500, dx: -35)).contains(.pushThrough))
    }

    @Test(arguments: [(ScreenEdge.left, CGVector(dx: -50, dy: 0)), (.right, CGVector(dx: 50, dy: 0)),
                      (.bottom, CGVector(dx: 0, dy: -50)), (.top, CGVector(dx: 0, dy: 50))])
    func pushDirectionIsYUpPerEdge(edge: ScreenEdge, delta: CGVector) {
        var e = TriggerEvaluator()
        let z = HotZone(id: "z", rect: CGRect(x: 0, y: 0, width: 10, height: 10), kind: .wall)
        _ = e.evaluate(s(5, 5), zones: [z], capsule: nil, edge: edge, onDockDisplay: true)
        let events = e.evaluate(s(5, 5, dx: delta.dx, dy: delta.dy), zones: [z], capsule: nil, edge: edge, onDockDisplay: true)
        #expect(events.contains(.pushThrough))
    }

    @Test func pushThroughOff() {
        var p = TriggerParameters()
        p.pushThrough = nil
        var e = TriggerEvaluator(parameters: p)
        _ = eval(&e, s(0, 500))
        #expect(!eval(&e, s(0, 500, dx: -500)).contains(.pushThrough))
    }

    @Test func heldButtonNeverArmsButIsReported() {
        var e = TriggerEvaluator()
        let held = eval(&e, s(0, 500, buttons: true))
        #expect(held == [.buttonHeld(true)])
        #expect(eval(&e, s(0, 501)) == [.buttonHeld(false), .zoneEntered(.wall), .pointerInside(true)])
    }

    @Test func fastMovementInSharedBandRestartsDwell() {
        var e = TriggerEvaluator()
        #expect(eval(&e, s(2, 100, ms: 0), zones: [band]) == [.zoneEntered(.shared), .pointerInside(true)])
        #expect(eval(&e, s(2, 130, ms: 17), zones: [band]).contains(.sharedSpeedExceeded)) // ≈ 1760 pt/s
    }

    @Test func slowMovementInSharedBandKeepsDwell() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(2, 100, ms: 0), zones: [band])
        #expect(!eval(&e, s(2, 102, ms: 17), zones: [band]).contains(.sharedSpeedExceeded)) // ≈ 118 pt/s
        #expect(!eval(&e, s(2, 104, ms: 33), zones: [band]).contains(.sharedSpeedExceeded))
    }

    @Test func crossingToNeighbourWithinGuardIsReported() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(2, 100, ms: 0), zones: [band])
        let events = eval(&e, s(-5, 100, ms: 30), zones: [band], on: false)
        #expect(events.first == .crossedToNeighbour)
        #expect(events.contains(.zoneLeft))
    }

    @Test func modifierPolicyNeedsOption() {
        var p = TriggerParameters()
        p.sharedPolicy = .modifier
        var e = TriggerEvaluator(parameters: p)
        #expect(!eval(&e, s(2, 100), zones: [band]).contains(.zoneEntered(.shared)))
        #expect(eval(&e, s(2, 101, mods: .option), zones: [band]).contains(.zoneEntered(.shared)))
    }

    @Test func wallToSharedReportsLeaveThenEnter() {
        var e = TriggerEvaluator()
        _ = eval(&e, s(1, 200), zones: [wall, band])
        #expect(eval(&e, s(1, 300), zones: [wall, band]) == [.zoneLeft, .zoneEntered(.wall)])
    }
}
