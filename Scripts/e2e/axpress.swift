// Presses a control in one of the APP UNDER TEST's own windows through accessibility: its close button
// (C8: closing Settings releases the dock's hold) or a named control (C9: the Style segment). Harness-
// owned targets only: it refuses any process that is not a Dedock debug or self-test build. regress.sh
// runs it under the real desktop lock.
//
// Build: swiftc -O Scripts/e2e/axpress.swift -o build/e2e/axpress
// Run:   build/e2e/axpress close <pid> <window title>
//        build/e2e/axpress press <pid> <window title> <control title or description>   (exit 3: not found)

import AppKit
import ApplicationServices

func fail(_ m: String) -> Never { FileHandle.standardError.write("axpress: \(m)\n".data(using: .utf8)!); exit(2) }

let a = Array(CommandLine.arguments.dropFirst())
guard (a.count == 3 && a[0] == "close") || (a.count == 4 && a[0] == "press"), let pid = Int32(a[1]) else {
    fail("usage: axpress close <pid> <window title> | press <pid> <window title> <control>")
}
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
let windows: [AXUIElement] = attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) ?? []
guard let w = windows.first(where: { (attr($0, kAXTitleAttribute) as String?) == a[2] }) else { fail("no window titled '\(a[2])'") }
let pressable: Set<String> = ["AXButton", "AXRadioButton", "AXCheckBox"]
func find(_ e: AXUIElement, _ name: String, _ depth: Int) -> AXUIElement? {
    let role: String = attr(e, kAXRoleAttribute) ?? ""
    if pressable.contains(role), (attr(e, kAXTitleAttribute) as String?) == name || (attr(e, kAXDescriptionAttribute) as String?) == name { return e }
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
let r = AXUIElementPerformAction(target, kAXPressAction as CFString)
guard r == .success else { fail("AXPress failed: \(r.rawValue)") }
print("pressed \(a[0] == "close" ? "close" : "'" + a[3] + "'") in '\(a[2])'")
