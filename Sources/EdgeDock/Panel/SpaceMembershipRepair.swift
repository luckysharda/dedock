import AppKit
import Diagnostics

/// Keeps a shown dock panel on every Space (architecture §6.9 "Spaces membership", DD-947).
/// After a full-screen Space closes, macOS can re-attach a `.canJoinAllSpaces` panel to one
/// desktop only. After a Space change, wake, full-screen exit or a Dock relaunch, `check`
/// verifies the panel is on the active Space; if not it assigns a different collection
/// behaviour, waits one run-loop turn, restores the original, re-checks after 120 ms, and retries
/// up to 3 times before rebuilding the panel.
@MainActor final class SpaceMembershipRepair {
    struct Window {
        var isVisible: () -> Bool
        var isOnActiveSpace: () -> Bool
        var behavior: () -> NSWindow.CollectionBehavior
        var setBehavior: (NSWindow.CollectionBehavior) -> Void
        /// Order out and back in (the last resort).
        var rebuild: () -> Void
    }

    static let attempts = 3
    static let recheck: Duration = .milliseconds(120)

    private let window: Window
    private let clock: any Clock<Duration>
    private var task: Task<Void, Never>?
    let edge: String

    init(window: Window, clock: any Clock<Duration>, edge: String) {
        self.window = window
        self.clock = clock
        self.edge = edge
    }

    convenience init(panel: NSPanel, clock: any Clock<Duration>, edge: String) {
        self.init(window: Window(
            isVisible: { [weak panel] in panel?.isVisible ?? false },
            isOnActiveSpace: { [weak panel] in panel?.isOnActiveSpace ?? true },
            behavior: { [weak panel] in panel?.collectionBehavior ?? [] },
            setBehavior: { [weak panel] in panel?.collectionBehavior = $0 },
            rebuild: { [weak panel] in
                panel?.orderOut(nil)
                panel?.orderFrontRegardless()
            }), clock: clock, edge: edge)
    }

    var isRepairing: Bool { task != nil }

    /// Checks membership and repairs it if needed. A hidden (ordered-out) panel needs nothing.
    func check(reason: String) {
        guard task == nil, window.isVisible(), !window.isOnActiveSpace() else { return }
        DedockLog.event(.display, "space.repair", ["edge": edge, "reason": reason, "step": "start"])
        let original = window.behavior()
        // Any different behaviour makes AppKit re-evaluate membership when the original returns.
        let other: NSWindow.CollectionBehavior = original.contains(.canJoinAllSpaces)
            ? original.subtracting(.canJoinAllSpaces).union(.moveToActiveSpace)
            : original.union(.canJoinAllSpaces)
        let window = window, clock = clock, edge = edge
        task = Task { @MainActor [weak self] in
            defer { self?.task = nil }
            for attempt in 1...Self.attempts {
                window.setBehavior(other)
                await Task.yield()                        // one run-loop turn
                window.setBehavior(original)
                do { try await clock.sleep(for: Self.recheck, tolerance: .zero) } catch { return }
                if window.isOnActiveSpace() {
                    DedockLog.event(.display, "space.repair", ["edge": edge, "step": "fixed", "attempt": attempt])
                    return
                }
            }
            window.rebuild()
            DedockLog.event(.display, "space.repair", ["edge": edge, "step": "rebuilt"])
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
