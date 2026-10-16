# dedock design guide

Status: **skeleton**. Behaviour, motion and layout grammar are fixed. The visual language is **pending the user's pick** (§7). When a direction is chosen, §7 is replaced by its full token set, and the "visual" cells in §5 are filled from it.

Cited paths are relative to the reference pack, `<pack>/`.

**User decision (binding, revised 2026-10-15).** dedock keeps the *features and behaviour* of DockDoor and CoolDock **and is visually based on them**: the Edge Dock looks like CoolDock's dock (turned vertical for the side edges) and the previews, switcher and settings look like DockDoor's. The chosen variant is §7 (A2 Frosted + E1 Capsule). An earlier "visuals must be new" rule is withdrawn.

**What this guide inherits.** `dedock-plan/design-system.md` blends DockDoor's glass language with CoolDock's capsule language. Since the user's revised decision, its visual sections are the **starting point** for §7: the concentric-radius rule, the 62 pt tile, the 34 / 24 / 18 panel radii and the glass styles. §7 records the exact values chosen.

Clean-room: DockDoor is GPL-3.0. Nothing here is DockDoor code; behaviour is restated as numbers. No CoolDock artwork, copy or assets are used. Notchy is out of scope: nothing from `notchy/` or `research/notchy-*` is read or used (`docs/plan.md` D-8).

"M1", "M2" in motion rows below are the motion principles in `dedock-inputs/animation-spec.md` §1, not milestones; milestones are `docs/plan.md` §4.1.

---

## Contents

1. [Principles](#1-principles)
2. [Behaviour preserved from the references](#2-behaviour-preserved-from-the-references)
3. [Motion tokens](#3-motion-tokens)
4. [Layout grammar (DD-903)](#4-layout-grammar-dd-903)
5. [Component inventory per surface](#5-component-inventory-per-surface)
6. [Accessibility](#6-accessibility)
7. [Visual direction: A2 Frosted + E1 Capsule](#7-visual-direction-a2-frosted--e1-capsule-user-pick-2026-10-15)
8. [Open conflicts carried from the plan](#8-open-conflicts-carried-from-the-plan)

---

## 1. Principles

| # | Principle | In practice |
|---|---|---|
| D1 | **Behave like the references, look like nothing else.** | Timings, curves, reveal logic and preview lifecycle come from §2–§3. Shapes, colours, type and materials come only from the chosen direction (§7). A review rejects any surface that reads as Liquid Glass cards with traffic lights, or as a floating dark capsule of rounded widget cards. |
| D2 | **The edge is a physical place.** | A dock belongs to an edge: it slides along the edge normal, its labels and previews open toward the screen centre, its hot zone is the physical screen edge. Left/right are designed first; bottom and top-below-menu-bar reuse the same grammar rotated. |
| D3 | **Quiet until reached for.** | Labels, window actions, mass actions and edit controls appear only when pointer or keyboard focus reaches them. Nothing animates while idle. |
| D4 | **One accent, used for state.** | The accent marks selection, focus, frontmost and drop targets. Chrome is otherwise neutral. App icons, thumbnails and widget data keep their own colour. A "Use system accent" option swaps the direction's accent for `controlAccentColor`. |
| D5 | **Native where it counts.** | System fonts only (SF Pro and its width/design variants, New York, SF Mono), SF Symbols, standard `NSMenu`, standard settings controls, system accessibility flags. No bundled fonts. |
| D6 | **Every motion has a reduced form; every material has a solid form.** | §3.4 and §6. A token without a reduced form fails review. |
| D7 | **Click-through by construction.** | Hidden or faded docks ignore the mouse. Shown docks hit-test only visible tiles and controls. Decorative elements (idle hints, shadows, spines) never take clicks. |

---

## 2. Behaviour preserved from the references

These rows are behaviour, not look. They hold for every visual direction.

### 2.1 Edge Dock timing (first feature: DD-912, DD-921–DD-929)

| # | Behaviour | Default | Source |
|---|---|---|---|
| T1 | Hot-zone thickness, measured from the physical edge (`NSScreen.frame`) | 3 pt (range 1–20, `docs/plan.md` D-12) | `dedock-plan/ux-patterns.md` §3.1; DD-923 |
| T2 | Hot-zone span | dock span + 40 pt each side; 24 pt corner exclusion | `dedock-plan/ux-patterns.md` §3.1 (DD-923 says 10 pt, §8) |
| T3 | Show delay (dwell) | 120 ms (range 0–5 s) | `dedock-plan/ux-patterns.md` §3.1 (DD-921 says 0.15 s, §8) |
| T4 | Show delay in a full-screen Space | 400 ms | `dedock-plan/ux-patterns.md` §3.1 (DD-924 says 0.75 s, §8) |
| T6 | Reveal | 0.22 s, decelerating, no overshoot | CoolDock RN 2.0.8, `cooldock/layout-modes.md` §2 |
| T7 | Hide | 0.18 s, accelerating | same |
| T8 | Hide hysteresis | dock frame outset 16 pt | `dedock-plan/ux-patterns.md` §3.1 |
| T9 | Hide delay | 400 ms | DD-922 |
| — | Reverse in place | from the presentation value, duration × remaining / total, floor 0.06 s | CoolDock RN 2.0.8; DD-928 |
| — | Idempotent requests | asking for the state already being animated to is a no-op | DD-928 |
| — | Exact timers | one-shot timers, fire within 16 ms; no polling | DD-912 AC3; CoolDock RN 2.0.8 |
| — | Pre-show re-check | if the pointer left the zone when the dwell fires, do nothing | `dedock-plan/ux-patterns.md` §3.3 anti-flicker 1 |
| T20 | Tile name label | instant (0 s), no fade, toward the screen centre; one label at a time | CoolDock RN 2.0.8, `cooldock/animations.md` §4.9 |
| T14 | Edge-tile preview dwell (previews, later milestone) | 0.25 s, counted only after the reveal has finished | `dedock-inputs/animation-spec.md` §3.2 |

### 2.2 State machine and inhibitors

States: `hidden → arming → revealing → shown → armingHide → hiding → hidden`; `hiding → revealing` on pointer return (reverse in place, no dwell). `shown` has sub-states `normal`, `faded` (window overlap, option), `focused` (keyboard), `editing`. Full diagram: `dedock-plan/ux-patterns.md` §3.3.

Hide inhibitors (DD-929): `previewOpen`, `popoverOpen`, `menuOpen`, `dragging`, `editing`, `textFocus`, `keyboardFocused`, `pinnedByUser`. Any one blocks `shown → armingHide`.

`editing` (Settings open) holds the dock only for the window's lifetime. Opening Settings shows the dock through that hold, never through an explicit reveal (an explicit reveal latches until the first pointer visit), so closing Settings returns to normal behaviour: with the pointer away, `armingHide` and the hide delay follow (REG-064).

### 2.3 Click-through (DD-933)

- While `hidden` or `faded`, the dock panel ignores mouse events.
- While shown, hit-testing returns nil outside visible tiles and controls. Test: a click 4 pt outside the container hits the window underneath.
- Interactive at the **start** of a reveal; pass-through at the **start** of a hide (`dedock-inputs/animation-spec.md` §3.1).
- The `NSPanel` frame stays fixed; only the content layer's translation animates (DD-927).

### 2.3a No modal sessions

While any dock is live, Dedock never starts an app-wide modal session (`runModal`, `beginModalSession`): a modal run loop stalls the pointer monitors and the reveal timers, so the dock stops working behind it (REG-057).

| Need | Use |
|---|---|
| A launch or error notice | a small floating, non-activating panel that never becomes key on its own (`becomesKeyOnlyIfNeeded`), so the user's typing stays in their app; OK by click (REG-057) |
| A file or app picker | a sheet on the Settings window (`beginSheetModal`), never `runModal` |
| A confirmation inside Settings | a sheet on the Settings window |

### 2.4 Preview lifecycle (later milestone; recorded so the look can plan for it)

| Behaviour | Value | Source |
|---|---|---|
| Appear | alpha 1 in one frame, then a 7 pt nudge away from the dock over 0.175 s ease-in-out; no fade-in, no scale | `dedock-inputs/animation-spec.md` §2.2 |
| Retarget (tile to tile) | content and frame swap in one frame, nudge re-runs | same |
| Keep-alive | 0.2 s poll; panel frame + 24 pt hit margin ∪ trigger tile; safe corridor | same; `dedock-plan/ux-patterns.md` §3.4 |
| Two dismiss languages | pointer-leave fades 0.30 s; explicit actions cut | `dedock-inputs/animation-spec.md` principle M1 |
| Dock coupling | the dock never hides while a preview's alpha > 0; an explicit dock hide cuts the preview first | same §3.5 |
| Placement | beside the tile on the screen-centre side; gap 10 pt; hit margin 24 pt overlaps the dock; clamp to `visibleFrame` 8 pt inset; never flip | same §3.3 |
| Switcher | show, selection and hide are cuts; 100 ms render delay; quick release switches without UI | same §2.3 `motion.switcher` |

---

## 3. Motion tokens

Adopted from `dedock-inputs/animation-spec.md` §2 in substance, renamed to dedock's `dd.motion.*` namespace. Do not re-litigate these values; evidence and lineage are in that file.

### 3.1 Primitives

| Token | SwiftUI | Core Animation / CSS | Lineage |
|---|---|---|---|
| `dd.curve.ui` | `.timingCurve(0.2, 0.7, 0.2, 1, duration:)` | `cubic-bezier(0.2, 0.7, 0.2, 1)` | CoolDock UI curve (FACT code) |
| `dd.curve.panelSlide` | `.easeInOut(duration:)` | `cubic-bezier(0.42, 0, 0.58, 1)` | DockDoor panel nudge (FACT src + measured) |
| `dd.curve.fade` | `.timingCurve(0.25, 0.1, 0.25, 1, duration:)` (never SwiftUI `.default`) | CA default; `cubic-bezier(0.25, 0.1, 0.25, 1)` | DockDoor fade-out (measured) |
| `dd.curve.hide` | `.easeIn(duration:)` | `cubic-bezier(0.42, 0, 1, 1)` | CoolDock hide (FRAME) |
| `dd.spring.edge` | `.spring(response: 0.208, dampingFraction: 1.0)` | `CASpringAnimation` mass 1, stiffness 910, damping 60.3 | 99 % settled at 0.220 s, 0 % overshoot (COMPUTED) |
| `dd.spring.settle` | `.spring(response: 0.242, dampingFraction: 1.0)` | stiffness 676, damping 52 | CoolDock ω = 26 spring |
| `dd.spring.snappy` | `.snappy(duration: 0.175)` = `.spring(response: 0.175, dampingFraction: 0.85)` | — | DockDoor hover (FACT src); overshoot only on fill/opacity, invisible |

### 3.2 Edge Dock (first feature)

| Token | Value | Reduced Motion |
|---|---|---|
| `dd.motion.edge.reveal` | `dd.spring.edge`; bezier form for the reverse path: `dd.curve.ui` 0.22 s. Nothing scales or fades. | opacity 0.15 s in place |
| `dd.motion.edge.hide` | `dd.curve.hide`, 0.18 s | opacity 0.15 s in place |
| `dd.motion.edge.reverse` | same curve as the new direction, duration × remaining / total, floor 0.06 s; read the presentation layer first | applies to alpha |
| `dd.motion.edge.floating` | scale 0.94 → 1 + opacity 0 → 1 on `dd.spring.settle`; hide reversed | opacity 0.15 s |
| `dd.motion.edge.windowFade` | `.easeInOut` 0.20 s; `ignoresMouseEvents = true` once α < 0.05 | instant |
| `dd.motion.tile.hover` | fill / brightness / opacity on `dd.spring.snappy` | instant |
| `dd.motion.tile.lift` | optional, off by default: 2 pt toward the screen centre (+x left dock, −x right, −y bottom, +y top) on `dd.curve.ui` 0.18 s; ignored while magnification is on | off |
| `dd.motion.tile.label` | instant, no fade, screen-centre side | instant |
| `dd.motion.edit.badges` | all tiles in the same frame: a cut, or scale 0.6 → 1 on `dd.spring.settle`; no stagger, no jiggle | cut |
| `dd.motion.reorder` | neighbours part along the dock axis, `.spring(duration: 0.30, bounce: 0)` (the plan's 0.15 bounce is dropped to honour motion principle M2, see §8) | `.easeInOut` 0.15 s |
| `dd.motion.profile` | old tiles fade out 0.08 s → container length on `dd.spring.settle` → new tiles fade in with blur 6 → 0 over 0.15 s `dd.curve.ui`; no stagger | cross-fade 0.15 s |
| `dd.motion.segment` | `dd.curve.ui` 0.30 s | instant |
| `dd.motion.tabStrip` | opacity `.easeOut` 0.15 s after the 0.4 s delay | instant |
| `dd.motion.popover` | anchored scale 0.9 + opacity, `dd.curve.ui` 0.18 s; close = cut | opacity 0.15 s |
| `dd.motion.sheet` | `dd.spring.settle` + scale 0.94 → 1 + opacity; close = cut | opacity 0.15 s |

### 3.3 Previews, cards, switcher (later milestones)

| Token | Value | Reduced Motion |
|---|---|---|
| `dd.motion.panel.in` | alpha 1 at once, then 7 pt → 0 away from the dock (left −x, right +x, bottom +y, top −y), `dd.curve.panelSlide` 0.175 s | alpha cut only |
| `dd.motion.panel.retarget` | one-frame content + frame swap, then `panel.in` again. Option "Smooth panel tracking": frame tween with `panel.relayout`, no nudge; never mix | swap |
| `dd.motion.panel.relayout` | `dd.curve.panelSlide` 0.20 s; a removed card disappears in one frame | instant |
| `dd.motion.panel.out` | α 1 → 0, `dd.curve.fade` 0.30 s, after the next 0.2 s poll | kept, capped at 0.20 s |
| `dd.motion.panel.reenter` | α → 1, `dd.curve.fade` 0.15 s (animation-spec §2.2). Note: the plan has since adopted **0.20 s**, measured live 2026-10-15 (`dedock-plan/design-system.md` §7.2.2, `dedock-plan/ux-patterns.md` T17). Use 0.20 s when previews are built. | instant |
| `dd.motion.panel.hideExplicit` | cut; after a tile click wait 0.15 s first | cut |
| `dd.motion.panel.poll` | 0.2 s | — |
| `dd.motion.hover` (cards) | `dd.spring.snappy` | instant |
| `dd.motion.dim` | `.easeInOut` 0.15 s (minimized/hidden card dim) | instant |
| `dd.motion.controls` | `dd.spring.snappy` (window actions idle → full) | instant |
| `dd.motion.switcher` | cuts; 0.10 s render delay; scroll-to-selection `.easeOut` 0.15 s | scroll instant |
| `dd.motion.dragSpringLoad` | hold 1.5 s, then 4 × `.easeInOut` 0.08 s blinks, then activate | one steady highlight |

### 3.4 Secondary motion rules

| Allowed | Not allowed |
|---|---|
| Idle-hint fade (≤ 0.15 s) when the dock leaves or arrives | Tile stagger on reveal, edit or profile switch (`dedock-inputs/animation-spec.md` §2.3 `motion.profile` and `motion.edit.badges` "no stagger"; CoolDock principle 5 "groups reveal together", `cooldock/animations.md` §1) |
| Running-indicator fade or grow on `dd.spring.snappy` when an app launches, quits or becomes frontmost | Anything that scales or fades during the edge slide (`dedock-inputs/animation-spec.md` §3.1) |
| Hover fill / opacity on `dd.spring.snappy`; optional 2 pt lift | Hover that moves tiles along the dock axis; overshoot on any edge surface (motion principle M2) |
| Label appearing instantly | Label fade-in or label delay |

### 3.5 Power tier

`motion` (default) → `lightweight` (Low Power Mode or `thermalState ≥ .serious`: keep the edge slide and panel nudge; drop the profile de-blur and live-thumbnail refresh) → `static` (Reduce Motion). Observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` and `NSProcessInfoPowerStateDidChange` (`dedock-inputs/animation-spec.md` §5).

---

## 4. Layout grammar (DD-903)

### 4.1 Axes

| Term | Meaning |
|---|---|
| Edge axis | the dock's long direction (vertical on left/right, horizontal on bottom/top) |
| Cross axis | the dock's thickness |
| `T` | dock thickness across the edge |
| `p` | container padding |
| `t` | tile thickness, `t = T − 2p` |
| `g` | gap between tiles |
| length | `lengthUnits × t`, lengthUnits ∈ {1.0, 1.5, 2.25, 3.0, 4.0}; side docks use the vertical variant of each widget, or only its 1.0 square |
| radii | concentric: `containerRadius = tileRadius + p` (DD-903 AC5). A direction without a container states the exception. |

Default tile thickness `t` = **56 pt** (DD-926, range 32–96). A visual direction may set its own default `t` inside that range (the senses in §7.2 use 52–60 pt), and sets `p`, `g`, tile radius and icon size; the formula above is fixed.

### 4.2 Per edge

| Edge | Slide axis | Hidden offset | Labels and previews | Running indicator (default) | Alignment |
|---|---|---|---|---|---|
| Left | x | content at −(T + edgeInset + shadowReach), min 8 | right of the tile | inner side (screen-centre) | top / center / bottom |
| Right | x | +(T + edgeInset + shadowReach) | left of the tile | inner side | top / center / bottom |
| Bottom (optional) | y | +(T + edgeInset + shadowReach) | above the tile | inner side (above) | leading / center / trailing |
| Top, below the menu bar (optional) | y | content above the menu bar's bottom edge, hidden under it | below the tile | inner side (below) | leading / center / trailing |

Rules:

1. **Physical edges.** A left dock stays left in right-to-left languages; only tile content follows layout direction (`dedock-plan/design-system.md` §9.6).
2. **Corners stay free.** Container and hot zone stop 24 pt short of each screen corner.
3. **Side docks never enter the menu-bar band**; on notched displays the top limit is `visibleFrame.maxY`.
4. **Top dock.** Hot zone is the top physical edge but its span follows the dock's content length (CoolDock 2.0.4 lesson, `cooldock/layout-modes.md` §2), so menus and status items outside the dock never trigger it. Shown position starts below the menu bar.
   - Zone, in order (REG-066): (a) the content span ±40 pt minus item-sized status-item rects (live, REG-044) and the notch; app menu titles are not subtracted (unknowable without Accessibility in M1; the 300 ms dwell protects menu-bar use, and menus draw above the dock). (b) If (a) is shorter than 80 pt in total: the nearest free stretch of the menu-bar line of at least 80 pt, closest to the dock's centre, inside the 24 pt corners; Settings hint "Reveal from the free part of the menu bar near the centre". (c) If no such stretch exists: reveal only with ⌥ held on contact, as with an auto-hiding menu bar; Settings hint "Hold ⌥ at the top edge to reveal". Derived at zone time, never stored.
5. **Bottom dock beside the native Dock** (same edge, visible or auto-hidden) sits above it (DD-912 AC5). Its zone cannot follow the content span, because the native Dock's span is excluded and the Dock is usually wider than the Edge Dock's content (the zone came out empty, REG-065). Beside the native Dock the span is the whole bottom edge minus the Dock's footprint and the corners, so the dock reveals from either side of the Dock; thickness 6 pt. Derived at zone time, never stored; the user's span setting is shown as overridden with the hint "Reveal from either side of the Dock".
   - **Reveal corridor (REG-067, every edge).** On the top edge and on the bottom beside the native Dock, the shown capsule does not touch its zone: on top, 19 pt of the menu-bar band lies outside zone ∪ capsule + 16 pt, and beside the Dock the gap is diagonal. A pointer pausing there for 400 ms would hide the dock on its way to it. So a reveal from the zone also counts a corridor as inside: the convex hull of the entry segment (the entry point ± 24 pt along the edge, clamped to the zone, full zone depth) and the capsule + 16 pt. It lasts until the pointer first reaches the capsule + 16 pt, so it never keeps the dock open over the menu bar or the native Dock after use; a new zone entry builds a new one; explicit reveals have none. The hull touches the bottom edge only along the entry segment, outside the Dock's footprint. Details in `docs/architecture.md` §6.5, decision 4.
6. **Fixed panel frame.** The `NSPanel` is sized once to dock + label room + shadow; only content moves. Labels draw inside this frame on the screen-centre side, so they never need a second window.
7. **Overflow** (DD-977): Adapt size shrinks tiles to 60 % of `t`, then scrolls along the edge axis.

### 4.3 Relayout hysteresis for side docks (M2, with DD-947)

A side dock is centred on its display's `visibleFrame`, which moves by a point or two whenever the native Dock's reserved area changes (an app icon added, for example when Settings switches Dedock to a regular app; magnification limits; autohide). Each change re-centres the capsule by about 1 pt: correct, but a visible nudge. M1 accepts it. From M2 a side dock re-centres only when the change along its axis is ≥ 4 pt, or when the capsule would otherwise overlap the newly reserved area; smaller changes keep its position. GEOM always reports the position actually placed, so the E2E C1 check is unchanged.

---

## 5. Component inventory per surface

"Visual" cells say *per §7* until a direction is chosen. Behaviour and state cells are final.

### 5.1 Edge Dock (first feature)

| Component | Behaviour / states | AX | Visual |
|---|---|---|---|
| Container | hidden / revealing / shown / armingHide / hiding; faded; focused; editing | `AXGroup`, list subrole: "Left dock, profile Default, 9 items" | per §7 |
| App tile | click launches or activates; ⌘-drag reorders (plain drag when "Drag to rearrange" is on, DD-975); right-click menu | `AXButton`: label app name; value "running, 3 windows" / "not running" | per §7 |
| Running indicator | running, frontmost, hidden app, not running; updates ≤ 100 ms after `NSWorkspace` notifications (DD-962) | folded into the tile's value | per §7 |
| Tile label | instant on hover, one at a time, screen-centre side | — (the tile carries the name) | per §7 |
| Folder tile | click opens a stack list toward the screen centre (MVP) or Finder (DD-964); spring-load 0.8 s during a drag | `AXButton`: "Downloads, folder, 24 items" | per §7; must not be a 2×2 icon cluster by default |
| Widget tile | click = primary action; hover = compact controls; right-click Customize / Refresh / Hide / Remove (DD-972) | `AXButton` or `AXGroup` with value | per §7 |
| Separator / spacer (DD-966) | divider across the cross axis; flexible spacer | ignored by AX | per §7 |
| Idle edge hint (optional, new) | visible only while `hidden`; brightens while `arming` (dwell feedback); drawn in the trigger window with `ignoresMouseEvents = true`; never inside the 24 pt corner exclusion; option Off (default: CoolDock shows nothing while hidden) / Subtle / Visible | not exposed | per §7 |
| Edit mode (DD-976) | right-click ▸ Edit Dock; remove buttons and drag handles appear on every tile in the same frame; Done; inhibitor `editing` | remove button: "Remove Safari" | per §7; must not be a small red minus at the top-trailing corner |
| Drop slot | insertion marker across the cross axis; neighbours part with `dd.motion.reorder` | — | per §7 |
| Profile tab strip (DD-953, later) | appears 0.4 s after the pointer enters, screen-centre side | `AXRadioButton` in `AXTabGroup` | per §7 |

### 5.2 Menu-bar item (first feature, minimal)

| Item | Behaviour |
|---|---|
| Status item | template image (a dock on an edge); in M1 a click opens a standard `NSMenu`; from M2 a click opens the **M3 Control panel** (§7.2a), which replaces the menu |
| Menu (M1, `docs/plan.md` T18) | Show/Hide Edge Dock, Edge ▸ Left / Right / Bottom / Top, Mode ▸ Reveal / Pinned, Keep Dock Open (`pinnedByUser`), Settings… (⌘,), Quit dedock (⌘Q). Later: the ⌃⌥⌘E shortcut (DD-930, M8), Layout menu and Reset Layout (M8), Edit Dock… (DD-976, M9) |
| Look | M1: system `NSMenu` in every direction (native). M2 and later: the M3 Control panel carries the same items; the direction may only change the status-item glyph and the panel's material (Window material, §7.2). |

### 5.3 Settings window

| Component | Behaviour | Visual |
|---|---|---|
| Shell | sidebar + content; search field in the sidebar | per §7 |
| Edge Dock pane (first feature) | scenario cards (DD-910 subset, `docs/plan.md` T17: Reveal on Left, Reveal on Right, Reveal at Bottom (beta), Pinned, Reveal at Top (beta)) with a "Recommended" tag computed from the native Dock's edge; choosing a card applies mode, edge and delays and shows a 2 s hint at that edge; any later change marks the card "Custom" | per §7 |
| Edge picker | screen diagram with clickable left / right / bottom / top bars | per §7 |
| Timing rows | show delay, hide delay, trigger thickness, edge inset, alignment, size | native controls, tinted per §7 |
| Live mock | a real dock rendered with the current settings | uses the real components |

### 5.4 Later surfaces (behaviour fixed in §2.4; visual per §7)

| Surface | Components |
|---|---|
| Preview panel | header (app icon, app name, window count, mass actions on header hover), window cards (thumbnail, title, window actions dim until reached), minimized / hidden state, compact row, media / calendar card, folder pop |
| Window switcher | centred grid of cards, search field, icon-only card for windowless apps, compact list |
| ⌘Tab overlay | preview strip attached to the system switcher |
| Sheets | widget gallery, profile editor, onboarding |

### 5.5 Names in UI text

| Name | In UI text | Elsewhere |
|---|---|---|
| The app | **Dedock**, capitalised as a proper noun, matching the bundle name `Dedock.app` that Finder, the menu bar and System Settings already show: "Quit Dedock", "Dedock 0.1", "Dedock restored the most recent backup." | lower case only in identifiers: bundle ids (`app.dedock.*`), the repo, paths, log subsystems, notification names |
| The side dock | **Edge Dock** (title case, two words): "Show Edge Dock", the panel's accessibility title | `EdgeDock` in code |
| The system's dock | **the Dock** | `native Dock` in docs and code, to tell it apart from the Edge Dock |

Accessibility descriptions follow the same rule (the status item's image description is "Dedock"). The E2E check `x-00 status item` matches the description, so it must match case-insensitively before the strings change. Docs prose may keep writing "dedock" in lower case until it is next edited; new UI strings use the forms above. The owner can still override this default.

---

## 6. Accessibility

| Area | Rule |
|---|---|
| Reduce Motion | follow the system flag by default (in-app override: Follow system / On / Off); every token's reduced form is in §3.2–§3.3; the edge slide becomes a 0.15 s fade in place and the reverse rule applies to alpha |
| Reduce Transparency | every translucent material renders its solid fallback (each direction in §7 lists one); the style picker explains why it is locked |
| Increase Contrast | solid fills; borders become ≥ 1 pt at ≥ 3:1 against the surface; focus and selection marks thicken by 1 pt; secondary text uses primary colour in tiles |
| Differentiate Without Colour | running / frontmost / hidden states differ by shape, not only colour; selection adds a non-colour mark |
| Contrast | text ≥ 4.5:1 (≥ 3:1 at ≥ 18 pt or 14 pt bold); non-text indicators and borders ≥ 3:1; a high-chroma accent that fails as text is used only as a fill with dark text |
| Focus vs hover | keyboard focus uses a distinct focus mark from pointer hover |
| VoiceOver | labels, values and hints as in §5 and `dedock-plan/ux-patterns.md` §9.1; when the dock reveals by keyboard, post layout-changed focused on the first tile and announce "Left dock" |
| Accessibility frames | an element's accessibility frame equals its click target: a dock tile's element is its whole cell, not the icon inside it, so pointer-based VoiceOver finds the tile wherever a click would open it (REG-054, REG-061) |
| Named controls | every control has a name (description or title), not only a value: a numeric field beside a slider is named after the slider's row (REG-063) |
| Keyboard | every surface reachable by shortcut and from the menu-bar menu; Esc closes; arrow keys move along the edge axis |
| Hit targets | ≥ 28 × 28 pt pointer targets; remove buttons ≥ 18 pt visual with a 28 pt hit area |
| Motor | all dwells adjustable; "Click to reveal" and "Sticky reveal" options (`dedock-plan/ux-patterns.md` §9.3) |

---

## 7. Visual direction: A2 Frosted + E1 Capsule (user pick, 2026-10-15)

The user picked from the reference-based design board: **A2 Frosted** (whole app) and **E1 Capsule** (Edge Dock). dedock looks like CoolDock's dock and DockDoor's previews: CoolDock's capsule turned vertical in its Dark Glass style, and DockDoor's previews in its Frosted style. Every value below is built from published screenshots and measurements (`<pack>/cooldock/design-system.md` §1–§7, §11; `<pack>/dockdoor/design-system.md` §2–§9). No code, artwork or assets are copied. Pt values are at the default size; everything scales with Dock Size (DD-926).

### 7.1 Edge Dock (E1 Capsule, CoolDock grammar turned vertical)

| Token | Value | Source |
|---|---|---|
| `dd.dock.tile.thickness` (`t`) | **62 pt** (fixed width on side docks, fixed height on bottom/top) | CoolDock tile height 62 pt |
| `dd.dock.padding` (`p`) | 8 pt | CoolDock padding 10 px at an 80 px tile, scaled to 62 pt |
| `dd.dock.gap` | 8 pt; "Widget Spacing" overrides later (P1) | CoolDock gap = padding |
| `dd.dock.thickness` (`T`) | `t + 2p` = **78 pt** | |
| `dd.dock.tile.radius` | 15 pt, continuous corners | CoolDock tile 20 px at 80 px |
| `dd.dock.capsule.radius` | `tile.radius + p` = **23 pt** (concentric rule, DD-903 AC5) | CoolDock 30 = 20 + 10 |
| `dd.dock.edgeInset` | 8 pt from the physical edge | DD-925 default |
| `dd.dock.hiddenOffset` | `T + edgeInset + shadowReach` = 78 + 8 + 24 = **110 pt** | design.md §4.2 rule |
| Length | content-driven, centred on the edge (alignment Center), max = visible edge length − 48 pt | CoolDock content-width capsule |
| Order (side dock, top → bottom) | widget tiles → 1 px divider → app tiles → folder tiles | CoolDock widgets → divider → apps |
| `dd.dock.widget.length` | 1.0 `t` (square), 1.5 `t` (clock), 2.25 / 3.0 `t` for vertical variants (M9) | CoolDock size classes, rotated |
| `dd.dock.app.icon` | 52 pt icon, bare (no plate), cell 54 pt along the dock axis | CoolDock bare app icons |
| `dd.dock.divider` | 1 px, 60 % of `t`, `white @ 0.18` | CoolDock thin divider |
| `dd.dock.indicator` | 4 pt circle, `white @ 0.9`, on the **inner** side, 1 pt outside the tile edge; hidden app = `white @ 0.45` | CoolDock running dot; DD-903 AC4 |
| Hover | **none on tiles** (CoolDock has no hover indicator); label only | CoolDock |
| `dd.dock.label` | **H4 Name and state** (pick, §7.2a): two lines, name 13 pt semibold and state 11 pt `#A0A0A5` (running dot `systemGreen`), fill `#202022 @ 0.94` (light: `#F6F6F6 @ 0.95`, text `#111`), radius 10 pt, padding 8 × 12 pt, 1 px inner edge `white @ 0.08`, 10 pt from the capsule toward the screen centre; instant, one at a time | owner pick 2026-10-16 (was the native-Dock-style tooltip) |
| Edit mode | red delete badge `#D85058`, 16 pt circle, "–" glyph, top-leading corner of each tile; dashed 1.5 pt `white @ 0.35` outline 3 pt outside the capsule; no jiggle, one frame | CoolDock edit badge |

**Materials (CoolDock's own style options; `dd.dock.style`, default Dark Glass):**

| Style | Capsule | Widget tile plate | Text | Notes |
|---|---|---|---|---|
| **Dark Glass** (default, A2) | behind-window blur, `.hudWindow`-class material forced `.active`, tint `#121214 @ 0.55`, saturation from the system material (the ≈ 1.6 seen in the reference cannot be set on `NSVisualEffectView`); 1 px inner edge `white @ 0.10`; shadow `0 8 24 black @ 0.25` | `white @ 0.09` + 1 px inner `white @ 0.08` | primary `#FFFFFF`, secondary `#A0A0A5` | wallpaper hue tints through |
| Black | `#0A0A0A @ 0.92`, blur 10 | `white @ 0.07` + 1 px inner `white @ 0.06` | `#FFFFFF` / `#878787` | CoolDock default in marketing |
| Light Glass | blur, tint `#EAEDF2 @ 0.55`, 1 px inner `white @ 0.68` | `white @ 0.45` + 1 px inner `white @ 0.55` | `#111111` / `#555555`; dot `black @ 0.7` | |
| **Dark** (owner, 2026-10-16) | solid, no blur: `#1C1C1E`; 1 px inner edge `white @ 0.08`; shadow as Dark Glass | `#2A2A2C` | `#FFFFFF` / `#98989D` | the matte option; also what every dark style becomes under Reduce Transparency |
| **Liquid Glass** (owner, 2026-10-16) | macOS 26 and later: the system glass material (`NSGlassEffectView`), treated as **LG4 Adaptive** (§7.2a): a dark or a light tint chosen from what is behind the capsule; macOS 14–15: Dark Glass with a specular top rim (`white @ 0.22` → 0 over 40 % of the height) as the stand-in, switching to the Light Glass tint by the same LG4 rule, labelled "Liquid Glass needs macOS 26" in the picker | tiles bare on the glass | follows the tint: Dark Glass text on the dark tint, Light Glass text and `black @ 0.7` running dots on the light tint | forced `.active` in a non-activating panel (R8) |
| Reduce Transparency | solid `#1C1C1E` (Dark Glass, Black, Dark, Liquid Glass) / `#EAEDF2` (Light Glass) | `#2A2A2C` / `#FFFFFF` | same | forced when the macOS setting is on |

Widget content follows CoolDock: one hero value per tile (SF Pro Semibold 20 pt, tabular digits, tracking −0.02 em), secondary caption 9 pt Medium `#A0A0A5`, data colours from system colours (`systemGreen` for the CPU ring, 4 pt stroke, round caps, track `white @ 0.15`).

### 7.2 Previews, switcher and settings (A2 Frosted, DockDoor grammar)

| Token | Value | Source |
|---|---|---|
| `dd.panel.material` | **Frosted**: `.ultraThinMaterial`-class blur forced `.active`, dark tint `#221E2C @ 0.62` / light `#F2F2F6 @ 0.78`; 1 px inner edge `white @ 0.08` (light: `black @ 0.06`); **no refraction rim**, no shadow by default | DockDoor Style ▸ Frosted, Material Ultra Thin |
| `dd.panel.radius` / padding | 34 pt / 14 pt | DockDoor container 20 + 20 × 0.7 |
| `dd.panel.header` | 22 pt app icon + app name 13 pt Medium; Close All / Minimize All accent capsules (21 pt tall, 10 pt text) appear on header hover | DockDoor header |
| `dd.card.size` | thumbnail width 300 pt (16:10, height 188), card = thumbnail + 6 pt each side | DockDoor default 300 × 188 |
| `dd.card.radius` / thumbnail radius | 24 pt / 18 pt continuous | DockDoor 24.2 / 18.2 |
| `dd.card.fill` / stroke | `white @ 0.07` / 1.75 pt `white @ 0.08` (light: `black @ 0.04` / `black @ 0.07`) | DockDoor card glass |
| `dd.card.selected` | system accent @ 0.40 fill + 2.5 pt accent ring | DockDoor selection |
| `dd.card.pills` | traffic-light pill (Quit `#E0386B`, Close `#FF4D47`, Minimize `#FFCC33`, Full Screen `#42D65C`; 13 pt orbs, 7 pt gap, 5 pt inner padding) at 0.25 opacity until the card **and** pill are hovered; title pill 24 pt tall, 10.5 pt text, middle-truncated; pills `white @ 0.12` | DockDoor traffic-light and title pills |
| Minimized / hidden card | thumbnail dimmed to 0.75 + `eye.slash` 32 pt + "Minimized" italic in place of the lights | DockDoor §9.6 |
| Layout | native Dock and bottom/top Edge Dock: one row; left/right Edge Dock: cards stack top to bottom, max 2 columns | DockDoor side-Dock layout |
| Placement | beside the hovered tile toward the screen centre, 10 pt gap, clamped to `visibleFrame` with 8 pt inset | `animation-spec.md` §3.3 |
| Switcher | the same Frosted panel and cards in a grid, centred; selection = accent ring; cuts, no slide | DockDoor switcher |
| Settings | DockDoor layout: full-height sidebar (~270 pt) with group labels (Features / Customization / System), accent selection row, content column with UPPERCASE 11 pt section headers and grouped cards (radius 10, dark `#1C1C1C` on `#252421`; light: white cards with a hairline), segmented controls and sliders with value fields; an **Edge Dock** pane under Features | DockDoor settings shell |

Light / Dark / System appearance applies to panels (DD-704); the dock style is chosen separately (CoolDock behaviour).

**Appearance options (owner, 2026-10-16).** Two independent settings:

| Setting | Values | Default | Applies to |
|---|---|---|---|
| Dock style (`dd.dock.style`) | Dark Glass, Black, Dark, Light Glass, Liquid Glass | Dark Glass | the Edge Dock capsule, its labels and its panels that grow out of it (P2) |
| Window appearance | System, Light, Dark | System | Settings, onboarding, notices, permission screens |
| Window material | Frosted (A2), Liquid Glass (macOS 26 and later; shown with "Needs macOS 26" before that), Solid | Frosted | the same windows; Reduce Transparency forces Solid |

### 7.2a App UI picks (owner, 2026-10-16; senses in `docs/design/app-ui/`)

| Surface | Pick | What it fixes |
|---|---|---|
| Settings window (T33) | **S1 Sidebar** | full-height sidebar (230 pt; Features, Customization, System), content column of grouped cards, the dock held shown while Settings is open so changes play on the real dock; selection row slides with the snappy spring, panes cross-fade 0.15 s |
| Notice and confirm panels (REG-057 notice, T25 drag-out confirm) | **P2 Capsule toast** | a 52 pt Dark Glass pill (radius 26) that unrolls from the dock's inner edge beside the tile's slot (confirm), or drops from the menu bar beside Dedock's icon (notice), with the reveal curve 0.22 s; fades out 0.30 s; one line of text; never key, never modal |
| Hover label (T25, DD-903) | **H4 Name and state** | two lines: name 13 pt semibold, state 11 pt (`● Running · N windows`, `Hidden · N windows`, `Not running`), 10 pt radius, fill `#202022 @ 0.94`; instant, one at a time, toward the screen centre; the state line updates live |
| Dock size (T25, DD-926) | **Z1 Slider with stops** | slider with S, M, L, XL stops (tiles 48, 62, 76, 92 pt), free while dragging, snaps to the nearest stop on release with the snappy spring; the dock follows on every frame |
| Separators and spacers (T26, DD-966) | **SP3 Islands** | a separator splits the dock into separate capsules with 8 pt between them, each keeping the 23 pt radius; a spacer is a half-cell (27 pt) of empty glass; in edit mode the gap shows a dashed bridge. The islands are one dock: one trigger zone, one reveal, one click-through region; separators and spacers are hidden from accessibility |
| Pointer-sharing edge (T40, DD-934) | **PS1 Toggle with help** | one switch per edge in the Edge Dock pane, under the edge picker: "Another Mac or iPad is on this side", with one line of help ("Pushing past this edge moves the pointer to it, so the dock opens only when the pointer rests at the edge") and the small before/after behaviour strip |
| Welcome (T29, DD-806) | **O1 Three-step window** | a 560 pt Frosted window (22 pt radius) with step dots: (1) choose how the dock appears (scenario cards, Recommended for the native Dock's position), (2) try it now (watches for the first reveal and confirms it), (3) the optional Accessibility note with Open System Settings; steps cross-fade 0.15 s; shown after `launch.edgeReady`, non-modal, never key on its own; replayable |
| Accessibility request (T28, DD-805) | **A1 Permissions pane** | Settings ▸ Permissions: one row per permission with a status chip (Not granted / Waiting / Granted) and Open System Settings; the chip flips by itself within 2 s of the grant (hot start), and back on a revoke; Screen Recording shown as "Not needed" until M3 |

| Menu-bar item (T34, DD-801) | **M3 Control panel** | a 330 pt panel in the Window material (Frosted by default), 20 pt radius, 14 pt modules: edge picker (Left, Right, Bottom, Top), mode (Reveal, Pinned), Keep Open, Show/Hide Edge Dock, and Settings… and Quit Dedock at the bottom; opens under the status item with the panel nudge (0.175 s); every change applies at once and the panel stays open. Rules below |
| Display fallback (T38, DD-941) | **D2 Hello reveal** | when the dock's display goes away and the dock moves to the built-in display (the main display when there is none, as on a desktop Mac), and again when it moves back, the dock plays one real reveal (0.22 s) on its new display, holds 1.0 s and hides (0.18 s), so you see where it went. Rules below |
| Liquid Glass treatment (T37, `dd.dock.style` = Liquid Glass, §7.1) | **LG4 Adaptive** | two tints on the system glass, dark `@ 0.30` and light `@ 0.42`, chosen from the average brightness behind the capsule when the dock reveals; the running dots and text flip with the tint; the change cross-fades 0.3 s. Rules below |

All 11 app UI surfaces are picked.

**Drag-out confirm (T25, row 43; P2 when built).**

- On drop the tile springs straight back to its slot (0.2 s, instant under Reduce Motion) while the question is open, so the dock never shows a gap; Remove then closes the gap with the normal relayout.
- The panel never takes key focus, so Esc and Return reach it only when it has focus (VoiceOver, Full Keyboard Access). A click elsewhere and the 8 s timeout always mean Keep. With Accessibility granted (T28), a global key monitor makes Esc work everywhere; the panel still does not take focus to get it.
- One question at a time; a second drag-out while one is open is ignored.
- The panel posts an accessibility announcement with its question when it shows.

**H4 state line.** "No windows" when the count is 0. In M2 the count comes from the window list (owner, layer, alpha and size, never titles) and is read when a tile becomes hovered and on running changes; it is approximate and not live while the label is shown until T28's Accessibility window list.

**M3 Control panel rules.**

- *Non-modal (§2.3a).* The panel is a non-activating `NSPanel`, not an `NSMenu`: no menu-tracking loop runs, so the pointer monitors, reveal timers and the dock keep working while it is open. It never starts a modal session; Quit asks nothing.
- *Key focus.* A click on the status item opens it and makes it key without activating Dedock (`.nonactivatingPanel`), so the keyboard works in it while the frontmost app stays frontmost. On close, key focus returns to that app.
- *Closing.* A click elsewhere, Esc, a second click on the status item, Settings… (opens Settings) or Quit. Changing a control does not close it.
- *Dock hold.* While the panel is open the dock does not hide and the pointer timer fallback runs, as for the M1 menu (`docs/plan.md` T18 (2)).
- *Keyboard.* Initial focus is the selected edge. Tab / Shift-Tab move between modules; the arrow keys move within the edge picker and the mode control and select as they move; Space toggles Keep Open and Show/Hide; Return activates the focused button; ⌘, opens Settings and ⌘Q quits while the panel is key. Full Keyboard Access shows the system focus ring on every control.
- *VoiceOver.* The status item reads "Dedock" with the current state as its value (for example "Left edge, Reveal, Keep Open off"); VO-Space opens the panel and VoiceOver moves into it. The panel is announced as "Dedock controls"; the edge picker is a radio group named "Edge" with radios named "Left", "Right", "Bottom", "Top"; the mode is a radio group named "Mode"; Keep Open and Show Edge Dock are switches with their names; Settings… and Quit Dedock are buttons. Each change is announced ("Right edge selected"). Every control has a name (REG-063 rule); an E2E check walks the panel's AX tree.
- *Reduce Motion.* The nudge becomes a 0.15 s fade.

**D2 Hello reveal rules.**

- It plays once per move, after the display set has been stable for 1 s (a dock connect can add and remove displays several times), and at most once every 10 s.
- It does not play at launch, while the screen is locked or asleep, when the new display shows a full-screen Space, or when the dock is already shown (Keep Open, Pinned).
- It is a normal reveal: never key, click-through as usual; if the pointer enters the dock during the 1.0 s hold, the ordinary hide rules take over.
- Reduce Motion: the reduced reveal and hide (§3.4).

**LG4 Adaptive rules.**

- *Until Screen Recording (M3).* The tint follows the average brightness of the wallpaper under the dock's edge on that display, read from the desktop picture file (no permission needed). It is recomputed when the wallpaper, the Space or the display changes, not on every reveal.
- *From M3, with Screen Recording granted* (the grant previews use; the owner decides whether LG4 uses it): one downsampled frame of the area behind the capsule, Dedock's own windows excluded, sampled at reveal; it is never stored and never leaves the Mac. Without the grant, the wallpaper average stays.
- *Hysteresis.* Switch to the light tint above 0.60 relative luminance and back to dark below 0.50, so the tint does not flicker over mid-grey content. The tint never changes while the dock is shown; a change found at reveal cross-fades 0.3 s.
- *Reduce Transparency.* Liquid Glass becomes the solid **Dark** style (`#1C1C1E`), not adaptive.
- *Windows.* When the Window material is Liquid Glass, Settings and the other windows follow the Window appearance (System, Light, Dark), not LG4 sampling.

### 7.3 Rules that stay

- Motion is §3 unchanged; the design pick does not alter any timing.
- Clean-room: values come from screenshots and published measurements; no CoolDock or DockDoor code, strings, artwork, wallpapers or icons are copied. App icons in mocks and tests are the system's own.
- Reference screenshots are not committed to this repo; pixel comparisons use dedock's own captures against the tokens above, plus side-by-side review with the reference pack outside the repo.

---

## 8. Open conflicts carried from the plan

| # | Conflict | Position taken here |
|---|---|---|
| 1 | Running-indicator side: DD-903 AC4 says inner side; `dedock-plan/design-system.md` §9.6 says edge side, "make it a setting" | Default inner side (DD-903 is the P0 acceptance criterion); expose a setting later |
| 2 | `panel.reenter` 0.15 s (animation-spec) vs 0.20 s (plan, measured live) | Token text keeps animation-spec; implement 0.20 s (§3.3 note) |
| 3 | Show delay 120 ms (T3) vs 0.15 s (DD-921); corner exclusion 24 pt (T2) vs 10 pt (DD-923); full-screen delay 400 ms (T4) vs 0.75 s (DD-924) | Use the `ux-patterns.md` values (`docs/plan.md` D-12); the pack stays read-only, so the PRD is not edited |
| 4 | Top edge: DD-902 AC4 says not offered in v1; the first-feature brief makes top-below-menu-bar optional | Grammar supports it (§4.2); ship behind a setting |
| 5 | `motion.reorder` spring bounce 0.15 (plan) vs motion principle M2 "nothing on an edge bounces" | bounce 0 (§3.2) |
| 6 | Pointer-sharing edges (DD-934): the system's push-through hand-off to a nearby device and Reveal mode's push-through answer the same gesture on a wall edge | Decided by the owner (2026-10-16): per-edge setting \"Pointer sharing uses this edge\" applying the shared-edge policy, plus the hand-off hide (`docs/plan.md` T40) |
