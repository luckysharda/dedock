import AppKit
import DedockCore
import DesignSystem
import Diagnostics

/// The pending question after a tile was dragged out of the dock (evaluation row 43, design
/// §2.3a). It answers exactly once: Remove, Keep, or Keep after `timeout` without an answer.
@MainActor final class RemovalConfirmation {
    enum Result: String { case remove, keep, timeout }

    let tile: TileID
    private let onResult: (Result) -> Void
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private var timer: Task<Void, Never>?
    private(set) var result: Result?

    init(tile: TileID, clock: any Clock<Duration>, timeout: Duration = .seconds(8), onResult: @escaping (Result) -> Void) {
        self.tile = tile
        self.clock = clock
        self.timeout = timeout
        self.onResult = onResult
    }

    /// Starts the no-answer timeout (Keep).
    func start() {
        let clock = clock, timeout = timeout
        timer = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: timeout, tolerance: .milliseconds(100)) } catch { return }
            self?.answer(.timeout)
        }
    }

    func answer(_ r: Result) {
        guard result == nil else { return }
        result = r
        timer?.cancel()
        onResult(r)
    }
}

/// The drag-out question as a P2 Capsule toast (design.md §7.2a): the tile's icon,
/// "Remove “<Name>”?", [Remove] [Keep], unrolling from the dock beside the tile's slot. Never
/// key, never modal (a modal alert stalled the pointer monitors, REG-057). Keep is the default;
/// Esc (when focused), a click elsewhere, or the timeout keep the tile.
@MainActor final class RemoveConfirmPanel: NSObject {
    let toast: CapsuleToast
    var panel: NSPanel { toast.panel }
    private let confirmation: RemovalConfirmation
    private var monitors: [Any] = []

    /// The full question: the AXTitle and the announcement.
    static func title(for name: String) -> String { "Remove \u{201C}\(name)\u{201D} from the Edge Dock?" }

    /// The pill's short line, the name middle-truncated so the pill stays within 520 pt.
    static func shortText(for name: String, room: CGFloat, measure: (String) -> CGFloat) -> String {
        let prefix = "Remove \u{201C}", suffix = "\u{201D}?"
        return prefix + ToastLayout.middleTruncated(name, prefix: prefix, suffix: suffix, maxWidth: room, measure: measure) + suffix
    }

    init(name: String, icon: NSImage?, tokens: DockTokens, confirmation: RemovalConfirmation) {
        self.confirmation = confirmation
        weak var weakSelf: RemoveConfirmPanel?
        let buttons = [
            CapsuleToast.Button(title: "Remove", role: .destructive) { weakSelf?.remove() },
            CapsuleToast.Button(title: "Keep", role: .plain, isDefault: true) { weakSelf?.keep() },
        ]
        // Room for the line: the widest pill less the icon, both buttons and the paddings.
        let L = ToastLayout.self
        let buttonsWidth = ["Remove", "Keep"].reduce(CGFloat(0)) { w, t in
            w + ToastButton(title: t, role: .plain, light: false) {}.intrinsicContentSize.width + L.spacing
        }
        let room = L.maxWidth - L.leadingWithIcon - CapsuleToast.iconSize - L.spacing - buttonsWidth - L.trailing - 2
        toast = CapsuleToast(CapsuleToast.Content(
            icon: icon, text: Self.shortText(for: name, room: room, measure: CapsuleToast.measure), truncation: .byTruncatingMiddle,
            buttons: buttons, accessibilityTitle: Self.title(for: name)), look: .dock(tokens))
        super.init()
        weakSelf = self
    }

    /// Shows the toast beside the tile's slot without making it key, and starts the timeout. A
    /// click anywhere outside it keeps the tile. Esc and Return reach it only when it has focus
    /// through VoiceOver or Full Keyboard Access: it never takes key focus itself (typing stays
    /// with the user's app), so for everyone else the click elsewhere and the timeout are the
    /// Keep paths. A global Esc needs the Accessibility grant (T28).
    func show(capsule: CGRect, slot: CGPoint, edge: ScreenEdge, visible: CGRect, reduceMotion: Bool) {
        let place = ToastLayout.confirm(width: toast.width, capsule: capsule, slot: slot, edge: edge, visible: visible)
        toast.show(at: place.frame, growth: place.growth, reduceMotion: reduceMotion)
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.keep() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask.union(.keyDown), handler: { [weak self] event in
            let esc = event.type == .keyDown && event.keyCode == 53
            let click = event.type != .keyDown
            let window = event.windowNumber, location = event.locationInWindow
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if esc { self.keep(); return true }      // Esc keeps (only when focused, see above)
                if click, CapsuleToast.clickIsElsewhere(eventWindow: window, panelWindow: self.panel.windowNumber,
                                                        location: location, pill: self.toast.pillRect) {
                    self.keep()                                                       // a click elsewhere keeps
                }
                return false
            }
            return consumed ? nil : event
        }) { monitors.append(m) }
        confirmation.start()
    }

    @objc func keep() { confirmation.answer(.keep) }
    @objc func remove() { confirmation.answer(.remove) }

    /// Called once the confirmation has an answer: fades out (0.30 s).
    func close() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        toast.dismiss()
    }
}
