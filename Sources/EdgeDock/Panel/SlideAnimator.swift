import AppKit
import DedockCore
import DesignSystem
import Diagnostics
import QuartzCore

/// Animates the content container's `sublayerTransform` translation along the edge normal
/// (or its opacity under Reduce Motion). The panel frame never moves (architecture §6.7).
@MainActor public final class SlideAnimator: NSObject, RevealAnimating {
    private let container: NSView
    private var layer: CALayer { container.layer! }
    private(set) var edge: ScreenEdge
    /// Translation that parks the content off-screen (from `DockLayout.hiddenOffset`).
    private(set) var hiddenOffset: CGVector
    private(set) var reduceMotion: Bool

    private var completion: (@MainActor (UInt64) -> Void)?
    private var activeGeneration: UInt64?
    private var activeKind = "none"
    private var activeTarget: AnimationRequest.Target = .hidden
    private static let generationKey = "dedock.generation"
    private var displayLink: CADisplayLink?
    private let frameLog = DedockEnvironment.current.frameLog

    private static let key = "dedock.reveal"

    public init(container: NSView, edge: ScreenEdge, hiddenOffset: CGVector, reduceMotion: Bool) {
        self.container = container
        self.edge = edge
        self.hiddenOffset = hiddenOffset
        self.reduceMotion = reduceMotion
        container.wantsLayer = true
        super.init()
    }

    /// Update the geometry after a relayout. At rest the current progress is kept. If a slide is
    /// in flight it is completed at its target and its generation reported, so the reveal machine
    /// never waits for an `animationFinished` that would otherwise never come (PR #7 review item 1).
    public func update(edge: ScreenEdge, hiddenOffset: CGVector, reduceMotion: Bool) {
        let p = presentationProgress
        let pending = activeGeneration.flatMap { g in completion.map { (g, $0) } }
        completion = nil
        activeGeneration = nil
        layer.removeAnimation(forKey: Self.key)
        self.edge = edge
        self.hiddenOffset = hiddenOffset
        self.reduceMotion = reduceMotion
        if let (generation, done) = pending {
            apply(progress: activeTarget == .shown ? 1 : 0)
            stopFrameLog()
            done(generation)
        } else {
            apply(progress: p)
        }
    }

    /// The animation currently on the layer (tests).
    var inFlightAnimation: CAAnimation? { layer.animation(forKey: Self.key) }

    // MARK: RevealAnimating

    public var presentationProgress: Double {
        let l = layer.presentation() ?? layer
        if reduceMotion { return Double(l.opacity) }
        let tx = Double(l.sublayerTransform.m41), ty = Double(l.sublayerTransform.m42)
        let travel = hypot(Double(hiddenOffset.dx), Double(hiddenOffset.dy))
        guard travel > 0 else { return 1 }
        return min(1, max(0, 1 - hypot(tx, ty) / travel))
    }

    public func run(_ request: AnimationRequest, completion: @escaping @MainActor (UInt64) -> Void) {
        let from = presentationProgress
        let to: Double = request.target == .shown ? 1 : 0
        let duration = request.duration.seconds

        // Replace any animation in flight; its completion must not fire.
        self.completion = nil
        layer.removeAnimation(forKey: Self.key)

        let animation: CABasicAnimation
        switch request.curve {
        case .revealSpring:
            animation = EdgeMotion.revealSpring(duration: duration)
        case .revealBezier:
            animation = CABasicAnimation()
            animation.timingFunction = EdgeMotion.revealBezier
        case .hideEaseIn:
            animation = CABasicAnimation()
            animation.timingFunction = EdgeMotion.hideEaseIn
        case .fade:
            animation = CABasicAnimation()
            animation.timingFunction = EdgeMotion.fade
        }
        animation.duration = duration
        animation.delegate = self
        // Tag the animation, so a late stop from a replaced one never completes this generation.
        animation.setValue(NSNumber(value: request.generation), forKey: Self.generationKey)
        animation.isRemovedOnCompletion = true

        let fadePath = reduceMotion || request.curve == .fade
        if fadePath {
            animation.keyPath = "opacity"
            animation.fromValue = Float(from)
            animation.toValue = Float(to)
        } else {
            animation.keyPath = "sublayerTransform"
            animation.fromValue = NSValue(caTransform3D: transform(for: from))
            animation.toValue = NSValue(caTransform3D: transform(for: to))
        }

        self.completion = completion
        activeGeneration = request.generation
        activeTarget = request.target
        let kind = fadePath ? (request.target == .shown ? "fadeIn" : "fadeOut") : (request.target == .shown ? "reveal" : "hide")
        activeKind = kind

        // Pin the start to now, in the layer's time base. With beginTime 0, Core Animation stamps
        // the start when the transaction commits; if that lands a frame after the add, the slide
        // effectively restarts one frame late (a small step back, then a lag; REG-039).
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        animation.fillMode = .backwards

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(progress: to)
        layer.add(animation, forKey: Self.key)
        CATransaction.commit()

        DedockLog.event(.reveal, "reveal.begin", [
            "edge": edge.rawValue, "kind": kind,
            "from": DedockLog.pt(translationAlongNormal(from)), "to": DedockLog.pt(translationAlongNormal(to)),
            "dur": String(format: "%.3f", duration), "curve": request.curve.rawValue, "gen": request.generation,
        ])
        startFrameLog()
    }

    public func stop() {
        let p = presentationProgress
        completion = nil
        activeGeneration = nil
        layer.removeAnimation(forKey: Self.key)
        apply(progress: p)
        stopFrameLog()
    }

    public func snap(to target: AnimationRequest.Target) {
        completion = nil
        activeGeneration = nil
        layer.removeAnimation(forKey: Self.key)
        apply(progress: target == .shown ? 1 : 0)
        stopFrameLog()
    }

    // MARK: Model values

    private func apply(progress p: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reduceMotion {
            layer.sublayerTransform = CATransform3DIdentity
            layer.opacity = Float(p)
        } else {
            layer.opacity = 1
            layer.sublayerTransform = transform(for: p)
        }
        CATransaction.commit()
    }

    private func transform(for p: Double) -> CATransform3D {
        let k = CGFloat(1 - p)
        return CATransform3DMakeTranslation(hiddenOffset.dx * k, hiddenOffset.dy * k, 0)
    }

    /// Signed translation along the edge normal, in pt (0 = shown).
    private func translationAlongNormal(_ p: Double) -> Double {
        let k = 1 - p
        return Double(edge.isVertical ? hiddenOffset.dx : hiddenOffset.dy) * k
    }

    // MARK: Frame log (DEDOCK_FRAME_LOG=1)

    private func startFrameLog() {
        guard frameLog, displayLink == nil else { return }
        let link = container.displayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopFrameLog() {
        guard displayLink != nil else { return }
        logFrame()
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frameTick(_ link: CADisplayLink) { logFrame() }

    private func logFrame() {
        let l = layer.presentation() ?? layer
        let t = l.sublayerTransform
        let tx = edge.isVertical ? t.m41 : t.m42
        DedockLog.event(.frame, "frame", [
            "edge": edge.rawValue, "tx": DedockLog.pt(Double(tx)),
            "alpha": String(format: "%.3f", l.opacity), "anim": activeGeneration == nil ? "none" : activeKind,
        ])
    }
}

extension SlideAnimator: CAAnimationDelegate {
    public nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        let tag = (anim.value(forKey: "dedock.generation") as? NSNumber)?.uint64Value
        MainActor.assumeIsolated {
            guard flag, let generation = activeGeneration, let done = completion, tag == generation else { return }
            completion = nil
            activeGeneration = nil
            let at = translationAlongNormal(presentationProgress)
            DedockLog.event(.reveal, "reveal.end", ["edge": edge.rawValue, "kind": activeKind, "at": DedockLog.pt(at), "gen": generation])
            stopFrameLog()
            done(generation)
        }
    }
}
