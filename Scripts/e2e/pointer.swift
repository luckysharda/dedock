// Synthetic pointer driver for dedock E2E (docs/evaluation.md §7.1 "SYN").
//
// Posts real CGEvent mouse events to the HID event tap, so NSEvent global
// monitors in the app under test see them exactly like hardware input,
// including explicit deltas while the cursor is clamped at a screen edge
// (push-through). Timing uses mach_wait_until, so steps land within tens of
// microseconds of their schedule.
//
// Build:  swiftc -O Scripts/e2e/pointer.swift -o build/e2e/pointer
// Needs:  the posting process passes CGPreflightPostEventAccess()
//         (Accessibility for the terminal host). Moves the real cursor, so
//         hold the desktop lock (Scripts/e2e/desktop-lock.sh) while it runs.
//
// Coordinates are global top-left points (same space as computer use and
// CGEvent). Every posted event and every `mark` is printed as one line:
//   mach=<ticks> ns=<uptime ns> ev=<kind> x=.. y=.. dx=.. dy=.. [label=..]
// `mach` is mach_absolute_time, the same clock as `machTimestamp` in
// `log stream --style ndjson`, so driver and app logs line up directly.
//
// Usage: pointer <command> [args]   (run `pointer help`)

import CoreGraphics
import Foundation

// MARK: - Clock

let timebase: mach_timebase_info_data_t = {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return info
}()

func nsToTicks(_ ns: UInt64) -> UInt64 { ns * UInt64(timebase.denom) / UInt64(timebase.numer) }
func ticksToNs(_ ticks: UInt64) -> UInt64 { ticks * UInt64(timebase.numer) / UInt64(timebase.denom) }

/// Absolute schedule anchored at the first call, so long scripts do not drift.
struct Schedule {
    private(set) var cursorTicks: UInt64 = mach_absolute_time()
    mutating func advance(ms: Double) {
        cursorTicks += nsToTicks(UInt64(max(0, ms) * 1_000_000))
        mach_wait_until(cursorTicks)
    }
    mutating func resync() { cursorTicks = mach_absolute_time() }
}

// MARK: - Output

var quiet = false
func emit(_ kind: String, _ p: CGPoint?, dx: Double = 0, dy: Double = 0, extra: String = "") {
    if quiet && kind != "mark" { return }
    let t = mach_absolute_time()
    var line = "mach=\(t) ns=\(ticksToNs(t)) ev=\(kind)"
    if let p { line += String(format: " x=%.1f y=%.1f dx=%.1f dy=%.1f", p.x, p.y, dx, dy) }
    if !extra.isEmpty { line += " " + extra }
    print(line)
}

// MARK: - Posting

let source = CGEventSource(stateID: .hidSystemState)
/// Stamped on every posted event (kCGEventSourceUserData) so a listener can
/// tell synthetic input from a person touching the mouse mid-run.
let synTag: Int64 = 0xDED0C
var modifierFlags: CGEventFlags = []
var buttonDown = false

func currentLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

func screenBounds() -> CGRect {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &count)
    return ids.prefix(Int(count)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
}

/// Posts a move to `p` carrying the given deltas. When dx/dy are nil they are
/// derived from the previous cursor location, like real hardware.
func post(to p: CGPoint, dx: Double? = nil, dy: Double? = nil) {
    let from = currentLocation()
    let ddx = dx ?? Double(p.x - from.x)
    let ddy = dy ?? Double(p.y - from.y)
    let type: CGEventType = buttonDown ? .leftMouseDragged : .mouseMoved
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else {
        FileHandle.standardError.write("pointer: could not create event\n".data(using: .utf8)!)
        exit(3)
    }
    e.setIntegerValueField(.mouseEventDeltaX, value: Int64(ddx.rounded()))
    e.setIntegerValueField(.mouseEventDeltaY, value: Int64(ddy.rounded()))
    e.setDoubleValueField(.mouseEventDeltaX, value: ddx)
    e.setDoubleValueField(.mouseEventDeltaY, value: ddy)
    e.flags = modifierFlags
    e.setIntegerValueField(.eventSourceUserData, value: synTag)
    e.post(tap: .cghidEventTap)
    emit(buttonDown ? "drag" : "move", p, dx: ddx, dy: ddy)
}

func postButton(_ down: Bool, at p: CGPoint, clickState: Int64 = 1) {
    let type: CGEventType = down ? .leftMouseDown : .leftMouseUp
    guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { exit(3) }
    e.setIntegerValueField(.mouseEventClickState, value: clickState)
    e.flags = modifierFlags
    e.setIntegerValueField(.eventSourceUserData, value: synTag)
    e.post(tap: .cghidEventTap)
    buttonDown = down
    emit(down ? "down" : "up", p)
}

func postModifier(_ key: String, down: Bool) {
    // Virtual key codes for the left-hand modifiers.
    let (code, flag): (CGKeyCode, CGEventFlags) = switch key {
    case "cmd": (55, .maskCommand)
    case "opt", "alt": (58, .maskAlternate)
    case "ctrl": (59, .maskControl)
    case "shift": (56, .maskShift)
    default: fatal("unknown modifier \(key) (cmd|opt|ctrl|shift)")
    }
    if down { modifierFlags.insert(flag) } else { modifierFlags.remove(flag) }
    guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { exit(3) }
    e.type = .flagsChanged
    e.flags = modifierFlags
    e.setIntegerValueField(.eventSourceUserData, value: synTag)
    e.post(tap: .cghidEventTap)
    emit(down ? "modDown" : "modUp", nil, extra: "key=\(key)")
}

func fatal(_ msg: String) -> Never {
    FileHandle.standardError.write("pointer: \(msg)\n".data(using: .utf8)!)
    exit(2)
}

// MARK: - Edges

enum Edge: String { case left, right, top, bottom }

/// Point clamped onto `edge` of the display containing `along`, plus the unit
/// direction that pushes into that edge.
func edgePoint(_ edge: Edge, along: Double, in b: CGRect) -> (CGPoint, CGVector) {
    switch edge {
    case .left: (CGPoint(x: b.minX, y: along), CGVector(dx: -1, dy: 0))
    case .right: (CGPoint(x: b.maxX - 1, y: along), CGVector(dx: 1, dy: 0))
    case .top: (CGPoint(x: along, y: b.minY), CGVector(dx: 0, dy: -1))
    case .bottom: (CGPoint(x: along, y: b.maxY - 1), CGVector(dx: 0, dy: 1))
    }
}

/// Seeded generator so crossing runs are reproducible (evaluation.md §3.3).
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Commands

/// Executes one command. Shared by the CLI and by `script`, which runs many
/// commands in one process so there is no process-launch latency between steps.
func run(_ args: [String], _ s: inout Schedule) {
    guard let cmd = args.first else { return }
    let a = Array(args.dropFirst())
    func d(_ i: Int, _ name: String) -> Double {
        guard i < a.count, let v = Double(a[i]) else { fatal("\(cmd): missing or bad <\(name)>") }
        return v
    }
    func opt(_ i: Int, _ def: Double) -> Double { i < a.count ? (Double(a[i]) ?? def) : def }
    func edge(_ i: Int) -> Edge {
        guard i < a.count, let e = Edge(rawValue: a[i]) else { fatal("\(cmd): <edge> must be left|right|top|bottom") }
        return e
    }

    switch cmd {
    case "pos":
        let p = currentLocation()
        print(String(format: "x=%.1f y=%.1f", p.x, p.y))

    case "screen":
        let b = screenBounds()
        print("x=\(b.minX) y=\(b.minY) w=\(b.width) h=\(b.height)")

    case "move": // move x y
        post(to: CGPoint(x: d(0, "x"), y: d(1, "y")))

    case "glide": // glide x y ms [hz]   straight line from the current point
        let to = CGPoint(x: d(0, "x"), y: d(1, "y")), ms = d(2, "ms"), hz = opt(3, 120)
        let from = currentLocation()
        let steps = max(1, Int((ms / 1000 * hz).rounded()))
        for i in 1...steps {
            let f = Double(i) / Double(steps)
            post(to: CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f))
            if i < steps { s.advance(ms: ms / Double(steps)) }
        }

    case "wait": // wait ms   (the cursor stays still: no events, like a resting hand)
        s.advance(ms: d(0, "ms"))

    case "resync": // restart the schedule at "now" (after an external pause)
        s.resync()

    case "mark": // mark label   (timestamped marker in the output)
        emit("mark", nil, extra: "label=\(a.first ?? "-")")

    case "edge": // edge <edge> <along>   jump onto the edge (inside the 3 pt zone)
        let (p, _) = edgePoint(edge(0), along: d(1, "along"), in: screenBounds())
        post(to: p)

    case "push": // push <edge> <along> <count> <step-pt> <window-ms>
        // Cursor pinned at the edge; each event carries `step` pt of delta into the edge.
        let e = edge(0), (p, dir) = edgePoint(e, along: d(1, "along"), in: screenBounds())
        let n = Int(d(2, "count")), step = d(3, "step"), win = d(4, "window-ms")
        for i in 0..<n {
            post(to: p, dx: dir.dx * step, dy: dir.dy * step)
            if i < n - 1 { s.advance(ms: win / Double(max(1, n - 1))) }
        }

    case "pull": // pull <edge> <along> <count> <step-pt> <window-ms>   deltas AWAY from the edge, cursor still pinned
        let e = edge(0), (p, dir) = edgePoint(e, along: d(1, "along"), in: screenBounds())
        let n = Int(d(2, "count")), step = d(3, "step"), win = d(4, "window-ms")
        for i in 0..<n {
            post(to: p, dx: -dir.dx * step, dy: -dir.dy * step)
            if i < n - 1 { s.advance(ms: win / Double(max(1, n - 1))) }
        }

    case "nudge": // nudge x y dx dy n win-ms   n events at a FIXED point carrying an explicit delta
        // (push-through mechanics anywhere on screen; used by the harness self-check)
        let p = CGPoint(x: d(0, "x"), y: d(1, "y")), dx = d(2, "dx"), dy = d(3, "dy")
        let n = Int(d(4, "n")), win = d(5, "win-ms")
        for i in 0..<n {
            post(to: p, dx: dx, dy: dy)
            if i < n - 1 { s.advance(ms: win / Double(max(1, n - 1))) }
        }

    case "crossings": // crossings <edge> <along> <count> <total-ms> <depth-pt> <seed> [hz]
        // `count` in/out crossings between the edge and `depth` pt inward, at
        // random (seeded) spacing that sums to total-ms. Each leg is a short glide.
        let e = edge(0), b = screenBounds()
        let (p, dir) = edgePoint(e, along: d(1, "along"), in: b)
        let count = Int(d(2, "count")), total = d(3, "total-ms"), depth = d(4, "depth-pt")
        var rng = SplitMix64(state: UInt64(d(5, "seed")))
        let hz = opt(6, 120)
        let inner = CGPoint(x: p.x - dir.dx * depth, y: p.y - dir.dy * depth)
        // 2 legs per crossing; random weights normalised to the total time.
        let weights = (0..<(count * 2)).map { _ in Double.random(in: 0.5...1.5, using: &rng) }
        let sum = weights.reduce(0, +)
        for (i, w) in weights.enumerated() {
            let legMs = total * w / sum
            let target = i % 2 == 0 ? p : inner
            emit("mark", nil, extra: "label=leg\(i)-\(i % 2 == 0 ? "in" : "out")")
            // glide, spending at most half the leg moving, the rest resting at the target
            let moveMs = min(legMs / 2, 40)
            let from = currentLocation()
            let steps = max(1, Int((moveMs / 1000 * hz).rounded()))
            for k in 1...steps {
                let f = Double(k) / Double(steps)
                post(to: CGPoint(x: from.x + (target.x - from.x) * f, y: from.y + (target.y - from.y) * f))
                s.advance(ms: moveMs / Double(steps))
            }
            s.advance(ms: legMs - moveMs)
        }

    case "circles": // circles cx cy r seconds [hz]   steady movement far from edges (perf: CPU while moving)
        let c = CGPoint(x: d(0, "cx"), y: d(1, "cy")), r = d(2, "r"), secs = d(3, "seconds"), hz = opt(4, 60)
        let n = Int(secs * hz)
        let wasQuiet = quiet
        quiet = true
        for i in 0..<n {
            let a = Double(i) / hz * 2 * .pi // one revolution per second
            post(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
            s.advance(ms: 1000 / hz)
        }
        quiet = wasQuiet
        emit("mark", nil, extra: "label=circles-done events=\(n)")

    case "click": // click x y [cmd|opt|ctrl|shift ...]
        let p = CGPoint(x: d(0, "x"), y: d(1, "y"))
        let mods = Array(a.dropFirst(2))
        mods.forEach { postModifier($0, down: true) }
        post(to: p)
        s.advance(ms: 30)
        postButton(true, at: p)
        s.advance(ms: 60)
        postButton(false, at: p)
        mods.reversed().forEach { postModifier($0, down: false) }

    case "drag": // drag x1 y1 x2 y2 ms [hold-ms] [cmd|opt|...]   press, travel, (hold), release
        let p1 = CGPoint(x: d(0, "x1"), y: d(1, "y1")), p2 = CGPoint(x: d(2, "x2"), y: d(3, "y2"))
        let ms = d(4, "ms"), hold = opt(5, 0)
        let mods = Array(a.dropFirst(a.count > 5 && Double(a[5]) != nil ? 6 : 5))
        mods.forEach { postModifier($0, down: true) }
        post(to: p1)
        s.advance(ms: 50)
        postButton(true, at: p1)
        s.advance(ms: 120) // past the drag threshold delay
        let steps = max(2, Int(ms / 1000 * 60))
        for k in 1...steps {
            let f = Double(k) / Double(steps)
            post(to: CGPoint(x: p1.x + (p2.x - p1.x) * f, y: p1.y + (p2.y - p1.y) * f))
            s.advance(ms: ms / Double(steps))
        }
        if hold > 0 { s.advance(ms: hold) }
        postButton(false, at: p2)
        mods.reversed().forEach { postModifier($0, down: false) }

    case "mod": // mod <cmd|opt|ctrl|shift> <down|up>
        guard a.count == 2 else { fatal("mod <key> <down|up>") }
        postModifier(a[0], down: a[1] == "down")

    default:
        fatal("unknown command \(cmd); run `pointer help`")
    }
}

let help = """
pointer — synthetic pointer driver for dedock E2E (global top-left points)

  pos | screen
  move x y                                    one move event (delta = from current point)
  glide x y ms [hz=120]                       straight line from the current point
  wait ms                                     keep still (no events)
  mark label                                  timestamped marker line
  edge <edge> <along>                         jump onto the edge of the screen
  push <edge> <along> n step win-ms           n events pinned at the edge, delta `step` INTO it
  pull <edge> <along> n step win-ms           same, delta AWAY from the edge
  nudge x y dx dy n win-ms                    n events at a fixed point with an explicit delta
  crossings <edge> <along> n total-ms depth seed [hz]   n seeded in/out crossings
  circles cx cy r seconds [hz=60]             steady circles (CPU-while-moving test)
  click x y [mods...]                         left click, optional cmd/opt/ctrl/shift held
  drag x1 y1 x2 y2 ms [hold-ms] [mods...]     press, travel, hold, release
  mod <cmd|opt|ctrl|shift> <down|up>
  script <file|->                             run commands, one per line, in one process
                                              (# comments; timings stay on one schedule)
Options (before the command): -q  print only marks
<edge> = left | right | top | bottom
"""

// MARK: - Main

var argv = Array(CommandLine.arguments.dropFirst())
if argv.first == "-q" { quiet = true; argv.removeFirst() }
guard let first = argv.first, first != "help", first != "-h", first != "--help" else {
    print(help)
    exit(0)
}
if !["pos", "screen"].contains(first) && !CGPreflightPostEventAccess() {
    fatal("this process may not post events: grant Accessibility to the terminal host")
}

setvbuf(stdout, nil, _IOLBF, 0)
var schedule = Schedule()
if first == "script" {
    let path = argv.count > 1 ? argv[1] : "-"
    let text: String
    if path == "-" {
        text = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    } else {
        guard let t = try? String(contentsOfFile: path, encoding: .utf8) else { fatal("cannot read \(path)") }
        text = t
    }
    schedule.resync()
    for raw in text.split(separator: "\n") {
        let line = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
        let words = line.split(separator: " ").map(String.init)
        if !words.isEmpty { run(words, &schedule) }
    }
} else {
    run(argv, &schedule)
}
