// Presses a control in one of the APP UNDER TEST's own windows through accessibility: its close button
// (C8: closing Settings releases the dock's hold) or a named control (C9: the Style segment). Harness-
// owned targets only: it refuses any process that is not a Dedock debug or self-test build, and
// (REG-051) it refuses unless DEDOCK_LOCK_OWNER holds the REAL desktop lock, checked through
// Scripts/e2e/desktop-lock.sh require (the one place the real lock path is defined).
//
// Build: swiftc -O Scripts/e2e/axpress.swift -o build/e2e/axpress
// Run:   build/e2e/axpress close <pid> <window title>
//        build/e2e/axpress press <pid> <window title> <control title or description>   (exit 3: not found)
//        build/e2e/axpress scroll <pid> <window title> <control>   bring our own control into view (any role, e.g.
//                                                                   Settings' "Dock size" slider) so a later pointer press
//                                                                   lands on screen (REG-068): AXScrollToVisible, else
//                                                                   page its enclosing AXScrollArea until it is inside
//        build/e2e/axpress menu <pid>          open the app's OWN status-item menu (x-18: menu above the top dock)
//        build/e2e/axpress menu-cancel <pid>   close it again (AXCancel on the menu)

import AppKit
import ApplicationServices

func fail(_ m: String) -> Never { FileHandle.standardError.write("axpress: \(m)\n".data(using: .utf8)!); exit(2) }

let a = Array(CommandLine.arguments.dropFirst())
guard (a.count == 3 && a[0] == "close") || (a.count == 4 && (a[0] == "press" || a[0] == "scroll")) || (a.count == 2 && (a[0] == "menu" || a[0] == "menu-cancel")),
      let pid = Int32(a[1]) else {
    fail("usage: axpress close <pid> <window title> | press|scroll <pid> <window title> <control> | menu <pid> | menu-cancel <pid>")
}
// REG-051: acting on a live app needs the REAL lock, checked here and not only by the caller.
// The tool lives at <worktree>/build/e2e/axpress; the lock script at <worktree>/Scripts/e2e/.
let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let lockScript = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Scripts/e2e/desktop-lock.sh").path
guard let owner = ProcessInfo.processInfo.environment["DEDOCK_LOCK_OWNER"], !owner.isEmpty else {
    fail("refusing: set DEDOCK_LOCK_OWNER (REG-051: needs the REAL desktop lock)")
}
guard FileManager.default.isExecutableFile(atPath: lockScript) else { fail("refusing: cannot find \(lockScript) to check the lock") }
let lock = Process()
lock.executableURL = URL(fileURLWithPath: lockScript)
lock.arguments = ["require", owner]
lock.standardOutput = FileHandle.nullDevice; lock.standardError = FileHandle.nullDevice
do { try lock.run(); lock.waitUntilExit() } catch { fail("refusing: lock check did not run") }
guard lock.terminationStatus == 0 else { fail("refusing: '\(owner)' does not hold the REAL desktop lock (REG-051)") }

let owned: Set<String> = ["app.dedock.Dedock.debug", "app.dedock.Fake"]
guard let bid = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, owned.contains(bid) else {
    fail("refusing: pid \(pid) is not a harness-owned Dedock build")
}
guard AXIsProcessTrusted() else { fail("this process lacks Accessibility") }

func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v as? T
}
if a[0] == "menu" || a[0] == "menu-cancel" {
    // The app's own status item (its AXExtrasMenuBar), never another app's menu bar.
    guard let bar: AXUIElement = attr(AXUIElementCreateApplication(pid), "AXExtrasMenuBar"),
          let items: [AXUIElement] = attr(bar, kAXChildrenAttribute), let item = items.first else { fail("no status item for pid \(pid)") }
    if a[0] == "menu" {
        // Opening a menu-bar item's menu blocks in menu tracking, so AXPress commonly returns
        // kAXErrorCannotComplete (-25204) although the menu IS open; the caller verifies the menu window.
        let r = AXUIElementPerformAction(item, kAXPressAction as CFString)
        guard r == .success || r == .cannotComplete else { fail("AXPress on the status item failed: \(r.rawValue)") }
        print(r == .success ? "opened the status-item menu" : "pressed the status item (AX: cannot complete, as during menu tracking)"); exit(0)
    }
    let menus: [AXUIElement] = attr(item, kAXChildrenAttribute) ?? []
    guard let menu = menus.first else { print("no open menu"); exit(0) }
    let r = AXUIElementPerformAction(menu, kAXCancelAction as CFString)
    guard r == .success else { fail("AXCancel on the menu failed: \(r.rawValue)") }
    print("closed the status-item menu"); exit(0)
}
let windows: [AXUIElement] = attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
guard let w = windows.first(where: { (attr($0, kAXTitleAttribute) as String?) == a[2] }) else { fail("no window titled '\(a[2])'") }
let pressable: Set<String> = ["AXButton", "AXRadioButton", "AXCheckBox"]
func find(_ e: AXUIElement, _ name: String, _ depth: Int) -> AXUIElement? {
    let role: String = attr(e, kAXRoleAttribute) ?? ""
    if a[0] == "scroll" || pressable.contains(role), (attr(e, kAXTitleAttribute) as String?) == name || (attr(e, kAXDescriptionAttribute) as String?) == name { return e }
    guard depth < 24, let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) else { return nil }
    for k in kids { if let hit = find(k, name, depth + 1) { return hit } }
    return nil
}
let target: AXUIElement
if a[0] == "close" {
    guard let close: AXUIElement = attr(w, kAXCloseButtonAttribute) else { fail("window '\(a[2])' has no close button") }
    target = close
} else {
    guard let hit = find(w, a[3], 0) else { FileHandle.standardError.write("axpress: no control '\(a[3])' in '\(a[2])'\n".data(using: .utf8)!); exit(3) }
    target = hit
}
if a[0] == "scroll" {
    if AXUIElementPerformAction(target, "AXScrollToVisible" as CFString) == .success {
        print("scrolled '\(a[3])' into view in '\(a[2])'"); exit(0)
    }
    // SwiftUI controls often lack AXScrollToVisible (-25206): page the nearest enclosing scroll area.
    func frame(_ e: AXUIElement) -> CGRect? {
        var pos = CGPoint.zero, size = CGSize.zero
        guard let p: AXValue = attr(e, kAXPositionAttribute), let s: AXValue = attr(e, kAXSizeAttribute),
              AXValueGetValue(p, .cgPoint, &pos), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: pos, size: size)
    }
    var area: AXUIElement? = attr(target, kAXParentAttribute)
    while let e = area, (attr(e, kAXRoleAttribute) as String?) != "AXScrollArea" { area = attr(e, kAXParentAttribute) }
    guard let sa = area else { fail("'\(a[3])' has no AXScrollToVisible and no enclosing scroll area") }
    for _ in 0..<30 {
        guard let c = frame(target), let v = frame(sa) else { fail("no frames to compare") }
        if v.contains(c) { print("paged '\(a[3])' into view in '\(a[2])'"); exit(0) }
        let action = c.midY > v.midY ? "AXScrollDownByPage" : "AXScrollUpByPage"
        guard AXUIElementPerformAction(sa, action as CFString) == .success else { fail("\(action) failed") }
        usleep(150_000)
    }
    fail("'\(a[3])' still not inside its scroll area after 30 pages")
}
let r = AXUIElementPerformAction(target, kAXPressAction as CFString)
guard r == .success else { fail("AXPress failed: \(r.rawValue)") }
print("pressed \(a[0] == "close" ? "close" : "'" + a[3] + "'") in '\(a[2])'")
