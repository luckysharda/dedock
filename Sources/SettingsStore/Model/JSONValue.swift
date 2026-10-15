import Foundation

/// A lossless JSON tree. Used for migrations and for the `unknown` bags that let keys written
/// by a newer build survive a round-trip through an older one (architecture §7).
///
/// Deviation: architecture §2 lists `JSONValue` in DedockCore; it lives here until a second
/// module needs it.
public enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not a JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // Whole numbers encode without a fraction so `120` stays `120`, not `120.0`.
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { a } else { nil } }
    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var doubleValue: Double? { if case .number(let n) = self { n } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var isNull: Bool { self == .null }
}

// MARK: - Lenient object mapping

/// A model type stored as a JSON object. Decoding never fails on a missing or mistyped field:
/// the field takes its default, and every key the type does not know is kept in `unknown`.
public protocol JSONObjectModel: Codable {
    static var knownKeys: Set<String> { get }
    init(object: [String: JSONValue])
    /// The known fields only; `unknown` is merged in by `encode(to:)`.
    var knownObject: [String: JSONValue] { get }
    var unknown: [String: JSONValue] { get }
}

extension JSONObjectModel {
    public init(from decoder: any Decoder) throws {
        let value = try JSONValue(from: decoder)
        guard let object = value.objectValue else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected an object"))
        }
        self.init(object: object)
    }

    public func encode(to encoder: any Encoder) throws {
        var merged = unknown
        for (k, v) in knownObject { merged[k] = v }
        try JSONValue.object(merged).encode(to: encoder)
    }

    public static func unknownKeys(of object: [String: JSONValue]) -> [String: JSONValue] {
        object.filter { !knownKeys.contains($0.key) }
    }
}

/// Typed readers over a JSON object, each with a default.
public struct JSONReader {
    public let object: [String: JSONValue]
    public init(_ object: [String: JSONValue]) { self.object = object }

    public func string(_ key: String) -> String? { object[key]?.stringValue }
    public func string(_ key: String, default value: String) -> String { string(key) ?? value }
    public func bool(_ key: String, default value: Bool) -> Bool { object[key]?.boolValue ?? value }
    public func double(_ key: String, default value: Double) -> Double { object[key]?.doubleValue ?? value }
    public func int(_ key: String, default value: Int) -> Int {
        guard let d = object[key]?.doubleValue, d.isFinite else { return value }
        return Int(d.rounded())
    }
    public func optionalBool(_ key: String) -> Bool? { object[key]?.boolValue }
    public func enumValue<E: RawRepresentable>(_ key: String, default value: E) -> E where E.RawValue == String {
        string(key).flatMap(E.init(rawValue:)) ?? value
    }
    public func object(_ key: String) -> [String: JSONValue] { object[key]?.objectValue ?? [:] }
    public func array(_ key: String) -> [JSONValue] { object[key]?.arrayValue ?? [] }
    public func models<M: JSONObjectModel>(_ key: String, as: M.Type) -> [M] {
        array(key).compactMap { $0.objectValue.map(M.init(object:)) }
    }
}

extension JSONValue {
    init(_ s: String?) { self = s.map(JSONValue.string) ?? .null }
    init(_ d: Double?) { self = d.map(JSONValue.number) ?? .null }
    init(_ i: Int) { self = .number(Double(i)) }
    init(_ b: Bool?) { self = b.map(JSONValue.bool) ?? .null }
    init<M: JSONObjectModel>(models: [M]) {
        self = .array(models.map { m in
            var merged = m.unknown
            for (k, v) in m.knownObject { merged[k] = v }
            return .object(merged)
        })
    }
}
