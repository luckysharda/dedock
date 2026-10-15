import DedockCore
import DedockTestSupport
import Foundation
import Testing
@testable import EdgeDock

/// The impure reveal path: one-shot timers on an injected clock, the animator and the gate
/// (architecture §6.6, §11). macOS only (uses DedockTestSupport).
@Suite(.serialized) @MainActor struct EdgeRevealControllerTests {
    let clock = ManualClock()
    let animator = FakeAnimator()
    let gate = FakeGate()

    func make(_ config: RevealConfig = .init()) -> EdgeRevealController {
        EdgeRevealController(config: config, clock: clock, animator: animator, gate: gate, edge: .left)
    }

    /// Lets timer tasks reach their sleep, or run after the clock advanced.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func dwellFiresOnceAtTheConfiguredDelay() async {
        let c = make()
        c.send(.zoneEntered(.wall))
        await settle()
        #expect(c.phase == .arming(.wall))
        clock.advance(by: .milliseconds(119))
        await settle()
        #expect(c.phase == .arming(.wall))          // not a millisecond early
        clock.advance(by: .milliseconds(1))
        await settle()
        #expect(c.phase == .revealing)
        #expect(animator.requests.map(\.target) == [.shown])
        clock.advance(by: .seconds(5))
        await settle()
        #expect(animator.requests.count == 1)        // fired once
        c.invalidate()
    }

    @Test func leavingBeforeTheDwellCancelsIt() async {
        let c = make()
        c.send(.zoneEntered(.wall))
        await settle()
        c.send(.zoneLeft)
        clock.advance(by: .seconds(1))
        await settle()
        #expect(c.phase == .hidden)
        #expect(animator.requests.isEmpty)
        c.invalidate()
    }

    @Test func reEnteringReArmsAFreshDwell() async {
        let c = make()
        c.send(.zoneEntered(.wall))
        await settle()
        clock.advance(by: .milliseconds(100))
        c.send(.zoneLeft)
        c.send(.zoneEntered(.wall))
        await settle()
        clock.advance(by: .milliseconds(100))        // 200 ms since the first entry, 100 since re-entry
        await settle()
        #expect(c.phase == .arming(.wall))
        clock.advance(by: .milliseconds(20))
        await settle()
        #expect(c.phase == .revealing)
        c.invalidate()
    }

    @Test func gateOpensBeforeTheRevealAndClosesBeforeTheHide() async {
        let c = make()
        #expect(gate.interactive == [false])          // hidden at start
        c.send(.zoneEntered(.wall))
        c.send(.pushThrough)
        #expect(gate.interactive == [false, true])
        animator.finishLatest()
        #expect(c.phase == .shown)
        c.send(.command(.hide(explicit: true)))
        #expect(gate.interactive == [false, true, false])
        #expect(animator.requests.map(\.target) == [.shown, .hidden])
        c.invalidate()
    }

    @Test func hideDelayRunsOnTheClock() async {
        let c = make()
        c.send(.zoneEntered(.wall))
        c.send(.pushThrough)
        animator.finishLatest()
        c.send(.zoneLeft)
        c.send(.pointerInside(false))
        await settle()
        #expect(c.phase == .armingHide)
        clock.advance(by: .milliseconds(399))
        await settle()
        #expect(c.phase == .armingHide)
        clock.advance(by: .milliseconds(1))
        await settle()
        #expect(c.phase == .hiding)
        c.invalidate()
    }
}
