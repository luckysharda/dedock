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
    /// A one-line note when the dock's trigger uses a fallback rule (REG-066), else nil.
    public var triggerHint: () -> String?

    public init(nativeDockEdge: @escaping () -> ScreenEdge, hasSharedEdge: @escaping (ScreenEdge) -> Bool,
                triggerHint: @escaping () -> String? = { nil }) {
        self.nativeDockEdge = nativeDockEdge
        self.hasSharedEdge = hasSharedEdge
        self.triggerHint = triggerHint
    }
}

/// The Settings window: an `NSWindow` dedock owns (architecture §8). Opening it switches the
/// app to `.regular` and activates it; closing switches back to `.accessory`.
@MainActor public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var backdrop: WindowBackdropView?
    private let chrome = SettingsChrome()
    private var settingsObserver: UUID?
    private var accessibilityObserver: (any NSObjectProtocol)?
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
            let root = SettingsRootView(settings: settings, environment: environment, navigation: SettingsNavigation(), chrome: chrome)
            let w = NSWindow(contentRect: CGRect(origin: .zero, size: SettingsTokens.windowSize),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Dedock Settings"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            // The backdrop under the SwiftUI content: Frosted, Liquid Glass or Solid (T37).
            let container = NSView(frame: CGRect(origin: .zero, size: SettingsTokens.windowSize))
            let backdrop = WindowBackdropView(frame: container.bounds)
            let hosting = NSHostingView(rootView: root)
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(backdrop)
            container.addSubview(hosting)
            w.contentView = container
            self.backdrop = backdrop
            w.contentMinSize = CGSize(width: 760, height: 520)
            w.delegate = self
            w.center()
            window = w
            applyLook()
            settingsObserver = settings.addObserver { [weak self] _ in self?.applyLook() }
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.applyLook() } }
        }
        let wasVisible = isVisible
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !wasVisible { onVisibilityChange?(true) }
    }

    /// The current Window appearance and material, after Reduce Transparency.
    var look: WindowLook {
        let app = settings.document.app
        return WindowLook(appearance: WindowLook.Appearance(rawValue: app.windowAppearance.rawValue) ?? .system,
                          material: WindowLook.Material(rawValue: app.windowMaterial.rawValue) ?? .frosted,
                          reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }

    /// Applies the look at once (a change in Settings plays on the open window).
    private func applyLook() {
        guard let window else { return }
        let look = look
        window.appearance = look.nsAppearance
        window.isOpaque = look.backdrop == .solid
        window.backgroundColor = look.backdrop == .solid ? .windowBackgroundColor : .clear
        backdrop?.apply(look.backdrop)
        chrome.backdrop = look.backdrop
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onVisibilityChange?(false)
    }
}
