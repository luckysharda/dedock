// Harness self-check: records what an NSEvent global monitor (the mechanism
// dedock's PointerHub uses, plan T5) receives, so the pointer driver can be
// verified without the app: positions, deltas while pinned at an edge, and
// post → receive latency.
//
// Build: swiftc -O Scripts/e2e/listen.swift -o build/e2e/listen
// Run:   build/e2e/listen <seconds>    (one line per event on stdout)
//   mach=<receive ticks> ev=<type> x=.. y=.. dx=.. dy=.. mods=.. syn=0|1   (x/y global top-left)
// syn=0 lines during a run mean someone else moved the mouse: the run is contaminated.

import AppKit

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "10") ?? 10
setvbuf(stdout, nil, _IOLBF, 0)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .flagsChanged]
let names: [NSEvent.EventType: String] = [
    .mouseMoved: "move", .leftMouseDragged: "drag", .leftMouseDown: "down", .leftMouseUp: "up", .flagsChanged: "flags",
]

_ = NSEvent.addGlobalMonitorForEvents(matching: mask) { e in
    let t = mach_absolute_time()
    // The event's own position (screen coords for global-monitor events, y up),
    // not NSEvent.mouseLocation, which is wherever the cursor is by callback time.
    let p = e.window == nil ? e.locationInWindow : NSEvent.mouseLocation
    var line = String(format: "mach=%llu ev=%@ x=%.1f y=%.1f", t, names[e.type] ?? "\(e.type.rawValue)", p.x, primaryHeight - p.y)
    if e.type != .flagsChanged {
        line += String(format: " dx=%.1f dy=%.1f", e.deltaX, e.deltaY)
    }
    line += " mods=\(e.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)"
    // syn=1: posted by Scripts/e2e/pointer (tag 0xDED0C); syn=0: real hardware or another process
    line += " syn=\(e.cgEvent?.getIntegerValueField(.eventSourceUserData) == 0xDED0C ? 1 : 0)"
    print(line)
}

print("ready mach=\(mach_absolute_time())")
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
app.run()
