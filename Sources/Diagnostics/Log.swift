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

    /// Debug builds log every value `.public` (the E2E harness greps the full line). Release
    /// builds keep the event name, keys and numeric/boolean values public and mark string values
    /// (bundle ids, paths, ids, error text) `.private` (REG-030).
    #if DEBUG
    static let redactsStrings = false
    #else
    static let redactsStrings = true
    #endif

    /// Logs `event k1=v1 k2=v2`. Values are sanitised (spaces → `_`, empty → `-`).
    public static func event(_ category: LogCategory, _ name: String, _ fields: KeyValuePairs<String, any CustomStringConvertible> = [:]) {
        let line = format(name, fields, redactStrings: redactsStrings)
        if let hidden = line.private {
            loggers[category]!.log("\(line.public, privacy: .public)\(hidden, privacy: .private)")
        } else {
            loggers[category]!.log("\(line.public, privacy: .public)")
        }
    }

    /// Debug-level variant for chatty events (edge trace, edge.push).
    public static func debug(_ category: LogCategory, _ name: String, _ fields: KeyValuePairs<String, any CustomStringConvertible> = [:]) {
        let line = format(name, fields, redactStrings: redactsStrings)
        if let hidden = line.private {
            loggers[category]!.debug("\(line.public, privacy: .public)\(hidden, privacy: .private)")
        } else {
            loggers[category]!.debug("\(line.public, privacy: .public)")
        }
    }

    /// Error text can contain paths and user data: public only in debug builds.
    public static func error(_ category: LogCategory, _ message: String) {
        if redactsStrings {
            loggers[category]!.error("\(message, privacy: .private)")
        } else {
            loggers[category]!.error("\(message, privacy: .public)")
        }
    }

    /// Splits a log line into its public and private parts. Without redaction everything is
    /// public, in field order; with it, string-valued fields move to the private part. The
    /// private part is nil when nothing is redacted: os_log renders even an empty `.private`
    /// interpolation as `<private>`, which corrupted the last field of every line (REG-043).
    static func format(_ name: String, _ fields: KeyValuePairs<String, any CustomStringConvertible>,
                       redactStrings: Bool) -> (public: String, private: String?) {
        var pub = name
        var priv = ""
        for (key, value) in fields {
            let text = " \(key)=\(sanitise(value.description))"
            if redactStrings && !isNumericOrBool(value) { priv += text } else { pub += text }
        }
        return (pub, priv.isEmpty ? nil : priv)
    }

    /// Numbers, booleans and numeric strings (e.g. `DedockLog.pt(_:)` output) are safe to keep public.
    static func isNumericOrBool(_ value: any CustomStringConvertible) -> Bool {
        switch value {
        case is Bool, is any BinaryInteger, is any BinaryFloatingPoint: return true
        default: return Double(value.description) != nil
        }
    }

    static func sanitise(_ s: String) -> String {
        s.isEmpty ? "-" : s.replacingOccurrences(of: " ", with: "_")
    }

    /// Formats a point value with two decimals, for `x=`/`y=`/`tx=` fields.
    public static func pt(_ v: Double) -> String { String(format: "%.2f", v) }
}
