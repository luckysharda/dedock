import AppKit
import Diagnostics
import SettingsStore

/// What a click on a tile does (architecture §6.9).
@MainActor public enum TileActions {
    /// Launch or activate an app; open a folder in Finder. Returns the contract `result` value.
    @discardableResult
    public static func activate(_ tile: TileModel) -> String {
        switch tile.kind {
        case .separator:
            return "missing"
        case .folder:
            guard let url = tile.url, FileManager.default.fileExists(atPath: url.path) else { return log(tile, "missing") }
            NSWorkspace.shared.open(url)
            return log(tile, "opened")
        case .app:
            guard let url = appURL(tile) else { return log(tile, "missing") }
            let running = tile.bundleID.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { DedockLog.error(.tiles, "tile.activate failed: \(error.localizedDescription)") }
            }
            return log(tile, running ? "activated" : "launched")
        }
    }

    /// What a dropped item can be pinned as: an application bundle, a plain folder, or nothing.
    /// Documents, packages (`.rtfd`, `.bundle`, libraries) and anything named `.app` that is not
    /// an application bundle (a plain file, an empty folder) are refused (REG-047).
    static func pinKind(_ url: URL) -> TileItem.Kind? {
        var isDir: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        if url.pathExtension.lowercased() == "app" {
            guard let bundle = Bundle(url: url), bundle.bundleIdentifier != nil else { return nil }
            let type = bundle.infoDictionary?["CFBundlePackageType"] as? String
            return type == nil || type == "APPL" ? .app : nil
        }
        return NSWorkspace.shared.isFilePackage(atPath: url.path) ? nil : .folder
    }

    public static func appURL(_ tile: TileModel) -> URL? {
        if let id = tile.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        if let url = tile.url, FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    private static func log(_ tile: TileModel, _ result: String) -> String {
        DedockLog.event(.tiles, "tile.activate", ["id": tile.id.rawValue, "bundle": tile.bundleID ?? "-", "result": result])
        return result
    }
}
