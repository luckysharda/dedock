import AppKit
import CoreGraphics

/// The number of an app's normal windows for the H4 hover label, from the window list: owner,
/// layer, alpha and size only, never titles (no Screen Recording needed). Approximate until T28's
/// Accessibility window list. Read when a tile becomes hovered and on running changes only
/// (no timer while the label is shown; T28 brings exact, live counts).
enum WindowCount {
    static func of(bundleID: String) -> Int {
        let pids = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.filter { w in
            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0,
                  let b = w[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: b) else { return false }
            return r.width > 40 && r.height > 40    // skip helper and drag windows
        }.count
    }
}
