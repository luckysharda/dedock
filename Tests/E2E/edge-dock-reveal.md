# E2E playbook: M1 Edge Dock reveal

How each scenario in `docs/evaluation.md` §7.3 is run with this harness. Pass rules are the evaluation doc's; this file says **how**. App ↔ harness interface: `Tests/E2E/contract.md`.

Drivers: **SYN** = `Scripts/e2e/scenario.sh` (synthetic pointer + log analysis), **CU** = computer use (screenshots, clicks, drags, menus), **AX** = `cua-driver` reads (accessibility tree, window list and levels), **SH** = shell checks.

---

## 0. Before any run

1. Harness self-test is green: `Tests/E2E/selftest/run.sh` (builds every tool; no app, no cursor).
2. **Contract shakedown first.** On a new build, run a short x-01 (`n=2`) and read `analyze events` plus any `WARN unrecognized …` lines before trusting any verdict: a renamed log value makes gates silently absent.
3. App built in the app worktree: `Scripts/make-app.sh debug` (always with its own `--scratch-path` if the harness builds it; never share e7's `.build`).
4. **Reference apps.** CoolDock and DockDoor compete for the screen edges. `launch.sh` records and warns but never quits them; quitting is the user's decision (open question in `docs/status.md`). Edge scenarios run only when neither is running.
5. **Desktop lock.** Tell the orchestrator (and through it the user: hands off the mouse) before any run longer than about 10 s, then
   `Scripts/e2e/desktop-lock.sh acquire dedock-app-f1 e2e "<scenario list>"`. Touch every 5 min; `release` at the end; message again.
6. Launch: `Scripts/e2e/launch.sh <run> --app <app worktree> [--set 'docks[0].edge="right"'] [--frame-log]`.
   One run per edge and per settings variant (the layout is seeded at launch).
7. Teardown: `Scripts/e2e/teardown.sh <run>` (REG-006 Dock prefs diff).

Coordinates: computer-use space (top-left, 1920 × 1080, 1 pt = 1 px). Probe point and the "inside" point come from GEOM (`<run>/data/e2e/geometry.json`); the fallbacks are §7.1's (`EDGE_X` 0 / 1919, `IN_X` 600 / 1319, `PROBE_Y` 540).

**Clicks only on harness-owned targets** (the TextEdit fixture, the dock itself, dedock's own menus and windows). Never on the user's windows.

---

## 1. SYN scenarios (`scenario.sh <run> <L|R> <id> [n=] [seed=] [dry=1]`)

`dry=1` prints the pointer script and its duration without moving anything. Every SYN run also records all input events and fails as **contaminated** if anything the driver did not post arrives (`analyze contamination`).

| ID | Command | Gates reported (`report.txt`) | Notes |
|---|---|---|---|
| x-01 dwell reveal | `scenario.sh R1 L x-01 n=50` | `dwell` (lateness p95 ≤ 16 ms, never early), `NFR-4 zoneEnter→reveal.begin` (p95 ≤ 16 ms over the show delay) | n=50 is the NFR-4 sample size (≈ 81 s). Follow with a CU screenshot of one shown state (dock on its edge, centred on `visibleFrame`). |
| x-02 leave before dwell | `scenario.sh R1 L x-02 n=10` | `leave-before-dwell` per trial (no `reveal.begin` between arming and hidden) | |
| x-03 push-through | `scenario.sh R1 L x-03 n=5` | `push-through` (arming→revealing `cause=push` before the show delay); pull trials must end `cause=dwell`, never `push` | Driver posts 10 × 5 pt toward the edge in 50 ms with the cursor pinned. Explicit deltas at a fixed point reach `NSEvent` monitors (verified mid-screen 2026-10-15); whether macOS keeps them for a post **clamped at the screen edge** is unverified until the first x-03 run. |
| x-04 hide delay | `scenario.sh R1 L x-04 n=5` | `hide delay` (p95 ≤ 16 ms late, never early), `hide duration` 180 ms ± 1 frame, "hide cancelled by return" count = n | CU screenshot ≈ 1 s after a leave: dock gone. |
| x-05 (a) reverse a hide | launch with `--frame-log`; `scenario.sh R1 L x-05a n=5` | `frames`: per-animation curve fit, `reversal duration` (= full × remaining, floor 0.06 s), `DD-928 continuity`, `max step`, `no flicker`; `reversals occurred` ≥ n (fails if timing drift let the hide finish first) | |
| x-05 (b) reverse a reveal | launch with `--frame-log --set 'docks[0].reveal.hideDelayMs=0'`; `scenario.sh R2 L x-05b n=5` | same as (a) | separate run (hide delay is seeded). |
| x-06 rapid crossings | in the x-05(b) run (`--frame-log --set 'docks[0].reveal.hideDelayMs=0'`): `scenario.sh R2 L x-06 seed=<k>` for k = 1…5 | the three DD-928 checks on every frame; `reversals occurred` ≥ 1; `final state` must match where the pointer ended (inside → hidden after the hide) | Primed with a dwell reveal. With the eval doc's defaults (120 ms dwell, 400 ms hide delay) 50 ms legs never move the dock, so the scenario would test nothing; it refuses to run without hide delay 0. |
| perf: CPU while moving | `scenario.sh R1 L perf-move` | `perf.txt`: CPU < 1.0 % (evaluation §6) — read `cpu_avg_pct`, the script's own verdict line is the idle gate | 60 s of circles in the screen centre. |
| perf: idle | no cursor: `Scripts/measure-idle.sh $APP_PID 60 <run>/perf.csv` with the dock hidden and hands off | CPU < 0.5 %, idle wakeups ≤ 1/s, RSS ≤ 120 MB | powermetrics (sudo) confirms wakeups: the user runs it. |
| perf: leaks / growth | `leaks $APP_PID`; `footprint` before and after `scenario.sh … x-01 n=100` | 0 leaks, growth ≤ 2 MB | |

Each command writes `build/e2e/runs/<run>/<id>-<L|R>/` (`driver.txt`, `listen.txt`, `log.ndjson` sliced to this scenario, `report.txt`). Raw runs stay git-ignored; only cropped dedock captures and CSVs go to `docs/evidence/edge-dock-reveal/<date>/`. Never commit CoolDock or DockDoor captures.

---

## 2. CU / AX / SH scenarios

| ID | Steps | Pass evidence |
|---|---|---|
| x-00 no permissions | `tccutil reset All app.dedock.Dedock.debug`; launch; CU screenshot; SH `lsappinfo info -only applicationType Dedock` | No permission prompt in the screenshot; status item visible; `analyze events` shows state `hidden`; no Dock icon (applicationType UIElement). |
| x-07 tile launch | `osascript -e 'quit app "Calculator"'`; CU `mouse_move` to the edge probe, wait 1 s; CU `left_click` the Calculator tile centre (GEOM `tiles[].frame`) | SH frontmost = Calculator within 2 s; log: `tile.activate result=launched`, then `reveal.transition … cause=explicit` and no `to=arming` for 500 ms (`cause=cooldown`); frontmost never Dedock. Click again: `result=activated`. |
| x-08 click-through | AX `set_window_frame` puts the TextEdit fixture at x 0…900, y 100…900 (L) or x 1020…1920 (R). (a) shown: CU click 4 pt outside the capsule's inner edge at its vertical centre; (b) shown: click a gap between tiles (GEOM); (c) hidden: click (`EDGE_X` ± 40, `PROBE_Y`) | (a)(c) TextEdit frontmost and its insertion point moved (screenshot); (b) passes through if the gap is outside every `hitRect`; log `gate.mouse ignores=true` while hidden. |
| x-09 drag reorder | CU `left_click_drag` tile 1 → below tile 3 with "Drag to rearrange" on; then SYN `pointer drag … cmd` with it off; then a plain drag with it off | log `inhibitor token=dragging on=true` during the drag, `tile.reorder`; new order in `data/layout.json` at once and after relaunch; plain drag with the setting off: no `tile.reorder`. |
| x-10 full screen | TextEdit fixture: CU `key` ctrl+cmd+f; SYN: `pointer edge <edge> <y>; wait 200; move <in>`, then `edge; wait 500`; CU screenshot; exit full screen; ×5 | 200 ms: no `to=revealing`; 500 ms: revealed with `show=400` lateness ≤ 16 ms; AX: TextEdit still frontmost and full screen; after exit the 120 ms dwell is back. |
| x-11 shared edge | — | **Deferred on this machine** (one display). |
| x-12 overlays (R) | Right dock shown (pinned mode is easiest); CU opens Control Center, Notification Center, the Dedock status menu; screenshot each | Each system surface is drawn above the dock; AX `list_windows`: dock panel layer below those surfaces; dock frame `minY ≥ visibleFrame` top (never in the menu bar). |
| x-13 settings + cards | CU via the status item: Open Settings…; pick each card; set show delay 0.50 s; quit (status menu) and relaunch with the same data dir | AX reads every control's value; `settings.changed` lines with `scenario=`; hint at the edge (screenshot); card reads "Custom" after the manual change; values survive relaunch (`layout.json` diff). Status menu "Show Edge Dock" is an explicit reveal: the dock stays shown until the pointer has visited it once, then the normal 400 ms hide applies (check both). |
| x-14 indicators | `open -a TextEdit`; `osascript -e 'quit app "Notes"'`; hide Calculator (⌘H via CU); screenshot after each | `tile.indicator` lines within 100 ms of each action; dot/dim per `docs/design.md` (placeholder visuals: state only). |
| x-15 folder tile | CU click the Downloads tile | Finder at Downloads or the stack list toward the screen centre; `inhibitor token=popoverOpen on=true` while the list is open. |
| x-16 inhibitors | open the stack, then SYN move far away and wait 1 s; same with Settings open; a held tile drag outside the dock | no `to=armingHide` while any token is on; after the last `on=false` with the pointer outside: hide delay starts (`analyze timing`). |
| x-17 Reduce Motion | CU System Settings ▸ Accessibility ▸ Display ▸ Reduce motion on; x-01 and x-04 with `--frame-log`; turn it off | `reveal.begin curve=fade`; `frames`: `tx` constant, alpha ramps over ≈ 9 frames. **Restore the setting** even on failure. |
| x-18 bottom / top | after left/right pass (M1 edge order: left/right, bottom, top) | as x-01…x-08 with `edge` bottom/top; top: menu-bar menus still open. |

---

## 3. Known harness facts (measured 2026-10-15)

- `NSEvent` global monitors get `mouseMoved` coalesced to the display rate (60 Hz here), with deltas summed: 10 posts × −5 pt arrive as 5 events totalling −50 pt. Push-through still accumulates correctly; at most 60 samples/s reach the app.
- Post → monitor latency ≈ 0.7 ms.
- `log stream --style ndjson` `machTimestamp` and the driver's `mach=` are the same clock (24 MHz ticks).
- zsh has a `log` builtin: scripts call `/usr/bin/log`.
- Video frames (H.264 4:2:0) shift coloured edges by ~1 px and colours by 2–3/255: colour and pixel checks use `screencapture` PNGs only; recordings use `-pix_fmt yuv444p` and serve timing/position.
