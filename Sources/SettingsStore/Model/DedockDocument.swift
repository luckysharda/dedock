import DedockCore
import Foundation

/// The whole dedock document, stored as `layout.json` (architecture §7, schema v1).
///
/// Every type decodes leniently: a missing or mistyped field takes its default, and keys this
/// build does not know are kept in `unknown` and written back on save.
public struct DedockDocument: JSONObjectModel, Sendable, Equatable {
    public static let currentSchema = 1

    public var schemaVersion: Int
    public var app: AppPreferences
    public var profiles: [Profile]
    public var docks: [DockConfig]
    public var displays: [KnownDisplay]
    public var unknown: [String: JSONValue]

    public init(
        schemaVersion: Int = DedockDocument.currentSchema, app: AppPreferences = .init(),
        profiles: [Profile] = [], docks: [DockConfig] = [], displays: [KnownDisplay] = [],
        unknown: [String: JSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.profiles = profiles
        self.docks = docks
        self.displays = displays
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["schemaVersion", "app", "profiles", "docks", "displays"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        schemaVersion = r.int("schemaVersion", default: DedockDocument.currentSchema)
        app = AppPreferences(object: r.object("app"))
        profiles = r.models("profiles", as: Profile.self)
        docks = r.models("docks", as: DockConfig.self)
        displays = r.models("displays", as: KnownDisplay.self)
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        [
            "schemaVersion": JSONValue(schemaVersion),
            "app": app.jsonValue,
            "profiles": JSONValue(models: profiles),
            "docks": JSONValue(models: docks),
            "displays": JSONValue(models: displays),
        ]
    }

    public func profile(_ id: ProfileID) -> Profile? { profiles.first { $0.id == id } }
    public func dock(_ id: DockID) -> DockConfig? { docks.first { $0.id == id } }

    /// The document created when no `layout.json` exists: one Reveal dock on the recommended
    /// edge and a "Default" profile with Finder, Safari and System Settings (architecture §7).
    /// The recommended edge is left when the native Dock is at the bottom or right, right when
    /// it is on the left (`features.md` "Edge Dock defaults").
    public static func makeDefault(nativeDockEdge: ScreenEdge? = .bottom) -> DedockDocument {
        let edge: ScreenEdge = nativeDockEdge == .left ? .right : .left
        let profile = Profile(id: "default", name: "Default", items: [
            TileItem(id: "t1", kind: .app, bundleID: "com.apple.finder",
                     path: "/System/Library/CoreServices/Finder.app"),
            TileItem(id: "t2", kind: .app, bundleID: "com.apple.Safari", path: "/Applications/Safari.app"),
            TileItem(id: "t3", kind: .app, bundleID: "com.apple.systempreferences",
                     path: "/System/Applications/System Settings.app"),
        ])
        let dock = DockConfig(id: "D1", edge: edge, mode: .reveal,
                              scenario: edge == .left ? "revealLeft" : "revealRight", profileID: profile.id)
        return DedockDocument(profiles: [profile], docks: [dock])
    }
}

// MARK: - App preferences

public struct AppPreferences: JSONObjectModel, Sendable, Equatable {
    public var showStatusItem: Bool
    /// `nil` follows the system Reduce Motion setting.
    public var reduceMotionOverride: Bool?
    public var unknown: [String: JSONValue]

    public init(showStatusItem: Bool = true, reduceMotionOverride: Bool? = nil, unknown: [String: JSONValue] = [:]) {
        self.showStatusItem = showStatusItem
        self.reduceMotionOverride = reduceMotionOverride
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["showStatusItem", "reduceMotionOverride"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        showStatusItem = r.bool("showStatusItem", default: true)
        reduceMotionOverride = r.optionalBool("reduceMotionOverride")
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        ["showStatusItem": .bool(showStatusItem), "reduceMotionOverride": JSONValue(reduceMotionOverride)]
    }
}

// MARK: - Profiles and tiles

public struct Profile: JSONObjectModel, Sendable, Equatable, Identifiable {
    public var id: ProfileID
    public var name: String
    public var items: [TileItem]
    public var unknown: [String: JSONValue]

    public init(id: ProfileID, name: String, items: [TileItem] = [], unknown: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.items = items
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["id", "name", "items"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        id = ProfileID(r.string("id", default: "default"))
        name = r.string("name", default: "Default")
        items = r.array("items").enumerated().compactMap { index, value in
            value.objectValue.map { TileItem(object: $0, fallbackID: TileID("t\(index + 1)")) }
        }
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        ["id": .string(id.rawValue), "name": .string(name), "items": JSONValue(models: items)]
    }
}

public struct TileItem: JSONObjectModel, Sendable, Hashable, Identifiable {
    /// Open set of kinds, so a kind written by a newer build round-trips unchanged.
    public struct Kind: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let app = Kind(rawValue: "app")
        public static let folder = Kind(rawValue: "folder")
        public static let separator = Kind(rawValue: "separator")
        /// Reserved.
        public static let spacer = Kind(rawValue: "spacer")
        /// Reserved.
        public static let widget = Kind(rawValue: "widget")
        public var description: String { rawValue }
    }

    public var id: TileID
    public var kind: Kind
    /// App tiles.
    public var bundleID: String?
    /// App tiles (last-known location) and folder tiles (fallback when there is no bookmark).
    /// A leading `~` is expanded on load.
    public var path: String?
    /// Folder tiles: a plain URL bookmark (the app is unsandboxed). Base64 in JSON.
    public var bookmark: Data?
    public var displayName: String?
    public var unknown: [String: JSONValue]

    public init(
        id: TileID, kind: Kind, bundleID: String? = nil, path: String? = nil,
        bookmark: Data? = nil, displayName: String? = nil, unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.bundleID = bundleID
        self.path = path.map(TileItem.expandTilde)
        self.bookmark = bookmark
        self.displayName = displayName
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["id", "kind", "bundleID", "path", "bookmark", "displayName"]

    public init(object: [String: JSONValue]) {
        self.init(object: object, fallbackID: TileID(UUID().uuidString))
    }

    /// - Parameter fallbackID: used when a hand-written seed omits `id`.
    public init(object: [String: JSONValue], fallbackID: TileID) {
        let r = JSONReader(object)
        id = r.string("id").map { TileID($0) } ?? fallbackID
        bundleID = r.string("bundleID")
        path = r.string("path").map(TileItem.expandTilde)
        bookmark = r.string("bookmark").flatMap { Data(base64Encoded: $0) }
        displayName = r.string("displayName")
        if let raw = r.string("kind") {
            kind = Kind(rawValue: raw)
        } else {
            // A seed tile with only a bundle id is an app; with only a path, an app if it ends
            // in `.app`, otherwise a folder.
            kind = bundleID != nil || path?.hasSuffix(".app") == true ? .app : (path != nil ? .folder : .separator)
        }
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        var o: [String: JSONValue] = ["id": .string(id.rawValue), "kind": .string(kind.rawValue)]
        if let bundleID { o["bundleID"] = .string(bundleID) }
        if let path { o["path"] = .string(path) }
        if let bookmark { o["bookmark"] = .string(bookmark.base64EncodedString()) }
        if let displayName { o["displayName"] = .string(displayName) }
        return o
    }

    static func expandTilde(_ path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else { return path }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return home + path.dropFirst()
    }
}

// MARK: - Docks

public struct DockConfig: JSONObjectModel, Sendable, Equatable, Identifiable {
    public enum Mode: String, Sendable, Equatable, CaseIterable { case reveal, pinned }

    public var id: DockID
    public var enabled: Bool
    public var edge: ScreenEdge
    public var mode: Mode
    /// The scenario card last applied (DD-910); any manual change sets `custom`.
    public var scenario: String
    public var display: DisplayBinding
    public var profileID: ProfileID
    public var reveal: RevealSettings
    public var placement: PlacementSettings
    public var appearance: AppearanceSettings
    public var unknown: [String: JSONValue]

    public init(
        id: DockID, enabled: Bool = true, edge: ScreenEdge = .left, mode: Mode = .reveal,
        scenario: String = "revealLeft", display: DisplayBinding = .init(), profileID: ProfileID = "default",
        reveal: RevealSettings = .init(), placement: PlacementSettings = .init(),
        appearance: AppearanceSettings = .init(), unknown: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.enabled = enabled
        self.edge = edge
        self.mode = mode
        self.scenario = scenario
        self.display = display
        self.profileID = profileID
        self.reveal = reveal
        self.placement = placement
        self.appearance = appearance
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = [
        "id", "enabled", "edge", "mode", "scenario", "display", "profileID", "reveal", "placement", "appearance",
    ]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        id = DockID(r.string("id", default: "D1"))
        enabled = r.bool("enabled", default: true)
        edge = r.enumValue("edge", default: ScreenEdge.left)
        mode = r.enumValue("mode", default: Mode.reveal)
        scenario = r.string("scenario", default: "custom")
        display = DisplayBinding(object: r.object("display"))
        profileID = ProfileID(r.string("profileID", default: "default"))
        reveal = RevealSettings(object: r.object("reveal"))
        placement = PlacementSettings(object: r.object("placement"))
        appearance = AppearanceSettings(object: r.object("appearance"))
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        [
            "id": .string(id.rawValue), "enabled": .bool(enabled), "edge": .string(edge.rawValue),
            "mode": .string(mode.rawValue), "scenario": .string(scenario), "display": display.jsonValue,
            "profileID": .string(profileID.rawValue), "reveal": reveal.jsonValue,
            "placement": placement.jsonValue, "appearance": appearance.jsonValue,
        ]
    }
}

public struct DisplayBinding: JSONObjectModel, Sendable, Equatable {
    public enum Role: String, Sendable, Equatable, CaseIterable { case main, identity }

    public var role: Role
    /// The display UUID when `role == .identity`.
    public var identity: String?
    public var fallbackToBuiltin: Bool
    public var unknown: [String: JSONValue]

    public init(role: Role = .main, identity: String? = nil, fallbackToBuiltin: Bool = true,
                unknown: [String: JSONValue] = [:]) {
        self.role = role
        self.identity = identity
        self.fallbackToBuiltin = fallbackToBuiltin
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["role", "identity", "fallbackToBuiltin"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        role = r.enumValue("role", default: Role.main)
        identity = r.string("identity")
        fallbackToBuiltin = r.bool("fallbackToBuiltin", default: true)
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        var o: [String: JSONValue] = ["role": .string(role.rawValue), "fallbackToBuiltin": .bool(fallbackToBuiltin)]
        if let identity { o["identity"] = .string(identity) }
        return o
    }
}

/// `docks[].reveal`. Key paths are an E2E contract: the harness patches them before launch.
/// Defaults settled by dedock-e9 (2026-10-15).
public struct RevealSettings: JSONObjectModel, Sendable, Equatable {
    public enum SpanMode: String, Sendable, Equatable, CaseIterable { case content, wholeEdge }
    public enum SharedEdgePolicy: String, Sendable, Equatable, CaseIterable { case slowDwell, modifier, wallOnly }

    public var showDwellMs: Int
    public var fullscreenDwellMs: Int
    public var hideDelayMs: Int
    public var triggerThicknessPt: Double
    public var spanMode: SpanMode
    public var cornerExclusionPt: Double
    /// `nil` (JSON `null`) turns push-through off; a missing key means the default 40 pt.
    public var pushThroughPt: Double?
    public var hysteresisPt: Double
    public var sharedEdgePolicy: SharedEdgePolicy
    public var hideInFullscreen: Bool
    public var unknown: [String: JSONValue]

    public init(
        showDwellMs: Int = 120, fullscreenDwellMs: Int = 400, hideDelayMs: Int = 400,
        triggerThicknessPt: Double = 3, spanMode: SpanMode = .content, cornerExclusionPt: Double = 24,
        pushThroughPt: Double? = 40, hysteresisPt: Double = 16, sharedEdgePolicy: SharedEdgePolicy = .slowDwell,
        hideInFullscreen: Bool = false, unknown: [String: JSONValue] = [:]
    ) {
        self.showDwellMs = showDwellMs
        self.fullscreenDwellMs = fullscreenDwellMs
        self.hideDelayMs = hideDelayMs
        self.triggerThicknessPt = triggerThicknessPt
        self.spanMode = spanMode
        self.cornerExclusionPt = cornerExclusionPt
        self.pushThroughPt = pushThroughPt
        self.hysteresisPt = hysteresisPt
        self.sharedEdgePolicy = sharedEdgePolicy
        self.hideInFullscreen = hideInFullscreen
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = [
        "showDwellMs", "fullscreenDwellMs", "hideDelayMs", "triggerThicknessPt", "spanMode",
        "cornerExclusionPt", "pushThroughPt", "hysteresisPt", "sharedEdgePolicy", "hideInFullscreen",
    ]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        let d = RevealSettings()
        showDwellMs = r.int("showDwellMs", default: d.showDwellMs)
        fullscreenDwellMs = r.int("fullscreenDwellMs", default: d.fullscreenDwellMs)
        hideDelayMs = r.int("hideDelayMs", default: d.hideDelayMs)
        triggerThicknessPt = r.double("triggerThicknessPt", default: d.triggerThicknessPt)
        spanMode = r.enumValue("spanMode", default: d.spanMode)
        cornerExclusionPt = r.double("cornerExclusionPt", default: d.cornerExclusionPt)
        switch object["pushThroughPt"] {
        case nil: pushThroughPt = d.pushThroughPt
        case .null?: pushThroughPt = nil
        case let value?: pushThroughPt = value.doubleValue ?? d.pushThroughPt
        }
        hysteresisPt = r.double("hysteresisPt", default: d.hysteresisPt)
        sharedEdgePolicy = r.enumValue("sharedEdgePolicy", default: d.sharedEdgePolicy)
        hideInFullscreen = r.bool("hideInFullscreen", default: d.hideInFullscreen)
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        [
            "showDwellMs": JSONValue(showDwellMs), "fullscreenDwellMs": JSONValue(fullscreenDwellMs),
            "hideDelayMs": JSONValue(hideDelayMs), "triggerThicknessPt": .number(triggerThicknessPt),
            "spanMode": .string(spanMode.rawValue), "cornerExclusionPt": .number(cornerExclusionPt),
            "pushThroughPt": JSONValue(pushThroughPt), "hysteresisPt": .number(hysteresisPt),
            "sharedEdgePolicy": .string(sharedEdgePolicy.rawValue), "hideInFullscreen": .bool(hideInFullscreen),
        ]
    }
}

public struct PlacementSettings: JSONObjectModel, Sendable, Equatable {
    public enum Alignment: String, Sendable, Equatable, CaseIterable { case start, center, end }

    public var alignment: Alignment
    /// Distance from the screen edge, 0–48 pt (DD-925).
    public var edgeGapPt: Double
    public var unknown: [String: JSONValue]

    public init(alignment: Alignment = .center, edgeGapPt: Double = 6, unknown: [String: JSONValue] = [:]) {
        self.alignment = alignment
        self.edgeGapPt = edgeGapPt
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["alignment", "edgeGapPt"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        alignment = r.enumValue("alignment", default: Alignment.center)
        edgeGapPt = r.double("edgeGapPt", default: 6)
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        ["alignment": .string(alignment.rawValue), "edgeGapPt": .number(edgeGapPt)]
    }
}

public struct AppearanceSettings: JSONObjectModel, Sendable, Equatable {
    public enum Size: String, Sendable, Equatable, CaseIterable { case s, m, l, xl }

    public var size: Size
    public var dragToRearrange: Bool
    public var unknown: [String: JSONValue]

    public init(size: Size = .m, dragToRearrange: Bool = false, unknown: [String: JSONValue] = [:]) {
        self.size = size
        self.dragToRearrange = dragToRearrange
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["size", "dragToRearrange"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        size = r.enumValue("size", default: Size.m)
        dragToRearrange = r.bool("dragToRearrange", default: false)
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        ["size": .string(size.rawValue), "dragToRearrange": .bool(dragToRearrange)]
    }
}

// MARK: - Known displays

public struct KnownDisplay: JSONObjectModel, Sendable, Equatable {
    public var identity: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var lastSeen: Date?
    public var unknown: [String: JSONValue]

    public init(identity: String, vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0,
                lastSeen: Date? = nil, unknown: [String: JSONValue] = [:]) {
        self.identity = identity
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.lastSeen = lastSeen
        self.unknown = unknown
    }

    public static let knownKeys: Set<String> = ["identity", "vendor", "model", "serial", "lastSeen"]

    public init(object: [String: JSONValue]) {
        let r = JSONReader(object)
        identity = r.string("identity", default: "")
        vendor = UInt32(clamping: r.int("vendor", default: 0))
        model = UInt32(clamping: r.int("model", default: 0))
        serial = UInt32(clamping: r.int("serial", default: 0))
        lastSeen = r.string("lastSeen").flatMap { ISO8601DateFormatter().date(from: $0) }
        unknown = Self.unknownKeys(of: object)
    }

    public var knownObject: [String: JSONValue] {
        var o: [String: JSONValue] = [
            "identity": .string(identity), "vendor": JSONValue(Int(vendor)),
            "model": JSONValue(Int(model)), "serial": JSONValue(Int(serial)),
        ]
        if let lastSeen { o["lastSeen"] = .string(ISO8601DateFormatter().string(from: lastSeen)) }
        return o
    }
}

// MARK: - Helpers

extension JSONObjectModel {
    /// This model as a JSON object, unknown keys included.
    public var jsonValue: JSONValue {
        var merged = unknown
        for (k, v) in knownObject { merged[k] = v }
        return .object(merged)
    }
}
