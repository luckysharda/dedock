import Foundation
import Testing
@testable import EdgeDock

@Suite struct RevealMotionTests {
    let motion = RevealMotion()

    @Test func revealFromRestUsesFullDurationAndSpring() {
        let spec = motion.animation(to: .shown, from: 0)
        #expect(spec == RevealAnimationSpec(target: .shown, duration: 0.22, curve: .revealSpring))
    }

    @Test func hideFromRestUsesFullDurationAndEaseIn() {
        let spec = motion.animation(to: .hidden, from: 1)
        #expect(spec == RevealAnimationSpec(target: .hidden, duration: 0.18, curve: .hideEaseIn))
    }

    /// system-design §3.3.1 remaining-travel table.
    @Test(arguments: [
        (0.10, 0.198, 0.060),
        (0.25, 0.165, 0.060),
        (0.50, 0.110, 0.090),
        (0.75, 0.060, 0.135),
    ])
    func reverseDurationsMatchSpecTable(p: Double, toShown: Double, toHidden: Double) {
        let reveal = motion.animation(to: .shown, from: p)
        let hide = motion.animation(to: .hidden, from: p)
        #expect(abs(reveal.duration - toShown) < 1e-9)
        #expect(abs(hide.duration - toHidden) < 1e-9)
        #expect(reveal.curve == .revealBezier)
        #expect(hide.curve == .hideEaseIn)
    }

    @Test func reduceMotionFadesInPlace() {
        var m = RevealMotion()
        m.reduceMotion = true
        #expect(m.animation(to: .shown, from: 0) == RevealAnimationSpec(target: .shown, duration: 0.15, curve: .fade))
        #expect(m.animation(to: .hidden, from: 1) == RevealAnimationSpec(target: .hidden, duration: 0.15, curve: .fade))
        #expect(abs(m.animation(to: .hidden, from: 0.6).duration - 0.09) < 1e-9)
        #expect(m.animation(to: .shown, from: 0.9).duration == 0.06)
    }

    @Test func progressIsClamped() {
        #expect(motion.animation(to: .shown, from: -0.5).duration == 0.22)
        #expect(motion.animation(to: .hidden, from: 1.5).duration == 0.18)
    }

    /// The spring constants are the critically damped spring that settles 99 % at 0.22 s:
    /// x(t) = 1 − (1 + ωt)·e^(−ωt), ω = √stiffness, damping = 2ω.
    @Test func springConstantsAreCriticallyDampedAndSettleAt220ms() {
        let omega = sqrt(RevealCurve.revealSpringStiffness)
        #expect(abs(RevealCurve.revealSpringDamping - 2 * omega) < 0.1)
        #expect(abs(2 * Double.pi / omega - RevealCurve.revealSpringResponse) < 0.001)
        let t = 0.22
        let x = 1 - (1 + omega * t) * exp(-omega * t)
        // ω = 30.17 puts 0.22 s at 98.999 %, i.e. "99 % settled" to rounding (animation-spec §2.1).
        #expect(x > 0.9899)
        #expect(x < 0.9925)
    }
}
