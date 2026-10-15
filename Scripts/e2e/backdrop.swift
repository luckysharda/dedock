// Neutral backdrop for E2E screenshots: a borderless solid mid-grey window at normal level (below the
// dock panel's level 24), ignoring the mouse, so a capture of the dock never contains the user's
// windows. Harness-owned; quits after <seconds> or on SIGTERM.
//
// Build: swiftc -O Scripts/e2e/backdrop.swift -o build/e2e/backdrop
// Run:   build/e2e/backdrop <x> <y> <w> <h> [seconds=20]     (global top-left points)

import AppKit

let a = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard a.count >= 4 else { FileHandle.standardError.write("usage: backdrop x y w h [seconds]\n".data(using: .utf8)!); exit(2) }
let (x, y, w, h) = (a[0], a[1], a[2], a[3])
let seconds = a.count > 4 ? a[4] : 20

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
let frame = NSRect(x: x, y: primaryHeight - y - h, width: w, height: h)  // top-left → AppKit
let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
win.backgroundColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1)  // #808080
win.isOpaque = true
win.hasShadow = false
win.ignoresMouseEvents = true
win.level = .normal
win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
win.orderFrontRegardless()
signal(SIGTERM) { _ in exit(0) }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exit(0) }
print("backdrop up")
fflush(stdout)
app.run()
