import Foundation

/// Debug-only switches read from the process environment (E2E contract §2; architecture §7).
/// Release builds ignore every one of them.
public struct DedockEnvironment: Sendable {
    /// `DEDOCK_E2E=1`: GEOM output and E2E log lines.
    public let e2e: Bool
    /// `DEDOCK_FRAME_LOG=1`: one `frame` log line per display-link callback while animating.
    public let frameLog: Bool
    /// `DEDOCK_EDGE_TRACE=1`: log every evaluated pointer sample (debug level).
    public let edgeTrace: Bool
    /// `DEDOCK_E2E_HOME` (alias of `DEDOCK_DATA_DIR`): the data folder override.
    public let dataDirectoryOverride: URL?

    public static let current = DedockEnvironment(ProcessInfo.processInfo.environment)

    public init(_ env: [String: String]) {
        #if DEBUG
        func flag(_ key: String) -> Bool { ["1", "true", "yes"].contains(env[key]?.lowercased() ?? "") }
        e2e = flag("DEDOCK_E2E")
        frameLog = flag("DEDOCK_FRAME_LOG")
        edgeTrace = flag("DEDOCK_EDGE_TRACE")
        let dir = env["DEDOCK_E2E_HOME"] ?? env["DEDOCK_DATA_DIR"]
        dataDirectoryOverride = dir.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        #else
        e2e = false
        frameLog = false
        edgeTrace = false
        dataDirectoryOverride = nil
        #endif
    }

    /// The data folder: the override, else `~/Library/Application Support/Dedock Debug` (debug)
    /// or `…/Dedock` (release). Fixed strings, never derived from the bundle (architecture §5).
    public var dataDirectory: URL {
        if let dataDirectoryOverride { return dataDirectoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #if DEBUG
        return base.appendingPathComponent("Dedock Debug", isDirectory: true)
        #else
        return base.appendingPathComponent("Dedock", isDirectory: true)
        #endif
    }
}
