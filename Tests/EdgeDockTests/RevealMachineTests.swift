import Foundation
import Testing
@testable import EdgeDock

typealias M = RevealMachine

/// Drives a machine to a given state using only public events.
func machine(in state: M.State) -> M {
    var m = M()
    func send(_ e: M.Event, _ p: Double) { _ = m.handle(e, presentation: p) }
    switch state {
    case .hidden:
        break
    case .arming:
        send(.enteredZone(.wall), 0)
    case .revealing:
        send(.enteredZone(.wall), 0)
        send(.pointer(.onDock), 0)
        send(.timerFired(.dwell), 0)
    case .shown:
        send(.enteredZone(.wall), 0)
        send(.pointer(.onDock), 0)
        send(.timerFired(.dwell), 0)
        send(.animationFinished(id: m.activeAnimationID!), 1)
    case .armingHide:
        m = machine(in: .shown)
        send(.leftZone, 1)
        send(.pointer(.away), 1)
    case .hiding:
        m = machine(in: .armingHide)
        send(.timerFired(.hideDelay), 1)
    }
    precondition(m.state == state, "fixture failed to reach \(state), got \(m.state)")
    return m
}

func animate(_ id: Int, _ target: RevealTarget, _ duration: TimeInterval, _ curve: RevealCurve) -> M.Effect {
    .animate(id: id, RevealAnimationSpec(target: target, duration: duration, curve: curve))
}

@Suite struct RevealMachineTransitionTests {
    struct Row: Sendable, CustomTestStringConvertible {
        let from: M.State
        let event: M.Event
        let presentation: Double
        let to: M.State
        let effects: [M.Effect]?   // nil = don't check effects
        var testDescription: String { "\(from) --\(event)--> \(to)" }
    }

    /// The full transition table of system-design §4.2 (architecture §14 gate: 100 % covered).
    static let rows: [Row] = [
        // hidden
        Row(from: .hidden, event: .enteredZone(.wall), presentation: 0, to: .arming,
            effects: [.startTimer(.dwell, after: 0.12)]),
        Row(from: .hidden, event: .enteredZone(.shared), presentation: 0, to: .arming,
            effects: [.startTimer(.dwell, after: 0.30)]),
        Row(from: .hidden, event: .explicitReveal, presentation: 0, to: .revealing, effects: nil),
        Row(from: .hidden, event: .leftZone, presentation: 0, to: .hidden, effects: []),
        Row(from: .hidden, event: .timerFired(.dwell), presentation: 0, to: .hidden, effects: []),
        Row(from: .hidden, event: .pushThrough, presentation: 0, to: .hidden, effects: []),
        Row(from: .hidden, event: .explicitHide, presentation: 0, to: .hidden, effects: []),
        // arming
        Row(from: .arming, event: .leftZone, presentation: 0, to: .hidden, effects: [.cancelTimer(.dwell)]),
        Row(from: .arming, event: .timerFired(.dwell), presentation: 0, to: .revealing,
            effects: [.setInteractive(true), animate(1, .shown, 0.22, .revealSpring)]),
        Row(from: .arming, event: .pushThrough, presentation: 0, to: .revealing,
            effects: [.cancelTimer(.dwell), .setInteractive(true), animate(1, .shown, 0.22, .revealSpring)]),
        Row(from: .arming, event: .restartDwell, presentation: 0, to: .arming,
            effects: [.cancelTimer(.dwell), .startTimer(.dwell, after: 0.12)]),
        Row(from: .arming, event: .explicitReveal, presentation: 0, to: .revealing, effects: nil),
        Row(from: .arming, event: .explicitHide, presentation: 0, to: .hidden,
            effects: [.cancelTimer(.dwell), .startTimer(.cooldown, after: 0.5)]),
        Row(from: .arming, event: .pointer(.away), presentation: 0, to: .arming, effects: []),
        // revealing
        Row(from: .revealing, event: .animationFinished(id: 1), presentation: 1, to: .shown, effects: []),
        Row(from: .revealing, event: .animationFinished(id: 99), presentation: 0.5, to: .revealing, effects: []),
        Row(from: .revealing, event: .enteredZone(.wall), presentation: 0.5, to: .revealing, effects: []),
        Row(from: .revealing, event: .explicitReveal, presentation: 0.5, to: .revealing, effects: []),
        Row(from: .revealing, event: .pointer(.away), presentation: 0.5, to: .revealing,
            effects: [.startTimer(.hideDelay, after: 0.4)]),
        Row(from: .revealing, event: .explicitHide, presentation: 0.5, to: .hiding,
            effects: [.setInteractive(false), animate(2, .hidden, 0.09, .hideEaseIn), .startTimer(.cooldown, after: 0.5)]),
        // shown
        Row(from: .shown, event: .pointer(.away), presentation: 1, to: .armingHide,
            effects: [.startTimer(.hideDelay, after: 0.4)]),
        Row(from: .shown, event: .pointer(.nearDock), presentation: 1, to: .shown, effects: []),
        Row(from: .shown, event: .enteredZone(.wall), presentation: 1, to: .shown, effects: []),
        Row(from: .shown, event: .explicitReveal, presentation: 1, to: .shown, effects: []),
        Row(from: .shown, event: .explicitHide, presentation: 1, to: .hiding,
            effects: [.setInteractive(false), animate(2, .hidden, 0.18, .hideEaseIn), .startTimer(.cooldown, after: 0.5)]),
        // armingHide
        Row(from: .armingHide, event: .pointer(.nearDock), presentation: 1, to: .shown,
            effects: [.cancelTimer(.hideDelay)]),
        Row(from: .armingHide, event: .pointer(.onDock), presentation: 1, to: .shown,
            effects: [.cancelTimer(.hideDelay)]),
        Row(from: .armingHide, event: .enteredZone(.wall), presentation: 1, to: .shown,
            effects: [.cancelTimer(.hideDelay)]),
        Row(from: .armingHide, event: .holdOpen(.menuOpen, active: true), presentation: 1, to: .shown,
            effects: [.cancelTimer(.hideDelay)]),
        Row(from: .armingHide, event: .timerFired(.hideDelay), presentation: 1, to: .hiding,
            effects: [.setInteractive(false), animate(2, .hidden, 0.18, .hideEaseIn)]),
        Row(from: .armingHide, event: .explicitHide, presentation: 1, to: .hiding,
            effects: [.cancelTimer(.hideDelay), .setInteractive(false), animate(2, .hidden, 0.18, .hideEaseIn),
                      .startTimer(.cooldown, after: 0.5)]),
        // hiding
        Row(from: .hiding, event: .animationFinished(id: 2), presentation: 0, to: .hidden, effects: []),
        Row(from: .hiding, event: .animationFinished(id: 1), presentation: 0.5, to: .hiding, effects: []),
        Row(from: .hiding, event: .pointer(.onDock), presentation: 0.5, to: .revealing,
            effects: [.setInteractive(true), animate(3, .shown, 0.11, .revealBezier)]),
        Row(from: .hiding, event: .enteredZone(.wall), presentation: 0.25, to: .revealing,
            effects: [.setInteractive(true), animate(3, .shown, 0.165, .revealBezier)]),
        Row(from: .hiding, event: .pointer(.nearDock), presentation: 0.5, to: .hiding, effects: []),
        Row(from: .hiding, event: .explicitHide, presentation: 0.5, to: .hiding, effects: []),
        Row(from: .hiding, event: .explicitReveal, presentation: 0.5, to: .revealing, effects: nil),
    ]

    @Test(arguments: rows)
    func transition(_ row: Row) {
        var m = machine(in: row.from)
        let effects = m.handle(row.event, presentation: row.presentation)
        #expect(m.state == row.to)
        if let expected = row.effects {
            #expect(effects.map(normalised) == expected.map(normalised))
        }
    }

    /// Every state has at least one row leaving it and every state is reached by some row.
    @Test func tableCoversEveryState() {
        let from = Set(Self.rows.map(\.from))
        let to = Set(Self.rows.filter { $0.from != $0.to }.map(\.to))
        #expect(from == Set(M.State.allCases))
        #expect(to == Set(M.State.allCases))
    }

    /// Animation ids depend on fixture history; compare with ids erased except their order.
    private func normalised(_ e: M.Effect) -> M.Effect {
        guard case .animate(_, let spec) = e else { return e }
        let rounded = RevealAnimationSpec(target: spec.target,
                                          duration: (spec.duration * 1000).rounded() / 1000,
                                          curve: spec.curve)
        return .animate(id: 0, rounded)
    }
}

@Suite struct RevealMachineBehaviourTests {
    @Test func leavingBeforeDwellReturnsHiddenWithoutAnimation() {
        var m = M()
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        let effects = m.handle(.leftZone, presentation: 0)
        #expect(m.state == .hidden)
        #expect(!effects.contains { if case .animate = $0 { true } else { false } })
    }

    @Test func fullscreenSpaceUsesLongerDwell() {
        var m = M()
        _ = m.handle(.fullscreenSpace(true), presentation: 0)
        #expect(m.handle(.enteredZone(.wall), presentation: 0) == [.startTimer(.dwell, after: 0.40)])
    }

    @Test func zeroDwellRevealsImmediately() {
        var timing = M.Timing()
        timing.showDelay = 0
        var m = M(timing: timing)
        _ = m.handle(.pointer(.onDock), presentation: 0)
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        #expect(m.state == .revealing)
    }

    @Test func pushThroughIsIgnoredOnSharedBands() {
        var m = M()
        _ = m.handle(.enteredZone(.shared), presentation: 0)
        #expect(m.handle(.pushThrough, presentation: 0) == [])
        #expect(m.state == .arming)
    }

    @Test func gateOpensBeforeRevealAnimationAndClosesBeforeHide() {
        var m = M()
        _ = m.handle(.pointer(.onDock), presentation: 0)
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        let reveal = m.handle(.timerFired(.dwell), presentation: 0)
        #expect(reveal.first == .setInteractive(true))
        var hidePath = machine(in: .armingHide)
        let hide = hidePath.handle(.timerFired(.hideDelay), presentation: 1)
        #expect(hide.first == .setInteractive(false))
    }

    @Test func holdOpenBlocksHidingUntilCleared() {
        var m = machine(in: .shown)
        _ = m.handle(.holdOpen(.previewOpen, active: true), presentation: 1)
        _ = m.handle(.pointer(.away), presentation: 1)
        #expect(m.state == .shown)
        let effects = m.handle(.holdOpen(.previewOpen, active: false), presentation: 1)
        #expect(m.state == .armingHide)
        #expect(effects == [.startTimer(.hideDelay, after: 0.4)])
    }

    @Test func everyHoldOpenTokenHoldsTheDock() {
        for token in HoldOpenToken.allCases {
            var m = machine(in: .shown)
            _ = m.handle(.holdOpen(token, active: true), presentation: 1)
            _ = m.handle(.pointer(.away), presentation: 1)
            #expect(m.state == .shown, "token \(token)")
        }
    }

    @Test func hideDelayExpiringMidRevealReversesInPlace() {
        // Case B of system-design §3.3.1: a short hide delay expires while still revealing.
        var timing = M.Timing()
        timing.hideDelay = 0.05
        var m = M(timing: timing)
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        _ = m.handle(.pointer(.away), presentation: 0)
        _ = m.handle(.timerFired(.dwell), presentation: 0)
        // Pointer is away from the dock → the hide timer started with the reveal.
        let effects = m.handle(.timerFired(.hideDelay), presentation: 0.5)
        #expect(m.state == .hiding)
        #expect(effects == [.setInteractive(false), animate(2, .hidden, 0.09, .hideEaseIn)])
    }

    @Test func pointerReturningDuringRevealCancelsHideTimer() {
        var m = M()
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        _ = m.handle(.pointer(.away), presentation: 0)
        _ = m.handle(.timerFired(.dwell), presentation: 0) // pointer .away → hide timer started
        #expect(m.handle(.pointer(.onDock), presentation: 0.3) == [.cancelTimer(.hideDelay)])
        #expect(m.handle(.timerFired(.hideDelay), presentation: 0.4) == [])
        #expect(m.state == .revealing)
    }

    @Test func revealFinishingWithPointerAwayGoesToArmingHide() {
        var m = M()
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        _ = m.handle(.pointer(.away), presentation: 0)
        _ = m.handle(.timerFired(.dwell), presentation: 0)
        _ = m.handle(.animationFinished(id: m.activeAnimationID!), presentation: 1)
        #expect(m.state == .armingHide)
    }

    @Test func explicitHideStartsCooldownThatBlocksReArming() {
        var m = machine(in: .shown)
        _ = m.handle(.explicitHide, presentation: 1)
        _ = m.handle(.animationFinished(id: m.activeAnimationID!), presentation: 0)
        #expect(m.state == .hidden)
        #expect(m.handle(.enteredZone(.wall), presentation: 0) == [])
        _ = m.handle(.timerFired(.cooldown), presentation: 0)
        #expect(m.handle(.enteredZone(.wall), presentation: 0) == [.startTimer(.dwell, after: 0.12)])
    }

    @Test func pinnedModeIgnoresPointerAndTimers() {
        var m = M(mode: .pinned)
        #expect(m.state == .shown)
        #expect(m.handle(.pointer(.away), presentation: 1) == [])
        #expect(m.handle(.timerFired(.hideDelay), presentation: 1) == [])
        #expect(m.handle(.explicitHide, presentation: 1) == [])
        #expect(m.state == .shown)
    }

    @Test func reduceMotionRevealIsAFade() {
        var motion = RevealMotion()
        motion.reduceMotion = true
        var m = M(motion: motion)
        _ = m.handle(.enteredZone(.wall), presentation: 0)
        let effects = m.handle(.timerFired(.dwell), presentation: 0)
        #expect(effects.contains(animate(1, .shown, 0.15, .fade)))
    }

    /// DD-928: requesting the state the dock is already heading to restarts nothing.
    @Test func repeatedRequestsAreIdempotent() {
        var revealing = machine(in: .revealing)
        for e: M.Event in [.enteredZone(.wall), .pushThrough, .explicitReveal, .timerFired(.dwell)] {
            #expect(revealing.handle(e, presentation: 0.4) == [])
        }
        var hiding = machine(in: .hiding)
        for e: M.Event in [.explicitHide, .leftZone, .pointer(.away), .timerFired(.hideDelay)] {
            #expect(hiding.handle(e, presentation: 0.4) == [])
        }
    }
}

/// Randomised event storms: invariants that must hold on every path.
@Suite struct RevealMachineFuzzTests {
    static let events: [M.Event] = [
        .enteredZone(.wall), .enteredZone(.shared), .leftZone, .pushThrough, .restartDwell,
        .pointer(.onDock), .pointer(.nearDock), .pointer(.away),
        .timerFired(.dwell), .timerFired(.hideDelay), .timerFired(.cooldown),
        .holdOpen(.menuOpen, active: true), .holdOpen(.menuOpen, active: false),
        .holdOpen(.previewOpen, active: true), .holdOpen(.previewOpen, active: false),
        .fullscreenSpace(true), .fullscreenSpace(false), .explicitReveal, .explicitHide,
    ]

    @Test(arguments: 0..<20)
    func invariantsHoldUnderRandomEvents(seed: Int) {
        var rng = SplitMix64(seed: UInt64(seed) &+ 7)
        var m = M()
        var lastTarget: RevealTarget?
        var interactive = false
        for _ in 0..<2000 {
            var event = Self.events.randomElement(using: &rng)!
            if Int.random(in: 0..<5, using: &rng) == 0, let id = m.activeAnimationID {
                event = .animationFinished(id: id)
            }
            let p = Double.random(in: 0...1, using: &rng)
            let effects = m.handle(event, presentation: p)

            for (i, effect) in effects.enumerated() {
                switch effect {
                case .setInteractive(let on):
                    interactive = on
                case .animate(_, let spec):
                    // DD-928: never restart an animation toward the target already in flight.
                    #expect(spec.target != lastTarget, "restarted toward \(spec.target) on \(event)")
                    lastTarget = spec.target
                    #expect(spec.duration >= 0.06 && spec.duration <= 0.22)
                    // DD-933: the gate changes in the same batch, before the animation.
                    #expect(i > 0 && effects[i - 1] == .setInteractive(spec.target == .shown))
                default:
                    break
                }
            }
            if m.state == .hidden || m.state == .arming {
                #expect(!interactive, "interactive while \(m.state)")
            }
            if m.state == .revealing || m.state == .hiding {
                #expect(m.activeAnimationID != nil)
            } else {
                #expect(m.activeAnimationID == nil)
            }
            if m.state == .shown || m.state == .armingHide { #expect(interactive) }
        }
    }
}
