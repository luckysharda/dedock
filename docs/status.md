# dedock status log

Newest entry first. Each entry: done, in progress, next, blockers and notes, then the feature table.

---

## 2026-10-16, second update

### Done: follow-up stack merged

| PR | Content | Merged |
|---|---|---|
| #20 | Behaviour follow-ups: live status items, full-screen flag per display, re-hold on a moving reading, stricter drop-to-pin, cancel reorder on relayout (REG-044…048); REG-021/023 guards that can fail | `fbd56bc` |
| #21 | Review follow-ups (REG-031…038), debug-only E2E command channel, `Scripts/check-deps.sh` | `18d116b` |
| #22 | E2E harness: re-baseline from `82d2d69`, x-00 prompts by window id, REG-055 refuses while OS pointer sharing is on, C7 cell edge | `d87917d` |
| #23 | REG-057…060: launch notices are non-modal panels that never take key focus, read-only notice, capped re-holds, first sync `reason=launch`, check-deps fails closed | `d505f07` |
| #24 | REG-056: the dock window is a named floating window, not a system dialog | `00a5fe3` |
| #25 | `design.md` §5.5 names in UI text ("Dedock", "Edge Dock", "the Dock") | `7cecb2c` |
| #26 | REG-061: a tile's accessibility element covers its whole cell | `ba29394` |
| #28 | E2E harness: paired GEOM snapshots, REG-061 gates, C8/C9 Settings rows, `axpress` (own windows only, real lock), REG-062 row | `7bd6f68` |
| #19 | DD-934 pointer-sharing edges as an open item | `9051948` |

### Candidate cards

| Candidate | Covers | Result |
|---|---|---|
| `af3a80e` | #20 + #21 | 21/21 scenarios, 55/55 checks; 2 drift warnings accepted (idle RSS: the baseline value was the outlier; first launch after a rebuild, reported, not gated) |
| `a726ee1` | #23 + #24 | 21/21, 63/65: no reveal while the recovery alert was up (app: `runModal`, fixed by the non-modal notice); C1 R 1 pt (harness: unpaired snapshot, fixed in #28) |
| `7690688` | #23 + #26 + #27 | 21/21, 75/79: REG-057, REG-061, REG-062 and C9 pass; 4 C8 FAILs hold #27 (REG-063, REG-064) |

### Open before M1 sign-off

| Item | Owner |
|---|---|
| #27 Settings: numeric fields beside sliders have no AX name (REG-063); opening Settings latches an explicit reveal, so closing it never hides the dock (REG-064); then a short C8 card | implementer, E2E lane |
| Bottom and top edges on the E2E card: M1 closes only when all four edges work (S-5) | E2E lane, implementer |
| AX hit test honours the click-through gate outside the capsule (#15 review) | implementer |
| Debug channel scoping: `notify` sends a target pid and needs the real lock; the app ignores commands for another pid (#28 review) | E2E lane, implementer |
| "The notice does not take focus" reads the system-wide focused element, not the frontmost app; REG-062's zone thickness expectation comes from the native Dock's edge (#28 review) | E2E lane |
| DD-934 pointer-sharing edges: (a) leave, (b) per-edge setting (proposed), (c) detect | owner |

Done from the first 2026-10-16 list: x-00 by window id and the listener `ready` line (#22), the C3 lower bound (superseded by the REG-061 whole-cell gate, #28), the `tile.reorderCancelled` emitter (#20), the `openSettings` debug command (#21).

### Watch

| Item | Note |
|---|---|
| Idle RSS ≈ 90 MB against the 120 MB budget (NFR-2) | before M3 previews, gate on `phys_footprint` (34 MB) next to RSS; RSS counts shared framework pages |
| Settings nudges a side dock by about 1 pt (the native Dock's reserved area changes when Dedock becomes a regular app) | accepted for M1; relayout hysteresis in M2 (`design.md` §4.3) |

### Design rules added (`design.md`)

§2.2 the Settings hold lasts only while Settings is open; §2.3a no modal sessions while docks are live; §4.3 relayout hysteresis for side docks (M2); §6 accessibility frames equal click targets, every control is named.

---

## 2026-10-16

### Done: M1 candidate stack merged

| PR | Content | Merged |
|---|---|---|
| #16 | No `<private>` suffix on debug lines (REG-043) | `d499bc8` |
| #15 | Tile accessibility: tiles are AX buttons (REG-040); point AX hit tests reach the tile buttons, not the window (REG-054) | `4786791` |
| #11 | E1 Capsule in Dark Glass | `4344b90` |
| #13 | Edge Dock behaviour (full-screen dwell, top-edge exclusions, reorder, drop to pin) | `a0d0c8d` |
| #18 | E2E harness follow-ups: tool-health ok-codes and `--retool` (REG-052), self-test isolation (REG-053), C3 inside-and-centred, x-00 new prompts only, `axprobe at` parent chain | `b67818a` |

`develop` = `b67818a`. After #13 the tree equals the audited candidate `82d2d69` plus #12.

### M1 candidate result (`82d2d69`, both side edges)

| Result | Detail |
|---|---|
| Scenarios | 21/21 PASS, 0 VOID |
| Checks | 52/52; 2 SKIP (cua C8, needs the `openSettings` debug command) |
| Tool health | OK |
| Baseline | the owner approved re-baselining from this run (E2E lane's follow-up branch) |

The earlier `db65db3` run's single VOID (a pointer move during x-06) was traced to the system's pointer-sharing feature answering the harness's synthetic edge pushes (harness REG-055). The product question it raises is open as DD-934 (#19).

### Open before M1 sign-off

| Item | Owner |
|---|---|
| x-00 counts a permission prompt as new by window id (snapshot before launch), not by the start time of its host process: the start-time rule can fail open (#18 review) | E2E lane, **required** |
| REG-051 self-test listener check also requires the listener's `ready` line | E2E lane |
| C3: lower bound on the AX frame size (≥ icon size − 2 pt); C7: one more probe point at the tile cell edge | E2E lane |
| `tile.reorderCancelled` (contract) has no emitter yet: lands with the #13 follow-up "cancel reorder on relayout" | implementer |
| `openSettings` debug command (cua C8 SKIP) | implementer |
| AX hit test honours the click-through gate outside the capsule (#15 review) | implementer |
| DD-934 pointer-sharing edges: (a) leave, (b) per-edge setting (proposed), (c) detect; owner decides (#19) | owner |

---

## 2026-10-15

### Done

| Item | Detail |
|---|---|
| Repo | `$DEDOCK_HOME/Dedock app`, initial commit `46b7af2` (`README.md`, `.gitignore` ignoring `.build/`, `.swiftpm/`, `build/`, `.worktrees/`, Xcode user data) |
| GitHub | private repo `luckysharda/dedock` (`origin`) |
| Branches | `main`, `staging`, `develop`, all pushed to `origin` |
| Worktree | `.worktrees/edge-dock-reveal` on `feature/edge-dock-reveal`, branched from `develop` |
| Docs drafted (all untracked, not committed) | `docs/architecture.md` (modules, layers, folder layout, Edge Dock subsystem, persistence), `docs/plan.md` (master plan: decisions D-1…D-12, gap analysis, milestones M1–M18, per-feature process, M1 tasks T0–T23), `docs/design.md` (skeleton: behaviour, `dd.motion.*` tokens, layout grammar, component inventory; visual direction pending), `docs/evaluation.md` (layers, E2E scripts, perf, visual and motion methods, M1 acceptance list), `docs/organization.md` (layout, branches, PRs, agent lanes, desktop lock, build commands), this file |

### M1 E2E progress (left edge, build `7e7ae7e`, placeholder visuals)

| Result | Scenarios |
|---|---|
| Passed | x-00, x-01, x-02, x-03, x-04, x-05a, x-06 (20 rapid crossings, non-vacuous), REG-006; idle CPU 0.017 %, RSS 34 MB (budget 0.5 %) |
| Open | x-05b; x-07 / x-08 (need the owner present to approve computer use); every right-edge scenario; E1 Capsule visuals after the implementer's capsule fix |

### Merged and in review (2026-10-15, late)

| PR | Content | State |
|---|---|---|
| #7 | M1 Edge Dock reveal (placeholder visuals); REG-027/028/029/039 | merged `7a160cc`; `regress.sh` 21/21 |
| #9 | Regression policy + CI regression step (macOS + Linux) | merged `52930e6`; both steps ran the REG suites |
| #10 | Release log privacy (REG-030) | merged `ced2536` |
| #14 | Architecture reconcile, check-deps.sh, branch kinds | merged `f407038` |
| #11 | E1 Capsule in Dark Glass (`design.md` §7.1) | merged `4344b90` (2026-10-16); shown to the owner live on 2026-10-15 (no feedback) |
| #12 | `test/e2e-harness` (harness + `regress.sh`); fail-closed REG-049, teardown REG-050, real-lock rule REG-051 | merged `f6f1d02` |
| #13 | Edge Dock behaviour (full-screen dwell, top-edge status-item exclusion, ⌘-drag reorder, drop to pin, REG-013…026) | merged `a0d0c8d` (2026-10-16); follow-ups below |
| #15 | Tile accessibility (REG-040; REG-054 hit test added 2026-10-16) | merged `4786791` (2026-10-16); live cua C2/C3/C7 pass |
| #16 | No `<private>` suffix on debug lines (REG-043) | merged `d499bc8` (2026-10-16) |

Merge order for the candidate stack: #16 → #15 → #11 → #13 (then #12). Done; see 2026-10-16.

### Deferred or routed (2026-10-15)

| Item | Decision |
|---|---|
| Edit-mode badges (`design.md` §7.1) | deferred to M9 (DD-976) |
| `dd.dock.style` setting; label colours re-applied on appearance change | implementer's review-followups PR |
| `openSettings` debug command (unblocks cua C8, now SKIP) | implementer's review-followups PR |
| Drag-out-to-remove (plan T15(3)) | deferred; #13 cancels instead |
| #13 follow-ups: REG-021 and REG-023 rewritten to fail with the fix reverted; status-item exclusion refresh; full-screen flag on display change; probe re-check; stricter drop filter; cancel reorder on relayout | implementer's follow-ups |
| Mid-slide relayout continues smoothly instead of snapping (DD-928) | implementer's follow-ups |

### Decisions taken today (cross-session)

| # | Decision | By |
|---|---|---|
| S-1 | Sessions: e9 planner, e7 implementer, f1 E2E/UI testing, b6 orchestrator (`organization.md` §6.0) | user |
| S-2 | Timing defaults: `ux-patterns.md` T1–T9 / `system-design.md` §5.1 win over `features.md` (120 ms dwell, 400 ms fullscreen dwell, 24/8 pt corners, 3 pt zone, span + 40 pt, 16 pt hysteresis, 400 ms hide delay) | planner |
| S-3 | Placeholder-visual Edge Dock build allowed before the design pick; every visual value in `DesignSystem` tokens marked PLACEHOLDER; motion timings are final | planner + orchestrator |
| S-4 | v0 persistence = `layout.json` only; `DEDOCK_E2E_HOME` = `DEDOCK_DATA_DIR`; E2E hooks debug-bundle only (`evaluation.md` §7.5) | planner |
| S-5 | M1 edge order: left/right (E2E gate) → bottom → top below the menu bar; M1 closes when all four work | planner |
| S-6 | E2E pointer driver = `Scripts/e2e/pointer.swift`, standalone, owned by the E2E lane; recordings use `-pix_fmt yuv444p`, colour checks use PNGs | planner |
| S-7 | Desktop lock = `$DEDOCK_HOME/.locks/desktop.lock` (`organization.md` §6.1) | orchestrator |
| S-8 | CI/CD + Docker: `docs/ci-cd.md` (on branch `planning`). Repo goes public only once CI runs, otherwise stays private; orchestrator performs the flip | user |
| S-10 | Testing may quit CoolDock and DockDoor before edge tests (inside the desktop lock; the owner relaunches them). No observation or timing of CoolDock; comparisons use public reference screenshots only | user |
| S-11 | Design: the look follows the references (revised D-6). Pick **A2 Frosted + E1 Capsule** (`design.md` §7) | user |
| S-12 | Repo public since CI is green (PR #1 merged as 7312bb6) | user + orchestrator |
| S-13 | Implementer decisions accepted: reversal region = zone or capsule + 16 pt; explicit reveal holds until first visit; timers `tolerance: .zero`; CLT test flags (`architecture.md` §6.5, §11) | planner |
| S-14 | Cold launch gate = first launch after login, binary not rebuilt; post-rebuild launch reported only (`evaluation.md` §6) | planner |
| S-9 | Disk full (≈0.4 GB free) after a Docker pull; Docker data purge pending with the user | user |

### In progress

| Item | State |
|---|---|
| Design gate for M1 (`docs/plan.md` T0) | **Awaiting the user's pick** of one app direction (A1 Folio, A2 Signal, A3 Dusk, A4 Instrument) and one Edge Dock sense (E1 Drawer, E2 Spine, E3 Rail, E4 Console), listed in `docs/design.md` §7. The pick fills `docs/design.md` §7 with the tokens dedock is measured against pixel for pixel. The look must differ from both DockDoor and CoolDock; behaviour matches them. |
| Package skeleton (`docs/plan.md` T1, T3, T4, T6) | WIP commit `bb9faf3` (18:20) on `feature/edge-dock-reveal`: `Package.swift` (`DedockCore`, `EdgeDock`, `Dedock` executable, `DedockCoreTests`, `EdgeDockTests`), sources under `Sources/DedockCore`, `Sources/EdgeDock/Trigger`, `Sources/EdgeDock/Reveal`, `Sources/Dedock`, and first swift-testing suites. Another lane is restructuring `Sources/DedockCore` (uncommitted). Not built or run by this lane, so nothing counts as implemented yet. |

### Next: implement M1 (Edge Dock reveal, `docs/plan.md` §6)

1. Finish the scaffold (T1, T2): all M1 modules (`DedockCore`, `DesignSystem`, `Diagnostics`, `DisplayTopology`, `SettingsStore`, `EventTapKit`, `EdgeDock`, `SettingsUI`; `docs/architecture.md` §2), test targets and the `DedockTestSupport` fakes target, `Scripts/make-app.sh`, `Scripts/run.sh`.
2. Pure logic first, test-first: trigger geometry for all edges, reveal state machine with `TestClock`, reversal planner, hit testing, layout grammar, settings store and migration (`docs/evaluation.md` §3).
3. App layer: pointer hub on global/local `NSEvent` monitors, the parked non-activating panel, content-layer animation with the `dd.motion.edge.*` tokens, click-through gate, app and folder tiles, running indicators, ⌘-drag reorder.
4. Minimal menu-bar item and the Edge Dock settings pane with the scenario cards subset.
5. E2E harness (`Scripts/e2e/pointer.swift`, `Scripts/measure-idle.sh`, `Scripts/measure-pixels.swift`, `Tests/E2E/edge-dock-reveal.md`), plus the debug hooks the checks need (`docs/evaluation.md` §7.3, each tied to a T-task), then the full M1 acceptance list (`docs/evaluation.md` §11) on left and right.
6. `docs/compare/edge-dock-reveal.md`, then PR `feature/edge-dock-reveal` → `develop` with the scorecard (T23).

Visual work (panel look, tiles, indicator, settings look) waits for the design pick; pure logic (T3–T6, T12, T16) does not.

### Blockers and notes

| # | Note | Effect |
|---|---|---|
| 1 | **No Xcode**, only Command Line Tools with Swift 6.4 | SwiftPM-first repo. swift-testing works; XCTest, XCUITest, `xcodebuild` and Instruments (`xctrace`) do not. Perf uses CLI tools instead (`docs/evaluation.md` §6). An `.xcodeproj` can be added later. |
| 2 | **No code-signing identity** | Ad-hoc signing is fine for the Edge Dock (global `NSEvent` monitors need no permission, `dedock-plan/system-design.md` §5.3). A stable self-signed identity is **required before** Accessibility and Screen Recording features (previews, switcher), because TCC grants follow the signature. |
| 3 | One display, 1920 × 1080 at 60 Hz | Multi-display shared-edge E2E (DD-931) and 120 Hz motion checks cannot run here; covered by fakes until a second display is attached. |
| 4 | Live observation of CoolDock | Closed by the owner (S-10): no observation or timing of CoolDock; comparisons use public reference screenshots only. Testing may quit CoolDock and DockDoor before edge tests, inside the desktop lock; the owner relaunches them. |
| 5 | DockDoor 1.40.7 installed, not running | Available for live comparison and coexistence checks. Launch it only inside the desktop lock. |
| 6 | Native Dock at the bottom, auto-hide off | Left and right docks have no native-Dock conflict. A bottom Edge Dock needs the native-Dock footprint rules (DD-991, DD-992). |
| 7 | Milestone naming | This repo's M1 (Edge Dock reveal) is a subset of AP-M3 "Edge Dock core"; the pack's own M1 (AP-M1) is the window engine (`dedock-plan/adoption-plan.md` §10.1; numbering in `docs/plan.md` §4.1). |
| 8 | Top edge | The pack schedules it at P2 (`dedock-plan/features.md` DD-1141). `docs/plan.md` D-11 pulls "Reveal below the menu bar" into M1 as an optional, beta-labelled edge. |

**Plan conflicts found while writing the evaluation** (the value in bold is what dedock uses; the plan should be corrected later):

| Topic | Plan says | dedock uses |
|---|---|---|
| Show dwell | 0.15 s (`features.md` defaults, DD-921) vs 120 ms (`system-design.md` §5.1, `ux-patterns.md` T3) | **120 ms** |
| Full-screen dwell | 0.75 s (DD-924) vs 400 ms (`system-design.md` §5.1, T4) | **400 ms** |
| Corner exclusion | 10 pt (`features.md` defaults, DD-923) vs 24 pt / 8 pt (`system-design.md` §5.1, T2) | **24 pt / 8 pt** |
| Idle CPU | < 0.5 % (NFR-1) vs < 0.3 % (`system-design.md` §9) | **gate 0.5 %**, target 0.3 % |
| DD-928 "no > 8 pt jump" (`docs/plan.md` T8 criterion 4 now states the three checks) | literal reading fails a clean reveal (frame steps up to 16 pt for the spring, 24.6 pt for the bezier form) | **8 pt applied to discontinuities at reversals** (`docs/evaluation.md` §3.3) |
| Running-dot side | inner side (DD-903) vs screen-edge side, "make it a setting" (`design-system.md` §9.6) | **inner side**, setting later (`docs/design.md` §8 row 1) |
| Tile thickness | 56 pt (`features.md` defaults, DD-926) vs `t` 62 inside T 76 at M (`design-system.md` §9.6) | **t = 56 pt** (`docs/design.md` §4.1); padding, gap and radii come with the design pick |
| Reorder motion | 0.2 s spring (DD-975, `docs/plan.md` §6 fixed values) vs `.spring(duration: 0.30, bounce: 0)` (`docs/design.md` §3.2 `dd.motion.reorder`) | **open**: settle before T15 is built |
| Reference-pack path | brief and docs disagreed on the relative path | `<pack>` placeholder (`organization.md` §1); its location is machine-specific |
| Stray file | `preflight.swift` (a TCC probe) sat untracked at the worktree root | **resolved**: no longer present |

**Doc consistency pass (2026-10-15).** Contradictions between the six `docs/` files were resolved in place. Picks made where the docs disagreed (confirm or reverse):

| Topic | Was | Now |
|---|---|---|
| Trigger thickness range | 1–8 pt (`docs/architecture.md`, `docs/design.md`) vs 1–20 pt (`docs/plan.md` D-12, `docs/evaluation.md`) | **1–20 pt** |
| Hide hysteresis range | 0–64 pt (`docs/architecture.md`) vs 0–40 pt (`docs/plan.md` §6) | **0–40 pt** |
| Folder tile in M1 | Finder only (`docs/architecture.md`) vs stack list or Finder (`docs/plan.md` T14) | **stack list toward the centre, Finder per setting; `popoverOpen` active in M1** |
| Persistence in M1 | `UserDefaults` keys + `layout.json` (`docs/plan.md` T16) vs `layout.json` only (`docs/architecture.md` §7) | **`layout.json` only** |
| Separators (DD-966) | M1 (`docs/architecture.md`) vs M2 (`docs/plan.md`) | **M2** |
| Overflow in M1 | silent in `docs/plan.md` T14 | **shrink tiles to 60 % of `t`, then clip** (`docs/architecture.md` §6.8, `docs/evaluation.md` §3.5); scrolling stays DD-977 (M9) |
| Module set | `DisplayTopology` only in `docs/architecture.md` | **kept**; added to `docs/plan.md`, `docs/organization.md` |
| Status menu | four different item lists | **`docs/plan.md` T18**; ⌃⌥⌘E, Reset Layout (M8) and Edit Dock… (M9) later |

### Feature status

"Implementation" is the code state; "Stage" is where the feature is in the process. Nothing is implemented yet.

**M1 Edge Dock reveal** (IDs from `dedock-plan/features.md`; scope from the brief plus `docs/plan.md` §4.1)

| ID | Feature | Implementation | Stage |
|---|---|---|---|
| DD-901 | Companion Edge Dock (non-activating, coexists with the native Dock) | Missing | In design |
| DD-902 | Edges: left / right default; bottom and top-below-menu-bar optional | Missing | In design |
| DD-903 | Vertical layout grammar | Missing | In design |
| DD-910 | Scenario cards (subset, `docs/plan.md` T17: Reveal on Left, Reveal on Right, Reveal at Bottom (beta), Pinned, Reveal at Top (beta)) | Missing | In design |
| DD-911 | Pinned mode | Missing | In design |
| DD-912 | Reveal mode and state machine | Missing | In design |
| DD-921 | Show delay | Missing | In design |
| DD-922 | Hide delay | Missing | In design |
| DD-923 | Trigger zone size and span | Missing | In design |
| DD-924 | Full-screen reveal delay | Missing | In design |
| DD-925 | Alignment and distance from edge | Missing | In design |
| DD-926 | Dock size | Missing | In design |
| DD-927 | Slide motion | Missing | In design |
| DD-928 | Reverse in place, idempotent state | Missing | In design |
| DD-929 | Hold-open inhibitors | Missing | In design |
| DD-931 | Shared display edges | Missing | In design |
| DD-933 | Click-through gate | Missing | In design |
| DD-961 | Pinned app tiles | Missing | In design |
| DD-962 | Running indicators (Dot style) | Missing | In design |
| DD-964 | Folder tiles (basic) | Missing | In design |
| DD-975 | Reorder by drag | Missing | In design |
| DD-801 | Menu-bar item (minimal) | Missing | In design |
| DD-802 | Settings window with the Edge Dock pane only | Missing | In design |
| — | SettingsStore (schema v1, migration harness) | Missing | In design |
| DD-978 | Edge Dock appearance (basic, from the design pick) | Missing | Design picked (A2 + E1); placeholder visuals in the build |
| DD-1141 | Top edge, Reveal below the menu bar (beta; `docs/plan.md` D-11) | Missing | In design |
| DD-941, DD-991, DD-992 | Main display with built-in fallback; native Dock read-only awareness; bottom dock above a visible native Dock (partial) | Missing | In design |
| DD-814 | Edge trace (subset) | Missing | In design |

**Later** (not started)

| Area | IDs | Implementation | Stage |
|---|---|---|---|
| Rest of Pillar B (Edge Dock) | DD-904, DD-905, DD-913, DD-914, DD-930, DD-932, DD-941 (full), DD-942–DD-947, DD-951–DD-958, DD-963, DD-964 (gallery), DD-965–DD-974, DD-976, DD-977, DD-978 (full), DD-979–DD-984, DD-991 (full), DD-992 (full), DD-993–DD-995 | Missing | Not started |
| Native-Dock hover previews | DD-101–DD-118 | Missing | Not started (needs signing identity) |
| Window switcher, ⌘Tab | DD-201–DD-215, DD-301–DD-306 | Missing | Not started (needs signing identity) |
| Window actions | DD-401–DD-407 | Missing | Not started |
| Widgets runtime, gestures, keybinds, filters, compact mode, appearance | DD-501–DD-511, DD-601–DD-669, DD-701–DD-712 | Missing | Not started |
| Rest of the app shell | DD-801 and DD-802 (full), DD-803–DD-813, DD-814 (full), DD-815–DD-817 | Missing | Not started |
| Pillar C (CoolDock parity) | DD-1001–DD-1149 (DD-1141 top edge is in M1) | Missing | Not started |
| Pillar D (DockDoor Pro parity) | DD-1201–DD-1389 | Missing | Not started |
