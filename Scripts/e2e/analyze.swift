// Turns an E2E run's logs into pass/fail numbers (docs/evaluation.md §6, §7.3, §8, §3.3).
//
// Build: swiftc -O Scripts/e2e/analyze.swift -o build/e2e/analyze
//
//   analyze events <log.ndjson>
//       Every contract event (Tests/E2E/contract.md §3) with ms since the first one.
//   analyze timing <log.ndjson> [show=120] [hide=400] [reveal=220] [hidedur=180] [tol=16]
//       Dwell (hidden→arming → arming→revealing, cause=dwell), NFR-4 (zoneEnter →
//       reveal.begin), hide delay (shown→armingHide → armingHide→hiding), motion
//       durations, push-through and leave-before-dwell. p95 gates use `tol` ms.
//   analyze frames <log.ndjson> [hz=auto] [devtol=2] [devpct=3]
//       Frame log (DEDOCK_FRAME_LOG=1): per-animation curve match against the
//       motion tokens, overshoot, duration, plus the three DD-928 checks.
//   analyze contamination <listen.txt> [idle=1]
//       Counts input the driver did not post (syn=0) during a run. With idle=1 (a run
//       that should see no input) zero events is clean; otherwise zero events fails.
//
// Exit status 0 = every gate in the command passed, 1 = a gate failed, 2 = usage/input error.
// Lines starting with "FAIL" name the failing gate; "PASS"/"INFO" otherwise.

import Foundation

// MARK: - Input

struct Event {
    let ms: Double          // since boot, from machTimestamp
    let category: String
    let name: String
    let kv: [String: String]
    func d(_ k: String) -> Double? { kv[k].flatMap(Double.init) }
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func ticksToMs(_ t: UInt64) -> Double { Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e6 }

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write("analyze: \(msg)\n".data(using: .utf8)!)
    exit(2)
}

func loadEvents(_ path: String) -> [Event] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    var out: [Event] = []
    for line in text.split(separator: "\n") where line.hasPrefix("{") {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              (obj["subsystem"] as? String) == "app.dedock.Dedock",
              var msg = obj["eventMessage"] as? String,
              let mach = (obj["machTimestamp"] as? NSNumber)?.uint64Value else { continue }
        // REG-043: a stray trailing "<private>" (an empty .private interpolation) must not corrupt
        // the last key=value; it is stripped here and flagged by regress.sh's contract check.
        while msg.hasSuffix("<private>") { msg.removeLast("<private>".count) }
        let words = msg.split(separator: " ")
        guard let first = words.first else { continue }
        var kv: [String: String] = [:]
        for w in words.dropFirst() {
            let p = w.split(separator: "=", maxSplits: 1)
            if p.count == 2 { kv[String(p[0])] = String(p[1]) }
        }
        out.append(Event(ms: ticksToMs(mach), category: obj["category"] as? String ?? "", name: String(first), kv: kv))
    }
    return out.sorted { $0.ms < $1.ms }
}

func opts(_ a: ArraySlice<String>) -> [String: Double] {
    var o: [String: Double] = [:]
    for s in a { let p = s.split(separator: "="); if p.count == 2, let v = Double(p[1]) { o[String(p[0])] = v } }
    return o
}

func pct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return .nan }
    let s = xs.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded(.up)))]
}

/// `metrics=<file>`: machine-readable numbers for Scripts/e2e/regress.sh (one JSON object
/// per line). Scoring reads these, never the PASS/FAIL text.
let metricsPath: String? = CommandLine.arguments.dropFirst(2).first { $0.hasPrefix("metrics=") }.map { String($0.dropFirst(8)) }
func metric(_ name: String, _ value: Double) {
    guard let path = metricsPath, value.isFinite else { return }
    let line = String(format: "{\"metric\":\"%@\",\"value\":%.4f}\n", name, value)
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
    else { FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8)) }
}

var failures = 0
func gate(_ ok: Bool, _ label: String, _ detail: String) {
    print("\(ok ? "PASS" : "FAIL") \(label): \(detail)")
    if !ok { failures += 1 }
}
func info(_ label: String, _ detail: String) { print("INFO \(label): \(detail)") }
func f1(_ x: Double) -> String { String(format: "%.1f", x) }

// MARK: - Motion tokens (docs/design.md §3, dedock-inputs/animation-spec.md §2.1)

/// CSS-style cubic bezier timing function.
func bezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ u: Double) -> Double {
    if u <= 0 { return 0 }; if u >= 1 { return 1 }
    func bx(_ s: Double) -> Double { 3 * x1 * s * (1 - s) * (1 - s) + 3 * x2 * s * s * (1 - s) + s * s * s }
    func by(_ s: Double) -> Double { 3 * y1 * s * (1 - s) * (1 - s) + 3 * y2 * s * s * (1 - s) + s * s * s }
    var lo = 0.0, hi = 1.0
    for _ in 0..<60 { let m = (lo + hi) / 2; if bx(m) < u { lo = m } else { hi = m } }
    return by((lo + hi) / 2)
}

/// Progress 0…1 of an animation `t` seconds after it started.
func progress(curve: String, t: Double, dur: Double) -> Double {
    switch curve {
    case "spring": // motion.edge.reveal: critically damped, response 0.208 s
        let w = 2 * Double.pi / 0.208
        return t <= 0 ? 0 : 1 - (1 + w * t) * exp(-w * t)
    case "bezier": return bezier(0.2, 0.7, 0.2, 1, t / dur)      // reversed path into reveal
    case "easeIn": return bezier(0.42, 0, 1, 1, t / dur)         // motion.edge.hide
    default: return min(1, max(0, t / max(dur, 1e-9)))           // fade: linear stand-in
    }
}

// MARK: - Commands

func cmdEvents(_ ev: [Event]) {
    guard let t0 = ev.first?.ms else { print("no dedock events"); return }
    for e in ev where e.category != "frame" {
        let kv = e.kv.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print(String(format: "%9.1f  %-8@ %-20@ %@", e.ms - t0, e.category as NSString, e.name as NSString, kv as NSString))
    }
}

/// Contract drift shows up as a warning instead of a gate that silently never prints
/// (Tests/E2E/contract.md §3 lists the values).
func warnUnknown(_ ev: [Event]) {
    let known: [String: (event: String, values: Set<String>)] = [
        "cause": ("reveal.transition", ["zone", "dwell", "push", "leave", "return", "hideDelay", "animationEnd",
                                        "explicit", "inhibitor", "cooldown", "settings", "suppression", "button"]),
        "kind": ("reveal.begin", ["reveal", "hide", "fadeIn", "fadeOut"]),
        "curve": ("reveal.begin", ["spring", "bezier", "easeIn", "fade"]),
    ]
    let states: Set<String> = ["hidden", "arming", "revealing", "shown", "armingHide", "hiding"]
    for (key, spec) in known.sorted(by: { $0.key < $1.key }) {
        var counts: [String: Int] = [:]
        for e in ev where e.name == spec.event { if let v = e.kv[key], !spec.values.contains(v) { counts[v, default: 0] += 1 } }
        for (v, c) in counts.sorted(by: { $0.key < $1.key }) { print("WARN unrecognized \(key)=\(v) on \(spec.event) (\(c)×): contract drift? gates keyed on \(key) may not print") }
    }
    var badStates: [String: Int] = [:]
    for e in ev where e.name == "reveal.transition" {
        for k in ["from", "to"] { if let v = e.kv[k], !states.contains(v) { badStates[v, default: 0] += 1 } }
    }
    for (v, c) in badStates.sorted(by: { $0.key < $1.key }) { print("WARN unrecognized state \(v) (\(c)×)") }
}

func cmdTiming(_ ev: [Event], _ o: [String: Double]) {
    warnUnknown(ev)
    let show = o["show"] ?? 120, hide = o["hide"] ?? 400, tol = o["tol"] ?? 16
    let revealDur = o["reveal"] ?? 220, hideDur = o["hidedur"] ?? 180
    let tr = ev.filter { $0.name == "reveal.transition" }
    func next(after t: Double, where pred: (Event) -> Bool) -> Event? { tr.first { $0.ms > t && pred($0) } }

    // Dwell: each hidden→arming, and the transition that ends that arming.
    var dwellErr: [Double] = [], early = 0, leaves = 0, pushes: [Double] = []
    for a in tr where a.kv["from"] == "hidden" && a.kv["to"] == "arming" {
        guard let end = next(after: a.ms, where: { $0.kv["from"] == "arming" }) else { continue }
        let dt = end.ms - a.ms
        if end.kv["to"] == "revealing" && end.kv["cause"] == "dwell" {
            dwellErr.append(dt - show)
            if dt < show - 2 { early += 1 }
        } else if end.kv["to"] == "revealing" && end.kv["cause"] == "push" {
            pushes.append(dt)
        } else if end.kv["to"] == "hidden" {
            leaves += 1
            // Leave-before-dwell must not start any animation in between.
            let anim = ev.contains { $0.name == "reveal.begin" && $0.ms > a.ms && $0.ms <= end.ms }
            gate(!anim, "leave-before-dwell", "arming→hidden after \(f1(dt)) ms, animation started: \(anim)")
        }
    }
    if !dwellErr.isEmpty {
        metric("dwell_late_p95_ms", pct(dwellErr, 0.95)); metric("dwell_trials", Double(dwellErr.count))
        gate(pct(dwellErr, 0.95) <= tol && early == 0, "dwell",
             "n=\(dwellErr.count) show=\(Int(show)) ms, lateness p50=\(f1(pct(dwellErr, 0.5))) p95=\(f1(pct(dwellErr, 0.95))) max=\(f1(dwellErr.max()!)) ms, fired early: \(early)")
    }
    if !pushes.isEmpty {
        metric("push_ms_max", pushes.max()!); metric("push_trials", Double(pushes.count))
        gate(pushes.allSatisfy { $0 < show }, "push-through", "n=\(pushes.count), arming→revealing after \(pushes.map(f1).joined(separator: ",")) ms (must be < \(Int(show)))")
    }
    metric("leave_before_dwell", Double(leaves))
    if leaves > 0 { info("leave-before-dwell", "\(leaves) arming episodes ended in hidden") }

    // NFR-4: zone entry → reveal animation committed.
    var nfr4: [Double] = []
    for z in ev where z.name == "edge.zoneEnter" {
        // Only a fresh approach counts: hidden → arming right after the zone entry. A zone entry
        // during a hide reverses it (cause=return) and has no dwell to measure.
        guard let arm = next(after: z.ms - 0.001, where: { $0.kv["to"] == "arming" || $0.kv["to"] == "revealing" }),
              arm.kv["from"] == "hidden", arm.kv["to"] == "arming",
              arm.ms - z.ms < 50,
              let end = next(after: arm.ms, where: { $0.kv["from"] == "arming" }),
              end.kv["to"] == "revealing", end.kv["cause"] == "dwell",
              let begin = ev.first(where: { $0.name == "reveal.begin" && $0.kv["kind"] != "hide" && $0.kv["kind"] != "fadeOut" && $0.ms >= end.ms - 0.001 })
        else { continue }
        nfr4.append(begin.ms - z.ms - show)
    }
    if !nfr4.isEmpty {
        metric("nfr4_p95_ms", pct(nfr4, 0.95))
        gate(pct(nfr4, 0.95) <= tol, "NFR-4 zoneEnter→reveal.begin", "n=\(nfr4.count), over show delay p95=\(f1(pct(nfr4, 0.95))) ms (gate ≤ \(Int(tol)))")
    }

    // Hide delay.
    var hideErr: [Double] = [], cancelled = 0
    // Measured only when the hide timer starts AT the armingHide transition (cause=leave). If the
    // pointer left while the dock was still revealing, the timer started at that earlier leave and
    // armingHide only follows at animationEnd (top edge: 300 ms dwell), so armingHide→hiding is
    // shorter than the delay by design: not a lateness sample.
    var leftWhileRevealing = 0
    for a in tr where a.kv["to"] == "armingHide" {
        guard let end = next(after: a.ms, where: { $0.kv["from"] == "armingHide" }) else { continue }
        if a.kv["cause"] != "leave" { if end.kv["to"] == "hiding" { leftWhileRevealing += 1 }; continue }
        if end.kv["to"] == "hiding" && end.kv["cause"] == "hideDelay" { hideErr.append(end.ms - a.ms - hide) }
        else if end.kv["to"] == "shown" { cancelled += 1 }
    }
    if leftWhileRevealing > 0 { print("INFO hide delay: \(leftWhileRevealing) hide(s) after leaving during the reveal (timer started at the leave; not timed)") }
    if !hideErr.isEmpty {
        metric("hide_late_p95_ms", pct(hideErr, 0.95))
        gate(pct(hideErr, 0.95) <= tol && hideErr.allSatisfy { $0 > -2 }, "hide delay",
             "n=\(hideErr.count) hide=\(Int(hide)) ms, lateness p95=\(f1(pct(hideErr, 0.95))) min=\(f1(hideErr.min()!)) ms")
    }
    metric("hide_cancelled", Double(cancelled))
    if cancelled > 0 { info("hide cancelled by return", "\(cancelled)") }

    // Uninterrupted motion durations (state time in revealing / hiding).
    // Only motions that started from rest (not reversals, cause=return/leave mid-motion).
    func spans(_ from: String, _ to: String) -> [Double] {
        tr.filter { $0.kv["to"] == from && $0.kv["from"] != "hiding" && $0.kv["from"] != "revealing" }.compactMap { s in
            guard let e = next(after: s.ms, where: { $0.kv["from"] == from }), e.kv["to"] == to else { return nil }
            return e.ms - s.ms
        }
    }
    let rv = spans("revealing", "shown"), hd = spans("hiding", "hidden")
    let frame = 1000.0 / 60
    // The spring's 99 % point (220 ms) is gated in `frames`; when the app declares the
    // spring settled (revealing → shown) is its own choice, so it is reported only.
    if !rv.isEmpty { info("revealing→shown", "\(rv.map(f1).joined(separator: ",")) ms (99 % point exp \(Int(revealDur)); see `frames`)") }
    // State time includes the commit → vsync gap (up to a frame); the motion itself is gated
    // in `frames` from the frame log (§8: first moved frame → final frame).
    if !hd.isEmpty { info("hiding→hidden", "\(hd.map(f1).joined(separator: ",")) ms state time (motion exp \(Int(hideDur)) ms; see `frames`)") }

    if let last = tr.last { info("final state", "\(last.kv["to"] ?? "?") (cause=\(last.kv["cause"] ?? "?"))") }
    if dwellErr.isEmpty && hideErr.isEmpty && nfr4.isEmpty && rv.isEmpty && hd.isEmpty && pushes.isEmpty && leaves == 0 {
        print("FAIL no reveal transitions found"); failures += 1
    }
}

func cmdFrames(_ ev: [Event], _ o: [String: Double]) {
    let begins = ev.filter { $0.name == "reveal.begin" }
    let frames = ev.filter { $0.name == "frame" }.compactMap { e -> (ms: Double, tx: Double, anim: String)? in
        guard let tx = e.d("tx") else { return nil }
        return (e.ms, tx, e.kv["anim"] ?? "none")
    }
    warnUnknown(ev)
    guard !begins.isEmpty, frames.count > 1 else { print("FAIL frame log: no reveal.begin or fewer than 2 frames (DEDOCK_FRAME_LOG=1 set?)"); exit(1) }

    let dts = zip(frames.dropFirst(), frames).map { $0.ms - $1.ms }.filter { $0 > 1 && $0 < 40 }
    let frameMs = o["hz"].map { 1000 / $0 } ?? pct(dts, 0.5)
    info("frame interval", "\(f1(frameMs)) ms (\(f1(1000 / frameMs)) Hz), \(frames.count) frames, \(begins.count) animations")

    // Shown = 0; hidden = the `from` of any full reveal (largest |from| seen).
    let hiddenTx = begins.compactMap { $0.d("from") }.max { abs($0) < abs($1) } ?? 0
    let travel = abs(hiddenTx)
    let devTol = max(o["devtol"] ?? 2, travel * (o["devpct"] ?? 3) / 100)
    // DD-928 check 2 bound: the largest per-frame step of any clean curve over the full travel.
    let cleanMax = ["spring", "bezier", "easeIn"].map { c -> Double in
        let dur = c == "easeIn" ? 0.18 : 0.22
        return (1...40).map { k in (progress(curve: c, t: Double(k) * frameMs / 1000, dur: dur) - progress(curve: c, t: Double(k - 1) * frameMs / 1000, dur: dur)) * travel }.max()!
    }.max()!

    // Pass 1: fit every animation (best t0 within ±1 frame of its commit).
    struct Anim {
        let i: Int, b: Event, from: Double, to: Double, dur: Double, curve: String
        let seg: [(ms: Double, tx: Double, anim: String)]
        var shift = 0.0, dev = Double.infinity
        var start: Double { b.ms - shift }                  // fitted animation start
        func value(at ms: Double) -> Double {               // analytic presentation value
            curve == "fade" ? from : from + (to - from) * progress(curve: curve, t: (ms - start) / 1000, dur: dur)
        }
    }
    var anims: [Anim] = []
    for (i, b) in begins.enumerated() {
        guard let from = b.d("from"), let to = b.d("to"), let dur = b.d("dur") else { continue }
        let end = i + 1 < begins.count ? begins[i + 1].ms : .infinity
        var a = Anim(i: i, b: b, from: from, to: to, dur: dur, curve: b.kv["curve"] ?? "?",
                     seg: frames.filter { $0.ms > b.ms && $0.ms <= end })
        if !a.seg.isEmpty {
            func dev(_ shift: Double) -> Double {
                var x = a; x.shift = shift
                return x.seg.map { abs($0.tx - x.value(at: $0.ms)) }.max()!
            }
            a.shift = stride(from: -frameMs, through: frameMs, by: 0.5).min { dev($0) < dev($1) }!
            a.dev = dev(a.shift)
        }
        anims.append(a)
    }

    // Pass 2: gates per animation, and the DD-928 checks.
    var maxStep = 0.0, reversalJumps: [Double] = [], flicker: [String] = []
    var motionMs: [String: [Double]] = [:]
    defer {
        for (k, v) in motionMs where !v.isEmpty { metric(k, v.reduce(0, +) / Double(v.count)) }
        metric("max_step_pt", maxStep); metric("reversals", Double(reversalJumps.count))
        if let w = reversalJumps.max() { metric("reversal_offset_max_pt", w) }
        metric("curve_dev_max_pt", anims.map(\.dev).filter(\.isFinite).max() ?? 0)
    }
    for (k, a) in anims.enumerated() {
        let label = "anim \(a.i) \(a.b.kv["kind"] ?? "?")/\(a.curve) \(f1(a.from))→\(f1(a.to)) dur=\(String(format: "%.3f", a.dur))s"
        let interrupted = k + 1 < anims.count && !ev.contains { $0.name == "reveal.end" && $0.ms > a.b.ms && $0.ms <= anims[k + 1].b.ms }

        // DD-928 check 1: a reversal starts from the old animation's presentation value at the commit.
        let isReversal = k > 0 && !ev.contains { $0.name == "reveal.end" && $0.ms > anims[k - 1].b.ms && $0.ms <= a.b.ms }
        if isReversal { reversalJumps.append(abs(a.from - anims[k - 1].value(at: a.b.ms))) }

        guard !a.seg.isEmpty else { info(label, "no frames"); continue }
        let overshoot = a.seg.map { f in (a.to - a.from) * (f.tx - a.to) > 0 ? abs(f.tx - a.to) : 0 }.max()!
        gate(a.dev <= devTol && overshoot <= 0.05, label,
             "max deviation \(f1(a.dev)) pt (tol \(f1(devTol))) at t0 shift \(f1(a.shift)) ms, overshoot \(f1(overshoot)) pt, frames \(a.seg.count)" + (interrupted ? " (interrupted)" : ""))

        // Duration (§8 rule 1: ± 1 frame). Spring: to its 99 % point (220 ms). Bezier and
        // ease-in end exactly at `dur`, and an ease-out is within 1 % long before that,
        // so they are timed to arrival at the target.
        // Arrival is only well defined for full-travel motions (spring reveal, ease-in hide). A
        // partial reversal's ease-out is so flat at the end that "at target" comes ~15 % early on
        // a few points of travel; its duration is checked by the reversal-duration rule and the
        // curve fit (which uses the logged duration) instead.
        if !interrupted, a.curve != "fade", abs(a.to - a.from) < travel * 0.5 {
            info("\(label) duration", "partial travel \(f1(abs(a.to - a.from))) pt: timed by the reversal rule and curve fit")
        } else if !interrupted, a.curve != "fade" {
            // Timed from the curve-fitted start, not the first moved frame: when the commit lands
            // just before a vsync the first frame has barely moved (< 0.05 pt) and "first moved"
            // slips a whole frame. Display-link frames are quantised, so the frame that shows the
            // target lands in [expected, expected + 1 frame] after the true start.
            let expected = a.curve == "spring" ? 220.0 : a.dur * 1000
            let near = a.curve == "spring" ? abs(a.to - a.from) * 0.01 + 0.05 : 0.05
            if let f = a.seg.first(where: { abs($0.tx - a.to) <= near }) {
                let reach = f.ms - a.start
                let moved = a.seg.first(where: { abs($0.tx - a.from) > 0.05 }).map { f.ms - $0.ms }
                motionMs[a.curve == "spring" ? "reveal99_ms" : (a.curve == "easeIn" ? "hide_motion_ms" : "reversal_motion_ms"), default: []].append(reach)
                // −3 ms: the fitted start is within ±2–3 ms; + 1 frame: vsync quantisation.
                gate(reach >= expected - 3 && reach <= expected + frameMs + 1, "\(label) duration",
                     "start → \(a.curve == "spring" ? "99 % of travel" : "at target") \(f1(reach)) ms (exp \(f1(expected))…\(f1(expected + frameMs)): one vsync of quantisation)"
                     + (moved.map { "; first moved frame → target \(f1($0)) ms" } ?? ""))
            } else {
                gate(false, "\(label) duration", "never reached the target")
            }
        }

        // Reverse in place (DD-928, system-design §3.3.1): duration = full × remaining travel / total, floor 0.06 s.
        if isReversal, travel > 0 {
            let full = a.to == 0 ? 0.22 : 0.18
            let want = max(0.06, full * abs(a.to - a.from) / travel)
            gate(abs(a.dur - want) * 1000 <= frameMs, "\(label) reversal duration",
                 "dur \(String(format: "%.3f", a.dur)) s for \(f1(abs(a.to - a.from) / travel * 100)) % remaining (exp \(String(format: "%.3f", want)) s ± 1 frame)")
        }

        // DD-928 check 3: monotonic toward the target inside one animation.
        let dir = (a.to - a.from).sign
        for (p, c) in zip(a.seg, a.seg.dropFirst()) where (c.tx - p.tx) != 0 && (c.tx - p.tx).sign != dir {
            flicker.append("anim \(a.i): moved away from target at +\(f1(c.ms - a.b.ms)) ms (\(f1(p.tx))→\(f1(c.tx)))")
        }
        // Endpoint frames it never travelled to (e.g. a one-frame flash of "fully shown").
        let farEnd = a.to == 0 ? hiddenTx : 0
        for f in a.seg.dropLast() where abs(f.tx - farEnd) < 0.25 && abs(a.from - f.tx) > 0.25 {
            flicker.append("anim \(a.i): frame at the far endpoint \(f1(f.tx)) mid-animation")
        }
    }
    for (a, c) in zip(frames, frames.dropFirst()) { maxStep = max(maxStep, abs(c.tx - a.tx)) }

    if !reversalJumps.isEmpty {
        let worst = reversalJumps.max()!
        gate(worst <= 8, "DD-928 continuity at reversal", "\(reversalJumps.count) reversals, worst start offset \(f1(worst)) pt (target ≤ 1, fail > 8)")
        if worst > 1 && worst <= 8 { info("DD-928 continuity", "above the 1 pt target") }
    }
    gate(maxStep <= cleanMax + 1, "DD-928 max step", "largest frame step \(f1(maxStep)) pt (clean-run max \(f1(cleanMax)) + 1)")
    gate(flicker.isEmpty, "DD-928 no flicker", flicker.isEmpty ? "direction changes only at reversals" : flicker.prefix(5).joined(separator: "; "))
}

/// `idle=1`: a run that should see no input at all, so 0 events is the clean result.
func cmdContamination(_ path: String, idle: Bool) {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    let all = text.split(separator: "\n")
    // The listener prints "ready" once its event tap is live; without it 0 events proves nothing
    // (the listener never ran), so a missing ready line fails even an idle run.
    let ready = all.contains { $0.hasPrefix("ready ") }
    let lines = all.filter { $0.hasPrefix("mach=") }
    let foreign = lines.filter { $0.contains(" syn=0") }
    let untagged = lines.filter { !$0.contains(" syn=") } // listener built before tagging: cannot tell
    // REG-055: the listener records each foreign event's source pid (src=; 0 = a real device).
    var counts: [String: Int] = [:]
    for l in foreign { if let r = l.range(of: " src=") { counts[String(l[r.upperBound...].prefix { $0 != " " }), default: 0] += 1 } }
    let sources = counts.sorted { $0.key < $1.key }
    metric("foreign_events", Double(foreign.count + untagged.count))
    gate(ready && (idle || !lines.isEmpty) && foreign.isEmpty && untagged.isEmpty, "input contamination\(idle ? " (idle: expect none)" : "")",
         (ready ? "" : "listener never started (no ready line); ")
         + "\(lines.count) events seen, \(foreign.count) not from the driver, \(untagged.count) unverifiable (no syn= field)"
         + (foreign.first.map { " (first: \($0))" } ?? "")
         + (sources.isEmpty ? "" : "; foreign sources: " + sources.map { "pid \($0.key) x\($0.value)" }.joined(separator: ", ")))
}

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    print("usage: analyze events|timing|frames <log.ndjson> [k=v ...] | analyze contamination <listen.txt>")
    exit(args.isEmpty ? 0 : 2)
}
switch args[0] {
case "events": cmdEvents(loadEvents(args[1]))
case "timing": cmdTiming(loadEvents(args[1]), opts(args.dropFirst(2)))
case "frames": cmdFrames(loadEvents(args[1]), opts(args.dropFirst(2)))
case "contamination": cmdContamination(args[1], idle: args.dropFirst(2).contains("idle=1"))
default: fail("unknown command \(args[0])")
}
exit(failures == 0 ? 0 : 1)
