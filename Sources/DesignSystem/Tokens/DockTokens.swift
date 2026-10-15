import AppKit

/// Edge Dock visual tokens: **E1 Capsule** in the **A2 Frosted** direction (docs/design.md §7.1,
/// user pick 2026-10-15). Views read sizes, colours, radii and materials only from here.
/// Motion timings are not tokens of the look; they live in `EdgeMotion`.
public struct DockTokens: Sendable {
    public enum Size: String, Sendable, CaseIterable { case s, m, l, xl }

    /// `dd.dock.style` (default Dark Glass).
    public enum Style: String, Sendable, CaseIterable { case darkGlass, black, lightGlass }

    // Geometry (design.md §7.1; scales with Dock Size, DD-926).
    public var tileThickness: CGFloat      // t: 62 pt at M
    public var padding: CGFloat            // p: 8 pt
    public var gap: CGFloat                // g: 8 pt
    public var separatorLength: CGFloat    // the 1 px divider along the dock axis
    public var appIcon: CGFloat            // 52 pt bare icon
    public var appCellLength: CGFloat      // 54 pt cell along the dock axis
    public var edgeGap: CGFloat            // 8 pt from the physical edge
    public var shadowMargin: CGFloat       // shadow reach, 24 pt
    public var endMargin: CGFloat          // 24 pt free at each end (max length = edge − 48)
    public var labelLane: CGFloat
    public var tileRadius: CGFloat         // 15 pt, continuous
    /// Concentric rule (DD-903 AC5): 15 + 8 = 23 pt.
    public var capsuleRadius: CGFloat { tileRadius + padding }
    public var thickness: CGFloat { tileThickness + 2 * padding }

    // Divider and running indicator.
    public var dividerFraction: CGFloat    // 60 % of t
    public var dividerColor: NSColor
    public var indicatorDiameter: CGFloat  // 4 pt
    public var indicatorOffset: CGFloat    // 1 pt outside the tile edge, inner side
    public var indicatorRunning: NSColor   // white @ 0.9
    public var indicatorHidden: NSColor    // white @ 0.45

    // Label: native-Dock-style tooltip, instant, toward the screen centre.
    public var labelFontSize: CGFloat      // 12 pt Medium
    public var labelPaddingH: CGFloat      // 9 pt
    public var labelPaddingV: CGFloat      // 4 pt
    public var labelRadius: CGFloat        // 6 pt
    public var labelGap: CGFloat           // 10 pt from the capsule
    public var labelFill: NSColor
    public var labelText: NSColor
    public var labelEdge: NSColor          // 1 px inner edge white @ 0.08

    // Capsule material.
    public var style: Style
    /// Behind-window blur under the tint (nil = solid, e.g. Reduce Transparency).
    public var blurMaterial: NSVisualEffectView.Material?
    public var capsuleTint: NSColor
    public var capsuleEdge: NSColor        // 1 px inner edge
    public var widgetPlate: NSColor
    public var widgetPlateEdge: NSColor
    public var textPrimary: NSColor
    public var textSecondary: NSColor
    public var shadowColor: NSColor
    public var shadowRadius: CGFloat       // 24 pt blur
    public var shadowY: CGFloat            // 8 pt down
    public var shadowOpacity: Float        // 0.25
    public var missingAppOpacity: CGFloat

    /// E1 Capsule at a Dock Size, in a style; `reduceTransparency` swaps the blur for the solid fallback.
    public static func capsule(_ size: Size = .m, style: Style = .darkGlass, reduceTransparency: Bool = false,
                               lightAppearance: Bool = false) -> DockTokens {
        let t: CGFloat = switch size {
        case .s: 50
        case .m: 62
        case .l: 74
        case .xl: 86
        }
        let k = t / 62
        func white(_ a: CGFloat) -> NSColor { NSColor(white: 1, alpha: a) }
        func hex(_ rgb: UInt32, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255, green: CGFloat((rgb >> 8) & 0xff) / 255,
                    blue: CGFloat(rgb & 0xff) / 255, alpha: a)
        }

        var tokens = DockTokens(
            tileThickness: t, padding: 8 * k, gap: 8 * k, separatorLength: 1, appIcon: 52 * k, appCellLength: 54 * k,
            edgeGap: 8, shadowMargin: 24, endMargin: 24, labelLane: 220, tileRadius: 15 * k,
            dividerFraction: 0.6, dividerColor: white(0.18),
            indicatorDiameter: 4, indicatorOffset: 1, indicatorRunning: white(0.9), indicatorHidden: white(0.45),
            labelFontSize: 12, labelPaddingH: 9, labelPaddingV: 4, labelRadius: 6, labelGap: 10,
            labelFill: lightAppearance ? hex(0xF6F6F6, 0.95) : hex(0x202022, 0.92),
            labelText: lightAppearance ? hex(0x111111) : white(1),
            labelEdge: white(0.08),
            style: style, blurMaterial: .hudWindow, capsuleTint: hex(0x121214, 0.55), capsuleEdge: white(0.10),
            widgetPlate: white(0.09), widgetPlateEdge: white(0.08), textPrimary: white(1), textSecondary: hex(0xA0A0A5),
            shadowColor: .black, shadowRadius: 24, shadowY: 8, shadowOpacity: 0.25, missingAppOpacity: 0.35)

        switch style {
        case .darkGlass:
            break
        case .black:
            tokens.blurMaterial = .hudWindow
            tokens.capsuleTint = hex(0x0A0A0A, 0.92)
            tokens.widgetPlate = white(0.07)
            tokens.widgetPlateEdge = white(0.06)
            tokens.textSecondary = hex(0x878787)
        case .lightGlass:
            tokens.blurMaterial = .popover
            tokens.capsuleTint = hex(0xEAEDF2, 0.55)
            tokens.capsuleEdge = white(0.68)
            tokens.widgetPlate = white(0.45)
            tokens.widgetPlateEdge = white(0.55)
            tokens.textPrimary = hex(0x111111)
            tokens.textSecondary = hex(0x555555)
            tokens.indicatorRunning = NSColor(white: 0, alpha: 0.7)
            tokens.indicatorHidden = NSColor(white: 0, alpha: 0.35)
            tokens.dividerColor = NSColor(white: 0, alpha: 0.18)
        }
        if reduceTransparency {
            tokens.blurMaterial = nil
            switch style {
            case .darkGlass, .black:
                tokens.capsuleTint = hex(0x1C1C1E)
                tokens.widgetPlate = hex(0x2A2A2C)
            case .lightGlass:
                tokens.capsuleTint = hex(0xEAEDF2)
                tokens.widgetPlate = hex(0xFFFFFF)
            }
        }
        return tokens
    }
}
