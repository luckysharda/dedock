import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DedockCore

/// P2 Capsule toast geometry (design.md §7.2a): the drag-out confirm beside the dock and the
/// launch notice under the menu bar. AppKit global coordinates (y up).
public enum ToastLayout {
    public static let height: CGFloat = 52
    public static let radius: CGFloat = 26
    public static let minWidth: CGFloat = 240
    public static let maxWidth: CGFloat = 520
    /// From the capsule's inner side (confirm) and from the menu bar (notice).
    public static let dockGap: CGFloat = 10
    public static let menuBarGap: CGFloat = 6
    /// Kept this far inside the visible frame.
    public static let inset: CGFloat = 8
    /// Leading padding with an icon / without, trailing padding, gap between items.
    public static let leadingWithIcon: CGFloat = 10
    public static let leading: CGFloat = 18
    public static let trailing: CGFloat = 8
    public static let spacing: CGFloat = 12

    /// The side the pill grows away from in its clip reveal: the side touching its origin.
    public enum Growth: String, Sendable { case right, left, up, down }

    public static func width(fitting content: CGFloat) -> CGFloat { min(max(content, minWidth), maxWidth) }

    /// The confirm: 10 pt off the capsule's inner side, centred on the tile's slot, growing
    /// away from the dock toward the screen centre; clamped `inset` inside `visible`.
    public static func confirm(width w: CGFloat, capsule: CGRect, slot: CGPoint, edge: ScreenEdge,
                               visible: CGRect) -> (frame: CGRect, growth: Growth) {
        let h = height
        let (origin, growth): (CGPoint, Growth) = switch edge {
        case .left: (CGPoint(x: capsule.maxX + dockGap, y: slot.y - h / 2), .right)
        case .right: (CGPoint(x: capsule.minX - dockGap - w, y: slot.y - h / 2), .left)
        case .bottom: (CGPoint(x: slot.x - w / 2, y: capsule.maxY + dockGap), .up)
        case .top: (CGPoint(x: slot.x - w / 2, y: capsule.minY - dockGap - h), .down)
        }
        return (clamp(CGRect(origin: origin, size: CGSize(width: w, height: h)), in: visible), growth)
    }

    /// The notice: 6 pt below the menu bar (the top of `visible`), centred on Dedock's status
    /// item, or on the display when the item is hidden or its frame unknown; grows downward.
    /// Only its sides are clamped: the 6 pt under the menu bar is the rule at the top.
    public static func notice(width w: CGFloat, statusItem: CGRect?, visible: CGRect) -> (frame: CGRect, growth: Growth) {
        let midX = statusItem?.midX ?? visible.midX
        var frame = CGRect(x: midX - w / 2, y: visible.maxY - menuBarGap - height, width: w, height: height)
        frame.origin.x = min(max(frame.minX, visible.minX + inset), visible.maxX - inset - w)
        return (frame, .down)
    }

    static func clamp(_ r: CGRect, in v: CGRect) -> CGRect {
        var r = r
        r.origin.x = min(max(r.minX, v.minX + inset), v.maxX - inset - r.width)
        r.origin.y = min(max(r.minY, v.minY + inset), v.maxY - inset - r.height)
        return r
    }

    /// `name` shortened in the middle ("Visual Stu…Code") until `measure(prefix + name + suffix)`
    /// fits `maxWidth`; unchanged when it already fits.
    public static func middleTruncated(_ name: String, prefix: String, suffix: String, maxWidth: CGFloat,
                                       measure: (String) -> CGFloat) -> String {
        func line(_ n: String) -> String { prefix + n + suffix }
        guard measure(line(name)) > maxWidth else { return name }
        let chars = Array(name)
        var keep = chars.count - 1
        while keep > 1 {
            let head = (keep + 1) / 2, tail = keep / 2
            let candidate = String(chars[..<head]) + "\u{2026}" + String(chars[(chars.count - tail)...])
            if measure(line(candidate)) <= maxWidth { return candidate }
            keep -= 1
        }
        return String(chars.prefix(1)) + "\u{2026}"
    }
}
