import AppKit

/// Running, frontmost and hidden state of regular apps, from `NSWorkspace` notifications
/// (DD-962). Only `activationPolicy == .regular` apps count.
@MainActor public final class RunningAppsMonitor {
    public private(set) var states: [String: TileModel.Running] = [:]
    public var onChange: (() -> Void)?
    private var observers: [any NSObjectProtocol] = []
    /// Apps that are not `.regular` yet, observed for a later policy change. The app object is
    /// held strongly so it outlives its KVO observation.
    private var watched: [pid_t: (app: NSRunningApplication, observation: NSKeyValueObservation)] = [:]

    public init() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ]
        for name in names {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    public func state(for bundleID: String?) -> TileModel.Running {
        bundleID.flatMap { states[$0] } ?? .none
    }

    public func refresh() {
        pruneWatched()
        var next: [String: TileModel.Running] = [:]
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            watchPolicy(app)
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { continue }
            let state: TileModel.Running = app.processIdentifier == frontmost ? .frontmost : (app.isHidden ? .hidden : .running)
            // Several instances: the strongest state wins.
            if let existing = next[id], rank(existing) >= rank(state) { continue }
            next[id] = state
        }
        guard next != states else { return }
        states = next
        // `tile.indicator` is logged by the coordinators, for dock tiles only: the full list of
        // running apps never goes to the log.
        onChange?()
    }

    private func rank(_ s: TileModel.Running) -> Int {
        switch s {
        case .none: 0
        case .hidden: 1
        case .running: 2
        case .frontmost: 3
        }
    }

    /// Apps that change their activation policy after launch (e.g. accessory → regular).
    private func watchPolicy(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy != .regular, !app.isTerminated, watched[pid] == nil else { return }
        let observation = app.observe(\.activationPolicy) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        watched[pid] = (app, observation)
    }

    /// Stop watching apps that quit or became regular.
    private func pruneWatched() {
        for (pid, entry) in watched where entry.app.isTerminated || entry.app.activationPolicy == .regular {
            entry.observation.invalidate()
            watched[pid] = nil
        }
    }
}
