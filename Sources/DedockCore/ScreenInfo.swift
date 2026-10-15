import CoreGraphics

/// An AppKit-free snapshot of one display, so geometry never touches `NSScreen`.
///
/// All rects are AppKit global coordinates (bottom-left origin, points), the same space
/// `NSEvent.mouseLocation` and `NSScreen.frame` use.
public struct ScreenInfo: Hashable, Sendable, Identifiable {
    /// Stable display identity (CGDisplayCreateUUIDFromDisplayID string form).
    public var id: String
    public var frame: CGRect
    public var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`; > 0 on notched displays.
    public var safeAreaTop: CGFloat
    /// `NSStatusBar.system.thickness`, used when the menu bar auto-hides.
    public var statusBarThickness: CGFloat

    public init(
        id: String,
        frame: CGRect,
        visibleFrame: CGRect? = nil,
        safeAreaTop: CGFloat = 0,
        statusBarThickness: CGFloat = 24
    ) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame ?? frame
        self.safeAreaTop = safeAreaTop
        self.statusBarThickness = statusBarThickness
    }

    /// Height of the menu-bar band at the top of this display (system-design §5.1).
    /// When the menu bar is shown it is `frame.maxY − visibleFrame.maxY`; when it auto-hides
    /// (that difference is 0) it is `max(statusBarThickness, safeAreaTop)`.
    public var menuBarHeight: CGFloat {
        let shown = frame.maxY - visibleFrame.maxY
        return shown > 0 ? shown : max(statusBarThickness, safeAreaTop)
    }
}
