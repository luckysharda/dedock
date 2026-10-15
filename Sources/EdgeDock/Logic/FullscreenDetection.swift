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
