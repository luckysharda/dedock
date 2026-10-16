import AppKit

/// How Dedock's own windows (Settings, onboarding, permission screens) look: the Window
/// appearance and Window material settings (design.md §7.2, owner 2026-10-16). The dock's
/// style is separate (`DockTokens.Style`).
public struct WindowLook: Equatable, Sendable {
    public enum Appearance: String, Sendable, CaseIterable { case system, light, dark }
    public enum Material: String, Sendable, CaseIterable { case frosted, liquidGlass, solid }
    /// What is drawn after the fallbacks.
    public enum Backdrop: String, Sendable { case frosted, glass, solid }

    public var appearance: Appearance
    public var backdrop: Backdrop

    /// - Parameters:
    ///   - reduceTransparency: forces Solid.
    ///   - systemGlass: whether the system glass exists (macOS 26+); before it Liquid Glass is
    ///     Frosted.
    public init(appearance: Appearance, material: Material, reduceTransparency: Bool,
                systemGlass: Bool = DockTokens.systemGlassAvailable) {
        self.appearance = appearance
        backdrop = switch material {
        case _ where reduceTransparency: .solid
        case .frosted: .frosted
        case .liquidGlass: systemGlass ? .glass : .frosted
        case .solid: .solid
        }
    }

    /// The window's appearance: nil follows the system.
    public var nsAppearance: NSAppearance? {
        switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// Frosted (`dd.panel.material`): the tint over the blur.
    public static func frostedTint(dark: Bool) -> NSColor {
        dark ? NSColor(srgbRed: 0x22 / 255, green: 0x1E / 255, blue: 0x2C / 255, alpha: 0.62)
            : NSColor(srgbRed: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF6 / 255, alpha: 0.78)
    }
}

/// A window's background for a `WindowLook`, placed under its content: Frosted is a
/// behind-window blur forced `.active` with the A2 tint; Liquid Glass the public system glass
/// (`NSGlassEffectView`, macOS 26+); Solid the window background.
@MainActor public final class WindowBackdropView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = CALayer()
    private var glass: NSView?
    public private(set) var backdrop: WindowLook.Backdrop = .solid

    override public init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        blur.blendingMode = .behindWindow
        blur.material = .underWindowBackground
        blur.state = .active          // the window is often not key (the panel grammar)
        blur.autoresizingMask = [.width, .height]
        blur.frame = bounds
        addSubview(blur)
        blur.wantsLayer = true
        blur.layer?.addSublayer(tint)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    override public func layout() {
        super.layout()
        tint.frame = blur.bounds
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply(backdrop)
    }

    public func apply(_ backdrop: WindowLook.Backdrop) {
        self.backdrop = backdrop
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blur.isHidden = backdrop != .frosted
        tint.backgroundColor = WindowLook.frostedTint(dark: dark).cgColor
        tint.frame = blur.bounds
        layer?.backgroundColor = backdrop == .solid ? NSColor.windowBackgroundColor.cgColor : NSColor.clear.cgColor
        if backdrop == .glass, #available(macOS 26, *) {
            if glass == nil {
                let g = NSGlassEffectView(frame: bounds)
                // The clear style: the regular one renders a window-sized surface over a dark
                // wallpaper as a near-uniform grey, indistinguishable from Solid. With clear glass
                // the wallpaper's hue tints through (A2's rule for every non-Solid material).
                g.style = .clear
                g.autoresizingMask = [.width, .height]
                addSubview(g, positioned: .below, relativeTo: blur)
                glass = g
            }
            glass?.isHidden = false
        } else {
            glass?.isHidden = true
        }
        CATransaction.commit()
    }
}
