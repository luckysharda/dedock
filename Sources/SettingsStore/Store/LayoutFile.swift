import DedockCore
import Foundation

/// Reads and writes `layout.json` in the data folder (architecture §7).
///
/// - Save: atomic replace, sorted keys, pretty-printed, keeping 5 rolling backups
///   `layout.json.1…5` (1 = the previous version).
/// - Load: decode → migrate → typed model. A corrupt file is renamed to
///   `layout.corrupt-<ISO8601>.json` and the newest readable backup is used; with no usable
///   file at all, a default document is seeded.
public actor LayoutFile {
    public static let fileName = "layout.json"
    public static let backupCount = 5

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    /// How `load` produced its document; the caller logs it and shows the one-time notice.
    public enum Source: Sendable, Equatable {
        case file
        /// The main file was missing or corrupt; this backup (1…5) was used.
        case backup(Int)
        /// Nothing usable existed; a default document was seeded (not yet saved).
        case defaultSeed
    }

    public struct LoadResult: Sendable, Equatable {
        public let document: DedockDocument
        public let source: Source
        /// Where a corrupt `layout.json` was moved, if it was.
        public let corruptFileMovedTo: URL?
    }

    /// Loads the document, recovering from corruption. Never fails on bad content; throws only
    /// if a corrupt file cannot be moved aside.
    public func load(nativeDockEdge: ScreenEdge? = .bottom) throws -> LoadResult {
        var movedTo: URL?
        if fileManager.fileExists(atPath: fileURL.path) {
            if let doc = try? Self.decode(Data(contentsOf: fileURL)) {
                return LoadResult(document: doc, source: .file, corruptFileMovedTo: nil)
            }
            movedTo = try moveCorruptFileAside()
        }
        for n in 1...Self.backupCount {
            let url = backupURL(n)
            guard fileManager.fileExists(atPath: url.path), let doc = try? Self.decode(Data(contentsOf: url)) else { continue }
            return LoadResult(document: doc, source: .backup(n), corruptFileMovedTo: movedTo)
        }
        return LoadResult(document: .makeDefault(nativeDockEdge: nativeDockEdge), source: .defaultSeed,
                          corruptFileMovedTo: movedTo)
    }

    /// Writes the document atomically, rotating the previous file into the backups.
    public func save(_ document: DedockDocument) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encode(document)
        if fileManager.fileExists(atPath: fileURL.path) {
            try rotateBackups()
        }
        try data.write(to: fileURL, options: .atomic)
    }

    public func backupURL(_ n: Int) -> URL { directory.appendingPathComponent("\(Self.fileName).\(n)") }

    // MARK: - Coding

    public static func decode(_ data: Data) throws -> DedockDocument {
        let tree = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = tree.objectValue else { throw LayoutFileError.notAnObject }
        return DedockDocument(object: try Migration.migrate(object))
    }

    public static func encode(_ document: DedockDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    // MARK: - Files

    private func rotateBackups() throws {
        let oldest = backupURL(Self.backupCount)
        if fileManager.fileExists(atPath: oldest.path) { try fileManager.removeItem(at: oldest) }
        for n in stride(from: Self.backupCount - 1, through: 1, by: -1) {
            let from = backupURL(n)
            if fileManager.fileExists(atPath: from.path) { try fileManager.moveItem(at: from, to: backupURL(n + 1)) }
        }
        try fileManager.copyItem(at: fileURL, to: backupURL(1))
    }

    private func moveCorruptFileAside() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'" // ISO 8601 basic format: no colons in file names
        var target = directory.appendingPathComponent("layout.corrupt-\(formatter.string(from: Date())).json")
        var suffix = 2
        while fileManager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("layout.corrupt-\(formatter.string(from: Date()))-\(suffix).json")
            suffix += 1
        }
        try fileManager.moveItem(at: fileURL, to: target)
        return target
    }
}

public enum LayoutFileError: Error, Equatable {
    case notAnObject
}
