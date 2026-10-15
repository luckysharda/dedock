import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif
/// Identifier of a dock instance (a display × edge binding).
public struct DockID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// Identifier of a tile inside a profile.
public struct TileID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { rawValue = value }
    public var description: String { rawValue }
}

/// Identifier of a profile (a named tile list).
public struct ProfileID: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ value: String) { rawValue = value }
    public var description: String { rawValue }
}

extension DockID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { rawValue = value }
}

extension TileID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { rawValue = value }
}

extension ProfileID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { rawValue = value }
}

// `RawRepresentable` + `Codable` with a `String` raw value encodes as a plain string (stdlib default).
