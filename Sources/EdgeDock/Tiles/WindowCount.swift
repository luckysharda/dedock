import AppKit
import CoreGraphics

/// The number of an app's normal windows for the H4 hover label, from the window list: owner
/// and layer and size only, never titles (no Screen Recording needed). Read for the hovered tile
/// only, never per pointer sample.
enum WindowCount {
    static func of(bundleID: String) -> Int {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.filter { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
            return r.width > 40 && r.height > 40    // skip helper and drag windows
        }.count
    }
}
