import AppKit

/// Non-activating borderless panel base (architecture §6.7). Never becomes key or main in v0,
/// joins every Space and fullscreen apps, and is immune to AppKit's screen constraint.
@MainActor open class FloatingPanel: NSPanel {
    public init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        isMovable = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override open var canBecomeKey: Bool { false }
    override open var canBecomeMain: Bool { false }

    /// AppKit otherwise pushes panels on shared edges onto the wrong screen.
    override open func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
