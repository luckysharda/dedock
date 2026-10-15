# dedock evaluation plan

How every dedock feature is checked before it merges into `develop`, and the filled-in acceptance list for **M1 Edge Dock** (the first feature, branch `feature/edge-dock-reveal`).

- Written 2026-10-15. Owner: whoever owns the feature's worktree. The evaluation lane runs E2E, perf, visual and motion checks (see `docs/organization.md`, "Sub-agent lanes").
- Reference paths such as `dedock-plan/system-design.md` are relative to the reference pack (`<pack>`, kept outside the repo; `organization.md` §1).
- `docs/design.md` exists as a skeleton: behaviour, motion tokens (`dd.motion.*`, the same values as `motion.*` in `dedock-inputs/animation-spec.md`) and layout grammar are fixed; the visual direction (§7 there) waits for the user's pick. Every pixel check against `docs/design.md` below is blocked until §7 is filled.
- `docs/plan.md` holds the milestone list, the per-feature process (§5) and the M1 task breakdown T0–T23 (§6). This file is the detail for its process steps 7–10 (unit tests, E2E, regression, comparison).
- Milestone names are this repo's own (`docs/plan.md` §4.1). "M1 Edge Dock" here is a subset of AP-M3 "Edge Dock core" in the pack's roadmap (`dedock-plan/adoption-plan.md` §10.1). AP-M1 is the window engine, which dedock builds in its own M3.
- In this file, "the plan" without a qualifier means the reference pack's `dedock-plan/`; the repo's plan is always written `docs/plan.md`. The pack is read-only: conflicts with it are recorded in `docs/plan.md` and `docs/status.md`, never edited in the pack.
- Clean-room and scope: DockDoor is GPL-3.0, so evaluation compares behaviour, never code. Notchy is out of scope: nothing from `notchy/` or `research/notchy-*` is read or used (`docs/plan.md` D-8).
- Motion token names are dedock's `dd.motion.*` (`docs/design.md` §3); citations of `dedock-inputs/animation-spec.md` keep its `motion.*` names. "Principle M2" in §8 is the motion principle in that file, not milestone M2.

---

## 1. Constraints on this machine (they shape every method below)

| Fact (checked 2026-10-15) | Consequence |
|---|---|
| Only Command Line Tools, Swift 6.4. No Xcode. | Tests use swift-testing through `swift test`. No XCTest, XCUITest, `xcodebuild`, Instruments or `xctrace` (`xctrace` exits with "requires Xcode"). `XCTCPUMetric`, `XCTMemoryMetric` and the Animation Hitches instrument from `dedock-plan/system-design.md` §9 and `dedock-plan/architecture.md` §14 are replaced by CLI tools (§6). |
| One display: 1920 × 1080 at 1× ("looks like 1920 × 1080 @ 60 Hz"). | 1 pt = 1 px in captures, which makes pixel measurement simple. Multi-display and 120 Hz checks cannot run here. They are covered by fakes and marked **deferred on this machine**. |
| Native Dock: bottom, auto-hide off (`defaults read com.apple.dock orientation` = bottom, `autohide` = 0). | Left and right Edge Docks do not conflict with the native Dock. Bottom-edge tests need the native-Dock footprint rules (DD-991, DD-992). |
| DockDoor 1.40.7 is installed and not running. | It can be launched for live comparison (§7) and for coexistence checks. |
| CoolDock 2.2.0 is in `/Applications` and is **running from a mounted DMG** (`/Volumes/CoolDock/CoolDock.app`). | It must be quit before any E2E run, because it competes for screen edges. The pack says CoolDock was never installed (`README.md`, Method). Whether it can be used for live comparison is an open question for the user (`docs/status.md`). Until the user answers, CoolDock comparison uses the pack's screenshots and frame grids only. |
| `ffmpeg`, `ffprobe`, `screencapture`, `top`, `footprint`, `vmmap`, `leaks`, `sample`, `powermetrics` (sudo) are present. AVFoundation lists "Capture screen 0" as video device index 1. | Screen recording for motion checks is `ffmpeg -f avfoundation`. The process that records needs the Screen Recording permission. |

---

## 2. Layers at a glance

| # | Layer | What it proves | Tool | Runs | Gate |
|---|---|---|---|---|---|
| L1 | Unit | Pure logic: geometry, state machines, layout, settings | swift-testing, `swift test`, `TestClock` | every build | PR: all green; 100 % of the reveal transition table covered |
| L2 | Integration | Services wired together over fake screens, clock, workspace and Dock prefs | swift-testing with fakes from the `DedockTestSupport` target | every build | PR |
| L3 | E2E | The real app on the real desktop | computer use (CU) + synthetic pointer driver (SYN) + `log stream` | per feature, before PR | PR: every scenario for the feature passes on left and right |
| L4 | Regression | Nothing that passed before is broken | checklist §5 (grows per feature) | every PR into `develop`; full list before `staging` | PR |
| L5 | Performance | Budgets from `dedock-plan/system-design.md` §9 and NFR-1…NFR-6 | `top`, `footprint`, `powermetrics`, `leaks`, os_log timestamps, release-mode micro-benchmarks | per feature; nightly once CI exists | PR: no budget exceeded |
| L6 | Visual (§9) | Placement, sizing and behaviour against the references; tokens against `docs/design.md` pixel for pixel | `screencapture`, `Scripts/measure-pixels.swift`, side-by-side composites | per feature with UI | PR: reviewer signs the visual table |
| L7 | Motion (§8) | Durations and curves match `dedock-inputs/animation-spec.md` | 60 fps screen recording + debug frame log | per feature with motion | PR |

A feature is **done** when its scorecard (§10) has no Fail, every waiver is approved by the user, and `docs/status.md` is updated.

---

## 3. L1 unit tests (swift-testing)

Conventions: one test target per module (`EdgeDockTests`, `SettingsStoreTests`, `DedockCoreTests`, `DesignSystemTests`). Parameterised `@Test(arguments:)` tables. Tags `.unit`, `.integration`, `.perf`. No test touches the real clock, real screens or real defaults. `TestClock` advances time by hand, so dwell and hide timers are deterministic (`dedock-plan/architecture.md` §14).

### 3.1 Default values used by the tests

The plan states some defaults twice with different numbers. Tests use the column "Used". The other value is superseded and the conflict is logged in `docs/status.md`.

| Parameter | Used | Source of the used value | Superseded value |
|---|---|---|---|
| Show dwell | 120 ms | `dedock-plan/system-design.md` §5.1, `dedock-plan/ux-patterns.md` T3, `dedock-inputs/animation-spec.md` §4 | 0.15 s (`dedock-plan/features.md`, Edge Dock defaults table and DD-921) |
| Full-screen dwell | 400 ms | `system-design.md` §5.1, `ux-patterns.md` T4, `dedock-inputs/side-dock-modes.md` §2 | 0.75 s (`features.md` DD-924) |
| Corner exclusion | 24 pt (8 pt when that Hot Corner is off) | `system-design.md` §5.1, `ux-patterns.md` T2 | 10 pt (`features.md` defaults table, DD-923) |
| Zone thickness / span | 3 pt / content span + 40 pt each side | `system-design.md` §5.1 | span = dock length (`features.md` DD-923) |
| Push-through | 40 pt of delta toward the edge | `system-design.md` §5.1 | none |
| Hide hysteresis / hide delay | 16 pt / 400 ms | `system-design.md` §5.1, T8, T9 | none |
| Re-arm cooldown after a tile launch | 500 ms | `system-design.md` §5.1 | none |
| Reveal / hide motion | `dd.motion.edge.reveal` spring (response 0.208, damping 1.0) / `dd.motion.edge.hide` ease-in (0.42, 0, 1, 1) 0.18 s | `dedock-inputs/animation-spec.md` §2.1 | "0.22 s ease-out" (`features.md` DD-927); "spring, bounce 0.06" (`dedock-plan/design-system.md` §7.2) |
| Idle CPU | gate < 0.5 % (NFR-1, MVP exit gate); target < 0.3 % | `features.md` NFR-1; `system-design.md` §9 | — (both tracked; only the gate fails a PR) |

### 3.2 Trigger geometry per edge (DD-902, DD-923, DD-931)

Every test below runs for each edge: **left, right** (default), **bottom** (optional, beta) and **top below the menu bar** (optional, beta). The plan defers the top edge to P2 (`features.md` DD-1141); `docs/plan.md` D-11 pulls it into M1 as an optional, beta-labelled edge, so its rows run in M1.

| Test | Arguments | Expect |
|---|---|---|
| Zone lies on the physical edge | edge × display frame (1920×1080 at origin; 2560×1440 offset; negative-origin display) | zone rect is `thickness` pt inside `screen.frame` (never `visibleFrame`) on that side |
| Zone span follows content | content length 120, 400, 1000 pt; alignment start/center/end | span = content ± 40 pt, clipped to the edge |
| "Whole edge" span option | edge | span = full edge minus exclusions |
| Corner exclusion | Hot Corner on / off per corner | 24 pt / 8 pt removed at each end |
| Menu-bar exclusion (left, right) | menu bar shown; auto-hidden; notched display (`safeAreaInsets.top` > 0) | top `menuBarHeight` removed; with auto-hide uses `max(NSStatusBar.thickness, safeAreaInsets.top)` (`system-design.md` §5.1) |
| Top edge (optional) | notch areas, status-item area | zone spans only the dock's length; excludes the notch and the status-item area; dock frame `maxY ≤ visibleFrame.maxY` (DD-1141) |
| Bottom edge (optional) | native Dock visible / auto-hidden / on another edge | zone excludes the native Dock's span (`system-design.md` §5.5, settled rule); dock sits at `visibleFrame.minY` |
| Shared-edge split | side-by-side equal displays; mixed heights (the 1920×1080 + 2560×1440 example in `system-design.md` §5.4); stacked | wall parts get a 3 pt zone, shared parts an 8 pt band; property test over 500 random arrangements: every wall zone lies on exactly one display's unshared edge segment |
| Push-through from deltas | sequences of `deltaX` toward / away from the edge, clamped position | reveal fires when accumulated toward-edge delta ≥ 40 pt; deltas away do not count; accumulator resets when no instance is armed |
| Hysteresis | pointer at panel frame + 15, 16, 17 pt | inside, inside, outside |
| Shared-edge slow dwell | speed 200 / 400 pt/s over the last 50 ms; neighbour-display appearance within 80 ms | reveal after 300 ms only when slow; crossing cancels arming |
| Modifier policy | ⌥ held / not held in the shared band | reveal on contact only with ⌥ |
| No arming with a mouse button held | `pressedMouseButtons` ≠ 0, no content drag | stays `hidden` (`system-design.md` §5.5, tiling drags) |

### 3.3 Reveal state machine (DD-912, DD-921, DD-922, DD-924, DD-928, DD-929)

States and transitions are the canonical set in `dedock-plan/system-design.md` §4.2: `hidden, arming, revealing, shown, armingHide, hiding`.

| Test | Expect |
|---|---|
| Transition table | One parameterised test per row of the §4.2 diagram (13 transitions) plus every illegal pair (state × event with no transition) is a no-op. Coverage 100 % of rows is the PR gate. |
| Dwell fires on time | With `TestClock`, entering a wall zone and staying 119 ms keeps `arming`; at 120 ms the state is `revealing`. Same at 400 ms when the display's Space is full screen (DD-924). |
| Leave before dwell | Leaving at 100 ms returns to `hidden` with no animation request (DD-912 criterion 2). |
| One-shot timers | No timer exists while `hidden` and the pointer is still (counts timers on the fake clock). Timers fire within 16 ms of the configured delay on the real clock (L2 test). |
| No relayout on movement | 1000 pointer samples inside the shown dock produce 0 layout passes (DD-912 criterion 4). |
| Hide delay | Pointer outside panel + 16 pt with no inhibitor → `armingHide`; 399 ms later still `armingHide`; 400 ms → `hiding`. Returning at 300 ms → `shown` (timer cancelled). |
| Range checks | show and hide delay accept 0–5 s; 0 s reveals on the first sample in the zone. |
| Idempotent requests | Requesting the state the dock is already heading to does not restart its animation (DD-928). |
| Reverse in place, duration | For p ∈ {0.10, 0.25, 0.50, 0.75} the planner returns the durations in `system-design.md` §3.3.1 (0.198 / 0.165 / 0.110 / 0.060 s to shown; 0.060 / 0.060 / 0.090 / 0.135 s to hidden), floor 0.06 s, curve = bezier form of `dd.motion.edge.reveal` or `dd.motion.edge.hide`. |
| Reverse in place, start value | The new animation's from-value equals the presentation value it was given (difference 0 pt). |
| Inhibitors | For each token (`dragging, menuOpen, previewOpen, popoverOpen, editing, textFocus, keyboardFocused, pinnedByUser`; `docs/design.md` §2.2): raised in `shown` blocks `armingHide`; raised in `armingHide` forces `shown`; cleared with the pointer outside starts the 400 ms hide delay. Several tokens: hide waits for the last one. |
| Preview coupling (later, with previews) | `armingHide → hiding` waits while preview alpha > 0 (`system-design.md` §4.2 invariant). Stubbed in M1 with a fake preview presenter. |
| Explicit hide + cooldown | Hotkey or tile launch → `hiding` directly; zone entries are ignored for 500 ms. |
| Menu-tracking fallback | `NSMenu.didBeginTracking` swaps the event monitors for a 30 Hz `.common`-mode timer; `didEndTracking` swaps back (DD-929). |

**DD-928, "20 rapid crossings in 2 s, no > 8 pt jump".** The wording cannot be met literally. An uninterrupted reveal already moves more than 8 pt between frames (COMPUTED at 60 Hz for 90 pt travel, `dd.motion.edge.reveal` spring: 8.2, 15.8, 16.1, 13.7, 10.7 … pt per frame; the bezier form used for reversals: 24.6, 22.2, 15.3 …; `dd.motion.edge.hide`: up to 12.6 pt). `dedock-inputs/animation-spec.md` §2.1 shows the same frame steps. dedock tests the intent, "no jumps or flicker", as three checks:

1. **Continuity at reversal.** At each reversal, the first rendered position of the new animation is within 1 pt of the last rendered position of the old one (target 0 pt). Any discontinuity above **8 pt** fails (the DD-928 number, applied to the discontinuity).
2. **No step larger than a clean run.** No frame-to-frame step exceeds the largest step of an uninterrupted reveal over the same travel (24.6 pt for the 90 pt bezier case), plus 1 pt tolerance.
3. **No flicker.** The direction of motion changes only at frames where a reversal was requested. The dock never shows a frame at "fully hidden" or "fully shown" that it did not travel to.

The unit version drives the planner with a `TestClock` and an analytic curve model, **with hide delay 0 and primed by one dwell reveal**, then 20 random in/out crossings in 2 s (seeded, 200 seeds), sampled at 60 and 120 Hz. Without those two conditions the test is vacuous: 40 legs average 50 ms, below the 120 ms dwell and the 400 ms hide delay, so no animation would start (push-through only counts while armed, §3.2). The test fails if no reversal occurred. The same three checks run on the debug frame log in E2E (`E2E-x-06`) and on the screen recording in L7. The wording in `dedock-plan/features.md` DD-928 ("no frame where the dock jumps more than 8 pt") is read this way by dedock (logged in `docs/status.md`; the pack itself is not edited); `docs/plan.md` T8 criterion 4 states the three checks.

### 3.4 Click-through hit testing (DD-933)

| Test | Expect |
|---|---|
| Hidden or hiding | `ignoresMouseEvents == true` from the first frame of a hide, and in `hidden` |
| Revealing | gate turns interactive at the start of the reveal; hit rects = **target** tile frames, not animated ones |
| Empty panel margins | `hitTest` returns nil for points 1, 4 and 20 pt outside the container, in gaps between tiles, and in the label margin |
| Tiles and controls | `hitTest` returns the tile for its centre and for points 1 pt inside each edge |
| Faded (later, DD-982) | alpha < 0.05 → `ignoresMouseEvents == true` |

### 3.5 Layout grammar (DD-903)

| Test | Expect |
|---|---|
| Tile thickness | `tileThickness = dockThickness − 2 × padding` for every dock size |
| Tile length | `tileLength = lengthUnits × tileThickness`, lengthUnits ∈ {1.0, 1.5, 2.25, 3.0, 4.0} |
| Concentric radii | container radius = tile radius + padding |
| Flow | side docks stack top to bottom; the bottom dock flows leading to trailing; the order in the model equals the visual order on both side edges |
| Alignment | start / center / end along the edge; centre is computed on `visibleFrame`, not `frame` |
| Distance from edge | 0–48 pt inset |
| Maximum length | container length ≤ `visibleFrame` length − 2 × 8 pt (`docs/architecture.md` §6.8); M1 shrinks tiles uniformly to 60 % of `t` and then clips; scrolling is DD-977 (P1, not M1). M1 asserts the dock never exceeds the maximum |
| Label side | hover label toward the screen centre: right of a left dock, left of a right dock, above a bottom dock, below a top dock |
| Indicator side | inner side (toward the screen centre) by default, per `docs/design.md` §4.2 and §8 row 1 (DD-903 says inner side; `design-system.md` §9.6 says screen-edge side and "make it a setting") |
| Hidden offset | content translation when hidden = −(thickness + edge inset + 8 pt) on the left, + on the right (`design-system.md` §9.6) |
| Edge change | changing edge re-lays out within one reveal cycle (DD-902 criterion 1) |

### 3.6 Settings round-trip and migration (SettingsStore)

| Test | Expect |
|---|---|
| Round-trip | every Edge Dock key (`dock[i].edge, mode, scenario, showDelay, hideDelay, fullscreenShowDelay, triggerThickness, triggerSpan, cornerExclusion, alignment, edgeInset, tileThickness, dragToRearrange, sharedEdgeTrigger`, tile list) survives encode → decode with equality |
| Defaults | an empty store returns the §3.1 defaults; the recommended scenario follows the native Dock edge (`features.md` defaults table: Left when the native Dock is bottom or right, Right when it is left) |
| Validation | out-of-range values are clamped and logged (e.g. `showDelay` 9 s → 5 s) |
| Unknown keys | kept on rewrite (forward compatibility) |
| Migration | schema version is stored; each migration vN → vN+1 has a fixture file and a golden output; v1 is the first schema, so M1 adds the harness and a v0 (empty) → v1 test |
| Corrupt file | a truncated `layout.json` is renamed `layout.corrupt-<ISO8601>.json` and the newest rolling backup (`layout.json.1`) loads, else defaults; the app does not crash (`docs/architecture.md` §7) |
| Atomic write | writes go to a temp file and rename; a crash mid-write (simulated) leaves the old file intact |
| Scenario cards | applying a card writes all its keys in one transaction; any later manual edit sets `scenario = Custom` (DD-910 criterion 4) |

### 3.7 Tiles and indicators

| Test | Expect |
|---|---|
| Running state (DD-962) | from fake `NSWorkspace` launch / terminate / activate / hide events: dot shown for `activationPolicy == .regular`, frontmost highlighted, hidden dimmed, accessory apps no dot |
| Icon size (DD-961) | icons requested at 256 pt nominal; never upscaled |
| Reorder (DD-975) | insertion index follows the pointer along the dock axis at every tile boundary ± half a tile; drop outside removes only after confirmation; order persisted immediately |
| Drag permission | plain drag reorders only when `dragToRearrange` is on; ⌘-drag always |
| Folder tile (DD-964 basic) | click opens Finder or the stack list toward the screen centre |

---

## 4. L2 integration tests (fakes)

| Fake | Used for |
|---|---|
| `FakeScreenProvider` | screen arrangements: single 1920×1080; side-by-side equal; mixed heights with bottoms aligned; stacked; notched built-in + external; display added / removed at runtime (`didChangeScreenParameters`) |
| `TestClock` | dwell, hide, cooldown and debounce timers |
| `FakePointerHub` | scripted pointer sample streams with location, delta, modifiers and pressed buttons |
| `FakeWorkspace` | app launch / terminate / activate / hide; full-screen Space flag per display |
| `FakeDockPreferences` | native Dock orientation × auto-hide (the 9-cell matrix of DD-991, run once bottom-edge support lands) |
| `FakeLayer` | records requested animations and lets the test set a presentation value |

| Scenario | Expect |
|---|---|
| Pointer stream → trigger → reveal controller → layer | the layer receives exactly one reveal animation with the `dd.motion.edge.reveal` parameters; gate opens in the same tick |
| Display removed while shown | the instance moves to the fallback display or suspends; no duplicate instance |
| Shared edge, mixed heights | wall part reveals on a 120 ms dwell; shared part needs the slow dwell; a fast crossing never reveals |
| Full-screen flag toggles 20× | each toggle picks the right dwell; no stuck state |
| Status-item menu tracking | while the fake menu tracks, the 30 Hz fallback timer runs and samples still drive the trigger |
| Settings change while shown | edge or size change re-lays out and re-animates within one cycle; no crash |
| Real-clock timer accuracy | 200 dwell timers on `ContinuousClock`: p95 lateness ≤ 16 ms (NFR-4) |

---

## 5. L4 regression checklist (grows per feature)

Run the whole list before merging `develop` into `staging`. Each PR runs the items whose area it touches. When a feature merges, its E2E scenarios that found a bug, and any bug fixed later, are added here with the PR number.

| ID | Check | Layer | Added by |
|---|---|---|---|
| REG-001 | Left and right reveal with dwell and with push-through | E2E-x-01, -02 | M1 |
| REG-002 | 20 rapid crossings in 2 s: the three DD-928 checks pass | L1 + E2E-x-06 | M1 |
| REG-003 | Click 4 pt outside the container reaches the window underneath; clicks on a hidden dock's area reach the window underneath | E2E-x-08 | M1 (`adoption-plan.md` §10.1 exit item 3) |
| REG-004 | No timer faster than 1 Hz while idle; idle CPU < 0.5 % | L5 | M1 (NFR-1) |
| REG-005 | Dock never covers the menu bar, Control Center, Notification Center or menu-bar menus on a right edge | E2E-R-12 | M1 (DD-901 criterion 5; DockDoor Pro GH#1633) |
| REG-006 | The native Dock's prefs are never written (`defaults read com.apple.dock` before = after) | E2E teardown | M1 (DD-901 criterion 1; DockDoor #1222 lesson) |
| REG-007 | No Space switch when revealing over a full-screen app (`NSApp.activate` never called) | E2E-x-10 | M1 |
| REG-008 | Five full-screen enter / exit cycles keep the dock working (20 cycles once DD-947 lands) | E2E-x-10 | M1 |
| REG-009 | Settings survive relaunch; a corrupt `layout.json` falls back to the newest backup, else defaults | L1 + E2E-x-13 | M1 |
| REG-010 | Dedock idles with no Accessibility or Screen Recording grant, and asks for neither in M1 | E2E-x-00 | M1 (`system-design.md` §5.3) |
| REG-011 | Native-Dock 9-cell matrix (DD-991) | E2E | later (bottom edge) |
| REG-012 | DockDoor regression set: #472, #297, #1222, #277, #1001 (`adoption-plan.md` §10.1 exit item 2) | E2E | later (previews) |

### 5.1 Regression policy

| Rule | Detail |
|---|---|
| **REG id first** | Every bug gets the next `REG-nnn` id in `Tests/E2E/regressions.md` (owned by the E2E lane) **before** its fix is written. The id names the symptom, the scenario that exposed it and the build it was seen on. Features add REG rows here when they merge (table above). |
| **Layer 1: unit, in CI** | The fix ships with a `.regression` unit test **in the same commit**. Each test lives in a suite whose type name ends in `Regression` (for example `@Suite("Regression", .tags(.regression)) struct EdgeDockRegression`), with one `@Test("REG-nnn …")` per id. `ci/regression.sh` runs `swift test --filter Regression` as its own step on macOS and Linux, so a failure is reported under its REG id. Owner: implementer. |
| **Layer 2: E2E, local** | `Scripts/e2e/regress.sh` replays every REG scenario that needs a real desktop against the build under test, inside the desktop lock, and writes a scorecard. The baseline (timings, CPU, RSS) is `Tests/E2E/baseline/m1.json`. Owner: E2E lane. Hosted CI cannot run it (no TCC grants, no real desktop). |
| **Merge gates** | PR → `develop`: CI green, including the `Regression tests` step; app-code PRs attach the `regress.sh` scorecard (PR template). `develop` → `staging`: a full `regress.sh` run on the candidate build with 0 failures. `staging` → `main`: the same run on the release build. |
| **Baseline drift** | `regress.sh` warns when a measured value drifts more than **20 %** from the baseline (worse direction), even if it is still under its budget. A drift warning blocks promotion to `staging` until it is explained in the PR or the baseline is updated on purpose (with the reason in `docs/status.md`). |
| **Empty layer** | Until the first `.regression` tests land, an empty layer 1 passes with a notice. Setting the repository variable `REGRESSION_REQUIRED=true` makes an empty layer fail. |
| **Never delete** | REG tests and scenarios are only retired with a written reason (feature removed), recorded in `Tests/E2E/regressions.md`. |

---

## 6. L5 performance budgets and how they are measured here

Budgets come from `dedock-plan/system-design.md` §9 and `dedock-plan/features.md` §0.3 (NFR-1…NFR-6). Instruments is not available, so each row names its CLI method. Every run records the macOS build, the dedock commit and whether DockDoor and CoolDock were running (they must not be).

| Metric | Budget | Method on this Mac | M1? |
|---|---|---|---|
| Idle CPU, nothing shown, pointer still | gate < 0.5 % over 60 s (target < 0.3 %) | `Scripts/measure-idle.sh` (`docs/plan.md` T22) wrapping `top -l 61 -s 1 -pid $PID -stats cpu`; drop the first sample; average the rest | yes |
| Idle wakeups | no timer faster than 1 Hz | `sudo powermetrics --samplers tasks --show-process-wakeups -i 1000 -n 60`, Dedock row ≤ 1 wakeup/s. Needs sudo, so the user runs it or approves it | yes |
| CPU, pointer moving far from edges | < 1.0 % | SYN driver draws circles in the screen centre for 60 s at 60 Hz; `top` as above | yes |
| Pointer-sample handling | ≤ 20 µs p99 | `swift test -c release --filter EdgeDockPerf`: 1 M `evaluate()` calls in batches of 1000 on `ContinuousClock`; plus the in-app histogram counter in debug builds | yes |
| Dwell expiry → reveal start | ≤ show delay + 16 ms (NFR-4) | os_log events `edge.zoneEnter` and `reveal.begin` (logged at `CATransaction` commit) from `log stream --style ndjson --level debug --predicate 'subsystem == "app.dedock.Dedock"'`; over 50 SYN trials, p95 of `(reveal.begin − zoneEnter) − showDelay` ≤ 16 ms. Cross-check: the first moving frame in the 60 fps recording is no later than 1 frame after the expected one | yes |
| Reveal / hide frames | 0.22 s / 0.18 s, 0 dropped frames at 60 Hz (120 Hz deferred: no 120 Hz display) | debug frame log (`DEDOCK_FRAME_LOG=1`): a display-link callback logs the content layer's presentation translation on every frame. A dropped frame is a frame where the value did not change mid-animation. Recording (§8) as the second source | yes |
| RSS, one Edge Dock | ≤ 120 MB (NFR-2) | `footprint $PID` → `phys_footprint`; `ps -o rss= -p $PID` | yes |
| Leaks and growth | 0 leaks; growth ≤ 2 MB after 100 reveal / hide cycles | `leaks $PID` and `footprint` before and after a SYN loop | yes |
| Cold launch → edge armed | ≤ 400 ms for the **first launch after login, binary not just rebuilt**; the first launch after a rebuild (macOS pre-main load and signature check of a freshly signed binary, measured ≈ 441 ms release vs ≈ 21 ms of dedock code) is reported, not gated. Warm launch measured 77–87 ms. | the app logs `launch.edgeReady` with the time since process start (from `kinfo_proc` start time) | yes |
| Widget wakeups while hidden | 0 pull fetches | provider counters | later (widgets) |
| Hover → preview, switcher, tap callback | NFR-3, NFR-5, NFR-6 | signposts and log timestamps | later (previews) |

Baseline for comparison: run the same idle CPU and RSS commands against live DockDoor 1.40.7 (pack figure ≈ 0 % CPU, 100–110 MB, `dockdoor/system-design.md` §5.4) and record both numbers in the scorecard.

---

## 7. L3 E2E with computer use

### 7.1 Drivers and evidence

| Driver | Use it for | Limits |
|---|---|---|
| **CU** (computer use: `screenshot`, `mouse_move`, `left_click`, `left_click_drag`, `key`) | moving to a point and confirming state by screenshot; clicks; settings pane; menu-bar item | one action takes hundreds of milliseconds, so CU cannot time anything under about 0.5 s. A pointer moved to the edge stops there and produces no further delta, so CU **cannot do push-through**. Terminals are click-only and browsers read-only for CU. |
| **SYN** (`Scripts/e2e/pointer.swift`, `docs/plan.md` T21, to be written in M1) | exact timing; push-through (posts `mouseMoved` with `kCGMouseEventDeltaX` while the cursor is clamped at the edge); rapid crossings; ⌘-drag | posting events needs the posting process to pass `CGPreflightPostEventAccess()` (Accessibility for the terminal host). SYN moves the real cursor, so it needs the desktop lock like CU |
| **LOG** | ground truth for states and times | the edge trace (DD-814 subset, `docs/plan.md` T20) and debug os_log lines record every reveal transition with monotonic time, pointer position, zone and inhibitors (`system-design.md` §10) |
| **GEOM** | exact coordinates | with `DEDOCK_E2E=1`, the debug build writes the container, tile and zone frames (AppKit and top-left coordinates) to `~/Library/Application Support/Dedock Debug/e2e/geometry.json` on every layout (data folder per `docs/architecture.md` §7) |

Coordinates below are in computer-use screen space: top-left origin, 1920 × 1080, 1 px = 1 pt on this display. AppKit y = 1080 − y. If the screenshot tool reports scaling, convert by its ratio. "Tile k" and "container" positions come from GEOM; the numbers given are for a centred dock and serve as a fallback.

Edge parameters used in every scenario:

| Symbol | Left (L) | Right (R) |
|---|---|---|
| `EDGE_X` (in the 3 pt zone) | 0 | 1919 |
| `IN_X` (well inside the screen, outside dock + 16 pt) | 600 | 1319 |
| `PROBE_Y` (inside the zone span for a centred dock) | 540 | 540 |
| push direction for SYN | `deltaX < 0` | `deltaX > 0` |

### 7.2 Setup and teardown (every run)

1. Take the desktop lock (`docs/organization.md`, "Desktop lock").
2. Record and quit the reference apps: `pgrep -lf "CoolDock|DockDoor" > build/e2e/<run>/before-apps.txt`, then quit them (`osascript -e 'quit app "CoolDock"'`, same for DockDoor). Relaunch whatever was running at teardown.
3. Record the native Dock prefs: `defaults read com.apple.dock > build/e2e/<run>/dock-before.plist`. Do not change them in M1.
4. `Scripts/make-app.sh debug`, then `DEDOCK_E2E=1 Scripts/run.sh` (starts `log stream` into `build/e2e/<run>/log.ndjson`).
5. Pin 3 test apps and 1 folder in the Edge Dock: Calculator, TextEdit, Notes, and the folder `~/Downloads`, through Settings ▸ Add App… / Add Folder… (`docs/plan.md` T15) or by starting from a seeded `layout.json` fixture. Use apps CU can drive at full tier.
6. Open one TextEdit window with its frame set to x 0…900, y 100…900 so it sits under a left dock (and one at x 1020…1920 for right-dock runs). This is the click-through target.
7. Teardown: quit Dedock; `defaults read com.apple.dock` and diff against step 3 (REG-006); relaunch the apps from step 2; release the lock.

### 7.3 What the app must expose for these checks

Debug builds only (compiled out of release). Without these, half of §6–§8 cannot run, so each is attached to an M1 task in `docs/plan.md` §6.1.

| Hook | What it produces | Used by | Attach to |
|---|---|---|---|
| Edge trace | every transition with monotonic time, pointer position, zone id, active inhibitors; export to a file | LOG in §7, x-01…x-06, x-16 | T20 |
| Timing events | os_log events `edge.zoneEnter`, `reveal.begin` (at `CATransaction` commit), `reveal.end`, `hide.begin`, `hide.end` with `.public` values | §6 dwell → reveal latency (NFR-4) | T20 |
| `launch.edgeReady` | time since process start (from `kinfo_proc` start time) when the first dock is armed | §6 cold launch | T20 |
| `DEDOCK_E2E=1` geometry dump | container, tile and zone frames in AppKit and top-left coordinates, written to `~/Library/Application Support/Dedock Debug/e2e/geometry.json` on every layout | GEOM in §7, §9 captures | T14 (layout) + T21 |
| `DEDOCK_FRAME_LOG=1` frame log | the content layer's presentation translation (and alpha) on every display-link frame | §3.3 DD-928 checks on the real app, §6 dropped frames, §8 | T8 |
| Sample-cost histogram | per-call cost of pointer-sample evaluation, p50 / p99 counters | §6 pointer-sample budget | T5 |
| Synthetic driver | `Scripts/e2e/pointer.swift`: scripted paths, push-through deltas, rapid crossings, ⌘-drag | SYN in §7 | T21 |

### 7.4 Scenarios (run each for L and R; IDs `E2E-L-nn` / `E2E-R-nn`)

| ID | Feature | Driver | Steps | Pass |
|---|---|---|---|---|
| x-00 | DD-901, REG-010 | CU + LOG | Launch with no Accessibility / Screen Recording grant. Screenshot. | No permission prompt. The status item is visible. The dock is parked hidden (LOG state `hidden`). Dedock has no Dock icon (LSUIElement). |
| x-01 | DD-912, DD-921 dwell reveal | SYN + LOG, CU confirm | SYN: jump to (`IN_X`, 540), then to (`EDGE_X`, 540) and hold still 300 ms. CU screenshot. | LOG: `hidden → arming` at entry, `arming → revealing` at 120 ms ± 16 ms, `revealing → shown` ≈ 220 ms later. Screenshot shows the dock on that edge, centred on `visibleFrame`. |
| x-02 | DD-912 leave before dwell | SYN + LOG | Enter the zone, leave after 80 ms. Repeat 10×. | No `revealing` in LOG; no animation requests. |
| x-03 | DD-912 push-through | SYN + LOG | Enter the zone and post 10 `mouseMoved` events of 5 pt toward the edge within 50 ms (cursor clamped). | `arming → revealing` before the 120 ms dwell, when accumulated delta reaches 40 pt. Pushing away from the edge never reveals. |
| x-04 | DD-922 hide delay | SYN + LOG, CU confirm | From `shown`, move to (`IN_X`, 540) and hold. CU screenshot after ≈ 1 s. | `shown → armingHide` when the pointer passes container + 16 pt; `armingHide → hiding` at 400 ms ± 16 ms; `hidden` ≈ 180 ms later. Screenshot: dock gone. Re-run returning at 300 ms: back to `shown`, no hide. |
| x-05 | DD-928 reverse in place | SYN + LOG + frame log | (a) Start a hide, return to the zone 90 ms into it. (b) Set hide delay 0 s, leave 100 ms into a reveal. | LOG: `hiding → revealing` (a) and `revealing → hiding` (b) with no dwell; FAIL if no reversal occurred. Frame log: the three DD-928 checks (§3.3) pass. Durations match the remaining-travel table within one frame. |
| x-06 | DD-928 rapid crossings | SYN + frame log | In the x-05(b) configuration (hide delay 0; the scenario refuses to run otherwise): dwell-reveal first, then 20 in/out crossings in 2 s between (`EDGE_X`, 540) and (`EDGE_X` ± 120, 540), random spacing (seeded). Each outbound leg starts a hide, each inbound leg reverses it. | The three DD-928 checks pass on every frame. At least one reversal occurred (else FAIL). The final state matches the pointer's final position. |
| x-07 | DD-961 click a tile launches the app | CU + Bash | Quit Calculator. Reveal (CU `mouse_move` to (`EDGE_X`, 540), wait 1 s). CU `left_click` on the Calculator tile centre (GEOM). | Within 2 s Calculator is frontmost (`osascript -e 'tell app "System Events" to name of first process whose frontmost is true'`). The dock starts hiding right after the click (explicit hide) and does not re-reveal for 500 ms even though the pointer is near the edge. Dedock never became the active app. Clicking again on the running app activates it. |
| x-08 | DD-933 empty area click-through | CU | (a) Dock shown: click 4 pt outside the container's inner edge, at the container's vertical centre, over the TextEdit window. (b) Dock shown: click in the gap between two tiles. (c) Dock hidden: click at (`EDGE_X` ± 40, 540). | (a) and (c): TextEdit becomes frontmost and its insertion point moves (screenshot). (b) passes through if the gap is outside the tile hit rects (per §3.4). No click is swallowed in any case. |
| x-09 | DD-975 drag reorder | CU (plain drag with "Drag to rearrange" on) + SYN (⌘-drag with it off) | Drag tile 1 (Calculator) to below tile 3. | Neighbours move apart during the drag with the reorder token from `docs/design.md`; the dock stays shown during the drag (`dragging` inhibitor in LOG); new order shown and present in `layout.json` immediately; survives relaunch. With the setting off, a plain drag does not reorder. |
| x-10 | DD-924, DD-901 criterion 4, REG-007/008 full screen | CU + SYN + LOG | Put TextEdit in full screen (CU `key` ctrl+cmd+f on TextEdit). SYN: hold at the edge 200 ms, leave; then hold 500 ms. CU screenshot. Exit full screen. Repeat 5×. | 200 ms: no reveal (full-screen dwell is 400 ms). 500 ms: dock revealed over the full-screen app; TextEdit stays frontmost and in full screen (no Space switch). After exit, the normal 120 ms dwell applies again. All 5 cycles pass. |
| x-11 | DD-931 multi-display shared edge | — | Needs a second display. | **Deferred on this machine.** Covered by L1 §3.2 and L2 §4. Run when a second display is attached: on the shared edge a fast crossing to the other display never reveals; a slow 300 ms dwell does; ⌥ + contact reveals with the Modifier policy. |
| x-12 | DD-901 criterion 5, REG-005 (R only) | CU | With the right dock shown, open Control Center, Notification Center and a menu-bar menu (e.g. the Dedock status item). Screenshot each. | Each system surface draws above the dock. The dock never extends into the menu-bar height. |
| x-13 | DD-910, DD-911, settings pane, DD-801 | CU + Bash | Open Settings from the status item. Pick "Reveal on Left", "Reveal on Right", "Pinned" in turn (then "Reveal at Bottom" and "Reveal at Top", both beta). Change the show delay to 0.50 s. Quit and relaunch. | Each card applies edge, mode and delays in one step and shows the 2 s hint at the chosen edge. The recommended badge sits on "Reveal on Left" (native Dock at bottom). After the manual delay change the card reads "Custom". Pinned: dock visible without touching the edge, at start / center / end. After relaunch every value is unchanged. Status menu items (`docs/plan.md` T18: Show/Hide Edge Dock, Edge ▸, Mode ▸, Keep Dock Open, Settings…, Quit dedock) work. |
| x-14 | DD-962 running indicators | CU + Bash + LOG | `open -a TextEdit`; `osascript -e 'quit app "Notes"'`; hide Calculator (⌘H). Screenshot after each. | Dot appears / disappears / dims as specified in `docs/design.md`; LOG shows the render within 100 ms of the workspace notification. |
| x-15 | DD-964 folder tile | CU | Click the Downloads tile. | Opens the stack list toward the screen centre (default, `docs/plan.md` T14), or Finder at Downloads when the folder setting says so. The stack list holds the dock open (`popoverOpen`). |
| x-16 | DD-929 inhibitors | CU + LOG | Open the folder stack, then move the pointer far away; open the Settings pane with live preview of this dock; start a tile drag and hold it outside the dock. | The dock does not hide while any token is set. When the last token clears with the pointer outside, the 400 ms hide delay starts. |
| x-17 | Reduce Motion (NFR-10) | CU (System Settings ▸ Accessibility ▸ Display ▸ Reduce motion) + recording | Turn Reduce motion on, run x-01 and x-04, turn it back off. | Reveal and hide are a 0.15 s opacity fade in place (leading edge constant across frames). Setting restored at the end. |
| x-18 | Bottom / top edge (optional, beta) | as x-01…x-08 | Turn the edge on in Settings first. Top: also click a menu-bar menu at the top edge. | Same pass rules. Top: the dock reveals below the menu bar; menu-bar clicks still open their menus. Bottom: zone excludes the native Dock span; dock sits above the native Dock. |

---

### 7.5 App ↔ harness contract

The canonical text is `Tests/E2E/contract.md` (owned jointly by the implementer and the E2E lane; any change lands on both sides in the same PR). Agreed points, 2026-10-15:

| Item | Rule |
|---|---|
| Scope | Every hook below is **debug-bundle only** (`app.dedock.Dedock.debug`); release builds ignore them. |
| `DEDOCK_E2E=1` | Writes the GEOM file `<data dir>/e2e/geometry.json` (atomic rewrite after every layout pass and state change: screens, docks, panel/capsule/tile/hit/zone rects in AppKit and top-left coordinates) and the `.public` E2E log lines. |
| `DEDOCK_FRAME_LOG=1` | One `frame edge=<e> tx=<pt> alpha=<a> anim=<kind>` line per display-link callback while animating, nothing while idle. |
| `DEDOCK_E2E_HOME=<dir>` | Alias of `DEDOCK_DATA_DIR`. The whole data directory is `<dir>`; v0 persists `layout.json` only, no `UserDefaults` (`architecture.md` §7). Seeding = drop `layout.json` there before launch, built from `Tests/E2E/fixtures/layout-seed.json` and patched per scenario (`docks[].reveal.*`, `docks[].edge`). |
| Bookmark-less tiles | The loader accepts tiles with only `bundleID` (apps) or `path` (folders) and fills the bookmark on first save. Real layouts resolve the bookmark first, then fall back. |
| Log events | `os_log` subsystem `app.dedock.Dedock`; message = event name + `key=value` pairs; timing from ndjson `machTimestamp`. `reveal.transition` causes: `zone` (hidden→arming), `dwell`, `push`, `leave`, `return`, `hideDelay`, `animationEnd` (revealing→shown, hiding→hidden), `explicit`, `inhibitor`, `cooldown`, `settings`, `suppression`, `button`. Events: `launch.edgeReady`, `edge.zoneEnter/zoneExit/push`, `reveal.transition/begin/end`, `gate.mouse`, `inhibitor`, `layout.pass`, `tile.activate/indicator/reorder`, `settings.changed`, `pointer.mode`. Never log window titles. |
| Harness pieces | `Scripts/e2e/pointer.swift` (standalone `swiftc -O` → `build/e2e/pointer`, not a Package.swift target), `Scripts/e2e/launch.sh`, `Scripts/e2e/analyze.swift`, `Scripts/e2e/desktop-lock.sh`, `Scripts/measure-idle.sh`, `Scripts/measure-pixels.swift`, `Tests/E2E/edge-dock-reveal.md`. |

## 8. L7 motion measurement

**Recording rule.** Record with `-pix_fmt yuv444p`: the default `yuv420p` halves chroma resolution, which shifts coloured edges at odd x by 1 px and solid colours by ~2/255 (measured by the E2E lane). Video is for timing and position only; every colour or pixel check uses `screencapture` PNGs (§9).

Targets are the resolved tokens in `dedock-inputs/animation-spec.md` §2.1 and §5. Do not re-derive them.

**Recording.**

```sh
# 60 fps, lossless, cursor visible; device "1" = Capture screen 0 on this Mac
ffmpeg -f avfoundation -framerate 60 -capture_cursor 1 -i "1:none" -t 4 \
  -c:v libx264 -preset ultrafast -crf 0 -pix_fmt yuv444p build/e2e/<run>/reveal-L.mkv
# check the cadence: pts deltas must all be ≈ 16.67 ms
ffprobe -v error -select_streams v -show_entries frame=pts_time -of csv=p=0 build/e2e/<run>/reveal-L.mkv
# crop to the edge strip and extract frames
ffmpeg -i build/e2e/<run>/reveal-L.mkv -vf "crop=200:1080:0:0" build/e2e/<run>/frames/%04d.png
```

Use a solid desktop picture for the run (record the user's current one first and restore it) so the container edge is easy to find. Trigger the motion with SYN so the start time is known.

**Measuring.** `Scripts/measure-pixels.swift` (to be written; CoreGraphics only) walks a scanline at the container's vertical centre in each frame and reports the x of the container's leading edge (first pixel that differs from the background by more than a threshold). The series, minus the hidden position, is the travelled distance per frame. The debug frame log (§6) gives the same series from the presentation layer; both must agree within 1 pt.

**Expected series at 60 Hz** (COMPUTED for 90 pt travel = T 76 + gap 6 + 8, the example in `animation-spec.md` §2.1. dedock's real travel is T + edge inset + shadow reach with T = t + 2p and t = 56 pt (`docs/design.md` §4); scale the series by real travel / 90):

| Motion | Token | Cumulative pt per frame | Frames |
|---|---|---|---|
| Reveal | `dd.motion.edge.reveal` spring, response 0.208, damping 1.0 | 0, 8.2, 24.0, 40.1, 53.7, 64.4, 72.3, 78.0, 81.9, 84.6, 86.4, 87.7, 88.5, 89.0, 89.4 … 90 | 99 % at frame 14 (0.233 s; 99 % point 0.220 s) |
| Reverse into reveal | bezier (0.2, 0.7, 0.2, 1), duration × remaining | full run: 0, 24.6, 46.9, 62.1, 71.6, 77.8, 81.8, 84.7, 86.6, 88.0, 88.9, 89.5, 89.9, 90 | 13–14 |
| Hide | `dd.motion.edge.hide` ease-in (0.42, 0, 1, 1), 0.18 s | 0, 1.3, 4.9, 10.2, 16.9, 24.9, 33.9, 43.9, 54.8, 66.6, 79.2, 90 | 11 |
| Reduce Motion | opacity 0.15 s, no travel | leading edge constant; alpha ramps over 9 frames | 9 |

**Pass rules.** Align t0 at the first frame that moved. (1) Duration within ± 1 frame. (2) Every sample within ± 2 pt of the expected curve (or ± 3 % of travel if larger). (3) Overshoot 0 pt: no frame beyond the final position (principle M2, "nothing on an edge bounces"). (4) Monotonic, except at requested reversals. (5) Start time: first moved frame ≤ 1 frame after `zoneEnter + showDelay` (NFR-4). (6) The DD-928 checks (§3.3) on reversal runs.

**Behaviour comparison for motion.** No recording of the CoolDock app exists in the pack. Compare the shape only against the frame grids in `cooldock/recordings/stills/v1.4-frames/` and `cooldock/animations.md` §4.1: reveal has its biggest jump first then a 1–2 frame settle; hide accelerates off-screen. Write the comparison as a sentence in the scorecard, not a number.

---

## 9. L6 visual comparison protocol

dedock's look is intentionally different from DockDoor and CoolDock (user decision). Compare **behaviour, placement, sizing and motion timing** with the references. Compare **pixels** only with dedock's own tokens in `docs/design.md`.

### 9.1 Captures

| Capture | How |
|---|---|
| dedock shown, left and right, light and dark appearance | `screencapture -x -R <x,y,w,h> build/e2e/<run>/dedock-<edge>-<appearance>.png` around the container (+ 40 pt margin, from GEOM) |
| dedock with Reduce Transparency on | same, for solid-fill colour checks |
| Live DockDoor 1.40.7 | launch it, hover a native Dock icon, `screencapture` the panel. In M1 this gives the panel-to-edge gap, glass panel size and the menu-bar clamp to compare with how dedock places its own surfaces; it is the primary reference once previews start |
| Pack references | `cooldock/screenshots/01-home-hero-dock-widgets.jpg` (capsule composition, tile proportions), `cooldock/screenshots/21-docs-layout-scenarios.jpg` (scenario cards, reveal controls), `cooldock/screenshots/website-assets/video-poster-overview-widget-browser-edit-mode.webp` (edit mode), `dockdoor/screenshots/140-side-dock-left-preview-ghostty.png` (a panel laid out at the left edge), `dockdoor/screenshots/100-dock-preview-chrome-with-media-widget.png` (panel scale) |

Side-by-side composite for review (same height, no scaling of dedock's capture):

```sh
ffmpeg -i build/e2e/<run>/dedock-L-dark.png -i "<pack>/cooldock/screenshots/01-home-hero-dock-widgets.jpg" \
  -filter_complex "[1]scale=-1:ih[b];[0][b]hstack=inputs=2" build/e2e/<run>/compare-cooldock.png
```

CoolDock's images are marketing renders at an unknown scale, so compare **proportions** (tile length to thickness, padding to thickness), not absolute points.

### 9.2 What is compared

| Aspect | Reference | Pass rule |
|---|---|---|
| Placement | CoolDock: dock sits on its edge at a small distance, centred, zone follows content (`cooldock/layout-modes.md` §2) | dedock: on the chosen edge, inset per `docs/design.md`, centred on `visibleFrame`, clear of the menu bar and the 24 pt corner exclusions |
| Sizing | CoolDock tiles ≈ 62 pt (`cooldock/design-system.md` §2); native Dock tile size on this Mac | dedock thickness and tile size equal the `docs/design.md` values; the reviewer notes the ratio to the native Dock tile |
| Behaviour | CoolDock reveal / hide rules (`cooldock/layout-modes.md` §2, §4) | E2E §7 passes |
| Motion | `animation-spec.md` §2.1 | §8 passes |
| Distinctness | CoolDock's near-black capsule and running dots; DockDoor's glass panel and cards | The reviewer lists at least 3 visual attributes where dedock differs from **both** (silhouette, material, colour, indicator, label, tile background, shadow). Fail if a person comparing the side-by-side could take dedock for either product, or if a surface reads as Liquid Glass cards with traffic lights or as a floating dark container of rounded widget cards (`docs/design.md` D1). |

### 9.3 Pixel check against `docs/design.md`

Do this at 1× (this display), so 1 pt = 1 px.

| Measured in the capture | Tolerance |
|---|---|
| Container thickness, length, padding, tile gap, tile size, icon size, edge inset (for a direction with no container, such as `docs/design.md` E2, the plate and spine extents) | exact; ± 1 px only where the edge is anti-aliased |
| Corner radii (container, tile) | ± 1 px, measured where the curve meets the straight edge |
| Indicator size and offset; label offset from the container | exact; ± 1 px for anti-aliasing |
| Solid colours (Reduce Transparency on, both appearances) | ± 2/255 per channel at the sample points listed in `docs/design.md` |
| Material surfaces (glass on) | against a golden capture over the same solid desktop picture: ≤ 0.5 % of pixels differ by more than 4/255 (the snapshot threshold in `dedock-plan/architecture.md` §14) |

`Scripts/measure-pixels.swift` prints RGBA at given points and edge positions along given scanlines; the scorecard stores its output as CSV.

### 9.4 Evidence storage

Raw recordings and full captures stay in `build/e2e/<run>/` (git-ignored; they can show the user's desktop). Only cropped dock-region PNGs and measurement CSVs are committed, under `docs/evidence/<feature>/<YYYY-MM-DD>/`. The written comparison (behaviour table plus links to those images) is `docs/compare/<feature>.md` (`docs/plan.md` §5 step 10); E2E scripts per feature live in `Tests/E2E/<feature>.md` (step 8).

---

## 10. Per-feature scorecard template

Copy into the PR description or `docs/evidence/<feature>/scorecard.md`.

```markdown
## Scorecard: <DD-ID> <title>
Branch: feature/<name> · Commit: <sha> · Date: <YYYY-MM-DD> · Evaluator: <lane or person>
Machine: macOS <build>, 1920×1080 @ 60 Hz, native Dock <edge/autohide>, DockDoor running? <y/n>, CoolDock running? <y/n>

| # | Acceptance criterion (from features.md or this file) | L1 | L2 | E2E (L / R) | Perf | Visual | Motion | Result | Evidence |
|---|---|---|---|---|---|---|---|---|---|
| 1 | ... | pass | pass | pass / pass | n/a | n/a | n/a | Pass | test name, run id, CSV |

Results: Pass · Fail · Waived (reason + user approval) · Deferred (reason, e.g. "needs a second display")

Perf numbers: idle CPU __ % (DockDoor baseline __ %) · RSS __ MB · dwell→reveal p95 __ ms over show delay · leaks __
Motion: reveal __ frames (exp. 14) · hide __ frames (exp. 11) · max deviation __ pt · overshoot __ pt
Visual: distinctness attributes: 1. __ 2. __ 3. __ · design.md pixel check: __ of __ within tolerance
Deviations from the plan (with the plan line they contradict): ...
Regression items added: REG-___
Verdict: Done / Not done — signed: ____
```

---

## 11. M1 Edge Dock acceptance list (filled in)

Status on 2026-10-15: nothing is implemented, so every row is **Not run**. "x" = run for left and right.

| # | ID | Criterion | Layers | Test / scenario | Status |
|---|---|---|---|---|---|
| 1 | DD-901 | The native Dock is never hidden, moved or reconfigured | E2E | REG-006 teardown diff | Not run |
| 2 | DD-901 | Non-activating panel: a tile click launches or focuses the app; dedock never becomes the active app | E2E | x-07 | Not run |
| 3 | DD-901 | Works over full-screen apps (`.fullScreenAuxiliary`), no Space switch | E2E | x-10 | Not run |
| 4 | DD-901 | System overlays (Control Center, Notification Center, banners, menu-bar menus) draw above a right dock | E2E | R-12 | Not run |
| 5 | DD-901 | Runs with no Accessibility or Screen Recording grant; no prompt | E2E | x-00 | Not run |
| 6 | DD-902 | Edge ∈ {left, right} (bottom, top-below-menu-bar optional); slide axis X on sides, Y on bottom/top | L1, E2E | §3.2, x-01, x-18 | Not run |
| 7 | DD-902 | Trigger, hysteresis maths are axis-generic; one suite runs for all edges | L1 | §3.2 parameterised over edges | Not run |
| 8 | DD-902 | Changing the edge re-lays out and re-animates within one reveal cycle | L1, L2 | §3.5 "Edge change", §4 | Not run |
| 9 | DD-903 | Thickness / length grammar, concentric radii, top-to-bottom flow on side docks | L1, L6 | §3.5, §9.3 | Not run |
| 10 | DD-903 | Hover label toward the screen centre, shown instantly (`dd.motion.tile.label`) | L1, E2E, L7 | §3.5, x-07 screenshot | Not run |
| 11 | DD-903 | Running indicator on the inner side (`docs/design.md` §4.2); its look per `docs/design.md` §7.1 (4 pt white dot, inner side) | L1, L6 | §3.5, §9.3 | Not run |
| 12 | DD-910 (subset) | Cards: Reveal on Left, Reveal on Right, Reveal at Bottom (beta), Pinned, Reveal at Top (beta) (`docs/plan.md` T17) | E2E | x-13 | Not run |
| 13 | DD-910 | Recommended badge follows the native Dock edge (bottom → Reveal on Left) | L1, E2E | §3.6 Defaults, x-13 | Not run |
| 14 | DD-910 | A card applies all its settings in one step and shows a 2 s hint at the edge | L1, E2E | §3.6 Scenario cards, x-13 | Not run |
| 15 | DD-910 | A later manual change marks the card "Custom" | L1, E2E | §3.6, x-13 | Not run |
| 16 | DD-911 | Pinned: always visible; start / center / end alignment | E2E, L6 | x-13 | Not run |
| 17 | DD-912 | State machine `hidden → arming → revealing → shown → armingHide → hiding → hidden`, all transitions | L1 | §3.3 transition table (100 %) | Not run |
| 18 | DD-912 | Leaving before the dwell returns to hidden with no animation | L1, E2E | §3.3, x-02 | Not run |
| 19 | DD-912 | One-shot timers, no polling, fire within 16 ms | L1, L2, L5 | §3.3, §4 timer accuracy, §6 wakeups | Not run |
| 20 | DD-912 | No relayout while moving inside the zone or the shown dock | L1 | §3.3 | Not run |
| 21 | DD-912 | Push-through (40 pt) reveals before the dwell | L1, E2E | §3.2, x-03 | Not run |
| 22 | DD-921 | Show delay 0–5 s, default 120 ms, reveal starts ≤ show delay + 16 ms | L1, L5, E2E | §3.3, §6, x-01 | Not run |
| 23 | DD-922 | Hide delay 0–5 s, default 400 ms; inhibitors pause it | L1, E2E | §3.3, x-04, x-16 | Not run |
| 24 | DD-923 | Zone 1–20 pt from `screen.frame`; span = content + 40 pt or whole edge; corner and menu-bar exclusions | L1 | §3.2 | Not run |
| 25 | DD-924 | Full-screen dwell 400 ms, separate from the normal dwell | L1, E2E | §3.3, x-10 | Not run |
| 26 | DD-925 | Alignment start / center / end; distance from edge 0–48 pt | L1, L6 | §3.5, §9.3 | Not run |
| 27 | DD-926 | One size control scales tiles, gaps and padding; live preview while dragging the slider | L1, E2E | §3.5, x-13 | Not run |
| 28 | DD-927 | Panel frame fixed; only the content layer's translation animates | L2, L7 | §4 FakeLayer, §8 | Not run |
| 29 | DD-927 | Reveal = `dd.motion.edge.reveal`, hide = `dd.motion.edge.hide`, frame counts per §8 | L7 | §8 | Not run |
| 30 | DD-927 | Reduce Motion: 0.15 s opacity fade in place | E2E, L7 | x-17 | Not run |
| 31 | DD-928 | Reversal from the presentation value, duration × remaining, floor 0.06 s | L1, E2E | §3.3, x-05 | Not run |
| 32 | DD-928 | Requesting the current target is a no-op | L1 | §3.3 | Not run |
| 33 | DD-928 | 20 crossings in 2 s: continuity ≤ 8 pt at reversals, no step above a clean run, no flicker | L1, E2E, L7 | §3.3, x-06 | Not run |
| 34 | DD-929 | Inhibitors block hiding (M1 tokens: dragging, menuOpen, popoverOpen, editing, pinnedByUser; previewOpen stubbed) | L1, E2E | §3.3, x-16 | Not run |
| 35 | DD-929 | Menu-tracking 30 Hz `.common` timer replaces stalled monitors | L1, L2 | §3.3, §4 | Not run |
| 36 | DD-931 | Shared edges: wall / shared split, slow dwell, crossing guard, Modifier option, topology recompute | L1, L2 | §3.2, §4 | Not run (E2E x-11 deferred: one display) |
| 37 | DD-933 | Hidden or faded: ignores mouse events; shown: hit test nil outside tiles | L1, E2E | §3.4, x-08 | Not run |
| 38 | DD-933 | Click 4 pt outside the container reaches the window underneath | E2E | x-08 (a) | Not run |
| 39 | DD-961 | Pinned app tiles: click launches or activates; icons at 256 pt nominal | L1, E2E | §3.7, x-07 | Not run |
| 40 | DD-962 | Running dot, frontmost highlight, hidden dimmed, update ≤ 100 ms | L1, E2E | §3.7, x-14 | Not run |
| 41 | DD-964 (basic) | Folder tile opens Finder or a stack list toward the screen centre | L1, E2E | §3.7, x-15 | Not run |
| 42 | DD-975 | ⌘-drag always reorders; plain drag only when enabled; insertion follows the pointer; persisted at once | L1, E2E | §3.7, x-09 | Not run |
| 43 | DD-975 | Drop outside the dock removes the tile after confirmation | L1, E2E | §3.7, x-09 variant | Not run |
| 44 | DD-801 (minimal) | Status item per `docs/plan.md` T18 (Show/Hide Edge Dock, Edge ▸, Mode ▸, Keep Dock Open, Settings…, Quit dedock); agent app with no Dock icon | E2E | x-00, x-13 | Not run |
| 45 | DD-802 (Edge Dock pane) | Pane exposes cards, edge, mode, delays, trigger, alignment, inset, size, drag to rearrange, shared-edge policy | E2E | x-13 | Not run |
| 46 | SettingsStore | Round-trip, defaults, clamping, unknown keys, v0 → v1 migration, corrupt-file recovery, atomic write | L1 | §3.6 | Not run |
| 47 | NFR-1 | Idle CPU < 0.5 % over 60 s; no timer > 1 Hz | L5 | §6 | Not run |
| 48 | NFR-2 | RSS ≤ 120 MB with one Edge Dock; 0 leaks after 100 cycles | L5 | §6 | Not run |
| 49 | NFR-4 | Dwell → reveal start ≤ show delay + 16 ms (p95, 50 trials) | L5 | §6 | Not run |
| 50 | Perf | Pointer sample ≤ 20 µs p99; cold launch → armed ≤ 400 ms; 0 dropped frames at 60 Hz | L5 | §6 | Not run |
| 51 | Visual | Placement, sizing, distinctness table signed; `docs/design.md` pixel check within tolerance | L6 | §9 | Not run |
| 52 | Clean-room | PR lists "Sources consulted"; no DockDoor code or strings | review | `docs/organization.md` | Not run |

Rows added because `docs/plan.md` §4.1 puts them in M1 scope (beyond the brief's list):

| # | ID | Criterion | Layers | Test / scenario | Status |
|---|---|---|---|---|---|
| 53 | DD-1141 (beta) | Top edge: reveals below the menu bar, never over it; zone spans only the dock's length, excludes the notch and status items; with an auto-hiding menu bar only ⌥ reveals | L1, E2E | §3.2 top rows, x-18 | Not run |
| 54 | DD-941 (partial) | Dock on the main display, falls back to the built-in display when it is disconnected | L2 | §4 "Display removed while shown" | Not run |
| 55 | DD-991 / DD-992 (partial) | Native Dock prefs read only, never written; change picked up within 1 s; bottom dock sits above a visible native Dock with its span excluded | L1, L2, E2E | §3.2 bottom rows, REG-006, x-18 | Not run |
| 56 | DD-978 (basic) | Basic appearance renders the `docs/design.md` style in light and dark, with its Reduce Transparency solid form | L6 | §9.3 | Not run |
| 57 | DD-814 (subset) | Edge trace logs every transition with monotonic time, position, zone and inhibitors; no window titles | L2, E2E | LOG checks in §7 | Not run |

M1 is done when rows 1–57 are Pass, Waived with user approval, or Deferred with a reason (the visual parts of rows 11, 51 and 56 wait for `docs/design.md` §7; row 36's E2E waits for a second display).

---

## 12. Later pillars (outline)

| Area | Extra checks beyond the layers above |
|---|---|
| Native-Dock previews, switcher, ⌘Tab (Pillar A) | Needs Accessibility and Screen Recording, so a stable self-signed signing identity first (`docs/status.md`). Live side-by-side with DockDoor 1.40.7: open delay (0.2 s, measured 0.225 s), panel in (alpha cut + 7 pt / 0.175 s), fade-out (CA default curve), explicit-hide cut, against the clips in `dockdoor/recordings/` and `research/animation-dumps/dockdoor-app-measurements.md`. DockDoor regression set REG-012. |
| Edge Dock previews (DD-967) | Preview coupling invariant: the dock never hides while the panel's alpha > 0; T14 dwell counted from the end of the reveal. |
| Widgets (Pillar C) | 0 pull fetches while hidden; network gate denies by default (stub `URLProtocol`). |
