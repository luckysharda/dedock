import DedockCore
import Diagnostics
import Foundation

/// Listens for debug commands and hands them to `handler` on the main actor.
@MainActor final class DebugCommandListener {
    // Written once in init, removed in deinit; never touched concurrently.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    init?(environment: DedockEnvironment = .current, handler: @escaping @MainActor (DebugCommand) -> Void) {
        #if DEBUG
        guard environment.e2e else { return nil }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(DebugCommand.notificationName), object: nil, queue: .main
        ) { note in
            let raw = note.userInfo?["cmd"] as? String ?? ""
            MainActor.assumeIsolated {
                guard let command = DebugCommand.parse(raw) else {
                    DedockLog.event(.app, "debug.command", ["cmd": raw, "ok": false])
                    return
                }
                DedockLog.event(.app, "debug.command", ["cmd": raw, "ok": true])
                handler(command)
            }
        }
        #else
        return nil
        #endif
    }

    deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
