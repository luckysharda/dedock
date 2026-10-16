import AppKit
import CoreGraphics
import DedockCore
import Diagnostics

/// Watches for full-screen Spaces and full-display windows per display (DD-924, T11), and the
/// menu-bar status items the top-edge zones avoid (REG-044).
///
/// Checked on Space changes, app activation, launch and quit, never by polling. A full-screen
/// change is reported only once a reading holds for the 120 ms confirmation hold, which
/// debounces Space-switch animations; a reading that moves during the hold starts a new hold
/// (REG-046), at most `maxReholds` times, so a flapping window cannot turn it into a poller
/// (REG-058). macOS posts nothing when a status item appears, so launches are re-checked once
/// more after `statusSettle`, by which time a launching app has usually added its items.
/// Known limit (REG-044): an item added later by an app that is already running, or items
/// rearranged with ⌘-drag, are picked up only at the next Space change, activation, launch or
/// quit; an Accessibility-based refresh comes with the M2 permissions.
@MainActor public final class FullscreenProbe {
    public private(set) var states: [DisplayIdentity: Bool] = [:]
    /// Called with the displays whose state changed.
    public var onChange: (([DisplayIdentity: Bool]) -> Void)?
    /// Status-item rects per display, AppKit global coordinates.
    public private(set) var statusItems: [DisplayIdentity: [CGRect]] = [:]
    /// Status-level windows on the menu-bar line that were not item-sized, per display (REG-066).
    public private(set) var statusItemsRejected: [DisplayIdentity: Int] = [:]
    /// Called when any display's status items changed.
    public var onStatusItemsChange: (() -> Void)?

    private let clock: any Clock<Duration>
    private let hold: Duration
    private let statusSettle: Duration
    private let layout: () -> DisplayLayout
    private let windows: () -> [WindowRecord]
    private var observers: [any NSObjectProtocol] = []
    private var confirm: Task<Void, Never>?
    private var settle: Task<Void, Never>?

    /// - Parameters:
    ///   - windows: the on-screen window source; defaults to `CGWindowListCopyWindowInfo`.
    public init(clock: any Clock<Duration>, hold: Duration = .milliseconds(120), statusSettle: Duration = .seconds(1),
                layout: @escaping () -> DisplayLayout, windows: (() -> [WindowRecord])? = nil) {
        self.clock = clock
        self.hold = hold
        self.statusSettle = statusSettle
        self.layout = layout
        self.windows = windows ?? FullscreenProbe.onScreenWindows
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.check()
                    self?.recheckStatusItemsLater()
                }
            })
        }
        let records = self.windows(), now = layout()
        states = FullscreenDetection.states(records, layout: now, ownPID: getpid())
        (statusItems, statusItemsRejected) = Self.statusItems(records, layout: now)
    }

    /// Re-holds after the first hold before an unsettled reading is left to the next notification.
    static let maxReholds = 3

    /// Re-check now (after a display change, for example), confirming after the hold.
    public func check() { check(rehold: 0) }

    private func check(rehold: Int) {
        let records = windows(), now = layout()
        updateStatusItems(records, layout: now)
        let candidate = FullscreenDetection.states(records, layout: now, ownPID: getpid())
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
            // Still moving: the new reading becomes the candidate for another hold (REG-046),
            // up to the cap; then the next notification re-checks (REG-058).
            guard confirmed == candidate else {
                if rehold < Self.maxReholds {
                    self.check(rehold: rehold + 1)
                } else {
                    DedockLog.event(.display, "display.fullscreenUnsettled", ["reholds": rehold])
                }
                return
            }
            let changed = confirmed.filter { self.states[$0.key] != $0.value }
            self.states = confirmed
            guard !changed.isEmpty else { return }
            for (id, on) in changed {
                DedockLog.event(.display, "display.fullscreen", ["display": id.uuid, "on": on])
            }
            self.onChange?(changed)
        }
    }

    private func updateStatusItems(_ records: [WindowRecord], layout: DisplayLayout) {
        let (next, rejected) = Self.statusItems(records, layout: layout)
        statusItemsRejected = rejected
        guard next != statusItems else { return }
        statusItems = next
        onStatusItemsChange?()
    }

    private func recheckStatusItemsLater() {
        settle?.cancel()
        let clock = clock, delay = statusSettle
        settle = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: delay, tolerance: .milliseconds(100)) } catch { return }
            guard let self else { return }
            self.updateStatusItems(self.windows(), layout: self.layout())
        }
    }

    static func statusItems(_ records: [WindowRecord], layout: DisplayLayout)
        -> (items: [DisplayIdentity: [CGRect]], rejected: [DisplayIdentity: Int]) {
        var result: [DisplayIdentity: [CGRect]] = [:]
        var rejected: [DisplayIdentity: Int] = [:]
        for d in layout.displays {
            let found = StatusItemGeometry.classify(records, display: d, primaryHeight: layout.primaryHeight)
            // Sorted: the window list is in z-order, which changes without the items changing.
            let rects = found.items.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
            if !rects.isEmpty { result[d.identity] = rects }
            if found.rejected > 0 { rejected[d.identity] = found.rejected }
        }
        return (result, rejected)
    }

    public func invalidate() {
        confirm?.cancel()
        settle?.cancel()
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
