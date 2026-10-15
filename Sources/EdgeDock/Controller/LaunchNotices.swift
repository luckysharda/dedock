import Foundation

/// Notices found while loading settings. They are held until the docks are live and then shown
/// asynchronously, so a notice never blocks dock setup or `launch.edgeReady` (REG-057).
@MainActor public final class LaunchNotices {
    public enum Notice: Equatable, Sendable {
        /// A corrupt layout was moved aside; the layout came from the backup or the defaults.
        case recovered(movedTo: String, fromBackup: Bool)
        /// The layout file could not be read; this session runs on defaults and saves nothing.
        case readOnly
    }

    private(set) var pending: [Notice] = []
    private(set) var docksLive = false
    private let present: @MainActor (Notice) -> Void
    private let schedule: @MainActor (@escaping @MainActor () -> Void) -> Void

    /// - Parameters:
    ///   - present: shows one notice (an alert in the app).
    ///   - schedule: runs a presentation later; defaults to the next main-queue turn.
    public init(present: @escaping @MainActor (Notice) -> Void,
                schedule: (@MainActor (@escaping @MainActor () -> Void) -> Void)? = nil) {
        self.present = present
        self.schedule = schedule ?? { work in DispatchQueue.main.async { MainActor.assumeIsolated { work() } } }
    }

    public func post(_ notice: Notice) {
        if docksLive { show(notice) } else { pending.append(notice) }
    }

    /// Called by `EdgeDockManager` once edge sensing is live.
    func docksAreLive() {
        guard !docksLive else { return }
        docksLive = true
        let held = pending
        pending = []
        for notice in held { show(notice) }
    }

    private func show(_ notice: Notice) {
        let present = present
        schedule { present(notice) }
    }
}
