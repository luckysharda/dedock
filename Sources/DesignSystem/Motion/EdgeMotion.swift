import QuartzCore

/// Edge Dock motion constants (docs/architecture.md §6.5 motion table; settled values, not placeholders).
public enum EdgeMotion {
    /// `motion.edge.reveal` as a CASpringAnimation: mass 1, stiffness 910, damping 60.3
    /// (critically damped, ω ≈ 30.17 rad/s, 99 % settled at 0.22 s, no overshoot).
    public static let revealSpringMass: CGFloat = 1
    public static let revealSpringStiffness: CGFloat = 910
    public static let revealSpringDamping: CGFloat = 60.3
    /// Bezier form of the reveal, for duration-scaled reversals.
    public static let revealBezierPoints: (Float, Float, Float, Float) = (0.2, 0.7, 0.2, 1)
    /// `motion.edge.hide`: ease-in.
    public static let hideEaseInPoints: (Float, Float, Float, Float) = (0.42, 0, 1, 1)

    @MainActor public static var revealBezier: CAMediaTimingFunction { timing(revealBezierPoints) }
    @MainActor public static var hideEaseIn: CAMediaTimingFunction { timing(hideEaseInPoints) }
    @MainActor public static var fade: CAMediaTimingFunction { CAMediaTimingFunction(name: .linear) }

    @MainActor public static func revealSpring(duration: CFTimeInterval) -> CASpringAnimation {
        let a = CASpringAnimation()
        a.mass = revealSpringMass
        a.stiffness = revealSpringStiffness
        a.damping = revealSpringDamping
        a.initialVelocity = 0
        // Cut at the token duration (99 % settled); the last 1 % lands on the model value.
        a.duration = duration
        return a
    }

    @MainActor private static func timing(_ p: (Float, Float, Float, Float)) -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: p.0, p.1, p.2, p.3)
    }
}
