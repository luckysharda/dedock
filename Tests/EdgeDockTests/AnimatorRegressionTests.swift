import AppKit
import DedockCore
import QuartzCore
import Testing
@testable import EdgeDock

/// Regression guards for the slide animator (macOS only; excluded on Linux).
@Suite("Regression", .tags(.regression)) @MainActor struct AnimatorRegressionTests {
    func makeAnimator() -> SlideAnimator {
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 400))
        return SlideAnimator(container: view, edge: .left, hiddenOffset: CGVector(dx: -90, dy: 0), reduceMotion: false)
    }

    /// REG-027: a relayout during a slide removed the animation without completing it, and the
    /// machine waited forever in revealing/hiding.
    @Test("REG-027: a relayout mid-slide still completes the in-flight generation")
    func reg027() throws {
        let a = makeAnimator()
        var finished: [UInt64] = []
        a.run(AnimationRequest(target: .shown, curve: .revealSpring, duration: .milliseconds(220), generation: 7)) { finished.append($0) }
        a.update(edge: .right, hiddenOffset: CGVector(dx: 90, dy: 0), reduceMotion: false)
        // The re-issued slide carries the same generation and completes it.
        let anim = try #require(a.inFlightAnimation)
        a.animationDidStop(anim, finished: true)
        #expect(finished == [7])
        // At rest an update keeps the progress and reports nothing.
        a.update(edge: .left, hiddenOffset: CGVector(dx: -90, dy: 0), reduceMotion: false)
        #expect(finished == [7])
    }

    /// REG-038: a relayout mid-slide snapped the dock to its target (a one-frame jump) instead of
    /// continuing the slide from where it was (DD-928).
    @Test("REG-038: a relayout mid-slide re-issues the slide, not a snap")
    func reg038() throws {
        let a = makeAnimator()
        var finished: [UInt64] = []
        a.run(AnimationRequest(target: .hidden, curve: .hideEaseIn, duration: .milliseconds(180), generation: 3)) { finished.append($0) }
        a.update(edge: .left, hiddenOffset: CGVector(dx: -110, dy: 0), reduceMotion: false)
        #expect(finished.isEmpty)                          // not completed by a snap
        let anim = try #require(a.inFlightAnimation)
        #expect(anim.duration > 0 && anim.duration <= 0.18 + 1e-9)
        #expect((anim.value(forKey: "dedock.generation") as? NSNumber)?.uint64Value == 3)
    }

    /// Same review: a late `finished` from a replaced animation must not complete the new one.
    @Test("REG-027: a stale animation stop never completes a newer generation")
    func reg027Pairing() {
        let a = makeAnimator()
        var finished: [UInt64] = []
        a.run(AnimationRequest(target: .shown, curve: .revealSpring, duration: .milliseconds(220), generation: 1)) { finished.append($0) }
        a.run(AnimationRequest(target: .hidden, curve: .hideEaseIn, duration: .milliseconds(180), generation: 2)) { finished.append($0) }
        let stale = CABasicAnimation(keyPath: "sublayerTransform")
        stale.setValue(NSNumber(value: UInt64(1)), forKey: "dedock.generation")
        a.animationDidStop(stale, finished: true)
        #expect(finished.isEmpty)
        let current = CABasicAnimation(keyPath: "sublayerTransform")
        current.setValue(NSNumber(value: UInt64(2)), forKey: "dedock.generation")
        a.animationDidStop(current, finished: true)
        #expect(finished == [2])
    }
}

extension AnimatorRegressionTests {
    /// REG-039: a reversal's animation took its start time from the transaction commit, which
    /// could land a frame after the add, so the slide restarted ~17 ms late (a step back, then a
    /// lag; x-06 R). The start is now pinned to the moment the animation is added.
    @Test("REG-039: a new slide starts at the moment it is added, not at a later commit")
    func reg039() throws {
        let a = makeAnimator()
        let before = CACurrentMediaTime()
        a.run(AnimationRequest(target: .hidden, curve: .hideEaseIn, duration: .milliseconds(180), generation: 1)) { _ in }
        let after = CACurrentMediaTime()
        let anim = try #require(a.inFlightAnimation)
        #expect(anim.beginTime >= before - 0.001 && anim.beginTime <= after + 0.001)
        #expect(anim.fillMode == .backwards)
    }
}
