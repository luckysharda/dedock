// Harness self-test: emits a scripted Edge Dock session through os_log in real
// time, in the exact format of Tests/E2E/contract.md, so Scripts/e2e/analyze.swift
// can be checked without the app.
//
//   fake-dock good   correct tokens: dwell 120 ms, spring reveal, hide delay 400 ms,
//                    ease-in hide interrupted by a return (bezier reversal from the
//                    presentation value), one leave-before-dwell
//   fake-dock bad    same, with seeded defects: dwell fires 35 ms late, the reversal
//                    starts 20 pt away from the presentation value, the reveal overshoots
//   fake-dock serve  stands in for a launched app for Scripts/e2e/launch.sh: logs
//                    launch.edgeReady, writes the GEOM file under $DEDOCK_E2E_HOME/e2e/,
//                    echoes the seeded layout's first dock edge, then idles until killed
//
// Build: swiftc -O Tests/E2E/selftest/fake-dock.swift -o build/e2e/fake-dock

import Foundation
import os

// Launched by Scripts/e2e/launch.sh with no argument: behave like the app.
let mode = CommandLine.arguments.dropFirst().first
    ?? (ProcessInfo.processInfo.environment["DEDOCK_E2E_HOME"] != nil ? "serve" : "good")
let bad = mode == "bad"
let reveal = Logger(subsystem: "app.dedock.Dedock", category: "reveal")
let edge = Logger(subsystem: "app.dedock.Dedock", category: "edge")
let frameLog = Logger(subsystem: "app.dedock.Dedock", category: "frame")

func log(_ l: Logger, _ s: String) { l.info("\(s, privacy: .public)") }
func sleepMs(_ ms: Double) { usleep(useconds_t(max(0, ms) * 1000)) }

let travel = 90.0, hidden = -90.0, frameMs = 1000.0 / 60

func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ u: Double) -> Double {
    if u <= 0 { return 0 }; if u >= 1 { return 1 }
    func bx(_ s: Double) -> Double { 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s }
    func by(_ s: Double) -> Double { 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s }
    var lo = 0.0, hi = 1.0
    for _ in 0..<60 { let m = (lo + hi) / 2; if bx(m) < u { lo = m } else { hi = m } }
    return by((lo + hi) / 2)
}
func spring(_ t: Double) -> Double { let w = 2 * Double.pi / 0.208; return 1 - (1 + w * t) * exp(-w * t) }

/// Runs one animation at 60 Hz, logging frames; stops after `stopAfterMs` if given.
/// Returns the last presented value.
@discardableResult
func animate(kind: String, curve: String, from: Double, to: Double, dur: Double, stopAfterMs: Double? = nil,
             overshoot: Double = 0) -> Double {
    log(reveal, "reveal.begin edge=left kind=\(kind) from=\(from) to=\(to) dur=\(dur) curve=\(curve)")
    // Like Core Animation: frames on an absolute 60 Hz grid, value from real elapsed time.
    let start = Date()
    func value(at t: Double) -> Double {
        let p: Double = switch curve {
        case "spring": spring(t)
        case "bezier": bezier(0.2, 0.7, 0.2, 1, t / dur)
        default: bezier(0.42, 0, 1, 1, t / dur)
        }
        return from + (to - from) * min(1, p)
    }
    let total = curve == "spring" ? 0.30 : dur // spring settles past its 0.22 s 99 % point
    // Like a display link: the first frame lands at the next vsync (here 7 ms after the
    // commit, always < 1 frame), then one frame every 16.7 ms.
    let phase = 0.007
    var k = 0.0
    while true {
        let due = phase + k * frameMs / 1000
        if let stop = stopAfterMs, due * 1000 > stop {
            sleepMs(stop - Date().timeIntervalSince(start) * 1000)
            return value(at: Date().timeIntervalSince(start)) // presentation value at the interrupt
        }
        if due > total + 1e-9 { break }
        sleepMs(due * 1000 - Date().timeIntervalSince(start) * 1000)
        let t = Date().timeIntervalSince(start)
        var v = value(at: t)
        if overshoot > 0, t > 0.1, t < 0.2 { v = to + overshoot } // seeded defect
        log(frameLog, String(format: "frame edge=left tx=%.2f alpha=1.000 anim=%@", v, kind))
        k += 1
    }
    // A display link always renders the final value at the first vsync at or after the end.
    sleepMs((phase + k * frameMs / 1000) * 1000 - Date().timeIntervalSince(start) * 1000)
    log(frameLog, String(format: "frame edge=left tx=%.2f alpha=1.000 anim=%@", to, kind))
    log(reveal, "reveal.end edge=left kind=\(kind) at=\(to)")
    return to
}

func transition(_ from: String, _ to: String, _ cause: String) {
    log(reveal, "reveal.transition edge=left from=\(from) to=\(to) cause=\(cause) inh=-")
}

if mode == "serve" {
    let env = ProcessInfo.processInfo.environment
    let launch = Logger(subsystem: "app.dedock.Dedock", category: "launch")
    guard env["DEDOCK_E2E"] == "1", let home = env["DEDOCK_E2E_HOME"] else {
        log(launch, "launch.e2eDisabled"); exit(3)
    }
    var edgeName = "left"
    if let data = FileManager.default.contents(atPath: home + "/layout.json"),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let docks = obj["docks"] as? [[String: Any]], let e = docks.first?["edge"] as? String { edgeName = e }
    let dir = home + "/e2e"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let x = edgeName == "right" ? 1838.0 : 6.0
    let geom: [String: Any] = ["schema": 1, "pid": Int(getpid()), "docks": [[
        "id": "dock-0", "edge": edgeName, "mode": "reveal", "state": "hidden",
        "capsule": ["topLeft": [x, 350, 76, 380]],
        "tiles": [["id": "t-1", "kind": "app", "name": "Calculator", "bundleId": "com.apple.calculator",
                   "frame": ["topLeft": [x + 6, 356, 64, 64]], "hitRect": ["topLeft": [x + 6, 356, 64, 64]]]],
    ]]]
    let out = try! JSONSerialization.data(withJSONObject: geom, options: [.prettyPrinted, .sortedKeys])
    FileManager.default.createFile(atPath: dir + "/geometry.json.tmp", contents: out)
    _ = try? FileManager.default.replaceItemAt(URL(fileURLWithPath: dir + "/geometry.json"), withItemAt: URL(fileURLWithPath: dir + "/geometry.json.tmp"))
    if !FileManager.default.fileExists(atPath: dir + "/geometry.json") { try? FileManager.default.moveItem(atPath: dir + "/geometry.json.tmp", toPath: dir + "/geometry.json") }
    // FAKE_READY_SUFFIX: hostile text for the REG-042 self-test (e.g. "<private> $(…) ;|&").
    log(launch, "launch.edgeReady ms=42.0 edge=\(edgeName) frameLog=\(env["DEDOCK_FRAME_LOG"] ?? "0")\(env["FAKE_READY_SUFFIX"] ?? "")")
    while true { sleep(60) }
}

// 1. Leave before the dwell: no animation.
log(edge, "edge.zoneEnter edge=left zone=z-0 kind=wall x=0 y=540")
transition("hidden", "arming", "zone")
sleepMs(80)
log(edge, "edge.zoneExit edge=left zone=z-0 x=40 y=540")
transition("arming", "hidden", "leave")
sleepMs(300)

// 2. Dwell reveal.
log(edge, "edge.zoneEnter edge=left zone=z-0 kind=wall x=0 y=540")
transition("hidden", "arming", "zone")
sleepMs(bad ? 155 : 120)
transition("arming", "revealing", "dwell")
animate(kind: "reveal", curve: "spring", from: hidden, to: 0, dur: 0.22, overshoot: bad ? 3 : 0)
transition("revealing", "shown", "animationEnd")
sleepMs(200)

// 3. Leave, hide delay, hide interrupted 90 ms in by a return.
transition("shown", "armingHide", "leave")
sleepMs(400)
transition("armingHide", "hiding", "hideDelay")
let presented = animate(kind: "hide", curve: "easeIn", from: 0, to: hidden, dur: 0.18, stopAfterMs: 90)
transition("hiding", "revealing", "return")
let remaining = abs(presented) / travel
animate(kind: "reveal", curve: "bezier", from: presented + (bad ? 20 : 0), to: 0, dur: max(0.06, 0.22 * remaining))
transition("revealing", "shown", "animationEnd")
sleepMs(100)
