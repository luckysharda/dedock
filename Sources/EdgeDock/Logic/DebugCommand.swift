import DedockCore
import Foundation

// Pure (architecture rule D5): parsing only; the listener is macOS-only (E2E/DebugCommands.swift).

/// Debug-only E2E command channel (debug bundle + `DEDOCK_E2E=1` only; never in release).
///
/// Post with: `DistributedNotificationCenter.default().postNotificationName(.init("app.dedock.debug.command"),
/// object: nil, userInfo: ["cmd": "setEdge=right"], deliverImmediately: true)`.
/// Commands: `setEdge=<left|right|bottom|top>` (same path as the status menu), `rebuildZones`,
/// `reveal`, `hide`, `openSettings`. Each logs `debug.command cmd=… ok=…`.
///
/// SECURITY RULE: any process in the user's session can post a distributed notification, so
/// commands stay benign and closed: a command may change only what the status menu can change
/// (`setEdge` saves the layout exactly as the status menu's edge choice does), must not write
/// any other file or launch apps, and takes no argument beyond an enum value or a number.
/// Unknown or malformed input is rejected, and the logged text is capped (`logged(_:)`).
public enum DebugCommand: Equatable, Sendable {
    /// At most this many characters of a posted command reach the log.
    public static let maxLoggedLength = 64

    /// The posted text as logged: any process can post arbitrary text into the debug log.
    public static func logged(_ raw: String) -> String {
        raw.count > maxLoggedLength ? String(raw.prefix(maxLoggedLength)) + "…" : raw
    }

    case setEdge(ScreenEdge)
    case rebuildZones
    case reveal
    case hide
    /// Opens the Settings window (as the status menu's Settings… does).
    case openSettings

    public static let notificationName = "app.dedock.debug.command"

    /// Parses the `cmd` user-info value. Unknown commands are rejected (nil).
    public static func parse(_ raw: String) -> DebugCommand? {
        let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
        switch parts.first {
        case "setEdge": return parts.count == 2 ? ScreenEdge(rawValue: parts[1]).map(DebugCommand.setEdge) : nil
        case "rebuildZones" where parts.count == 1: return .rebuildZones
        case "reveal" where parts.count == 1: return .reveal
        case "hide" where parts.count == 1: return .hide
        case "openSettings" where parts.count == 1: return .openSettings
        default: return nil
        }
    }
}
