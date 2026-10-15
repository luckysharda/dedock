import AppKit
import Diagnostics

/// Running, frontmost and hidden state of regular apps, from `NSWorkspace` notifications
/// (DD-962). Only `activationPolicy == .regular` apps count.
@MainActor public final class RunningAppsMonitor {
    public private(set) var states: [String: TileModel.Running] = [:]
    public var onChange: (() -> Void)?
    private var observers: [any NSObjectProtocol] = []
    private var policyObservations: [pid_t: NSKeyValueObservation] = [:]

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
        let changed = Set(next.keys).union(states.keys).filter { next[$0] != states[$0] }
        states = next
        for id in changed.sorted() {
            DedockLog.event(.tiles, "tile.indicator", ["bundle": id, "state": (next[id] ?? .none).rawValue])
        }
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

    /// Apps that change their activation policy after launch.
    private func watchPolicy(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard policyObservations[pid] == nil, !app.isTerminated else { return }
        policyObservations[pid] = app.observe(\.activationPolicy) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}
