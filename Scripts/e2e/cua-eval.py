#!/usr/bin/env python3
"""Evaluates the regress.sh "cua checks" (C1-C7) from the files the cua() step wrote:

    Scripts/e2e/cua-eval.py <cua-dir> <geometry.json> <app-pid> <L|R>

Prints "<check id>\t<0|1>\t<detail>" per check. Inputs: windows.jsonl / tree.jsonl / hit-*.json(l)
from Scripts/e2e/axprobe (which never records another app's role or label, REG-041), front-*.json,
cua-state.json from cua-driver get_window_state.
"""
import json, sys, os
C, geom, pid, side = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
# GEOM taken as a pair with the window list / AX tree (regress.sh cua step); else the given file.
paired = os.path.exists(f"{C}/geom-pair.json")
g = json.load(open(f"{C}/geom-pair.json" if paired else geom)); d = g["docks"][0]
notes = [l.strip() for l in open(f"{C}/pair.txt")] if os.path.exists(f"{C}/pair.txt") else []
pair_note = (" [" + "; ".join(notes) + "]") if notes else ""
tiles = {t["name"]: t["frame"]["topLeft"] for t in d["tiles"]}
def rows(f): return [json.loads(l) for l in open(f) if l.strip()]
def first_line(f):
    try: return open(f).readline().strip()
    except OSError: return "0 not recorded"
res = []
def chk(cid, ok, detail): res.append((f"cua {cid} {side}", int(bool(ok)), detail))
ws = [w for w in rows(f"{C}/windows.jsonl") if w["w"] > 50 and w["h"] > 50]
px, py, pw, ph = d["panel"]["topLeft"]
ok = len(ws) == 1 and ws[0]["layer"] == 24 and ws[0]["onscreen"] and all(abs(a - b) <= 0.5 for a, b in zip((ws[0]["x"], ws[0]["y"], ws[0]["w"], ws[0]["h"]), (px, py, pw, ph)))
tree = rows(f"{C}/tree.jsonl")
# REG-056: the panel's AX identity. It reported AXSystemDialog (VoiceOver: "system dialog") with no
# name; the fix pins role AXWindow, subrole AXFloatingWindow, description "Edge Dock".
PANEL_SUBROLE, PANEL_LABEL = "AXFloatingWindow", "Edge Dock"
wins = [e for e in tree if e.get("depth") == 0 and e.get("role") == "AXWindow"]
wsub = sorted({f"{e.get('subrole') or '-'} '{e.get('label', '')}'" for e in wins})
chk("C1 panel window", ok, f"{len(ws)} window(s); layer {ws[0]['layer'] if ws else '-'} (exp 24); frame {[ws[0][k] for k in ('x','y','w','h')] if ws else '-'} vs GEOM {[px,py,pw,ph]}{' (paired snapshot)' if paired else ''}{pair_note}")
chk("C1 REG-056 panel AX identity", len(wins) == 1 and wins[0].get("subrole") == PANEL_SUBROLE and wins[0].get("label") == PANEL_LABEL,
    f"AX window subrole/label: {', '.join(wsub) or 'no AXWindow'} (exp AXWindow {PANEL_SUBROLE} '{PANEL_LABEL}')")
tl = [e for e in tree if e.get("label") in tiles and e.get("depth", 0) >= 1]
# The AX element may be the icon inside the tile cell (E1: 52 pt icon in a 62x54 cell): require it to
# lie inside the GEOM tile frame and be centred on it (±2 pt), and report the size difference. Lower
# bound: at least MIN_FRAC of the cell in each dimension, so a degenerate (e.g. 1x1 or 0x0) AX frame
# at the centre does not pass.
MIN_FRAC = 0.8   # E1: 52/62 = 0.84 passes; a half-size frame does not (review of #22)
def inside_centred(e, f):
    x, y, w, h = f; ex, ey, ew, eh = (e.get(k, -999) for k in ("x", "y", "w", "h"))
    return ex >= x - 1 and ey >= y - 1 and ex + ew <= x + w + 1 and ey + eh <= y + h + 1 \
        and abs((ex + ew / 2) - (x + w / 2)) <= 2 and abs((ey + eh / 2) - (y + h / 2)) <= 2 \
        and ew >= MIN_FRAC * w and eh >= MIN_FRAC * h
# REG-061 (DEDOCK_REG061=1, once the fix is in the build): the tile's AX element IS the whole cell
# (the click target), so its frame must equal the GEOM tile frame within 1 pt.
REG061 = os.environ.get("DEDOCK_REG061") == "1"
def whole_cell(e, f):
    return all(abs(a - b) <= 1 for a, b in zip((e.get(k, -999) for k in ("x", "y", "w", "h")), f))
fit = whole_cell if REG061 else inside_centred
frames_ok = all(any(fit(e, tiles[n]) for e in tl if e["label"] == n) for n in tiles)
fit_text = "AX frame = GEOM cell ±1 pt (REG-061)" if REG061 else f"AX frame inside, centred and >= {MIN_FRAC:.0%} of the GEOM tile"
sizes = sorted({f"{e.get('w')}x{e.get('h')} in {tiles[e['label']][2]}x{tiles[e['label']][3]}" for e in tl})
chk("C3 tiles in AX tree", len({e["label"] for e in tl}) == len(tiles) and frames_ok, f"{len({e['label'] for e in tl})}/{len(tiles)} tiles labelled with their app name; {fit_text}: {frames_ok} (AX vs tile size: {', '.join(sizes)})")
roles = sorted({e.get("role") for e in tl})
chk("C3 REG-040 tiles are buttons", tl and all(e.get("role") == "AXButton" for e in tl), f"tile roles: {roles} (exp AXButton)")
acts = sorted({a for e in tl for a in e.get("actions", [])})
chk("C3 REG-040 tiles pressable", tl and all("AXPress" in e.get("actions", []) for e in tl), f"tile AX actions: {acts or 'none'} (exp AXPress on every tile)")
try:
    st = json.load(open(f"{C}/cua-state.json")); els = (st.get("structuredContent") or st).get("elements", [])
    seen = {e.get("label") for e in els} & set(tiles)
    chk("C2 cua-driver sees tiles", len(seen) == len(tiles), f"cua-driver get_window_state: {len(els)} elements, {len(seen)}/{len(tiles)} tiles")
except Exception as ex:
    chk("C2 cua-driver sees tiles", False, f"cua-driver output unreadable: {type(ex).__name__}")
si = [e for e in tree if e.get("role") == "AXMenuBarItem" and (e.get("label") or "").lower() == "dedock"]  # "dedock" or "Dedock"
chk("C4 status item", len(si) == 1, f"AXMenuBarItem 'dedock' (any case): {len(si)}")
fronts = [json.load(open(f"{C}/{f}")) for f in ("front-launch.json", "front-shown.json")]
chk("C5 non-activating", all(f.get("pid") != pid for f in fronts), "frontmost after launch and with the pointer on a shown tile is not Dedock")
hid = rows(f"{C}/hit-hidden.jsonl")
chk("C6 click-through while hidden", hid and all(h["hit"].get("pid") != pid for h in hid), f"{sum(h['hit'].get('pid') != pid for h in hid)}/{len(hid)} tile centres reach the window underneath")
t = json.load(open(f"{C}/hit-shown-tile.json")); o = json.load(open(f"{C}/hit-shown-outside.json"))
first = next(iter(tiles))
chk("C7 shown tile takes the hit", t.get("pid") == pid and t.get("label") == first, f"pointer on '{first}': hit {'Dedock' if t.get('pid') == pid else 'other app'}, label '{t.get('label', '')}'")
try:
    ce = json.load(open(f"{C}/hit-shown-cell.json"))
    # REG-061: once the tile's AX element is the whole cell, the cell edge must find the tile itself
    # (AXButton with its label), not just "somewhere in the dock" (the content AXGroup today).
    ok = ce.get("pid") == pid and (not REG061 or (ce.get("role") == "AXButton" and ce.get("label") == first))
    chk("C7 tile cell edge stays in the dock", ok,
        f"2 pt inside the '{first}' cell, outside its icon: hit {'Dedock' if ce.get('pid') == pid else 'other app'} ({ce.get('role') or '-'} '{ce.get('label', '')}')"
        + (" (REG-061: exp AXButton '" + first + "')" if REG061 else " (REG-061 pending: role reported, not gated)"))
except Exception as ex:
    chk("C7 tile cell edge stays in the dock", False, f"not probed or unreadable: {type(ex).__name__}")
gate_note = first_line(f"{C}/gate-outside.txt") if os.path.exists(f"{C}/gate-outside.txt") else ""
chk("C7 4 pt outside passes through", o.get("pid") != pid, f"4 pt outside the capsule: hit {'Dedock' if o.get('pid') == pid else 'other app'}" + (f"; {gate_note}" if gate_note else ""))
# C9: dd.dock.style in GEOM (Settings builds): the harness seed uses the default, Dark Glass, whose
# material is hudWindow ('solid' under Reduce Transparency). SKIP when the build writes no style.
MATERIALS = {"darkGlass": {"hudWindow", "solid"}, "black": {"hudWindow", "solid"}, "lightGlass": {"popover", "solid"}}
if "style" not in d:
    res.append((f"cua C9 dock style tokens {side}", "skip", "this build writes no dd.dock.style to GEOM"))
else:
    chk("C9 dock style tokens", d.get("style") == "darkGlass" and d.get("material") in MATERIALS["darkGlass"],
        f"GEOM style {d.get('style')!r}, material {d.get('material')!r} (exp the default darkGlass / hudWindow)")
SETTINGS_SIDE = side == "L"   # C8 and the C9 live switch run once per run, on the left launch
if not SETTINGS_SIDE:
    pass
elif not os.path.exists(f"{C}/c9-switch.txt"):
    res.append((f"cua C9 style switch in Settings reaches GEOM {side}", "skip", "pending: run with settings=1 on a build with the Style setting"))
else:
    sw = first_line(f"{C}/c9-switch.txt")
    try: gs = json.load(open(f"{C}/geom-style.json"))["docks"][0]
    except Exception: gs = {}
    chk("C9 style switch in Settings reaches GEOM", sw.startswith("1 ") and gs.get("style") == "lightGlass" and gs.get("material") in MATERIALS["lightGlass"],
        f"pressed 'Light Glass': {sw[2:]}; GEOM style {gs.get('style')!r}, material {gs.get('material')!r} (exp lightGlass / popover)")
# C8 (regress.sh settings=1): the Settings window, its labels, and the editing hold. Without the
# files (no Settings in the build, or settings=0) every C8 row is SKIP, never a PASS.
C8 = ["C8 Settings window opens", "C8 settings controls labelled", "C8 dock held shown while Settings is open",
      "C8 closing Settings releases the hold"]
SETTINGS_TITLE = "Dedock Settings"
CONTROLS = {"AXButton", "AXCheckBox", "AXRadioButton", "AXSlider", "AXPopUpButton", "AXMenuButton",
            "AXTextField", "AXComboBox", "AXIncrementor", "AXSwitch", "AXSegmentedControl"}
if not SETTINGS_SIDE:
    pass
elif not os.path.exists(f"{C}/settings-tree.jsonl"):
    for cid in C8: res.append((f"cua {cid} {side}", "skip", "pending: run with settings=1 on a build with the Settings window"))
else:
    st = rows(f"{C}/settings-tree.jsonl")
    # the Settings window's subtree: from its depth-0 AXWindow row to the next depth-0 row
    sub, inside = [], False
    for e in st:
        if e.get("depth") == 0: inside = e.get("role") == "AXWindow" and e.get("label") == SETTINGS_TITLE
        if inside: sub.append(e)
    wins = [w for w in rows(f"{C}/settings-windows.jsonl") if w.get("layer") == 0 and w.get("onscreen") and w["w"] > 100]
    op = first_line(f"{C}/c8-open.txt")
    chk("C8 Settings window opens", bool(sub) and len(wins) >= 1 and op.startswith("1 "),
        f"AXWindow '{SETTINGS_TITLE}': {'yes' if sub else 'no'}; normal-level windows on screen: {len(wins)}; debug.command openSettings ok: {'yes' if 'openSettings' in op and op.startswith('1') else op[2:60]}")
    # system parts with no name of their own: window buttons and the scroller's arrows/pages
    SYSTEM = {"AXCloseButton", "AXMinimizeButton", "AXZoomButton", "AXFullScreenButton",
              "AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"}
    ctrls = [e for e in sub if e.get("role") in CONTROLS and e.get("subrole") not in SYSTEM]
    bare = [e.get("role") for e in ctrls if not (e.get("name", e.get("label")) or "").strip()]  # a value is not a name
    chk("C8 settings controls labelled", bool(ctrls) and not bare,
        f"{len(ctrls)} controls, {len(bare)} without a label" + (f" ({', '.join(sorted(set(bare)))})" if bare else ""))
    chk("C8 dock held shown while Settings is open", op.startswith("1 "), op[2:])
    cl = first_line(f"{C}/c8-close.txt")
    gone = not any(w.get("layer") == 0 and w.get("onscreen") and w["w"] > 100 for w in rows(f"{C}/settings-windows-after.jsonl")) \
        if os.path.exists(f"{C}/settings-windows-after.jsonl") else False
    chk("C8 closing Settings releases the hold", cl.startswith("1 ") and gone, f"window closed: {gone}; {cl[2:]}")
for r in res: print(f"{r[0]}\t{r[1]}\t{r[2]}")
