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
    @Test("REG-027: a relayout mid-slide completes the in-flight generation")
    func reg027() {
        let a = makeAnimator()
        var finished: [UInt64] = []
        a.run(AnimationRequest(target: .shown, curve: .revealSpring, duration: .milliseconds(220), generation: 7)) { finished.append($0) }
        a.update(edge: .right, hiddenOffset: CGVector(dx: 90, dy: 0), reduceMotion: false)
        #expect(finished == [7])
        #expect(a.presentationProgress == 1)
        // At rest an update keeps the progress and reports nothing.
        a.update(edge: .left, hiddenOffset: CGVector(dx: -90, dy: 0), reduceMotion: false)
        #expect(finished == [7])
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
