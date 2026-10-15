import AppKit
import DedockCore
import DesignSystem
import SettingsStore
import SwiftUI

/// What the Settings window needs from the rest of the app, injected by the composition root
/// (SettingsUI never imports EdgeDock: architecture rule D3).
@MainActor public struct SettingsEnvironment {
    public var nativeDockEdge: () -> ScreenEdge
    /// Displays whose edge is shared with another display, for the shared-edge policy row.
    public var hasSharedEdge: (ScreenEdge) -> Bool

    public init(nativeDockEdge: @escaping () -> ScreenEdge, hasSharedEdge: @escaping (ScreenEdge) -> Bool) {
        self.nativeDockEdge = nativeDockEdge
        self.hasSharedEdge = hasSharedEdge
    }
}

/// The Settings window: an `NSWindow` dedock owns (architecture §8). Opening it switches the
/// app to `.regular` and activates it; closing switches back to `.accessory`.
@MainActor public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let settings: SettingsModel
    private let environment: SettingsEnvironment
    /// Called with `true` when the window opens and `false` when it closes (the app holds the
    /// dock open with the `editing` token meanwhile, so changes are visible live).
    public var onVisibilityChange: ((Bool) -> Void)?

    public init(settings: SettingsModel, environment: SettingsEnvironment) {
        self.settings = settings
        self.environment = environment
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show() {
        if window == nil {
            let root = SettingsRootView(settings: settings, environment: environment, navigation: SettingsNavigation())
            let w = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsTokens.windowSize),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Dedock Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: root)
            w.contentMinSize = CGSize(width: 760, height: 520)
            w.delegate = self
            w.center()
            window = w
        }
        let wasVisible = isVisible
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { onVisibilityChange?(true) }
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onVisibilityChange?(false)
    }
}
