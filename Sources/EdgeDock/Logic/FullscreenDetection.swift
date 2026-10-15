import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import DedockCore

// Pure (architecture rule D5). Decides "this display is showing a full-screen window" from
// on-screen window records, without Accessibility or Screen Recording (architecture §6.9, T11).

/// The part of a `CGWindowListCopyWindowInfo` record the decision needs. Titles are never read.
public struct WindowRecord: Sendable, Hashable {
    public let ownerPID: Int32
    /// `kCGWindowLayer`: 0 is the normal application layer.
    public let layer: Int
    /// `kCGWindowAlpha`.
    public let alpha: Double
    /// `kCGWindowBounds`, CoreGraphics global coordinates (top-left origin, y down).
    public let bounds: CGRect

    public init(ownerPID: Int32, layer: Int, alpha: Double, bounds: CGRect) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
    }
}

public enum FullscreenDetection {
    /// Tolerance for a window that covers the display "exactly" (rounding, 1 px borders).
    public static let tolerance: CGFloat = 1

    /// True when a visible layer-0 window of another process covers all of `display`.
    /// - Parameters:
    ///   - displayFrameCG: the display's frame in CoreGraphics global coordinates.
    ///   - ownPID: dedock's own process (its panels never count).
    public static func isFullscreen(_ windows: [WindowRecord], displayFrameCG: CGRect, ownPID: Int32) -> Bool {
        let d = displayFrameCG.insetBy(dx: tolerance, dy: tolerance)
        return windows.contains { w in
            // Alpha-0 overlays (some apps keep invisible full-display windows) never count.
            w.layer == 0 && w.alpha > 0.01 && w.ownerPID != ownPID && w.bounds.contains(d)
        }
    }

    /// The per-display result for every display in `layout`, keyed by identity.
    public static func states(_ windows: [WindowRecord], layout: DisplayLayout, ownPID: Int32) -> [DisplayIdentity: Bool] {
        let h = layout.primaryHeight
        var result: [DisplayIdentity: Bool] = [:]
        for d in layout.displays {
            result[d.identity] = isFullscreen(windows, displayFrameCG: d.frame.flippedVertically(primaryHeight: h), ownPID: ownPID)
        }
        return result
    }
}

public enum StatusItemGeometry {
    /// `kCGStatusWindowLevel`: menu-bar status items (and the clock, Control Center items).
    public static let statusLayer = 25

    /// Widest window still taken for a status item; anything wider is a backdrop or an overlay.
    public static let maxItemWidth: CGFloat = 400

    /// Status-item rects on `display`, in AppKit global coordinates, for the top-edge zone
    /// (architecture §6.4: the top zone skips status items so they never trigger the dock).
    public static func rects(_ windows: [WindowRecord], display: DisplaySnapshot, primaryHeight: CGFloat) -> [CGRect] {
        classify(windows, display: display, primaryHeight: primaryHeight).items
    }

    /// Item-sized windows at the status level on the menu-bar line, and how many status-level
    /// windows touching it were rejected. A window taller than the menu bar or wider than
    /// `maxItemWidth` (a full-width backdrop, an app's drop-down overlay) is not a status item:
    /// taking one removed the whole top zone (REG-066).
    public static func classify(_ windows: [WindowRecord], display: DisplaySnapshot,
                                primaryHeight: CGFloat) -> (items: [CGRect], rejected: Int) {
        let menuBar = CGRect(x: display.frame.minX, y: display.frame.maxY - display.menuBarHeight,
                             width: display.frame.width, height: display.menuBarHeight)
        var items: [CGRect] = []
        var rejected = 0
        for w in windows where w.layer == statusLayer && w.alpha > 0.01 {
            let r = w.bounds.flippedVertically(primaryHeight: primaryHeight)
            guard r.intersects(menuBar) else { continue }
            if r.height <= display.menuBarHeight + 1, r.width <= maxItemWidth, r.minY >= menuBar.minY - 1 {
                items.append(r)
            } else {
                rejected += 1
            }
        }
        return (items, rejected)
    }
}
