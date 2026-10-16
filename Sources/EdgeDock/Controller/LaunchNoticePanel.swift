import AppKit
import DesignSystem

/// The one-time launch notice (a damaged or unreadable layout) as a P2 Capsule toast (design.md
/// §7.2a): one line and [OK], dropping from the menu bar under Dedock's status item, in the
/// window look (Window appearance × Window material, like Settings). It is never modal:
/// `NSAlert.runModal` ran a modal session on the main thread, and the pointer monitors and
/// reveal timers stalled until OK was clicked (REG-057). It
/// neither activates Dedock nor becomes key on its own, so the user's app keeps focus and
/// keystrokes. OK or a click elsewhere closes it; it never times out.
@MainActor public final class LaunchNoticePanel: NSObject {
    let toast: CapsuleToast
    public var panel: NSPanel { toast.panel }
    private let onClose: (LaunchNoticePanel) -> Void
    private var monitors: [Any] = []
    private var closed = false

    /// The pill's line, and the longer explanation read by VoiceOver (accessibility help).
    public static func text(for notice: LaunchNotices.Notice) -> (line: String, detail: String) {
        switch notice {
        case let .recovered(movedTo, fromBackup):
            (fromBackup ? "Your Edge Dock layout was damaged. Dedock restored the backup."
                        : "Your Edge Dock layout was damaged. Dedock started fresh.",
             "The damaged file was kept as \(movedTo).")
        case .readOnly:
            ("Dedock can't read its layout, so changes won't be saved.",
             "The Edge Dock is using the default layout until the layout file can be read again.")
        }
    }

    /// - Parameters:
    ///   - look: the Window appearance and material (Reduce Transparency already applied).
    ///   - onClose: called with this notice once OK or a click elsewhere closes it.
    public init(_ notice: LaunchNotices.Notice,
                look: WindowLook = WindowLook(appearance: .system, material: .frosted,
                                              reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency),
                onClose: @escaping (LaunchNoticePanel) -> Void = { _ in }) {
        self.onClose = onClose
        let text = Self.text(for: notice)
        weak var weakSelf: LaunchNoticePanel?
        toast = CapsuleToast(CapsuleToast.Content(
            icon: nil, text: text.line, truncation: .byTruncatingTail,
            buttons: [CapsuleToast.Button(title: "OK", role: .accent, isDefault: true) { weakSelf?.dismiss() }],
            accessibilityTitle: text.line, accessibilityHelp: text.detail),
            look: .window(look, dark: Self.isDark(look)))
        super.init()
        weakSelf = self
    }

    /// The look's appearance, resolved: System follows the app's effective appearance.
    static func isDark(_ look: WindowLook) -> Bool {
        let appearance = look.nsAppearance ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .darkAqua)!
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Shows the notice 6 pt under the menu bar, centred on Dedock's status item (or on the
    /// display when the item is hidden), and returns at once; no modal session is started.
    /// - Parameter visible: the visible frame of the display with the menu bar.
    public func show(statusItem: CGRect? = nil, visible: CGRect? = nil, reduceMotion: Bool = false) {
        let v = visible ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let place = ToastLayout.notice(width: toast.width, statusItem: statusItem, visible: v)
        toast.show(at: place.frame, growth: place.growth, reduceMotion: reduceMotion)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            let esc = event.type == .keyDown && event.keyCode == 53
            let click = event.type != .keyDown
            let window = event.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if esc { self.dismiss(); return true }                               // only when focused
                if click, window != self.panel.windowNumber { self.dismiss() }      // a click elsewhere
                return false
            }
            return consumed ? nil : event
        }) { monitors.append(m) }
    }

    /// Closes the notice: reported at once, then a 0.30 s fade.
    @objc public func dismiss() {
        guard !closed else { return }
        closed = true
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        toast.dismiss()
        onClose(self)
    }
}
