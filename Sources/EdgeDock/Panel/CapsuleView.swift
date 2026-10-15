import AppKit
import DesignSystem
import QuartzCore

/// The Dark Glass capsule (docs/design.md §7.1), drawn in AppKit under the SwiftUI tiles:
/// a behind-window `NSVisualEffectView` forced `.active` (the panel is never key, and an
/// inactive material renders flat), a tint layer, a 1 px inner edge and a soft shadow. SwiftUI
/// cannot composite an AppKit-backed blur inside a group, so the capsule lives here.
@MainActor final class CapsuleView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = CALayer()
    private let edge = CALayer()
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
        edge.borderWidth = 1
        edge.backgroundColor = NSColor.clear.cgColor
        blur.layer?.addSublayer(edge)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    // The capsule never takes clicks; the root view routes them.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func apply(frame: CGRect, tokens t: DockTokens) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.frame = frame
        blur.frame = bounds
        radius = t.capsuleRadius

        // Light Glass blurs in the light appearance; the dark styles in the dark one.
        blur.appearance = NSAppearance(named: t.style == .lightGlass ? .aqua : .darkAqua)
        if let material = t.blurMaterial {
            blur.material = material
            blur.isHidden = false
        }
        // Reduce Transparency: no blur, the tint is solid.
        blur.state = t.blurMaterial == nil ? .inactive : .active
        blur.layer?.cornerRadius = radius
        blur.layer?.cornerCurve = .continuous

        tint.frame = bounds
        tint.backgroundColor = t.capsuleTint.cgColor
        tint.cornerRadius = radius
        tint.cornerCurve = .continuous

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
}
