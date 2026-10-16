// Read-only window / accessibility probe for the regress.sh "cua checks" (alongside cua-driver,
// which lists only layer-0 windows and has no point query). Never clicks, types or moves.
//
// Build: swiftc -O Scripts/e2e/axprobe.swift -o build/e2e/axprobe
//
//   axprobe windows <pid>        every window of the pid at any level (CGWindowList, top-left coords):
//                                {"id","layer","x","y","w","h","alpha","onscreen","name"}
//   axprobe tree <pid> [depth=6] the app's AX tree (windows and their descendants):
//                                {"depth","role","subrole","label","name","x","y","w","h","enabled","actions"}
//                                (label: description, title or value; name: description or title only)
//   axprobe at <x> <y> only=<pid> the AX element under a global top-left point: {"pid","role","label","other_app"}
//                                — who would receive a click there. Role/label only for <pid> (privacy:
//                                another app's element can hold the user's content); never an app name.
//   axprobe front                the frontmost app: {"pid","app","bundle"}
//   axprobe focus [pid]          who holds KEY focus: {"pid","source","front","app_focus"}. pid/source from
//                                the system-wide AXFocusedUIElement (else the focused application; -1/none
//                                when the system refuses, e.g. kAXErrorCannotComplete); front = the
//                                frontmost app's pid; app_focus = whether <pid> reports a focused element
//                                of its own (a key window). Pids and booleans only: never content.
//   axprobe occluder <x> <y> <pid> [above=24]
//                                whether ANOTHER app takes the click at the global top-left point from a
//                                window above layer <above> (over the dock's level): the AX hit there
//                                belongs to an app other than <pid> AND that app has an on-screen window
//                                above <above> covering the point. A window that only covers the point
//                                (a mouse-transparent full-screen overlay) does not count. Output:
//                                {"occluded","layer","x","y","w","h"} of that window, or {"occluded":false}.
//                                Layer and bounds only: never a name or a pid.
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
    // The name alone (no value): a control labelled only by its value (a slider's number) has no name (C8).
    d["name"] = ((attr(e, kAXDescriptionAttribute) as String?).flatMap { $0.isEmpty ? nil : $0 }) ?? (attr(e, kAXTitleAttribute) as String?) ?? ""
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
guard let cmd = a.first else { fail("usage: axprobe windows|tree|at|focus|occluder|front ...") }

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
    var d: [String: Any] = ["pid": Int(pid), "role": mine ? ((attr(e, kAXRoleAttribute) as String?) ?? "") : "",
                            "label": mine ? label(e) : "", "other_app": !mine]
    if mine {  // the hit element and its parent chain up to the window (for findings like REG-054)
        var chain: [[String: Any]] = []
        var cur: AXUIElement? = e
        while let c = cur, chain.count < 8 {
            var row = element(c, depth: chain.count)
            row["subrole"] = (attr(c, kAXSubroleAttribute) as String?) ?? ""
            chain.append(row)
            cur = attr(c, kAXParentAttribute)
            if (row["role"] as? String) == "AXWindow" || (row["role"] as? String) == "AXApplication" { break }
        }
        d["chain"] = chain
    }
    out(d)
case "focus":
    guard AXIsProcessTrusted() else { fail("this process lacks Accessibility") }
    let sys = AXUIElementCreateSystemWide()
    var pid: pid_t = -1, source = "none"
    if let e: AXUIElement = attr(sys, kAXFocusedUIElementAttribute), AXUIElementGetPid(e, &pid) == .success {
        source = "focusedUIElement"
    } else if let app: AXUIElement = attr(sys, kAXFocusedApplicationAttribute), AXUIElementGetPid(app, &pid) == .success {
        source = "focusedApplication"
    }
    let front = Int(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)
    var appFocus = false
    if a.count > 1, let p = Int32(a[1]) {
        let el: AXUIElement? = attr(AXUIElementCreateApplication(p), kAXFocusedUIElementAttribute)
        appFocus = el != nil
    }
    out(["pid": Int(pid), "source": source, "front": front, "app_focus": appFocus])
case "occluder":
    guard a.count > 3, let x = Double(a[1]), let y = Double(a[2]), let pid = Int32(a[3]) else { fail("occluder <x> <y> <pid> [above]") }
    let above = a.count > 4 ? Int(a[4].replacingOccurrences(of: "above=", with: "")) ?? 24 : 24
    guard AXIsProcessTrusted() else { fail("this process lacks Accessibility") }
    var hit: AXUIElement?, hitPid: pid_t = -1
    if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &hit) == .success, let e = hit {
        AXUIElementGetPid(e, &hitPid)
    }
    var d: [String: Any] = ["occluded": false]
    // On-screen windows come front to back, so the first match is the topmost occluder.
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for w in list where hitPid > 0 && hitPid != pid && (w[kCGWindowOwnerPID as String] as? Int32) == hitPid {
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        guard layer > above, (w[kCGWindowAlpha as String] as? Double ?? 0) > 0, r.contains(CGPoint(x: x, y: y)) else { continue }
        d = ["occluded": true, "layer": layer, "x": r.minX, "y": r.minY, "w": r.width, "h": r.height]
        break
    }
    out(d)
case "front":
    let f = NSWorkspace.shared.frontmostApplication
    out(["pid": Int(f?.processIdentifier ?? -1), "app": f?.localizedName ?? "", "bundle": f?.bundleIdentifier ?? ""])
default:
    fail("unknown command \(cmd)")
}
