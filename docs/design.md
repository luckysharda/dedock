# dedock design guide

Status: **skeleton**. Behaviour, motion and layout grammar are fixed. The visual language is **pending the user's pick** (§7). When a direction is chosen, §7 is replaced by its full token set, and the "visual" cells in §5 are filled from it.

Cited paths are relative to the reference pack, `<pack>/`.

**User decision (binding).** dedock keeps the *features and behaviour* of DockDoor and CoolDock (timings, reveal logic, preview lifecycle). Its *visual design* is new and must not look like either app. Reference screenshots are for comparison only.

**What this guide does not inherit.** `dedock-plan/design-system.md` blends DockDoor's glass language with CoolDock's capsule language (its own preamble says so). Its visual sections are therefore **not** dedock's look: §2 colours, §3 materials (Liquid Glass / Frosted / Solid styles), §4 radii (incl. the 34 / 24 / 18 panel formula and the S/M/L/XL thickness ladder derived from CoolDock's 62 pt tile), §6 elevation, and the look of every §9 component. This guide takes from the plan only behaviour, timing, layout grammar, state and accessibility rules.

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
7. [Visual direction: PENDING USER PICK](#7-visual-direction-pending-user-pick)
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

### 2.3 Click-through (DD-933)

- While `hidden` or `faded`, the dock panel ignores mouse events.
- While shown, hit-testing returns nil outside visible tiles and controls. Test: a click 4 pt outside the container hits the window underneath.
- Interactive at the **start** of a reveal; pass-through at the **start** of a hide (`dedock-inputs/animation-spec.md` §3.1).
- The `NSPanel` frame stays fixed; only the content layer's translation animates (DD-927).

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
5. **Bottom dock over a visible native Dock** reveals above it (DD-912 AC5).
6. **Fixed panel frame.** The `NSPanel` is sized once to dock + label room + shadow; only content moves. Labels draw inside this frame on the screen-centre side, so they never need a second window.
7. **Overflow** (DD-977): Adapt size shrinks tiles to 60 % of `t`, then scrolls along the edge axis.

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
| Status item | template image (a dock on an edge); click opens a standard `NSMenu` |
| Menu (M1, `docs/plan.md` T18) | Show/Hide Edge Dock, Edge ▸ Left / Right / Bottom / Top, Mode ▸ Reveal / Pinned, Keep Dock Open (`pinnedByUser`), Settings… (⌘,), Quit dedock (⌘Q). Later: the ⌃⌥⌘E shortcut (DD-930, M8), Layout menu and Reset Layout (M8), Edit Dock… (DD-976, M9) |
| Look | system `NSMenu` in every direction (native). The direction may only change the status-item glyph. |

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
| Keyboard | every surface reachable by shortcut and from the menu-bar menu; Esc closes; arrow keys move along the edge axis |
| Hit targets | ≥ 28 × 28 pt pointer targets; remove buttons ≥ 18 pt visual with a 28 pt hit area |
| Motor | all dwells adjustable; "Click to reveal" and "Sticky reveal" options (`dedock-plan/ux-patterns.md` §9.3) |

---

## 7. Visual direction: PENDING USER PICK

Pick **one app direction** (A1–A4) and **one Edge Dock sense** (E1–E4). They mix and match; the natural pairing is listed. The chosen pair replaces this section with full tokens (palette, type scale, radii, elevation, component specs, SwiftUI notes).

### 7.1 App-wide directions

| ID | Name | Material | Shape | Type | Accent | Feel |
|---|---|---|---|---|---|---|
| A1 | **Folio** | paper/print: opaque matte paper, ink hairlines, no blur | small 4 pt radii, rectangular labels, "photo-mount" thumbnails | New York titles and numerals, SF Pro body, small-caps eyebrows | green ink `#1F6B4A` / `#5CC893` | calm, editorial, a printed field guide |
| A2 | **Signal** | high-contrast graphic: flat opaque fills, 2 pt borders, no blur, no soft shadow | 0 pt radii, one 6 pt chamfered corner on containers | SF Pro Expanded uppercase labels, SF Mono numerals | acid lime `#D4FF00` (fill with black text) | bold, instrument signage, binary states |
| A3 | **Dusk** | tinted translucent: blur under a heavy indigo/lavender tint, film grain, no refraction rim | edge-fused: square on the anchor side, 20 pt round on the free side; round plates | SF Pro Rounded | rose `#C2255C` / `#FF6B9A` | atmospheric, soft, evening |
| A4 | **Instrument** | matte solid hardware: anodised fills, 1 pt bevel highlight, soft long shadow | machined 10 pt radii, key-shaped tiles, LEDs | SF Pro Condensed labels, SF Pro body | signal orange `#FF5F1F` (fill with dark text; as text `#A8380B`) | tactile, industrial, precise |

### 7.2 Edge Dock senses

| ID | Name | Container | Tiles and indicator | Idle hint | Natural pair |
|---|---|---|---|---|---|
| E1 | **Drawer** | flush to the edge (inset 0), square on the edge side, 22 pt round on the free side | 56 pt plates, label as a tab on the drawer's free edge, 3 × 12 pt bar indicator on the inner side | a 3 × 48 pt lip at the edge | A3 Dusk |
| E2 | **Spine** | no container (stated exception to DD-903 AC5): separate plates threaded on a 2 pt spine line | 52 pt plates, caption tag with a leader line, 6 pt station dot indicator | short ruler ticks along the span | A1 Folio |
| E3 | **Rail** | flat rectangular strip, inset 4 pt, 0 pt radius with one 6 pt chamfer, 2 pt border, cells divided by hairlines | no plates; hover inverts the whole cell; 2 pt full-height bar indicator; mono index digits | a 2 pt hairline along the span | A2 Signal |
| E4 | **Console** | raised instrument module, inset 8 pt, radius 16 = 10 + 6 | key-shaped tiles with bevel, engraved label plate, LED indicator | three dim LEDs at the edge | A4 Instrument |

All four keep §2–§3: reveal 0.22 s decelerating, no overshoot; hide 0.18 s accelerating; reverse in place; labels instant toward the centre; hover by fill/opacity (optional 2 pt lift); fixed panel frame with translating content; Reduce Motion → 0.15 s fade.

### 7.3 What the chosen pair must deliver

1. Light and dark palettes as dynamic `NSColor` providers, plus Increase Contrast and Reduce Transparency variants.
2. Type scale mapped to SwiftUI text styles.
3. Container, tile, label, indicator, folder, widget, idle-hint and edit-mode specs at the default `t` = 56, with S/L variants.
4. Preview panel, switcher and settings specs (for later milestones).
5. An HTML mockup that matches the tokens, checked side by side with the reference screenshots for difference, not similarity.

---

## 8. Open conflicts carried from the plan

| # | Conflict | Position taken here |
|---|---|---|
| 1 | Running-indicator side: DD-903 AC4 says inner side; `dedock-plan/design-system.md` §9.6 says edge side, "make it a setting" | Default inner side (DD-903 is the P0 acceptance criterion); expose a setting later |
| 2 | `panel.reenter` 0.15 s (animation-spec) vs 0.20 s (plan, measured live) | Token text keeps animation-spec; implement 0.20 s (§3.3 note) |
| 3 | Show delay 120 ms (T3) vs 0.15 s (DD-921); corner exclusion 24 pt (T2) vs 10 pt (DD-923); full-screen delay 400 ms (T4) vs 0.75 s (DD-924) | Use the `ux-patterns.md` values (`docs/plan.md` D-12); the pack stays read-only, so the PRD is not edited |
| 4 | Top edge: DD-902 AC4 says not offered in v1; the first-feature brief makes top-below-menu-bar optional | Grammar supports it (§4.2); ship behind a setting |
| 5 | `motion.reorder` spring bounce 0.15 (plan) vs motion principle M2 "nothing on an edge bounces" | bounce 0 (§3.2) |
