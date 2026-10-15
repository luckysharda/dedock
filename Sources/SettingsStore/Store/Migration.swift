import Foundation

/// Schema migrations, applied to the raw JSON tree before typed decoding (architecture §7).
///
/// Step `n` turns a schema-`n` document into schema `n + 1`. v1 is the first schema, so there
/// are no steps yet; the table is where they go.
public enum Migration {
    public typealias Step = @Sendable ([String: JSONValue]) throws -> [String: JSONValue]

    public static let steps: [Int: Step] = [:]

    /// Migrates `object` up to `DedockDocument.currentSchema`. A document from a *newer* build
    /// is left as is: its unknown keys survive through the `unknown` bags.
    public static func migrate(_ object: [String: JSONValue],
                               steps: [Int: Step] = Migration.steps,
                               to target: Int = DedockDocument.currentSchema) throws -> [String: JSONValue] {
        var doc = object
        var version = JSONReader(doc).int("schemaVersion", default: 1)
        while version < target {
            guard let step = steps[version] else { throw MigrationError.missingStep(from: version) }
            doc = try step(doc)
            version += 1
            doc["schemaVersion"] = .number(Double(version))
        }
        return doc
    }
}

public enum MigrationError: Error, Equatable {
    case missingStep(from: Int)
}
