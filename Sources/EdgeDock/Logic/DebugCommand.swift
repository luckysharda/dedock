import DedockCore
import Foundation

// Pure (architecture rule D5): parsing only; the listener is macOS-only (E2E/DebugCommands.swift).

/// Debug-only E2E command channel (debug bundle + `DEDOCK_E2E=1` only; never in release).
///
/// Post with: `DistributedNotificationCenter.default().postNotificationName(.init("app.dedock.debug.command"),
/// object: nil, userInfo: ["cmd": "setEdge=right"], deliverImmediately: true)`.
/// Commands: `setEdge=<left|right|bottom|top>` (same path as the status menu), `rebuildZones`,
/// `reveal`, `hide`. Each logs `debug.command cmd=… ok=…`.
public enum DebugCommand: Equatable, Sendable {
    case setEdge(ScreenEdge)
    case rebuildZones
    case reveal
    case hide

    public static let notificationName = "app.dedock.debug.command"

    /// Parses the `cmd` user-info value. Unknown commands are rejected (nil).
    public static func parse(_ raw: String) -> DebugCommand? {
        let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
        switch parts.first {
        case "setEdge": return parts.count == 2 ? ScreenEdge(rawValue: parts[1]).map(DebugCommand.setEdge) : nil
        case "rebuildZones" where parts.count == 1: return .rebuildZones
        case "reveal" where parts.count == 1: return .reveal
        case "hide" where parts.count == 1: return .hide
        default: return nil
        }
    }
}
