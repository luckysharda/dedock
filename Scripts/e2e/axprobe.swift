// Read-only window / accessibility probe for the regress.sh "cua checks" (alongside cua-driver,
// which lists only layer-0 windows and has no point query). Never clicks, types or moves.
//
// Build: swiftc -O Scripts/e2e/axprobe.swift -o build/e2e/axprobe
//
//   axprobe windows <pid>        every window of the pid at any level (CGWindowList, top-left coords):
//                                {"id","layer","x","y","w","h","alpha","onscreen","name"}
//   axprobe tree <pid> [depth=6] the app's AX tree (windows and their descendants):
//                                {"depth","role","subrole","label","x","y","w","h","enabled","actions"}
//   axprobe at <x> <y> only=<pid> the AX element under a global top-left point: {"pid","role","label","other_app"}
//                                — who would receive a click there. Role/label only for <pid> (privacy:
//                                another app's element can hold the user's content); never an app name.
//   axprobe front                the frontmost app: {"pid","app","bundle"}
//
// One JSON object per line. Needs Accessibility for the host process (tree / at).

import AppKit
import ApplicationServices

func out(_ d: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
    return v as? T
}

func frame(_ e: AXUIElement) -> CGRect? {
    var pos = CGPoint.zero, size = CGSize.zero
    guard let p: AXValue = attr(e, kAXPositionAttribute), let s: AXValue = attr(e, kAXSizeAttribute),
          AXValueGetValue(p, .cgPoint, &pos), AXValueGetValue(s, .cgSize, &size) else { return nil }
    return CGRect(origin: pos, size: size)
}

/// The text a screen reader would announce: description, then title, then value.
func label(_ e: AXUIElement) -> String {
    for name in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
        if let s: String = attr(e, name), !s.isEmpty { return s }
    }
    return ""
}

func element(_ e: AXUIElement, depth: Int) -> [String: Any] {
    var d: [String: Any] = ["depth": depth, "role": (attr(e, kAXRoleAttribute) as String?) ?? "",
                            "subrole": (attr(e, kAXSubroleAttribute) as String?) ?? "", "label": label(e)]
    if let f = frame(e) { d["x"] = f.minX; d["y"] = f.minY; d["w"] = f.width; d["h"] = f.height }
    if let en: Bool = attr(e, kAXEnabledAttribute) { d["enabled"] = en }
    var names: CFArray?
    if AXUIElementCopyActionNames(e, &names) == .success, let acts = names as? [String], !acts.isEmpty { d["actions"] = acts }
    return d
}

func walk(_ e: AXUIElement, depth: Int, max: Int) {
    out(element(e, depth: depth))
    guard depth < max, let kids: [AXUIElement] = attr(e, kAXChildrenAttribute) else { return }
    for k in kids { walk(k, depth: depth + 1, max: max) }
}

func fail(_ m: String) -> Never { FileHandle.standardError.write("axprobe: \(m)\n".data(using: .utf8)!); exit(2) }

let a = Array(CommandLine.arguments.dropFirst())
guard let cmd = a.first else { fail("usage: axprobe windows|tree|at|front ...") }

switch cmd {
case "windows":
    guard a.count > 1, let pid = Int32(a[1]) else { fail("windows <pid>") }
    let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        out(["id": w[kCGWindowNumber as String] as? Int ?? -1, "layer": w[kCGWindowLayer as String] as? Int ?? 0,
             "x": b["X"] ?? 0, "y": b["Y"] ?? 0, "w": b["Width"] ?? 0, "h": b["Height"] ?? 0,
             "alpha": w[kCGWindowAlpha as String] as? Double ?? 0, "onscreen": w[kCGWindowIsOnscreen as String] as? Bool ?? false,
             "name": w[kCGWindowName as String] as? String ?? ""])
    }
case "tree":
    guard a.count > 1, let pid = Int32(a[1]) else { fail("tree <pid> [depth]") }
    guard AXIsProcessTrusted() else { fail("this process lacks Accessibility") }
    let app = AXUIElementCreateApplication(pid)
    let maxDepth = a.count > 2 ? Int(a[2]) ?? 6 : 6
    let windows: [AXUIElement] = attr(app, kAXWindowsAttribute) ?? []
    for w in windows { walk(w, depth: 0, max: maxDepth) }
    if let extras: AXUIElement = attr(app, "AXExtrasMenuBar") { walk(extras, depth: 0, max: 2) }
case "at":
    guard a.count > 2, let x = Float(a[1]), let y = Float(a[2]) else { fail("at <x> <y>") }
    guard AXIsProcessTrusted() else { fail("this process lacks Accessibility") }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), x, y, &hit) == .success, let e = hit else {
        out(["pid": -1, "app": "", "role": "", "label": ""]); exit(0)
    }
    var pid: pid_t = 0
    AXUIElementGetPid(e, &pid)
    // Privacy: another app's element can carry the user's own content (a terminal's text, a
    // document). Only the app under test (`only=<pid>`) gets its role and label reported; for any
    // other app just the fact that it, not the dock, would receive the click.
    let only = a.count > 3 ? Int32(a[3].replacingOccurrences(of: "only=", with: "")) : nil
    let mine = only == nil || only == pid
    out(["pid": Int(pid), "role": mine ? ((attr(e, kAXRoleAttribute) as String?) ?? "") : "",
         "label": mine ? label(e) : "", "other_app": !mine])
case "front":
    let f = NSWorkspace.shared.frontmostApplication
    out(["pid": Int(f?.processIdentifier ?? -1), "app": f?.localizedName ?? "", "bundle": f?.bundleIdentifier ?? ""])
default:
    fail("unknown command \(cmd)")
}
