import AppKit
import CoreGraphics
import DedockCore
import Diagnostics

/// Watches for full-screen Spaces and full-display windows per display (DD-924, T11).
///
/// Checked on Space changes and app activation, never by polling. A change is reported only if
/// it still holds after a 120 ms confirmation hold, which debounces Space-switch animations.
@MainActor public final class FullscreenProbe {
    public private(set) var states: [DisplayIdentity: Bool] = [:]
    /// Called with the displays whose state changed.
    public var onChange: (([DisplayIdentity: Bool]) -> Void)?

    private let clock: any Clock<Duration>
    private let hold: Duration
    private let layout: () -> DisplayLayout
    private let windows: () -> [WindowRecord]
    private var observers: [any NSObjectProtocol] = []
    private var confirm: Task<Void, Never>?

    /// - Parameters:
    ///   - windows: the on-screen window source; defaults to `CGWindowListCopyWindowInfo`.
    public init(clock: any Clock<Duration>, hold: Duration = .milliseconds(120),
                layout: @escaping () -> DisplayLayout, windows: (() -> [WindowRecord])? = nil) {
        self.clock = clock
        self.hold = hold
        self.layout = layout
        self.windows = windows ?? FullscreenProbe.onScreenWindows
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        states = FullscreenDetection.states(self.windows(), layout: layout(), ownPID: getpid())
    }

    /// Re-check now (after a display change, for example), confirming after the hold.
    public func check() {
        let candidate = FullscreenDetection.states(windows(), layout: layout(), ownPID: getpid())
        guard candidate != states else {
            confirm?.cancel()
            return
        }
        confirm?.cancel()
        let clock = clock, hold = hold
        confirm = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: hold, tolerance: .zero) } catch { return }
            guard let self else { return }
            let confirmed = FullscreenDetection.states(self.windows(), layout: self.layout(), ownPID: getpid())
            guard confirmed == candidate else { return } // still moving: the next notification re-checks
            let changed = confirmed.filter { self.states[$0.key] != $0.value }
            self.states = confirmed
            guard !changed.isEmpty else { return }
            for (id, on) in changed {
                DedockLog.event(.display, "display.fullscreen", ["display": id.uuid, "on": on])
            }
            self.onChange?(changed)
        }
    }

    public func invalidate() {
        confirm?.cancel()
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        observers.removeAll()
    }

    /// On-screen windows, owner / layer / alpha / bounds only (no Screen Recording needed).
    public static func onScreenWindows() -> [WindowRecord] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
            let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1
            return WindowRecord(ownerPID: pid, layer: layer, alpha: alpha, bounds: bounds)
        }
    }
}
