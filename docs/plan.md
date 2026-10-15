# dedock master plan

Status: draft 1, 2026-10-15. Branch `feature/edge-dock-reveal`.

**Citations.** Paths in backticks are relative to the read-only reference pack at `<pack>/`, unless they start with `docs/`, `Sources/`, `Tests/`, `Scripts/` or `Tools/`, which are paths in this repo. "PRD" means `dedock-plan/features.md`. Milestones `M1`…`M18` are this plan's own numbering. Where the reference pack's roadmap (`dedock-plan/adoption-plan.md` §10, its M0–M14) is meant, it is written "AP-M3" and so on.

---

## 1. Goal and decisions so far

**Goal.** Build dedock, a native macOS menu-bar app with two parts:

- **Edge Dock** (CoolDock-class): a second dock of apps, folders and live widget tiles. It slides out when the pointer touches a screen edge. Left and right edges are the default, bottom is supported, and top (below the menu bar) is optional. It includes CoolDock's reveal/hide behaviour, layouts, profiles and widgets.
- **Window previews** (DockDoor-class): hover an app in the native Dock or the Edge Dock to see its windows with actions. Plus a window switcher (⌥Tab), ⌘Tab previews and window actions.

The scope is the union of DockDoor Free, DockDoor Pro and CoolDock. Every feature of the three is either scheduled or deferred with a written reason (union guarantee, `dedock-plan/adoption-plan.md` §13).

| # | Decision | Detail | Source |
|---|---|---|---|
| D-1 | **Everything lives in `Dedock app/`** | `$DEDOCK_HOME/Dedock app` is the repo root. All code, scripts, docs and build output go inside it. The reference pack next to it stays read-only and is never copied into the repo. | user request |
| D-2 | Repo and branches | Private GitHub `luckysharda/dedock`. `main` = released, `staging` = release candidates, `develop` = integration. | repo `README.md` |
| D-3 | One worktree per feature | `Dedock app/.worktrees/<feature>` on branch `feature/<feature>`, created off `develop`, merged back to `develop` by PR. `.worktrees/` is git-ignored. First worktree: `.worktrees/edge-dock-reveal`. | user |
| D-4 | **SwiftPM first** | Xcode is not installed. Only Command Line Tools with Swift 6.4 are available. `swift build` and `swift test` (swift-testing) work. XCTest, XCUITest, `xcodebuild`, `actool` and Instruments do not. So: a root `Package.swift` with one library per module (the DedockKit set from `dedock-plan/architecture.md` §4 and §12) plus a `Dedock` executable target. `Scripts/make-app.sh` assembles `build/Dedock.app` (`LSUIElement = YES`, bundle id `app.dedock.Dedock.debug`) and signs it ad hoc. An `.xcodeproj` can be added later, pointing at the same package. | user, toolchain check 2026-10-15 |
| D-5 | Signing | Ad-hoc signing is enough for the Edge Dock: edge sensing uses `NSEvent` global monitors, which need no permission (`dedock-plan/system-design.md` §5.3). A stable self-signed identity is needed before any Accessibility or Screen Recording feature (M3), because TCC grants are keyed to the code signature. | `dedock-plan/architecture.md` §14 "TCC caveat" |
| D-6 | **Behaviour and look = references** (revised 2026-10-15) | Features, behaviour and visual design follow CoolDock (Edge Dock) and DockDoor (previews, switcher, settings). The user picked **A2 Frosted + E1 Capsule** from the reference-based board (option 1 of each section was the exact reference; 2–4 were the references' own style options). Tokens in `docs/design.md` §7. Motion timing stays fixed by `dedock-inputs/animation-spec.md`. The earlier "visuals must be new" rule is withdrawn. Clean-room still applies: values from screenshots and measurements, no copied code or assets. | user decision |
| D-7 | Clean room | DockDoor is GPL-3.0. dedock reproduces features and behaviour only, never code, strings or assets. CoolDock and DockDoor Pro are closed source; only their public material (screenshots, docs, release notes) is used. Rules in `dedock-plan/adoption-plan.md` §7. | `README.md` "Licensing" |
| D-8 | **Notchy is out of scope** | Nothing from `notchy/` or `research/notchy-*` is read, cited or used. | user decision |
| D-9 | Platform | Swift 6 strict concurrency, SwiftUI hosted in AppKit, macOS 14+, Liquid Glass on macOS 26+ with a fallback material, non-sandboxed, Developer ID + notarization later (needs a paid account), Sparkle 2. | `dedock-plan/adoption-plan.md` §2 |
| D-10 | First feature | Edge Dock reveal on the left and right edges (M1, §6). Previews come later. | user |
| D-11 | Top edge pulled forward | The PRD schedules the top edge (DD-1141) as P2 in AP-M10. By user decision, M1 adds **Reveal below the menu bar** on the top edge as an optional, beta-labelled edge. Pinned and Floating on top follow in M8. | user; PRD DD-1141 |
| D-12 | PRD timing drift resolved for M1 | The PRD and `dedock-plan/ux-patterns.md` §3.1 disagree on four defaults. M1 uses the `ux-patterns.md` / `system-design.md` §5.1 values, because `animation-spec.md` §4's timeline and the runtime algorithm both use them: show delay **120 ms** (PRD DD-921 says 0.15 s), corner exclusion **24 pt, 8 pt when that Hot Corner is off** (PRD DD-923 says 10 pt), full-screen show delay **400 ms** (PRD DD-924 says 0.75 s), spring-loaded folder **0.8 s** (PRD DD-968 says 0.6 s; not in M1). Trigger thickness range follows the PRD (1–20 pt). Recorded in `docs/design.md` §2.1 and §8. | `dedock-plan/ux-patterns.md` §3.1 "PRD drift" |

### 1.1 Repo layout (target)

`dedock-plan/architecture.md` §12 assumes Xcode with the package in `Packages/DedockKit`. Because of D-4 the package moves to the repo root. Module details, layers and per-module folders are in `docs/architecture.md` §2–§4. (A first skeleton, WIP commit `bb9faf3` on `feature/edge-dock-reveal`, has a subset of targets: DedockCore, EdgeDock and the Dedock executable; T1 adds the rest.)

```text
Dedock app/                      repo root (D-1)
├── Package.swift                swift-tools-version 6.x, macOS 14, Swift 6 language mode
├── Support/Info.plist           template filled by make-app.sh
├── Sources/
│   ├── DedockCore/              IDs, geometry, ScreenEdge, interval maths, clock protocol (no AppKit)
│   ├── DesignSystem/            panel base, material, tokens from docs/design.md, motion tokens
│   ├── Diagnostics/             os.Logger categories, signposts, edge trace ring buffer
│   ├── DisplayTopology/         NSScreen → DisplayLayout, screen-change and wake observation
│   ├── SettingsStore/           typed model, layout.json schema + migrations
│   ├── EventTapKit/             PointerHub only in M1 (event taps come in M4)
│   ├── EdgeDock/                Trigger/, Reveal/, Panel/, Layout/, Displays/, NativeDock/, Tiles/, Drag/
│   ├── SettingsUI/              Settings window; Edge Dock pane in M1
│   └── Dedock/                  executable: composition root, status item, lifecycle
│   (later: PrivateBridges, Permissions, WindowKit, DockObserver, PreviewUI, Switcher,
│    DedockWidgets, DockLocking, Automation, Updates, NetworkGate, ... per dedock-plan/architecture.md §4, §4.1)
├── Tests/
│   ├── <Module>Tests/           swift-testing suites, one per library
│   ├── DedockTestSupport/       shared fakes target (TestClock, FakeScreenProvider, FakePointerHub, FakeWorkspace, ...)
│   └── E2E/<feature>.md         E2E scripts: one per acceptance criterion (process §5 step 8)
├── Scripts/
│   ├── make-app.sh              build/Dedock.app, Info.plist, iconutil icon, ad-hoc codesign
│   ├── run.sh                   make-app.sh, quit a running copy, run in the foreground
│   ├── check-deps.sh         module layering rules (docs/architecture.md §3)
│   ├── measure-idle.sh          idle CPU / RSS sampler (replaces XCTest metrics)
│   ├── measure-pixels.swift     pixel and edge measurement (docs/evaluation.md §8, §9)
│   └── tcc-reset.sh             from M3
├── Tools/
│   ├── (E2E driver lives in Scripts/e2e/pointer.swift, owned by the E2E lane)
│   └── FixtureHost/             from M3: opens N titled windows
├── docs/
│   ├── plan.md                  this file
│   ├── architecture.md  evaluation.md  organization.md  status.md
│   ├── design.md                design guide (skeleton; visual tokens filled at the M1 design gate)
│   ├── features/<feature>.md    behaviour spec + "Sources consulted" (process §5 step 2)
│   ├── evidence/<feature>/      cropped captures + measurement CSVs
│   ├── design/<feature>/        design-sense pages and loops
│   ├── compare/<feature>.md     side-by-side comparison vs reference
│   └── qa-matrix.md             manual matrix (displays, Dock positions, OS versions)
├── build/                       git-ignored output (Dedock.app)
└── .worktrees/                  git-ignored feature worktrees
```

---

## 2. Feature gap analysis

dedock has **zero features today**, so every row is `missing`. One row per feature family. The DD ids come from the PRD; the "Mx #" column is the row of the PRD's Feature-mix matrix that the family covers (rows 1–64), so both checks of the union guarantee can be traced. Priorities are the PRD's (P0 MVP, P1 v1.0, P2 v2+, P3 deferred with a reason). Where one family spans priorities, it is split into one row per priority. Sources: DD = DockDoor Free, Pro = DockDoor Pro, CD = CoolDock, new = none of them.

### 2.1 Pillar A: DockDoor parity

| DD id(s) | Feature | Source | Pri | dedock | Target | Mx # |
|---|---|---|---|---|---|---|
| DD-101–DD-104, DD-106–DD-108, DD-110 | Native-Dock hover previews: panel, which windows, sort, placement, timing and dismissal, Dock-state awareness, no system-Dock mutation, window buttons on cards | DD, Pro (sort, buttons), new (state, safety) | P0 | missing | M3 | 1 |
| DD-105, DD-109, DD-111–DD-113, DD-115 | Trigger mode, hover actions and large previews, header mass actions, card/panel layout, keyboard navigation, card context menu | DD, Pro (layout) | P1 | missing | M6 | 1 |
| DD-116, DD-117 | Dock icon click behaviours; quick quit and new window | DD, Pro | P1 | missing | M6 | 33 |
| DD-114, DD-118 | Drag and drop on cards; Space badges | DD | P2 | missing | M12 | 1 |
| DD-201–DD-204, DD-210, DD-213 | Window switcher (⌥Tab) core: behaviour, scope, ordering, keys inside, keyboard isolation | DD, Pro, new (isolation) | P0 | missing | M4 | 2 |
| DD-206–DD-209, DD-215 | Switcher placement, search, mouse selection, layout, alternate shortcut | DD, Pro (search) | P1 | missing | M6 | 2 |
| DD-205, DD-211, DD-214 | Group by app, pointer follows focus, full-screen exclusions | DD | P2 | missing | M12 | 2 |
| DD-212 | Trackpad swipe opens the switcher | DD | P2 | missing | M12 | 10 |
| DD-301–DD-304, DD-306 | ⌘Tab window overlay: keys, auto-select first window, scope, actions on the selection (no restart to toggle) | DD, Pro ("Glance") | P1 | missing | M6 | 3 |
| DD-305 | ⌘Tab appearance overrides | DD | P2 | missing | M12 | 3 |
| DD-401, DD-402 | Window action engine; focus a specific window | DD | P0 | missing | M3 | 4 |
| DD-403, DD-405, DD-407 | Snapping (halves, quarters, center, maximize); menu bar ▸ Window Actions; respect reserved edges | DD, new (reserved edges) | P1 | missing | M7 | 4, 19 |
| DD-404, DD-406 | Bring window to current Space; snapping shortcuts | DD, new | P2 | missing | M12 | 4 |
| DD-509 | Shared widget provider runtime (scaffold in M3, full in M9) | new | P0 | missing | M3 / M9 | 5 |
| DD-501, DD-502, DD-505–DD-507 | Widgets on Dock hover: media widget, calendar widget and selection, widget display mode | DD, CD, Pro | P1 | missing | M9 | 5, 7 |
| DD-503, DD-504 | Media widget scrolling; media extras (output picker etc.) | DD | P2 | missing | M12 | 5, 38 |
| DD-508 | Pin a widget to the screen | DD, Pro | P2 | missing | M12 | 8 |
| DD-510 | Lyrics and artwork lookups (opt-in, network) | DD, Pro | P2 | missing | M12 | 6 |
| DD-511 | Folder Pop (folder contents on Dock hover) | DD | P2 | missing | M12 | 9 |
| DD-601, DD-603, DD-604 | Card swipes, gesture sensitivity, middle-click on a card | DD | P1 | missing | M6 | 10 |
| DD-602, DD-605–DD-609 | Aero Shake, modifier-click, scroll on Dock icons, scroll on media icons, switcher swipes, title-bar scroll | DD | P2 | missing | M12 | 10 |
| DD-614, DD-615 | Switcher shortcut recorder; backward key | DD | P0 | missing | M4 | 11 |
| DD-613, DD-616, DD-617 | ⌘W/M/Q/H on the selection; selection key; layout-independent key labels | DD, new (labels) | P1 | missing | M6 | 11 |
| DD-618–DD-620 | Vim motions; pass ⌃+arrows; use the switcher for ⌘Tab | DD | P2 | missing | M12 | 11 |
| DD-636 | Built-in junk-window rules | DD | P0 | missing | M3 | 12 |
| DD-631–DD-633 | Hide apps; window-title filters; widget app filters | DD, Pro | P1 | missing | M6 | 12 |
| DD-634, DD-635 | Extra app folders; add an app by bundle | DD | P2 | missing | M12 | 12 |
| DD-651 | Text-list fallback without Screen Recording | DD | P0 | missing | M3 | 13 |
| DD-652 | Compact mode on demand | DD, Pro | P1 | missing | M6 | 13 |
| DD-653, DD-654 | Compact row style; grid/list toggle in the panel | DD | P2 | missing | M12 | 13 |
| DD-701, DD-704, DD-711 | Background material with OS fallback; Light/Dark/System; Reduce Motion and Reduce Transparency (visuals from `docs/design.md`) | DD, CD, Pro | P0 | missing | M2 (Edge Dock subset in M1) | 16 |
| DD-703, DD-708 | Thumbnail size; minimized/hidden card distinction | DD, Pro | P0 | missing | M3 | 16 |
| DD-702, DD-705, DD-706 | Material tuning; density and shape; selection highlight | DD | P1 | missing | M6 | 16 |
| DD-707, DD-709, DD-710, DD-712 | Title overflow; panel shadow; custom tint and gradient; per-surface overrides | DD | P2 | missing | M12 | 16 |
| DD-801 | Menu bar item (minimal in M1: Edge Dock controls, Settings, Quit; full in M2; Layout menu and Reset Layout in M8) | DD, CD, Pro | P0 | missing | M1 / M2 / M8 | 19 |
| DD-802 | Settings window (Edge Dock pane in M1; full shell in M2; panes appear as features ship) | DD, CD, Pro | P0 | missing | M1 / M2 | 18 |
| DD-805, DD-806, DD-807, DD-808 | Permissions with hot start; onboarding with scenario cards; health monitor and self-heal; launch at login | DD, CD, new | P0 | missing | M2 | 20 |
| DD-809 | Updates (Sparkle 2, stable/beta) | DD, CD, Pro | P0 | missing | M2 | 21 |
| DD-809 (update chip, progress) | Update chip in the Edge Dock with download progress | CD, Pro | P2 | missing | M13 | 21 |
| DD-815, DD-816 | Private-API isolation (capability table); privacy and network ledger | new, Pro (ledger) | P0 | missing | M2 | 23, 24 |
| DD-803 | Settings search | DD, Pro | P1 | missing | M7 | 18 |
| DD-810 | Backup, restore and reset | DD, CD gap, Pro | P1 | missing | M7 | 22 |
| DD-811, DD-812 | AppleScript for windows/previews and for the Edge Dock | DD, new, Pro | P1 | missing | M7 | 23 |
| DD-814 | Diagnostics export (edge trace subset in M1) | CD, Pro | P1 | missing | M1 (trace) / M7 | 24 |
| DD-804, DD-817 | Live preview mock in Settings; localization | DD | P2 | missing | M12 | 18 |
| DD-813 | Command-line tool | new | P2 | missing | M14 | 23 |
| no id (AP §6) | Dock Locking to one display | DD | deferred to v2 | missing | M12 | 14 |
| no id (AP §6) | Active-app indicator under the native Dock (Edge Dock indicator is DD-962) | DD | deferred to v2 | missing | M12 | 15 |
| no id (AP §6) | Live video previews (SCStream), off by default | DD | deferred to v2 | missing | M12 | 17 |
| no id (AP §6) | **Declined:** freemium upsell banners; onboarding confetti and sound; "Prevent dock from hiding during previews" toggle (mutates system auto-hide, DockDoor #1222); "Show preview above app labels" toggle (behaviour kept on, no toggle) | DD | not adopted | n/a | none | — |

### 2.2 Pillar B: Edge Dock

| DD id(s) | Feature | Source | Pri | dedock | Target | Mx # |
|---|---|---|---|---|---|---|
| DD-901 | Companion Edge Dock: non-activating panel, never moves the native Dock, works over full screen, never covers system overlays | CD, new, Pro | P0 | missing | M1 | 25, 63 |
| DD-902 | Left, right and bottom edges (top: DD-1141) | new | P0 | missing | M1 | 25 |
| DD-903 | Vertical layout grammar (thickness × length units, labels and indicators toward screen centre) | new | P0 | missing | M1 | 25 |
| DD-904 | Several docks at once (one per display × edge) | new | P1 | missing | M8 | 25 |
| DD-905 | Edge Bar style (thin edge-to-edge bar) | new, Pro | P2 | missing | M13 | 58 |
| DD-910 | Scenario cards (M1 subset: Reveal on Left, Reveal on Right, Reveal at Bottom (beta), Pinned, Reveal at Top (beta); Swap and Floating cards in M8) | CD | P0 | missing | M1 / M8 | 25 |
| DD-911, DD-912 | Pinned (Fixed) mode; Reveal mode with the reveal state machine | CD | P0 | missing | M1 | 25, 27 |
| DD-913, DD-914 | Swap with the native Dock (consented auto-hide snapshot/restore); Floating (horizontal/vertical, under the menu bar) | CD | P1 | missing | M8 | 25, 47 |
| DD-921–DD-923, DD-925–DD-929, DD-931, DD-933 | Show delay, hide delay, trigger zone size/span, alignment and distance, dock size, slide motion, reverse in place, hold-open inhibitors, shared display edges, click-through gate | CD, Pro, new | P0 | missing | M1 | 27 |
| DD-934 | Pointer-sharing edges: an edge that also hands the pointer to a nearby Mac or iPad (the system's pointer-sharing feature) must not lose the pointer to a reveal push, and a dock must not stay open while the pointer is on the other device. **Open (§7 question 6)** | new | P1 | missing | decide in M2; ship in M2 | 27, 29 |
| DD-924 | Full-screen reveal delay (pulled into M1 with a no-permission full-screen heuristic) | new | P1 | missing | M1 | 27 |
| DD-926 (widget spacing, presets) | Separate tile-gap control; Compact/Cozy/Roomy presets | CD, Pro | P1 | missing | M8 | 26 |
| DD-927 (speed) | Animation speed 1×–4× | Pro | P2 | missing | M13 | 27 |
| DD-930, DD-932 | Global show/hide shortcut (⌃⌥⌘E); reveal while dragging | CD, prior art | P1 | missing | M8 | 11, 27 |
| DD-941 | One display, falls back to the built-in display (M1: main display only) | CD | P0 | missing | M1 (partial) / M2 | 29 |
| DD-947 | Topology, Space and wake recovery | CD | P0 | missing | M2 | 29 |
| DD-942–DD-946 | Attached displays list; all displays; independent per display; display identity UI; per-display, per-edge profile binding | CD, new, Pro | P1 | missing | M8 | 29 |
| DD-951–DD-954, DD-956, DD-958 | Profiles: management, what a profile stores, hover tab strip, context-menu switch, keyboard switching, export/import | CD, Pro | P1 | missing | M10 | 30 |
| DD-955, DD-957 | Swipe to switch profile; automatic switching (AppSense-style rules) | CD, Pro, new | P2 | missing | M13 | 30 |
| DD-961, DD-962 (dot), DD-964 (basic), DD-975 | Pinned app tiles; running indicators; basic folder tiles (Finder or simple stack); reorder by drag | CD, DD, Pro | P0 | missing | M1 | 15, 31, 32 |
| DD-978 (basic) | Edge Dock material (the chosen design sense's surface; Reduce Transparency → solid) | CD, DD | P0 | missing | M1 | 26 |
| DD-966 | Separators and spacers | CD | P0 | missing | M2 | 31 |
| DD-967 | Window previews from Edge Dock tiles (hold the reveal) | DD, CD | P0 | missing | M3 | 1 |
| DD-963, DD-964 (gallery), DD-965, DD-968 | Running-apps section; folder gallery; app folders; drop onto tiles | CD, Pro | P1 | missing | M9 | 9, 31 |
| DD-971–DD-974 | Widget gallery; widget interaction model; core widget set; "Show when…" conditions | CD, DD | P1 | missing | M9 | 5, 7, 34, 35, 36, 39 |
| DD-976, DD-977, DD-978 (full), DD-980 | Edit mode; overflow (adapt size / scroll); full appearance options; import from the native Dock | CD, Pro, prior art | P1 | missing | M9 | 26, 32 |
| DD-962 (cards, counts), DD-969, DD-970, DD-979 | Card indicators and window counts; file shelf tile; notification badges; hover lift | CD, Pro, new | P2 | missing | M13 | 15, 31, 52, 54 |
| DD-981 | Hide during full screen | CD, Pro | P0 | missing | M2 | 28 |
| DD-982, DD-983 | Hide on window hover (fade or slide away); reserve dock space | CD, Pro | P1 | missing | M8 | 4, 28 |
| DD-984 | App tile context menu | CD, Pro | P1 | missing | M9 | 33 |
| DD-991, DD-992 | Native-Dock conflict matrix (9 cells); sit beside a visible native Dock (M1: read native Dock edge, auto-hide and footprint, exclude its span) | new, CD | P0 | missing | M1 (partial) / M2 | 47 |
| DD-993 | DockDoor / CoolDock coexistence | new | P1 | missing | M8 | 47 |
| DD-995 | Opt-in network gate for widgets | CD | P1 | missing | M9 | 42, 46 |
| DD-994 | Local widget SDK (superseded by DD-1371's sandbox) | new, Pro | P2 | missing | M14 | 48 |

### 2.3 Pillar C: CoolDock parity

| DD id(s) | Feature | Source | Pri | dedock | Target | Mx # |
|---|---|---|---|---|---|---|
| DD-1002–DD-1005 | World clock; day/month/year progress; timer; stopwatch | CD | P1 | missing | M9 | 36 |
| DD-1001 | Clock style pack (our own faces) | CD | P2 | missing | M13 | 36 |
| DD-1006 | Pomodoro | CD | P1 | missing | M9 | 36 |
| DD-1007–DD-1009 | Drink water; posture timer; habit tracker | CD | P2 | missing | M13 | 36 |
| DD-1010, DD-1011 | Next meeting with Join; reminders and quick to-do | CD | P1 | missing | M9 | 7, 37 |
| DD-1012, DD-1013 | Mail unread (Apple Events only); latest note | CD | P2 | missing | M13 | 37 |
| DD-1014 | Audio output and volume | CD | P1 | missing | M9 | 38 |
| DD-1015, DD-1017, DD-1018 | Per-app volume; mic mute and level; voice memo | CD | P2 | missing | M13 | 38 |
| DD-1016 | Background sounds | CD | P3 | missing | deferred: no public API for the system feature; own audio needs licensed assets | 38 |
| DD-1019 | Floating video preview | CD | P3 | missing | deferred: per-browser scripting; duplicates browser Picture in Picture | 38 |
| DD-1020, DD-1024 | Network throughput; quick toggles | CD | P1 | missing | M9 | 39 |
| DD-1021–DD-1023, DD-1025 | Bluetooth batteries; temperature; top apps; keyboard lock | CD | P2 | missing | M13 | 39 |
| DD-1026, DD-1027, DD-1031 | Applications library; Downloads; screenshots | CD | P1 | missing | M9 | 40 |
| DD-1028–DD-1030, DD-1032–DD-1036 | Recent files; find files; web search; clipboard history; bookmarks; cloud-folder drop; App Switcher tile; Window Manager tile | CD | P2 | missing | M13 | 2, 4, 40 |
| DD-1037–DD-1042 | Colour picker; converter; calculator; emoji; quick contacts; recent photo | CD | P2 | missing | M13 | 41 |
| DD-1043 | Weather family (behind the network gate) | CD | P1 | missing | M9 | 42 |
| DD-1044 | Web widget (URL tile) | CD (inferred) | P3 | missing | deferred: WebKit memory per tile; breaks the network-ledger model | — |
| DD-1051, DD-1052 | Size classes and variant families; change size in place | CD, new | P1 | missing | M9 | 34 |
| DD-1053 | Per-tile surface and colour override | CD, Pro | P2 | missing | M13 | 26 |
| DD-1061, DD-1063–DD-1079, DD-1088 (counts), DD-1092 | Connected-account framework (Keychain only) and providers: Stripe, Polar, Dodo, Lemon Squeezy, Shopify, Plausible, Simple Analytics, DataFast, Dub, Resend, Supabase, GitHub, Linear, stocks, crypto, Claude and Codex meters, YouTube counts, Home Assistant | CD | P2 | missing | M15 | 43, 44, 45 |
| DD-1062 | Encrypted-file credential store | CD | P3 | missing | deferred: its key would live in the Keychain anyway | 45 |
| DD-1080–DD-1087 | AI-usage meters: Cursor, Antigravity, GLM/Z.ai, Grok, OpenCode, Copilot, Gemini API, Perplexity | CD | P3 | missing | deferred: no documented personal usage API; scraping breaks and may breach terms | 44 |
| DD-1088 (Studio), DD-1089, DD-1090, DD-1091 | YouTube Studio; X followers; TikTok followers; Gmail unread | CD | P3 | missing | deferred: OAuth + Google verification; paid X tier; TikTok app review; restricted Gmail scopes | 37, 44 |
| DD-1093 | Apple Home accessories | CD | P3 | missing | deferred: HomeKit not available to a native AppKit app | 44 |
| DD-1101, DD-1103–DD-1105 | Wallpaper browser; wallpaper tile; app-icon style; wallpaper per profile | CD, new | P2 | missing | M16 | 26, 46 |
| DD-1102 | Bundled 150+ wallpaper library | CD | P3 | missing | deferred: licensed partner content; own library is a business decision (O-1) | 46 |
| DD-1111, DD-1112, DD-1114–DD-1116 | MCP server (read) and change levels; URL scheme; Shortcuts actions; Shortcut-runner / Quick Actions tile | CD, new, Pro | P2 | missing | M16 | 23, 55 |
| DD-1113 | Assistant wallpaper suggestions | CD | P3 | missing | deferred: needs a tagged library and the MCP write path | 46 |
| DD-1121 | New Message and New Document on app tiles | CD | P1 | missing | M9 | 33 |
| DD-1122 | New window with a browser profile | CD | P2 | missing | M13 | 33 |
| DD-1131, DD-1132 | Automatic local snapshots; sync layouts through a folder | new, CD request | P2 | missing | M16 | 22 |
| DD-1141 | Top edge (M1: Reveal below the menu bar, beta, D-11; M8: Pinned and Floating on top) | CD | P2 (pulled forward) | missing | M1 / M8 | 25 |
| DD-1142 | Replace the native Dock (two modes) | CD, Pro | P3 | missing | deferred: writes `com.apple.dock`, crash-safe restore and a watchdog needed; companion thesis | 25, 47 |
| DD-1143 | Dock background menu | CD | P1 | missing | M9 | 32 |
| DD-1144 | What's New, roadmap and feedback | CD | P1 | missing | M11 | 50 |
| DD-1145 | Licence and purchase UX | CD, Pro | P3 | missing | deferred: business model undecided (O-1, decide before M11) | 49 |
| DD-1146 | Per-permission cards and chips | CD, Pro | P1 | missing | M9 | 20 |
| DD-1147 | Window tiles in the Edge Dock (pinned windows, minimized windows) | CD, Pro (overlaps DD-1201) | TBD | missing | proposed P2, M13 (decide at M9) | 64 |

### 2.4 Pillar D: DockDoor Pro parity

| DD id(s) | Feature | Source | Pri | dedock | Target | Mx # |
|---|---|---|---|---|---|---|
| DD-1201 | Minimize into the Edge Dock (experimental, only while the native Dock auto-hides) | Pro | P2 | missing | M17 | 51 |
| DD-1202–DD-1204, DD-1208 | Card scroll actions; process stats in the header; browser-profile badges; capture quality and cache settings | Pro | P2 | missing | M12 | 1, 16 |
| DD-1205–DD-1207 | Switcher: pinned apps first, last-used time; Preview Navigator hotkey | Pro | P2 | missing | M12 | 2, 11 |
| DD-1209 | Hide the active window | Pro | P2 | missing | M12 | 4 |
| DD-1223 | Relaunch in the tile menu | Pro | P1 | missing | M9 | 33 |
| DD-1221, DD-1222, DD-1224, DD-1226, DD-1227 | Move windows to a Desktop; Show Exposé; menu-bar command browser; native or card menu style; one tile per window | Pro | P2 | missing | M12 | 33, 56, 59 |
| DD-1225 | The app's own Dock-menu items | Pro | P3 | missing | deferred: no public API; the known route shows the native Dock's menu on screen | 33 |
| DD-1237 | Accessibility isolation list | Pro | P1 | missing | M6 | 12, 60 |
| DD-1231, DD-1232, DD-1234–DD-1236, DD-1238, DD-1240 | File and link tiles; minimized windows section; permanent Trash; inline folders; custom icons and scale; live Calendar/Clock icons; multi-instance apps | Pro | P2 | missing | M13 | 9, 31, 60 |
| DD-1233 | Handoff tile | Pro | P3 | missing | deferred: no public API reads another device's Handoff activity | 31 |
| DD-1239 | Third-party live icons (Dock tile plug-ins) | Pro | P3 | missing | deferred: runs other apps' code; needs the DD-1371 sandbox first | 31 |
| DD-1251–DD-1255 | Long-press trigger; middle-click on tiles; pinch and swipe on icons; panel animation style; open folders with | Pro | P2 | missing | M12 | 9, 10 |
| DD-1261–DD-1263, DD-1271 | Scroll-up shelf (File Tray, Open Apps, Widgets pages); Control Center drawer | Pro | P2 | missing | M17 | 54, 55 |
| DD-1281, DD-1283, DD-1285, DD-1286 | Media fallbacks; widget card or dot style; Show Desktop tile; quick notes | Pro | P2 | missing | M13 | 5, 34, 37, 40 |
| DD-1282 | Widget stacks with paging | Pro | P2 | missing | M17 | 57 |
| DD-1284 | Pin a widget panel to the lock screen | Pro | P3 | missing | deferred: needs a private window-server space above the lock screen | 8 |
| DD-1287 | Community widget equivalents (Codex Tracker, volume boost) | Pro marketplace | P3 | missing | deferred: plugin material (DD-1371) or a separate audio feature | 38, 43 |
| DD-1301, DD-1302, DD-1304, DD-1305 | Spring magnification and companions; launch bounce; haptics | Pro | P2 | missing | M17 | 52, 53 |
| DD-1303 | Liquid Crest | Pro | P3 | missing | deferred: cosmetic; unmeasured per-frame glass cost | 52 |
| DD-1311, DD-1313 | Full-size taskbar style with edge zones; text size and colour | Pro | P2 | missing | M13 | 26, 58 |
| DD-1312 | Reflective shelf | Pro | P3 | missing | deferred: cosmetic; doubles icon drawing; no meaning on side docks | 26 |
| DD-1314 | Alternate app icon | Pro | P3 | missing | deferred: agent app has no Dock icon; changing a signed bundle's icon breaks the signature | 26 |
| DD-1331 | Profile icon and dock background image | Pro | P2 | missing | M13 | 30 |
| DD-1343 | Shortcut conflict detection | Pro | P1 | missing | M6 | 11 |
| DD-1341, DD-1342 | Letter navigation; shared trigger modifier | Pro | P2 | missing | M12 | 11 |
| DD-1356 | Right-to-left layout for vertical docks | Pro | P1 | missing | M8 | 61 |
| DD-1353–DD-1355 | Show the hidden dock in Mission Control; keep it during Show Desktop; window level override | Pro | P2 | missing | M13 | 28, 63 |
| DD-1351, DD-1352 | Move the native Dock to another edge; hide it in Mission Control | Pro | P3 | missing | deferred with DD-1142: writes `com.apple.dock`; undocumented macOS 27 helper | 47 |
| DD-1371, DD-1372 | Sandboxed plugin SDK; reviewed widget catalogue | Pro (model replaced) | P2 | missing | M14 | 48 |
| DD-1381 | Homebrew cask | DD, Pro | P1 | missing | M11 | 62 |

**Totals** (counted from PRD Appendix 1; an id split across priorities, such as DD-809 or DD-964, counts once per part):

| Priority | Pillar A | Pillar B | Pillar C | Pillar D |
|---|---|---|---|---|
| P0 | 35 | 28 | 0 | 0 |
| P1 | 44 | 35 | 20 | 5 |
| P2 | 35 | 9 | 61 | 49 |
| P3 | 0 (3 un-numbered AP §6 deferrals) | 0 | 21 | 10 |

Coverage check: every DD id in the PRD appears in the tables above (the headings DD-600, DD-630 and DD-650 are range labels, not features), and every Feature-mix matrix row 1–64 is referenced in the "Mx #" column.

**Upgraded rows.** 18 rows were "expanded for CoolDock parity" and 46 "expanded for DockDoor Pro parity" (PRD Pillar C and D intros). Their later parts land where AP §10.4 and §10.6 put them; this plan maps AP milestones as in §4.2. Each row's own acceptance criteria are read at the time the row is built.

---

## 3. Recommended add-on features (beyond the references)

**Add-ons, not parity.** None of the three references ships these, and none is already a PRD row. They are built only after parity, in M18, and each needs its own design gate. Each is local-only (no network, NFR-9).

| # | Add-on | What it does | Why | Builds on |
|---|---|---|---|---|
| X-1 | **Adaptive dwell** | Learns per edge from the local edge trace: shortens the show delay when the pointer decelerates into the edge (intent) and lengthens it after repeated accidental reveals (reveal followed by a hide with no tile hover). Bounded to 0.5×–2× of the user's setting; off by default. | Fixed dwell is the main tuning complaint in CoolDock's roadmap (requests for longer delays, `cooldock/layout-modes.md` §5). | DD-921, DD-814 trace |
| X-2 | **Per-Space dock contents** | Bind a profile to a macOS Space (Desktop 1 = Work, Desktop 2 = Media) so the dock follows the Space. | Profile rules cover app, Focus, time and display (DD-957), not Spaces. | DD-951, DD-957 |
| X-3 | **Workspace tiles** | A tile that saves a set of apps and their window frames and restores them in one click (launch missing apps, then place windows). | References pin apps or windows, never a layout of several windows. | DD-401, DD-1147 |
| X-4 | **Presentation guard** | Hide docks, previews and widget content while the screen is shared or recorded, or a presentation app is in play mode. Feasibility of share detection to be verified (public API unclear). | Previews show window thumbnails and widget data on shared screens. | DD-981, DD-816 |
| X-5 | **Dwell-to-click accessibility mode** | Hovering a tile for N s activates it; a ring shows progress. For users who find clicking hard. | NFR-10 covers VoiceOver and motion, not motor input. | DD-961, DD-1251 |
| X-6 | **Pin suggestions** | Local launch counts suggest pinning frequently used apps that are not in the dock, and unpinning tiles never used in 30 days. Data never leaves the Mac. | Saves manual dock curation; no reference does it. | DD-961, DD-963 |
| X-7 | **Trackpad edge swipe** | A two-finger inward swipe that starts at the screen edge reveals the dock, for trackpad users who do not want edge pushes. Needs the Accessibility event tap. | Edge pushes are awkward on large trackpads; references only use swipes on tiles and cards. | DD-212 tap, DD-912 |
| X-8 | **Wallpaper-derived tint** | Optional dock accent sampled from the current wallpaper of that display, updated when the wallpaper changes. | References offer a fixed accent or monochrome only (DD-978). | DD-978, DD-1101 |

---

## 4. Build order and milestones

### 4.1 Milestones

Order: Edge Dock reveal first, then the app shell, then previews, switcher, ⌘Tab, window actions, then the rest of the Edge Dock, widgets, profiles, and the v2 long tail. This follows the AP roadmap's content and gates, re-ordered so the user's first feature lands first.

| M | Name | Scope (PRD ids) | Exit criteria (summary) | AP equivalent |
|---|---|---|---|---|
| **M1** | **Edge Dock reveal** | DD-901, DD-902, DD-903, DD-910 (subset), DD-911, DD-912, DD-921–DD-929, DD-931, DD-933, DD-961, DD-962 (dot), DD-964 (basic), DD-975, DD-978 (basic), DD-1141 (Reveal on top, beta), DD-941 / DD-991 / DD-992 (partial), DD-801 / DD-802 (minimal), DD-814 (edge trace) | §6 acceptance criteria; NFR-1, NFR-2, NFR-4 met; works with every TCC grant reset | AP-M3 subset (+ AP-M0 bootstrap parts) |
| M2 | App shell, settings and Edge Dock P0 completion | DD-801, DD-802, DD-805–DD-809, DD-815, DD-816, DD-701, DD-704, DD-711, DD-941, DD-947, DD-966, DD-981, DD-991, DD-992; stable signing identity; CI string guard | Permissions hot start; `killall Dock` and sleep/wake recovery; 9-cell native Dock matrix green; 20 full-screen cycles OK; onboarding replayable | AP-M0 + rest of AP-M3 |
| M3 | Window engine and Dock hover previews | DD-401, DD-402, DD-101–DD-104, DD-106–DD-108, DD-110, DD-636, DD-651, DD-703, DD-708, DD-509 (scaffold), DD-967 | DockDoor regressions #472, #297, #1222, #277, #1001 pass; previews in all three native Dock orientations and from Edge Dock tiles; text lists with Screen Recording denied | AP-M1 + AP-M2 (previews) |
| M4 | Window switcher | DD-201–DD-204, DD-210, DD-213, DD-614, DD-615 | Key-script tests; switcher first frame ≤ 100 ms (NFR-5); tap callback < 1 ms p99 (NFR-6) | AP-M2 (switcher) |
| M5 | MVP hardening and private beta | all P0 ids | AP §10.1 exit gate: performance, regressions, Edge Dock matrix, clean-room guard, Screen Recording denied; testers on macOS 14, 15, 26, 27 | AP-M4 |
| M6 | Previews and switcher completion, ⌘Tab overlay | DD-105, DD-109, DD-111–DD-113, DD-115–DD-117, DD-206–DD-209, DD-215, DD-301–DD-304, DD-306, DD-601, DD-603, DD-604, DD-613, DD-616, DD-617, DD-631–DD-633, DD-652, DD-702, DD-705, DD-706, DD-1237, DD-1343 | ⌘Tab overlay toggles without restart; every listed P1 criterion passes | AP-M5 (part) |
| M7 | Window actions, snapping and automation | DD-403, DD-405, DD-407, DD-803, DD-810–DD-812, DD-814 | Snapping respects reserved bands; AppleScript returns JSON with `ok`/`reason`; settings search over every row | AP-M5 (part) |
| M8 | Edge Dock modes and displays | DD-904, DD-910 (Swap, Floating cards), DD-913, DD-914, DD-924 (full), DD-926 (spacing, presets), DD-930, DD-932, DD-942–DD-946, DD-982, DD-983, DD-993, DD-1141 (Pinned/Floating top), DD-1356, DD-801 (Layout menu, Reset Layout) | Swap restores native auto-hide in 20 of 20 kill tests; six docks on two displays keep idle CPU < 0.5 %, RSS ≤ 150 MB | AP-M6 |
| M9 | Tiles, widgets and editing (+ CoolDock wave 1) | DD-501, DD-502, DD-505–DD-507, DD-509 (full), DD-963, DD-964 (gallery), DD-965, DD-968, DD-971–DD-974, DD-976–DD-978, DD-980, DD-984, DD-995, DD-1002–DD-1006, DD-1010, DD-1011, DD-1014, DD-1020, DD-1024, DD-1026, DD-1027, DD-1031, DD-1043, DD-1051, DD-1052, DD-1121, DD-1143, DD-1146, DD-1223; decide DD-1147 | ≤ 2 wake-ups/s from widgets on two docks; providers paused while hidden | AP-M7 (widgets, editing) |
| M10 | Profiles | DD-951–DD-954, DD-956, DD-958 | Profiles end to end; export/import with placeholders for missing apps | AP-M7 (profiles) |
| M11 | v1.0 release | DD-1144, DD-1381, DD-816 (ledger on the site); O-1 decided; Developer ID + notarization | AP §10.2 exit gate incl. the union audit; VoiceOver reaches every tile and card | AP-M8 |
| M12 | Power-user parity | Pillar A P2 rows, DD-1202–DD-1209, DD-1221, DD-1222, DD-1224, DD-1226, DD-1227, DD-1251–DD-1255, DD-1341, DD-1342; Dock Locking, native-Dock indicator, live video previews (AP §6) | Every listed item shipped or declined in writing | AP-M9 |
| M13 | Edge Dock 2 (+ CoolDock local wave 2) | DD-905, DD-927 (speed), DD-955, DD-957, DD-962 (cards), DD-969, DD-970, DD-979, DD-809 (chip), C1 P2 widgets, DD-1053, DD-1122, DD-1147 (if P2), D3/D6/D8/D9/D11 P2 rows | AP §10.3 criteria for these rows | AP-M10 |
| M14 | Extensibility | DD-994, DD-1371, DD-1372, DD-813 | Hostile sample widgets cannot reach network, screen, windows or files | AP-M11 |
| M15 | Connected widgets | DD-1061, DD-1063–DD-1079, DD-1088 (counts), DD-1092 | No credential in any export, log, diagnostics file or MCP output (leak test) | AP-M12 |
| M16 | Personalization and automation | DD-1101, DD-1103–DD-1105, DD-1111, DD-1112, DD-1114–DD-1116, DD-1131, DD-1132 | MCP tools cannot raise their own level | AP-M13 |
| M17 | Feel, shelf and Control Center | DD-1201, DD-1261–DD-1263, DD-1271, DD-1282, DD-1301, DD-1302, DD-1304, DD-1305 | Magnification ≤ 5 % CPU while sweeping; Minimize overlay never outlives 1 s | AP-M14 |
| M18 | Add-ons | X-1…X-8 (§3) | Each add-on passes its own design gate and criteria | none |
| P3 | Deferred backlog | all P3 ids (§2) | Reviewed at every exit gate; leaves only when its revisit trigger fires (AP §10.5) | AP §10.5 |

M2 and M3 can overlap once M1 is merged (M3 needs the signing identity from M2 first). M12–M17 split into two tracks as in AP §10 (M12 → M13 → M14 and M15 → M16 → M17).

### 4.2 Why this order

- **Edge Dock first** needs no permission, so it can be built and tested before signing exists (D-5). It also exercises the panel, motion, settings and persistence foundations every later surface reuses.
- **Shell second**: permissions, onboarding, health and the signing identity gate every Pillar A feature.
- **Previews before the switcher**: both share the window engine (M3) and the panel; the switcher adds the event tap.
- **v1 items before v2**, and every P0 before the private beta (M5), as in AP §10.1.

---

## 5. Per-feature process

Every feature (one worktree each) goes through these steps. A step is done only when its output exists.

| # | Step | What happens | Output |
|---|---|---|---|
| 1 | **Worktree** | `git -C "$DEDOCK_HOME/Dedock app" fetch origin` then `git -C "$DEDOCK_HOME/Dedock app" worktree add .worktrees/<feature> -b feature/<feature> origin/develop` | a clean worktree on `feature/<feature>` |
| 2 | **Research the reference** | Read the PRD rows, then the matching `dockdoor/`, `dockdoor-pro/` or `cooldock/` sections, `cooldock/how-it-is-built.md`, `dedock-plan/ux-patterns.md`, `dedock-plan/system-design.md`, `dedock-inputs/animation-spec.md` and `apple-developer-reference.md` for the APIs. Note behaviour, defaults and timings only. Never open DockDoor source (clean-room role split, AP §7.2). | `docs/features/<feature>.md`: behaviour spec, defaults, APIs, "Sources consulted" |
| 3 | **Four design senses** | Four original visual directions for the feature's surfaces. Each is an HTML page section with a looping CSS/JS animation of the real interaction (for the Edge Dock: edge touch → reveal → tile hover → leave → hide, on left, right and bottom), driven by the fixed motion tokens so only visuals differ. The relevant reference screenshots sit beside each sense for comparison (e.g. `cooldock/screenshots/01-home-hero-dock-widgets.jpg`, `cooldock/screenshots/21-docs-layout-scenarios.jpg`, `dockdoor/screenshots/140-side-dock-left-preview-ghostty.png`, `dockdoor/screenshots/100-dock-preview-chrome-with-media-widget.png`). Each sense lists its tokens (colour, material, radius, indicator, label, light/dark, Reduce Transparency). A checklist confirms no sense reuses reference artwork, shapes or colour schemes (near-black capsule, glass-pill cards, traffic-light pill style, CoolDock rock motif). | `docs/design/<feature>/senses.html` (shown to the user locally or as a private page) |
| 4 | **User picks** | The user chooses one sense, or a mix. No implementation starts before this. | the decision, quoted |
| 5 | **Update `docs/design.md`** | Record the chosen tokens and component specs, the reasons, and the rejected senses in one line each. Later features extend the same design language rather than starting over. | `docs/design.md` |
| 6 | **Implement** | Write tests first for pure logic (state machines, geometry, layout). Swift 6 strict concurrency. Module rules from `dedock-plan/architecture.md` §5. Own strings only. | code + tests in the worktree |
| 7 | **Unit tests** | `swift test` (swift-testing). Parameterised tables, `TestClock` for timers, fakes for screens, workspace and Dock prefs. | all green; state-machine transition table 100 % covered |
| 8 | **E2E (computer use)** | `Scripts/make-app.sh`, launch `build/Dedock.app`, then: (a) `Scripts/e2e/pointer.swift` posts exact synthetic pointer paths and the edge trace (DD-814) gives timings; (b) computer use takes screenshots and drives clicks, drags and Settings to check what is on screen. Each acceptance criterion maps to a named E2E script in `Tests/E2E/<feature>.md`. | E2E log with screenshots and trace excerpts |
| 9 | **Regression** | Full `swift test`, every earlier feature's E2E script, `Scripts/measure-idle.sh` (NFR-1, NFR-2), `Scripts/check-deps.sh`, string guard (from M2). | regression log |
| 10 | **Side-by-side comparison** | `docs/compare/<feature>.md`: a behaviour table (dedock measured vs reference value, e.g. reveal 0.22 s / hide 0.18 s from CoolDock RN 2.0.8, frame steps from `dedock-inputs/animation-spec.md` §2.1) and screenshots of dedock next to the reference screenshots. Behaviour must match within tolerance; visuals must clearly differ. Recordings with `screencapture -v` where timing needs frames. | comparison doc |
| 11 | **PR into `develop`** | PR from `feature/<feature>` with summary, PRD ids covered, test evidence, comparison link and a "Sources consulted" section (clean-room). Merge after review. Remove the worktree. | merged PR |
| 12 | **Promote** | `develop` → `staging` by PR for a release candidate (manual QA matrix `docs/qa-matrix.md`); `staging` → `main` by PR for a release, tagged. | RC build; release tag |

---

## 6. M1 task breakdown: Edge Dock reveal

**Goal.** Push the pointer to the left or right edge (bottom and top optional) and a dock of pinned apps and folders slides out with the reference timing; it slides back when the pointer leaves. Running apps show an indicator; tiles can be reordered by drag; a minimal menu-bar item and an Edge Dock settings pane control it.

**Fixed values for M1** (D-12 and `dedock-inputs/animation-spec.md`; all user-adjustable where a range is given):

| Parameter | Value | Range | Source |
|---|---|---|---|
| Hot-zone thickness | 3 pt from `NSScreen.frame` (6 pt on an edge shared with the native Dock) | 1–20 pt | PRD DD-923, `ux-patterns.md` T1 |
| Hot-zone span | dock length + 40 pt each side; option "whole edge" | — | `ux-patterns.md` T2 |
| Corner exclusion | 24 pt; 8 pt for a corner whose Hot Corner is off | 0–96 pt | `system-design.md` §5.1 |
| Menu-bar exclusion (left/right) | top `screen.frame.maxY − visibleFrame.maxY`, or `max(statusBar thickness, safeAreaInsets.top)` when the menu bar auto-hides | — | `system-design.md` §5.1 |
| Show delay | 120 ms | 0–5 s | `ux-patterns.md` T3 |
| Full-screen show delay | 400 ms | 0–5 s | `ux-patterns.md` T4 |
| Push-through | 40 pt of accumulated delta toward the edge | 16–200 pt / off | `system-design.md` §5.1 |
| Hide hysteresis / hide delay | 16 pt / 400 ms | 0–40 pt / 0–5 s | `ux-patterns.md` T8, T9 |
| Re-arm cooldown after an explicit hide | 500 ms | — | `system-design.md` §5.1 |
| Reveal | `dd.motion.edge.reveal` (= `motion.edge.reveal`): spring response 0.208, damping 1.0 (99 % at 0.22 s, no overshoot); reversed path: bezier (0.2, 0.7, 0.2, 1) at the scaled duration | fixed | `animation-spec.md` §2.1 |
| Hide | `dd.motion.edge.hide` (= `motion.edge.hide`): ease-in (0.42, 0, 1, 1), 0.18 s | fixed | `animation-spec.md` §2.1 |
| Reverse in place | duration = full × remaining travel, floor 0.06 s | — | `system-design.md` §3.3.1 |
| Reduce Motion | 0.15 s opacity fade in place, same reversal rule | — | `animation-spec.md` §5 |
| Tile label | instant, toward the screen centre | — | `ux-patterns.md` T20 |
| Reorder | neighbours part with a 0.2 s spring (open: `dd.motion.reorder` in `docs/design.md` §3.2 says 0.30 s; settle before T15, `docs/status.md`) | — | PRD DD-975 |
| Dock size / padding / gap / inset | tile thickness 56 pt, padding 6 pt, gap 8 pt, edge inset 6 pt (visual values may change at the design gate; ranges stay) | 32–96 / 2–16 / 0–24 / 0–48 pt | PRD "Edge Dock defaults at a glance" |
| Default edge | Left when the native Dock is at the bottom or right; Right when it is on the left | — | AP §9.1 |

### 6.1 Tasks

| # | Task | PRD | Acceptance criteria |
|---|---|---|---|
| T0 | **Design gate** for the Edge Dock (capsule/strip, tiles, running indicator, hover label, folder stack, scenario cards, Settings pane) | D-6 | (1) `docs/design/edge-dock-reveal/senses.html` shows 4 senses, each with a reveal/hide loop on left, right and bottom at the fixed tokens, beside `cooldock/screenshots/01-…`, `cooldock/screenshots/21-…`, `dockdoor/screenshots/140-…`. (2) The user picked one. (3) `docs/design.md` records its tokens, light/dark and Reduce Transparency variants. (4) The no-copy checklist passes. |
| T1 | **Package skeleton** | D-4 | (1) Root `Package.swift`: macOS 14, Swift 6 language mode; library targets DedockCore, DesignSystem, Diagnostics, DisplayTopology, SettingsStore, EventTapKit, EdgeDock, SettingsUI (`docs/architecture.md` §2); executable `Dedock`; test targets per library plus the shared `DedockTestSupport` fakes target. (2) `swift build` and `swift test` pass on a clean clone. (3) `Scripts/check-deps.sh` fails the build on an upward or same-layer import (`docs/architecture.md` §3 D1–D5, D8). (4) `DedockCore` imports no AppKit. |
| T2 | **App bundle script** | D-4 | (1) `Scripts/make-app.sh` builds release or debug and writes `build/Dedock.app` with Info.plist `LSUIElement = YES`, `CFBundleIdentifier = app.dedock.Dedock.debug`, `LSMinimumSystemVersion = 14.0`, version from git. (2) Icon from an `.iconset` via `iconutil` (no asset catalog; `actool` is unavailable). (3) Signed ad hoc; `codesign --verify --deep --strict` passes. (4) Re-running is idempotent. (5) Launching shows no Dock icon and no window, only the status item. |
| T3 | **Core geometry** | DD-902, DD-903 | (1) `ScreenEdge` = left, right, bottom, top; axis helpers (normal, along-axis, inward direction). (2) AppKit/CG coordinate conversion and interval subtraction with parameterised tests over multi-display layouts. (3) The same test tables run for every edge. |
| T4 | **Hot-zone construction** | DD-923, DD-931 (part), DD-941 (part) | (1) Zones built only on configuration or display change, never per sample (`system-design.md` §5.2). (2) Thickness from the physical edge; span = dock length + 40 pt each side or whole edge; 24/8 pt corner exclusion read from the Hot Corner prefs; menu-bar height excluded on left/right. (3) Edge split into wall and shared segments; property test: every zone lies on an unshared segment of exactly one display, or is marked shared. (4) Zones rebuilt within 1 s of `didChangeScreenParametersNotification`. (5) M1 places the dock on the main display, falling back to the built-in display if it is disconnected. |
| T5 | **PointerHub** | DD-912, NFR-1 | (1) `NSEvent` global + local monitors for `mouseMoved` and `*MouseDragged`; deltas accumulated on every event; evaluation at full rate inside the 96 pt near band, 15 Hz outside, with a trailing sample. (2) While a dedock `NSMenu` tracks, monitors are swapped for a 30 Hz `.common`-mode timer and restored afterwards. (3) No timer runs while the pointer is still and nothing is shown. (4) Works with every TCC grant reset (`tccutil reset All app.dedock.Dedock.debug`). |
| T6 | **Reveal state machine** | DD-912, DD-921, DD-922, DD-928, DD-929 | (1) States `hidden`, `arming`, `revealing`, `shown`, `armingHide`, `hiding` with the transitions in `ux-patterns.md` §3.3; 100 % of the transition table covered with `TestClock`. (2) Dwell and hide delays are one-shot timers that fire within 16 ms of the value (no polling). (3) Leaving the zone before the dwell returns to `hidden` with no animation; the trigger is re-checked right before showing. (4) 40 pt push-through reveals early. (5) A request for the state already being entered is a no-op. (6) Inhibitors `menuOpen`, `popoverOpen` (folder stack), `dragging`, `editing` (Settings pane live preview), `pinnedByUser` block hiding; `previewOpen` exists as a hook for M3. (7) 500 ms re-arm cooldown after a tile click hides the dock. |
| T7 | **Dock panel and click-through** | DD-901, DD-933 | (1) Borderless non-activating `NSPanel`, `canBecomeKey` false, `hidesOnDeactivate` false, `hasShadow` false (shadow drawn by the content), collection behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, shown with `orderFrontRegardless()`, never `NSApp.activate`. (2) Panel placed once at its shown frame; only the content layer moves. (3) Hidden: `ignoresMouseEvents = true`. Shown: `hitTest` returns nil outside tiles; E2E: a click 4 pt outside the visible dock reaches the window underneath. (4) Clicking a tile launches/focuses the app and the frontmost app keeps key focus otherwise. (5) Control Center, Notification Center, a notification banner and a menu-bar menu all draw above the dock on each edge (E2E per edge). (6) `constrainFrameRect` returns the rect unchanged. |
| T8 | **Slide motion** | DD-927, DD-928 | (1) Reveal and hide use the `dd.motion.edge.*` tokens on the content layer's translation (`sublayerTransform`, `docs/architecture.md` §6.7) along the edge normal; the window frame never animates. (2) Measured from the edge trace: slide start ≤ show delay + 16 ms (NFR-4). (3) Reversal reads the presentation value; durations at p = 0.25 / 0.5 / 0.75 match `system-design.md` §3.3.1 (to shown 0.165 / 0.110 / 0.060 s; to hidden 0.060 / 0.090 / 0.135 s) ± 1 frame. (4) 20 rapid in/out crossings in 2 s: continuity ≤ 8 pt at each reversal, no frame step larger than a clean run's largest, no flicker (`docs/evaluation.md` §3.3). (5) Reduce Motion (system flag) turns slides into a 0.15 s fade in place. (6) Click gate flips at the start of each transition. |
| T9 | **Edges and vertical layout** | DD-902, DD-903, DD-1141 (part) | (1) Left and right slide on X, bottom on Y; changing the edge re-lays out and re-animates within one reveal cycle. (2) Tiles have fixed thickness and variable length (`tileThickness = dockThickness − 2 × padding`); app icons stack vertically on side docks. (3) Labels and running indicators sit toward the screen centre. (4) Radii concentric (outer radius = tile radius + padding). (5) Top edge (beta toggle): the dock reveals below the menu bar, never over it; the zone spans only the dock's length and excludes the notch and the status-item area; with an auto-hiding menu bar the top dock reveals only with ⌥ held. (6) Bottom edge labelled beta on macOS 27 (O-3). |
| T10 | **Pinned and Reveal modes** | DD-911, DD-912, DD-925, DD-926 | (1) Pinned: always visible; alignment start/center/end on each edge. (2) Reveal: the T6 machine. (3) Distance from edge 0–48 pt (default 6 pt). (4) One size control scales tile, padding and gap together, with live preview while dragging the slider. (5) Mode, alignment and size changes apply without restart. |
| T11 | **Full-screen reveal delay** | DD-924 | (1) A display whose frontmost window covers the whole display (CGWindowList, layer 0, no Accessibility needed) is treated as full screen after a 120 ms confirmation hold; alpha-0 overlays are ignored. (2) That display's dwell becomes 400 ms. (3) Test: enter/leave full screen 20 times; the delay switches correctly every time. (Hiding during full screen, DD-981, is M2.) |
| T12 | **Shared display edges** | DD-931 | (1) Shared segments use an 8 pt band; reveal after 300 ms in the band at < 300 pt/s; cancel if the pointer appears on the neighbour within 80 ms. (2) Policy options: Dwell + pressure (default), Modifier only (⌥), Off. (3) Settings marks the edge "shared" and warns when the whole span is shared. (4) Unit tests with fake two-display layouts of different heights (`system-design.md` §5.4 example). (5) A manual two-display check is logged in `docs/qa-matrix.md` when a second display is available. |
| T13 | **Native-Dock awareness (partial)** | DD-991, DD-992 (part), DD-901 (1) | (1) Reads native Dock orientation, auto-hide and tile size from `com.apple.dock` prefs (read-only; never written) and reacts to `com.apple.dock.prefchanged` within 1 s. (2) Default edge per AP §9.1. (3) Bottom dock with a visible native Dock sits above it (`visibleFrame.minY`); the hot zone excludes the native Dock's span. (4) If less than 200 pt of edge remains, Settings explains and suggests another edge. (Full 9-cell matrix test is M2.) |
| T14 | **Layout engine and tiles** | DD-903, DD-961, DD-962, DD-964 (basic) | (1) `LayoutEngine` is a pure function, tested for horizontal and vertical orientation. (2) Pinned app tile: click launches or activates; icon from `NSWorkspace` at 256 pt nominal, never upscaled; instant label toward the centre. (3) Running indicator for `activationPolicy == .regular` apps; frontmost highlighted; hidden apps dimmed; updates within 100 ms of `NSWorkspace` launch/terminate/activate/hide notifications. (4) Folder tile: click opens a simple stack list toward the screen centre (or Finder, per setting); the open stack holds the dock (`popoverOpen`). (5) Missing apps show a placeholder tile. |
| T15 | **Adding, reordering and removing tiles** | DD-975 | (1) ⌘-drag always reorders; plain drag reorders only when "Drag to rearrange" is on (default off). (2) Insertion index follows the pointer along the dock axis; neighbours part with a 0.2 s spring. (3) Drag a tile out of the dock to remove it, with confirmation (default on). (4) Drop an `.app` or a folder from Finder onto empty dock space to pin it; Settings also has Add App… / Add Folder…. (5) Order persists immediately and survives relaunch. (6) While a drag is in flight the dock stays shown (`dragging`). |
| T16 | **Persistence** | SettingsStore | (1) One typed document, `layout.json` (schema version 1), in `~/Library/Application Support/Dedock/` (`Dedock Debug/` in debug builds); no `UserDefaults` in M1 and no file access outside SettingsStore (`docs/architecture.md` §7). (2) It holds the dock instance, its settings and tiles; app tiles stored as bundle id + last-known path, folder tiles as a bookmark. (3) A corrupt file is renamed `layout.corrupt-<ISO8601>.json` and the newest rolling backup (or a default layout) loads, with a log entry. (4) Round-trip, unknown-key and migration-scaffold tests. |
| T17 | **Scenario cards (subset)** | DD-910 | (1) Cards: Reveal on Left, Reveal on Right, Reveal at Bottom (beta), Pinned, Reveal at Top (beta). (2) "Recommended" badge from the native Dock's edge. (3) Choosing a card applies mode, edge, delays and trigger in one step and shows a 2 s hint at that edge. (4) Any later manual change marks the card "Custom". |
| T18 | **Menu-bar item (minimal)** | DD-801 (subset) | (1) Status item with: Show/Hide Edge Dock; Edge ▸ Left / Right / Bottom / Top; Mode ▸ Reveal / Pinned; Keep Dock Open (`pinnedByUser`); Settings…; Quit dedock (⌘Q). (2) While the menu is open the dock does not hide and the pointer timer fallback runs (T5). (3) Relaunching the app while running opens Settings. |
| T19 | **Edge Dock settings pane** | DD-802 (subset) | (1) Settings window (an `NSWindow` hosting SwiftUI, `docs/architecture.md` §8) with an Edge Dock pane: scenario cards, edge, mode, show/hide delays, full-screen delay, trigger thickness/span/corner exclusion, shared-edge policy, alignment, distance, size, drag to rearrange, confirm removal, tile list with add/remove. (2) Every change applies live, no restart. (3) Keyboard reachable; VoiceOver labels on every control (NFR-10). (4) Visuals from `docs/design.md`. |
| T20 | **Edge trace and signposts** | DD-814 (subset) | (1) Debug switch logs every transition with monotonic time, pointer position, zone id and active inhibitors to a ring buffer; export to a file. (2) `OSSignposter` intervals for dwell, reveal and hide. (3) No window titles are logged. |
| T21 | **E2E harness** | process §5 | (1) `Scripts/e2e/pointer.swift` replays scripted pointer paths (approach, dwell, push, leave, 20 rapid crossings) with exact timing. (2) Computer-use scripts cover click-through, overlays, drag reorder, menu and Settings. (3) Every T-criterion above has a named E2E or unit test. The driver needs Accessibility for the process that posts events; dedock itself does not. |
| T22 | **Performance and regression gate** | NFR-1, NFR-2, NFR-4 | (1) `Scripts/measure-idle.sh`: idle CPU < 0.5 % averaged over 60 s with the dock hidden and the pointer still; RSS ≤ 120 MB with the dock shown. (2) Slide start ≤ show delay + 16 ms over 50 trials (from the trace). (3) Full unit and E2E suites green. |
| T23 | **Comparison and PR** | process §5 | (1) `docs/compare/edge-dock-reveal.md`: measured reveal/hide durations and frame steps vs CoolDock RN 2.0.8 values and `animation-spec.md` §2.1 frame check; screenshots of dedock beside the reference screenshots showing different visuals. (2) PR into `develop` with PRD ids, test evidence and "Sources consulted". |

### 6.2 Not in M1 (and where it goes)

| Item | PRD | Goes to |
|---|---|---|
| Hide during full screen; topology, Space and wake recovery; display fallback UI | DD-981, DD-947, DD-941 (full) | M2 |
| Full 9-cell native Dock matrix with automated test per cell | DD-991, DD-992 (full) | M2 |
| Separators and spacers | DD-966 | M2 |
| Window previews from tiles (the `previewOpen` inhibitor is wired but unused) | DD-967 | M3 |
| Swap, Floating, several docks, global shortcut, drag reveal, other display modes, top-edge Pinned/Floating | DD-913, DD-914, DD-904, DD-930, DD-932, DD-942–DD-946, DD-1141 (rest) | M8 |
| Running-apps section, folder gallery, app folders, drops onto tiles, edit mode, overflow, full appearance, native Dock import, context menus, widgets | DD-963, DD-964 (gallery), DD-965, DD-968, DD-976, DD-977, DD-978 (full), DD-980, DD-984, DD-971–DD-974 | M9 |
| Profiles | DD-951–DD-958 | M10 / M13 |

---

## 7. Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | **No Xcode.** No XCTest, XCUITest, `xcodebuild`, `actool`, Instruments or asset catalogs; String Catalog compilation may be unavailable. | Certain / Medium | swift-testing for unit tests; E2E via the synthetic pointer driver (`Scripts/e2e/pointer.swift`) + computer use; idle CPU/RSS via `top`/`ps` scripts and signposts in logs; icons via `iconutil` and SF Symbols; plain `.strings` or Swift strings until Xcode exists. Check early that any snapshot-testing library runs under `swift test` without XCTest, or compare `NSHostingView` renders ourselves. Add an `.xcodeproj` if Xcode is installed. |
| R2 | **TCC grants reset on every ad-hoc re-sign** | Certain (from M3) / High | Create a stable self-signed code-signing identity in M2 and sign every build with it; `Scripts/tcc-reset.sh`; separate debug bundle id. |
| R3 | Global mouse monitors stall while dedock's own menus track | High / Low | 30 Hz `.common`-mode timer during `NSMenu` tracking (T5); `menuOpen` inhibitor. |
| R4 | Dock covers system overlays (Control Center, Notification Center, banners, menus), as DockDoor Pro shipped on the right edge (GH#1633) | Medium / Medium | Level `.mainMenu` (24) at rest: above the native Dock, below menu-bar dropdowns and pop-up menus; never `.screenSaver` (`docs/architecture.md` §6.7); E2E per edge (T7 criterion 5). |
| R5 | Native Dock competes for the bottom edge (CoolDock's macOS 27 report) | Medium / Medium | Side edge by default; zone excludes the native Dock's span; bottom labelled beta (O-3). |
| R6 | Shared display edges misfire, or only one display is available for testing | Medium / Medium | Dwell + pressure rule with unit tests over fake layouts; manual check logged when a second display is available. |
| R7 | Full-screen detection without Accessibility is a heuristic in M1 | Medium / Low | CGWindowList full-display check with a 120 ms hold; the AX-based check arrives with M2 permissions. |
| R8 | Liquid Glass renders inactive in a non-activating panel (CoolDock 2.1.0 fix) | Medium / Low | Force the active appearance on the material; fallback material on macOS 14–15 and under Reduce Transparency. |
| R9 | **Copying instead of rebuilding**: reference code, strings or assets entering the repo (GPL contamination) | Medium / High | The look matches the references by design (D-6), so the guard is on *sources*: values come from screenshots and measurements only; no reference media in the repo (CI `guards`); clean-room role split; CI string guard against `ci/clean-room-strings.txt` from M2; "Sources consulted" in every PR. |
| R10 | PRD defaults disagree with `ux-patterns.md` | Certain / Low | D-12 picks one set for M1; confirm with the user; record in `docs/design.md`. |
| R11 | Only macOS 27 on the build machine; target is macOS 14+ | High / Medium | Avoid APIs newer than macOS 14 without availability checks; test on macOS 14, 15 and 26 virtual machines or beta testers before M5. |
| R12 | E2E timing is noisy through computer use | High / Low | Use the synthetic pointer driver (`Scripts/e2e/pointer.swift`) and the edge trace for timing assertions; use computer use for what is on screen. The driver needs Accessibility for the posting process (Terminal), not for dedock. |
| R13 | Scope: about 300 PRD ids across four pillars | High / Medium | Strict milestone gates; P2 rows may be declined in writing; union audit at M5 and M11; add-ons only after parity. |
| R14 | Business model (O-1) undecided affects licensing UI, notarization and the docs site | Medium / Medium | Decide before M11; nothing before M11 depends on it. |
| R15 | The system's pointer-sharing feature uses the same push-through-the-edge gesture as Reveal mode on a wall edge, so a reveal push can carry the pointer to another device (seen in E2E, harness REG-055) | Medium / Medium | DD-934: dwell reveals before the push is long; per-edge pointer-sharing setting; hide on hand-off; E2E preflight checks the feature is off (REG-055) |

### Open questions for the user

1. Confirm D-12 (120 ms show delay, 24 pt corners, 400 ms full-screen delay) or keep the PRD's 0.15 s / 10 pt / 0.75 s.
2. Confirm the milestone order in §4.1, especially the private beta (M5) before ⌘Tab and window actions.
3. Priority for DD-1147 (window tiles in the Edge Dock): proposed P2 in M13, decided at M9.
4. Which of the add-ons X-1…X-8 to keep.
5. O-1 business model, needed before M11.
6. DD-934 pointer-sharing edges: when an Edge Dock edge is also the edge where the pointer passes to a nearby device, which default? Proposed: (b) below, plus the hand-off hide, with (c) only if the M2 spike finds a reliable public signal. See `docs/architecture.md` §"Pointer-sharing edges".
