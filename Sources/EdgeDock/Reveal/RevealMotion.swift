import Foundation

/// Edge Dock reveal/hide motion (DD-927, DD-928; `animation-spec.md` §2.1, settled by dedock-e9).
public struct RevealMotion: Sendable, Equatable {
    /// `motion.edge.reveal`: 0.22 s, critically damped.
    public var revealDuration: TimeInterval = 0.22
    /// `motion.edge.hide`: 0.18 s ease-in.
    public var hideDuration: TimeInterval = 0.18
    /// Reduce Motion: opacity fade in place.
    public var reducedMotionDuration: TimeInterval = 0.15
    /// Shortest reversal; under ~4 frames at 60 Hz reads as a snap (system-design §3.3.1).
    public var reverseFloor: TimeInterval = 0.06
    public var reduceMotion: Bool = false

    public init() {}

    /// The animation that takes the dock from presentation progress `from` (0 = hidden,
    /// 1 = shown) to `target`. Duration is the full duration scaled by the remaining travel,
    /// with `reverseFloor` as a minimum; a start from rest uses the full duration.
    public func animation(to target: RevealTarget, from progress: Double) -> RevealAnimationSpec {
        let p = min(1, max(0, progress))
        let remaining = target == .shown ? 1 - p : p
        let atRest = target == .shown ? p <= 0 : p >= 1

        if reduceMotion {
            return RevealAnimationSpec(
                target: target,
                duration: scaled(reducedMotionDuration, remaining: remaining, atRest: atRest),
                curve: .fade)
        }
        switch target {
        case .shown:
            // A spring cannot be shortened exactly, so a reversal into a reveal uses the
            // bezier form of the same motion (animation-spec §2.1).
            return RevealAnimationSpec(
                target: .shown,
                duration: scaled(revealDuration, remaining: remaining, atRest: atRest),
                curve: atRest ? .revealSpring : .revealBezier)
        case .hidden:
            return RevealAnimationSpec(
                target: .hidden,
                duration: scaled(hideDuration, remaining: remaining, atRest: atRest),
                curve: .hideEaseIn)
        }
    }

    private func scaled(_ full: TimeInterval, remaining: Double, atRest: Bool) -> TimeInterval {
        atRest ? full : max(reverseFloor, full * remaining)
    }
}

public enum RevealTarget: Sendable, Equatable { case shown, hidden }

public struct RevealAnimationSpec: Sendable, Equatable {
    public var target: RevealTarget
    public var duration: TimeInterval
    public var curve: RevealCurve
}

public enum RevealCurve: Sendable, Equatable {
    /// SwiftUI `.spring(response: 0.208, dampingFraction: 1.0)`;
    /// `CASpringAnimation` mass 1, stiffness 910, damping 60.3. 99 % settled at 0.22 s, no overshoot.
    case revealSpring
    /// `CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.2, 1)`, used for duration-scaled reversals.
    case revealBezier
    /// `CAMediaTimingFunction(controlPoints: 0.42, 0, 1, 1)`.
    case hideEaseIn
    /// Reduce Motion: opacity only, linear-ish, in place (no translation).
    case fade

    public static let revealSpringResponse: Double = 0.208
    public static let revealSpringStiffness: Double = 910
    public static let revealSpringDamping: Double = 60.3
    public static let revealBezierControlPoints: (Float, Float, Float, Float) = (0.2, 0.7, 0.2, 1)
    public static let hideEaseInControlPoints: (Float, Float, Float, Float) = (0.42, 0, 1, 1)
}
