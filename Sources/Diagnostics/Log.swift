import Foundation
import os

/// Log categories under subsystem `app.dedock.Dedock` (E2E contract §3).
public enum LogCategory: String, Sendable, CaseIterable {
    case launch, edge, reveal, layout, tiles, settings, pointer, frame, display, app
}

/// Structured log lines: `<event> key=value …`, every value `.public`, no spaces inside values.
/// The E2E harness greps the event name at the start of the message, so names are a contract.
/// Never log window titles.
public enum DedockLog {
    public static let subsystem = "app.dedock.Dedock"

    private static let loggers: [LogCategory: Logger] = Dictionary(
        uniqueKeysWithValues: LogCategory.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) })

    /// Logs `event k1=v1 k2=v2`. Values are sanitised (spaces → `_`, empty → `-`).
    public static func event(_ category: LogCategory, _ name: String, _ fields: KeyValuePairs<String, any CustomStringConvertible> = [:]) {
        var line = name
        for (key, value) in fields {
            line += " \(key)=\(sanitise(value.description))"
        }
        loggers[category]!.log("\(line, privacy: .public)")
    }

    /// Debug-level variant for chatty events (edge trace, edge.push).
    public static func debug(_ category: LogCategory, _ name: String, _ fields: KeyValuePairs<String, any CustomStringConvertible> = [:]) {
        var line = name
        for (key, value) in fields {
            line += " \(key)=\(sanitise(value.description))"
        }
        loggers[category]!.debug("\(line, privacy: .public)")
    }

    public static func error(_ category: LogCategory, _ message: String) {
        loggers[category]!.error("\(message, privacy: .public)")
    }

    static func sanitise(_ s: String) -> String {
        s.isEmpty ? "-" : s.replacingOccurrences(of: " ", with: "_")
    }

    /// Formats a point value with two decimals, for `x=`/`y=`/`tx=` fields.
    public static func pt(_ v: Double) -> String { String(format: "%.2f", v) }
}
