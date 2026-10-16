import AppKit
import DesignSystem
import QuartzCore

/// One dock capsule (docs/design.md §7.1), drawn in AppKit under the SwiftUI tiles. SwiftUI
/// cannot composite an AppKit-backed blur inside a group, so the capsule lives here.
///
/// - Blur styles (Dark Glass, Black, Light Glass, the Liquid Glass stand-in): a behind-window
///   `NSVisualEffectView` forced `.active` (the panel is never key, and an inactive material
///   renders flat), a tint layer, a 1 px inner edge and a soft shadow.
/// - Liquid Glass on macOS 26+: the public system glass (`NSGlassEffectView`) with the LG4 tint.
/// - Liquid Glass stand-in on macOS 14–15: the blur plus a specular rim at the top.
/// - Solid styles (Dark, Reduce Transparency): the tint alone.
@MainActor final class CapsuleView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = CALayer()
    private let edge = CALayer()
    private let rim = CAGradientLayer()
    /// The system glass, created only when a style needs it (macOS 26+).
    private var glass: NSView?
    private var radius: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.wantsLayer = true
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        addSubview(blur)

        blur.layer?.addSublayer(tint)
        rim.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        blur.layer?.addSublayer(rim)
        edge.borderWidth = 1
        edge.backgroundColor = NSColor.clear.cgColor
        blur.layer?.addSublayer(edge)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // The capsule never takes clicks; the root view routes them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameters:
    ///   - crossFade: a tint change found at reveal fades over 0.3 s (LG4).
    ///   - radius: overrides the capsule radius (the P2 toast pill is 26 pt).
    func apply(frame: CGRect, tokens t: DockTokens, crossFade: Bool = false, radius r: CGFloat? = nil) {
        if crossFade {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            layer?.add(fade, forKey: "lg4.fade")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        blur.frame = bounds
        radius = r ?? t.capsuleRadius

        // Light Glass (and Liquid Glass's light tint) blurs in the light appearance.
        let light = t.style == .lightGlass || (t.blurMaterial == .popover)
        blur.appearance = NSAppearance(named: light ? .aqua : .darkAqua)
        if let material = t.blurMaterial {
            blur.material = material
        }
        // Solid styles and Reduce Transparency: no blur, the tint is solid.
        blur.state = t.blurMaterial == nil ? .inactive : .active
        blur.layer?.cornerRadius = radius
        blur.layer?.cornerCurve = .continuous

        applyGlass(t)

        tint.frame = bounds
        tint.backgroundColor = t.capsuleTint.cgColor
        tint.cornerRadius = radius
        tint.cornerCurve = .continuous

        // The stand-in's specular rim: white @ 0.22 fading to 0 over 40 % of the height, at the
        // top (AppKit layers are y-up: the top is the far end of the gradient).
        rim.frame = bounds
        rim.isHidden = t.specularRim <= 0
        rim.colors = [NSColor(white: 1, alpha: 0).cgColor, NSColor(white: 1, alpha: 0).cgColor,
                      NSColor(white: 1, alpha: t.specularRim).cgColor]
        rim.locations = [0, 0.6, 1]
        rim.startPoint = CGPoint(x: 0.5, y: 0)
        rim.endPoint = CGPoint(x: 0.5, y: 1)

        edge.frame = bounds
        edge.cornerRadius = radius
        edge.cornerCurve = .continuous
        edge.borderColor = t.capsuleEdge.cgColor

        layer?.shadowColor = t.shadowColor.cgColor
        layer?.shadowOpacity = t.shadowOpacity
        layer?.shadowRadius = t.shadowRadius / 2
        layer?.shadowOffset = CGSize(width: 0, height: -t.shadowY) // AppKit y-up: downward
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        CATransaction.commit()
    }

    /// Liquid Glass on macOS 26+: the system glass under the tiles, tinted per LG4; hidden for
    /// every other style. Public API only (`NSGlassEffectView`).
    private func applyGlass(_ t: DockTokens) {
        guard let tintColor = t.systemGlassTint else {
            glass?.isHidden = true
            blur.isHidden = false
            return
        }
        if #available(macOS 26, *) {
            let view: NSGlassEffectView
            if let existing = glass as? NSGlassEffectView {
                view = existing
            } else {
                view = NSGlassEffectView(frame: bounds)
                view.autoresizingMask = [.width, .height]
                addSubview(view, positioned: .below, relativeTo: blur)
                glass = view
            }
            view.frame = bounds
            view.cornerRadius = radius
            view.tintColor = tintColor
            // The glass renders for its appearance; match the LG4 tint so the light tint is not
            // laid on dark glass.
            view.appearance = NSAppearance(named: t.textPrimary.isDarkInk ? .aqua : .darkAqua)
            view.isHidden = false
            blur.isHidden = true       // the glass replaces the blur; tint and edge are not needed
        }
    }
}

private extension NSColor {
    /// Dark text means a light surface (Light Glass ink).
    var isDarkInk: Bool { (usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.5 }
}
