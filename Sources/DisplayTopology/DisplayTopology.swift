import AppKit
import DedockCore
import Diagnostics

/// Cancels an observation. Dropping the token also ends the observation.
@MainActor public final class ObservationToken {
    fileprivate var isCancelled = false
    public init() {}
    public func cancel() { isCancelled = true }
}

/// The AppKit adapter that produces `DisplayLayout` values (architecture §6.10).
///
/// Screen-parameter changes are debounced (1 s default); wake triggers an immediate refresh.
/// Every change bumps `layout.generation`; observers are only called when the layout changes.
@MainActor public final class DisplayTopology {
    public private(set) var layout: DisplayLayout

    private let debounce: Duration
    private let clock: any Clock<Duration>
    private let read: @MainActor () -> [DisplaySnapshot]
    private struct Observer {
        weak var token: ObservationToken?
        let handler: @MainActor (DisplayLayout) -> Void
    }
    private var observers: [Observer] = []
    private var debounceTask: Task<Void, Never>?
    private var notificationTokens: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameter reader: snapshot source; defaults to `NSScreen.screens`. Tests inject fakes.
    public init(debounce: Duration = .seconds(1), clock: any Clock<Duration> = ContinuousClock(),
                reader: (@MainActor () -> [DisplaySnapshot])? = nil) {
        self.debounce = debounce
        self.clock = clock
        self.read = reader ?? { ScreenReader.snapshots() }
        layout = DisplayLayout(displays: read(), generation: 1)
        DedockLog.event(.display, "display.layout", ["gen": layout.generation, "count": layout.displays.count])
        startObserving()
    }

    public func observe(_ handler: @escaping @MainActor (DisplayLayout) -> Void) -> ObservationToken {
        let token = ObservationToken()
        observers.removeAll { $0.token == nil || $0.token?.isCancelled == true }
        observers.append(Observer(token: token, handler: handler))
        return token
    }

    /// Re-reads the screens now (after wake and for "Reset Layout"). Notifies only on change.
    public func refreshNow() {
        debounceTask?.cancel()
        debounceTask = nil
        let displays = read()
        guard displays != layout.displays else { return }
        layout = DisplayLayout(displays: displays, generation: layout.generation + 1)
        DedockLog.event(.display, "display.layout", ["gen": layout.generation, "count": layout.displays.count])
        observers.removeAll { $0.token == nil || $0.token?.isCancelled == true }
        for observer in observers { observer.handler(layout) }
    }

    /// Schedules a debounced refresh (screen-parameter changes arrive in bursts).
    public func scheduleRefresh() {
        debounceTask?.cancel()
        let clock = clock
        let delay = debounce
        debounceTask = Task { @MainActor [weak self] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.refreshNow()
        }
    }

    private func startObserving() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        notificationTokens = [
            (center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNow() }
            }),
        ]
    }

    /// Stops observing the system (the instance otherwise lives for the app's lifetime).
    public func invalidate() {
        debounceTask?.cancel()
        for (center, token) in notificationTokens { center.removeObserver(token) }
        notificationTokens = []
    }
}

/// Reads `NSScreen` into `DisplaySnapshot`s.
@MainActor public enum ScreenReader {
    public static func snapshots() -> [DisplaySnapshot] {
        let screens = NSScreen.screens
        let thickness = NSStatusBar.system.thickness
        return screens.enumerated().map { index, screen in
            let id = displayID(of: screen)
            return DisplaySnapshot.make(
                identity: identity(of: id),
                displayID: id,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: screen.safeAreaInsets.top,
                statusBarThickness: thickness,
                auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
                auxiliaryTopRight: screen.auxiliaryTopRightArea,
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: index == 0,
                backingScale: screen.backingScaleFactor)
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// Hardware identity: the display UUID plus vendor / model / serial (architecture §6.10).
    public static func identity(of id: CGDirectDisplayID) -> DisplayIdentity {
        var uuidString = "display-\(id)"
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) as String? {
            uuidString = string
        }
        return DisplayIdentity(uuid: uuidString, vendor: CGDisplayVendorNumber(id),
                               model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }
}
