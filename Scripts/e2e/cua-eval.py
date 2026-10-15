#!/usr/bin/env python3
"""Evaluates the regress.sh "cua checks" (C1-C7) from the files the cua() step wrote:

    Scripts/e2e/cua-eval.py <cua-dir> <geometry.json> <app-pid> <L|R>

Prints "<check id>\t<0|1>\t<detail>" per check. Inputs: windows.jsonl / tree.jsonl / hit-*.json(l)
from Scripts/e2e/axprobe (which never records another app's role or label, REG-041), front-*.json,
cua-state.json from cua-driver get_window_state.
"""
import json, sys, os
C, geom, pid, side = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
g = json.load(open(geom)); d = g["docks"][0]
tiles = {t["name"]: t["frame"]["topLeft"] for t in d["tiles"]}
def rows(f): return [json.loads(l) for l in open(f) if l.strip()]
res = []
def chk(cid, ok, detail): res.append((f"cua {cid} {side}", int(bool(ok)), detail))
ws = [w for w in rows(f"{C}/windows.jsonl") if w["w"] > 50 and w["h"] > 50]
px, py, pw, ph = d["panel"]["topLeft"]
ok = len(ws) == 1 and ws[0]["layer"] == 24 and ws[0]["onscreen"] and all(abs(a - b) <= 0.5 for a, b in zip((ws[0]["x"], ws[0]["y"], ws[0]["w"], ws[0]["h"]), (px, py, pw, ph)))
tree = rows(f"{C}/tree.jsonl")
# REG-056 (reported, not yet gated): the panel's AX window subrole and label. AXSystemDialog reads
# as "system dialog". The fix pins subrole AXFloatingWindow and description "Edge Dock"; this becomes
# a gate on those values once the fix lands.
wins = [e for e in tree if e.get("depth") == 0 and e.get("role") == "AXWindow"]
wsub = sorted({f"{e.get('subrole') or '-'} '{e.get('label', '')}'" for e in wins})
chk("C1 panel window", ok, f"{len(ws)} window(s); layer {ws[0]['layer'] if ws else '-'} (exp 24); frame {[ws[0][k] for k in ('x','y','w','h')] if ws else '-'} vs GEOM {[px,py,pw,ph]}; AX window subrole/label {', '.join(wsub) or '-'} (REG-056; exp AXFloatingWindow 'Edge Dock' once fixed)")
tl = [e for e in tree if e.get("label") in tiles and e.get("depth", 0) >= 1]
# The AX element may be the icon inside the tile cell (E1: 52 pt icon in a 62x54 cell): require it to
# lie inside the GEOM tile frame and be centred on it (±2 pt), and report the size difference. Lower
# bound: at least MIN_FRAC of the cell in each dimension, so a degenerate (e.g. 1x1 or 0x0) AX frame
# at the centre does not pass.
MIN_FRAC = 0.6
def inside_centred(e, f):
    x, y, w, h = f; ex, ey, ew, eh = (e.get(k, -999) for k in ("x", "y", "w", "h"))
    return ex >= x - 1 and ey >= y - 1 and ex + ew <= x + w + 1 and ey + eh <= y + h + 1 \
        and abs((ex + ew / 2) - (x + w / 2)) <= 2 and abs((ey + eh / 2) - (y + h / 2)) <= 2 \
        and ew >= MIN_FRAC * w and eh >= MIN_FRAC * h
frames_ok = all(any(inside_centred(e, tiles[n]) for e in tl if e["label"] == n) for n in tiles)
sizes = sorted({f"{e.get('w')}x{e.get('h')} in {tiles[e['label']][2]}x{tiles[e['label']][3]}" for e in tl})
chk("C3 tiles in AX tree", len({e["label"] for e in tl}) == len(tiles) and frames_ok, f"{len({e['label'] for e in tl})}/{len(tiles)} tiles labelled with their app name; AX frame inside, centred and >= {MIN_FRAC:.0%} of the GEOM tile: {frames_ok} (AX vs tile size: {', '.join(sizes)})")
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
si = [e for e in tree if e.get("role") == "AXMenuBarItem" and e.get("label") == "dedock"]
chk("C4 status item", len(si) == 1, f"AXMenuBarItem 'dedock': {len(si)}")
fronts = [json.load(open(f"{C}/{f}")) for f in ("front-launch.json", "front-shown.json")]
chk("C5 non-activating", all(f.get("pid") != pid for f in fronts), "frontmost after launch and with the pointer on a shown tile is not Dedock")
hid = rows(f"{C}/hit-hidden.jsonl")
chk("C6 click-through while hidden", hid and all(h["hit"].get("pid") != pid for h in hid), f"{sum(h['hit'].get('pid') != pid for h in hid)}/{len(hid)} tile centres reach the window underneath")
t = json.load(open(f"{C}/hit-shown-tile.json")); o = json.load(open(f"{C}/hit-shown-outside.json"))
first = next(iter(tiles))
chk("C7 shown tile takes the hit", t.get("pid") == pid and t.get("label") == first, f"pointer on '{first}': hit {'Dedock' if t.get('pid') == pid else 'other app'}, label '{t.get('label', '')}'")
try:
    ce = json.load(open(f"{C}/hit-shown-cell.json"))
    chk("C7 tile cell edge stays in the dock", ce.get("pid") == pid,
        f"2 pt inside the '{first}' cell, outside its icon: hit {'Dedock' if ce.get('pid') == pid else 'other app'} ({ce.get('role') or '-'} '{ce.get('label', '')}')")
except Exception as ex:
    chk("C7 tile cell edge stays in the dock", False, f"not probed or unreadable: {type(ex).__name__}")
chk("C7 4 pt outside passes through", o.get("pid") != pid, f"4 pt outside the capsule: hit {'Dedock' if o.get('pid') == pid else 'other app'}")
for r in res: print(f"{r[0]}\t{r[1]}\t{r[2]}")
