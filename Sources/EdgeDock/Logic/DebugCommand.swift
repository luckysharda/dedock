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
/// (`setEdge` saves the layout exactly as the status menu's edge choice does), plus the dock's
/// display binding (`bindDisplay`, the E2E stand-in for the M8 display picker, limited to the
/// displays currently connected). It must not write any other file or launch apps, and takes
/// no argument beyond an enum value or a number.
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
    /// Binds the first dock to a display: `main`, or a connected display's id (T38 E2E).
    case bindDisplay(DisplayTarget)

    public enum DisplayTarget: Equatable, Sendable {
        case main
        /// A `CGDirectDisplayID`; the manager accepts it only if that display is connected.
        case id(UInt32)
    }

    public static let notificationName = "app.dedock.debug.command"

    /// Who a posted command is for. A distributed notification reaches every listening debug
    /// instance, so each command names its target process in `userInfo["pid"]`; another
    /// session's debug Dedock must not act on it.
    public enum Addressing: Equatable, Sendable {
        case mine
        /// Meant for another process: ignored quietly.
        case other
        /// No usable pid: rejected and logged.
        case missing
    }

    /// Reads `userInfo["pid"]` (a number, or a decimal string) against `ownPID`.
    public static func addressing(_ pid: Any?, ownPID: Int32) -> Addressing {
        let value: Int32? = switch pid {
        case let n as Int32: n
        case let n as Int: Int32(exactly: n)
        case let n as NSNumber: Int32(exactly: n.int64Value)
        case let s as String: Int32(s)
        default: nil
        }
        guard let value, value > 0 else { return .missing }
        return value == ownPID ? .mine : .other
    }

    /// Parses the `cmd` user-info value. Unknown commands are rejected (nil).
    public static func parse(_ raw: String) -> DebugCommand? {
        let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
        switch parts.first {
        case "setEdge": return parts.count == 2 ? ScreenEdge(rawValue: parts[1]).map(DebugCommand.setEdge) : nil
        case "rebuildZones" where parts.count == 1: return .rebuildZones
        case "reveal" where parts.count == 1: return .reveal
        case "hide" where parts.count == 1: return .hide
        case "openSettings" where parts.count == 1: return .openSettings
        case "bindDisplay" where parts.count == 2:
            if parts[1] == "main" { return .bindDisplay(.main) }
            guard !parts[1].isEmpty, parts[1].allSatisfy(\.isASCII), parts[1].allSatisfy(\.isNumber),
                  let id = UInt32(parts[1]) else { return nil }
            return .bindDisplay(.id(id))
        default: return nil
        }
    }
}
