# dedock status log

Newest entry first. Each entry: done, in progress, next, blockers and notes, then the feature table.

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
