# App ↔ E2E harness contract

What the debug build of dedock must emit or accept so the E2E harness (`Scripts/e2e/`, `Tests/E2E/`) can check it. Proposed 2026-10-15 by the E2E lane; revised the same day per the planner (no UserDefaults in v0, debug-only switches). The planner records the agreed version in `docs/evaluation.md` §7.x. Anything here that changes must change on both sides in the same PR.

Everything below is **debug-build only** unless marked otherwise. Release builds may compile the hooks out.

---

## 1. Build and launch

| Item | Value |
|---|---|
| Bundle id | `app.dedock.Dedock.debug` |
| Build | `Scripts/make-app.sh debug` → `build/Dedock.app` (repo root of the worktree under test) |
| Launch for E2E | `Scripts/e2e/launch.sh <worktree>` (harness-owned): sets the env below, opens the app with `open -n --env …` or execs the binary directly, starts `log stream` |
| Process name | `Dedock` (for `pgrep -x Dedock`) |

## 2. Environment switches

| Variable | Effect |
|---|---|
| `DEDOCK_E2E=1` | Turns on GEOM output (§4) and the `.public` E2E log lines (§3). |
| `DEDOCK_FRAME_LOG=1` | Turns on the per-frame motion log (§5). Off by default even with `DEDOCK_E2E` because it logs 60 lines/s while moving. |
| `DEDOCK_E2E_HOME=<abs dir>` | **Isolation.** Alias of `DEDOCK_DATA_DIR`: the app's whole data directory (`layout.json` and anything else it persists) is `<dir>`. v0 persistence is `layout.json` only, with no `UserDefaults` (`docs/architecture.md` §7), so E2E runs never touch the user's real dedock data and the harness resets state with `rm -rf <dir>`. |
| Seeding and setting overrides | If `<DEDOCK_E2E_HOME>/layout.json` exists at launch, it is loaded like a normal saved layout. The harness builds it from `Tests/E2E/fixtures/layout-seed.json` (owned by the implementer, since the schema is theirs) and patches per-scenario values into it before launch, e.g. `docks[0].reveal.showDwellMs`, `.hideDelayMs`, `.triggerThicknessPt`, `docks[0].edge` (key names and units are the implementer's schema: `Tests/E2E/fixtures/layout-seed.json`). Live changes during a run go through the Settings UI (computer use), as a user would make them. **Requirement:** the loader accepts a tile that has only `bundleID` (apps) or only `path` (folders), with no URL bookmark, and fills the bookmark in on first save. Real user layouts still resolve the bookmark first, then fall back to bundleID/path. |
| Release builds | Every `DEDOCK_E2E*` and `DEDOCK_FRAME_LOG` switch, and the bookmark-less seed loading, take effect only in the debug bundle (`app.dedock.Dedock.debug`) and are ignored in release builds. |

## 3. Log events (`os_log`, subsystem `app.dedock.Dedock`)

Read with:

```sh
log stream --style ndjson --level debug --predicate 'subsystem == "app.dedock.Dedock"'
```

Timing comes from the ndjson `machTimestamp` field (mach absolute time). The pointer driver prints the same clock for every event it posts, so the two series line up with no clock conversion.

Every message starts with the **event name**, then space-separated `key=value` pairs. No spaces inside values (use `,` for lists, `-` for none). All values `.public`. Never log window titles. **Nothing else on the line**: in debug builds no `<private>` segment, not even an empty one (REG-043; the regress contract check fails any line containing `<private>`). Release builds may redact string values (REG-030), never numbers.

| Category | Event | Keys | When |
|---|---|---|---|
| `launch` | `launch.edgeReady` | `ms` (since process start, from `kinfo_proc`) | first time a hot zone is armed after launch |
| `edge` | `edge.zoneEnter` | `edge` (left/right/bottom/top), `zone` (id), `kind` (wall/shared), `x`, `y` (AppKit global pt) | pointer sample first lands inside a zone |
| `edge` | `edge.zoneExit` | `edge`, `zone`, `x`, `y` | pointer sample first lands outside the zone it was in |
| `edge` | `zones.computed` | `edge`, `dock`, `rule` (primary/besideNativeDock/nearestFree/optionOnly), `span` (a..b, the candidate along the edge before exclusions), `statusItems`, `statusRejected` (status-level windows not item-sized), `notch` (bool), `nativeDock` (a..b or `-`), `segments` | once per zone rebuild (REG-065/066). Spans and counts only, never names |
| `edge` | `edge.push` | `edge`, `acc` (accumulated toward-edge delta, pt) | each time the push-through accumulator changes while armed (debug only) |
| `reveal` | `reveal.transition` | `edge`, `from`, `to` (hidden/arming/revealing/shown/armingHide/hiding), `cause` (zone/dwell/push/leave/return/hideDelay/animationEnd/explicit/inhibitor/cooldown/settings/suppression/button), `inh` (active inhibitors, comma list or `-`) | every state-machine transition |
| `reveal` | `reveal.begin` | `edge`, `kind` (reveal/hide/fadeIn/fadeOut), `from`, `to` (translation pt), `dur` (s), `curve` (spring/bezier/easeIn/fade) | at the `CATransaction` commit that starts the animation |
| `reveal` | `reveal.end` | `edge`, `kind`, `at` (final translation pt) | animation completion |
| `reveal` | `gate.mouse` | `edge`, `ignores` (true/false) | every change of `ignoresMouseEvents` on the dock panel |
| `reveal` | `inhibitor` | `edge`, `token`, `on` (true/false) | every inhibitor raised or cleared |
| `layout` | `layout.pass` | `edge`, `reason`, `tiles` | every layout pass (for "no relayout on movement") |
| `tiles` | `tile.activate` | `id`, `bundle`, `result` (launched/activated/opened/missing) | tile click handled |
| `tiles` | `tile.indicator` | `bundle`, `state` (none/running/frontmost/hidden) | indicator re-rendered |
| `tiles` | `tile.reorder` | `id`, `from`, `to` | drop that changes the order |
| `tiles` | `tile.reorderCancelled` | `id`, `reason` (relayout) | a reorder drag in progress was cancelled because the tile layout changed under it |
| `settings` | `settings.changed` | `key`, `value`, `scenario` | a settings write; logged before the resulting `docks.sync reason=settings`. **Emitted today only for `key=dd.dock.style`** (value darkGlass/black/lightGlass, once per dock whose style changed; Settings branch). Other keys don't log it yet |
| `settings` | `settings.recovered` | `source` (backup/default), `moved` (file name) | a corrupt `layout.json` was moved aside (REG-036) |
| `settings` | `settings.notice` | `kind` (recovered/readOnly) | a launch notice is posted, always AFTER `launch.edgeReady` (REG-036, REG-057) |
| `settings` | `settings.readFailed` | `readOnly` (true) | `layout.json` unreadable (I/O error); left in place, not treated as corrupt; the app runs read-only (REG-036, REG-057) |
| `app` | `debug.command` | `cmd`, `ok` (true/false), `reason` (e.g. `pid`) | a debug command over `app.dedock.debug.command` (DEBUG + `DEDOCK_E2E` only). The harness addresses it by pid (userInfo `pid`, `Scripts/e2e/notify`); with the app-side filter, another pid is ignored silently and a missing or malformed pid logs `ok=false reason=pid` |
| `display` | `display.fullscreenUnsettled` | `reholds` (3) | the full-display probe gave up re-holding a flapping window; waits for the next notification (REG-058) |
| `pointer` | `pointer.mode` | `mode` (monitors/menuTimer) | swap to or from the 30 Hz menu-tracking timer |
| `app` | `docks.sync` | `reason` (launch/displays/dockPrefs/settings/statusItems/reduceMotion/appearance), `docks` (count); `appearance` = a Light/Dark switch (label colours follow the system; the style is unchanged) | the set of Edge Docks is re-synced |

The harness matches on the event name at the start of `eventMessage`; extra keys may be added freely, but renaming or removing one is a contract change.

## 4. GEOM file (`DEDOCK_E2E=1`)

Path: `~/Library/Application Support/Dedock Debug/e2e/geometry.json` (the debug data dir, `docs/architecture.md` §7) — or `<DEDOCK_E2E_HOME>/e2e/geometry.json` when `DEDOCK_E2E_HOME` is set. Rewritten atomically (temp file + rename) after every layout pass and every state change of a dock.

```json
{
  "schema": 1,
  "pid": 12345,
  "written": "2026-10-15T18:30:00.123Z",
  "screens": [
    { "id": 1, "main": true, "scale": 1,
      "frame":        { "appkit": [0, 0, 1920, 1080], "topLeft": [0, 0, 1920, 1080] },
      "visibleFrame": { "appkit": [0, 0, 1920, 1055], "topLeft": [0, 25, 1920, 1055] } }
  ],
  "docks": [
    { "id": "dock-0", "screen": 1, "edge": "left", "mode": "reveal", "state": "shown",
      "panel":   { "appkit": [x, y, w, h], "topLeft": [x, y, w, h] },
      "capsule": { "appkit": [...], "topLeft": [...] },
      "tiles": [
        { "id": "t-1", "kind": "app", "name": "Calculator", "bundleId": "com.apple.calculator",
          "frame":   { "appkit": [...], "topLeft": [...] },
          "hitRect": { "appkit": [...], "topLeft": [...] } }
      ],
      "zones": [
        { "id": "z-0", "kind": "wall", "rect": { "appkit": [...], "topLeft": [...] } }
      ] }
  ]
}
```

Rects are `[x, y, width, height]` in global points. `topLeft` is computer-use space (origin at the top-left of the main display, y down). Tile frames are the **target** (laid-out) frames, not animated ones. `state` is the reveal state at write time.

Per-dock fields added since M1 (additive; the harness reads them when present):
- `showDwellMs`: the EFFECTIVE show dwell after per-edge derivation (the top edge's minimum is 300 ms; REG-062). Scenarios judge against it, not the stored setting.
- `style` (darkGlass/black/lightGlass, and from T37a dark/liquidGlass) and `material` (hudWindow/popover; `solid` for Dark and under Reduce Transparency; `glass` for Liquid Glass on macOS 26+, whose stand-in on 14–15 is hudWindow for the dark tint and popover for the light one): `dd.dock.style` (C9).
- `liquidTint` (dark/light): only with `style` liquidGlass; the adaptive tint in use. The log reports each reading (`dock.tint.reading luminance= pending= applied=`) and each change (`dock.tint tint=`), category `edge`.
- `zoneRule` (primary/besideNativeDock/nearestFree/optionOnly): which rule built the trigger zones (REG-065/066).
- `nativeDock`: `{"edge", "autohide", "rect"}`, the native Dock's footprint strip on this dock's edge, or `null` when the native Dock isn't on that edge. It's used by the bottom rows "zone reachable beside the native Dock" and "native Dock span never triggers".
- `zones`: may hold several strips (bottom beside the native Dock; top between status items). An empty list means the dock cannot be revealed from its edge, which geom-check and the scenarios report as a FAIL.

## 5. Frame log (`DEDOCK_FRAME_LOG=1`)

Category `frame`, one line per display-link callback while an animation is in flight (and one final line when it ends), nothing while idle:

```
frame edge=left tx=-41.27 alpha=1.000 anim=reveal
```

`tx` is the content layer's **presentation** translation along the edge normal, in pt (0 = shown; negative = toward the left/top edge for left/top docks, positive for right/bottom). `alpha` is the presentation opacity. `anim` is the animation kind from `reveal.begin`, or `none`. The harness takes the timestamp from `machTimestamp`.

## 6. What the harness provides

| Piece | Path |
|---|---|
| Synthetic pointer driver (real `CGEvent` `mouseMoved` posted to `.cghidEventTap`, with explicit `kCGMouseEventDeltaX/Y`; NSEvent convention deltaY > 0 = down) | `Scripts/e2e/pointer.swift` → `build/e2e/pointer` |
| Launch + log capture | `Scripts/e2e/launch.sh` |
| Log / frame-log analysis (transition timings, DD-928 checks) | `Scripts/e2e/analyze.swift` |
| Idle CPU / RSS sampler | `Scripts/measure-idle.sh` |
| Pixel measurement on captures | `Scripts/measure-pixels.swift` |
| Desktop lock | `Scripts/e2e/desktop-lock.sh` (atomic `mkdir` lock `${DEDOCK_LOCKS:-$HOME/dedock/.locks}/desktop.lock`, docs/organization.md §6.1) |
| Scenario scripts | `Tests/E2E/edge-dock-reveal.md` |
