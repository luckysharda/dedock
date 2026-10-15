import AppKit

/// Edge Dock visual tokens.
///
/// **PLACEHOLDER** (dedock-e9, 2026-10-15): every value here is a neutral stand-in until the user
/// picks a design sense at the design gate (`docs/plan.md` T0). Views must read sizes, colours,
/// radii and materials only from here, never hard-code them, so the chosen design is a pure
/// token + view-skin swap. Motion timings are NOT placeholders; they live in `EdgeMotion`.
public struct DockTokens: Sendable {
    public enum Size: String, Sendable, CaseIterable { case s, m, l, xl }

    // Geometry (PLACEHOLDER values; ranges from plan.md §6 are fixed).
    public var tileThickness: CGFloat      // t, 32–96 pt
    public var padding: CGFloat            // p, 2–16 pt
    public var gap: CGFloat                // g, 0–24 pt
    public var separatorLength: CGFloat
    public var edgeGap: CGFloat            // 0–48 pt
    public var labelLane: CGFloat
    public var shadowMargin: CGFloat
    public var tileRadius: CGFloat
    /// Concentric rule (DD-903 item 5): capsule radius = tile radius + padding.
    public var capsuleRadius: CGFloat { tileRadius + padding }
    public var thickness: CGFloat { tileThickness + 2 * padding }

    // Indicator and label (PLACEHOLDER).
    public var indicatorDiameter: CGFloat
    public var indicatorInset: CGFloat
    public var labelFontSize: CGFloat
    public var labelPadding: CGFloat
    public var labelRadius: CGFloat
    public var labelGap: CGFloat

    // Colours (PLACEHOLDER: neutral greys that adapt to light/dark).
    public var capsuleFill: NSColor
    public var capsuleStroke: NSColor
    public var tileFill: NSColor
    public var tileHoverFill: NSColor
    public var indicatorRunning: NSColor
    public var indicatorFrontmost: NSColor
    public var labelFill: NSColor
    public var labelText: NSColor
    public var shadowColor: NSColor
    public var shadowRadius: CGFloat
    public var shadowOpacity: Float
    public var hiddenAppOpacity: CGFloat
    public var missingAppOpacity: CGFloat

    public static func placeholder(_ size: Size = .m) -> DockTokens {
        let t: CGFloat = switch size {
        case .s: 44
        case .m: 56
        case .l: 68
        case .xl: 84
        }
        let k = t / 56
        return DockTokens(
            tileThickness: t, padding: 6 * k, gap: 8 * k, separatorLength: 10 * k, edgeGap: 6,
            labelLane: 180, shadowMargin: 12, tileRadius: 10 * k,
            indicatorDiameter: 4, indicatorInset: 2, labelFontSize: 12, labelPadding: 6, labelRadius: 6, labelGap: 8,
            capsuleFill: NSColor.windowBackgroundColor.withAlphaComponent(0.92),
            capsuleStroke: NSColor.separatorColor,
            tileFill: NSColor.gray.withAlphaComponent(0.12),
            tileHoverFill: NSColor.gray.withAlphaComponent(0.28),
            indicatorRunning: NSColor.secondaryLabelColor,
            indicatorFrontmost: NSColor.labelColor,
            labelFill: NSColor.windowBackgroundColor,
            labelText: NSColor.labelColor,
            shadowColor: NSColor.black, shadowRadius: 8, shadowOpacity: 0.25,
            hiddenAppOpacity: 0.5, missingAppOpacity: 0.35)
    }
}
