#!/usr/bin/env python3
"""Checks a GEOM file (Tests/E2E/contract.md §4) against the M1 layout and trigger rules
(docs/evaluation.md §3.2, §3.5; docs/plan.md §6 fixed values).

    Scripts/e2e/geom-check.py <geometry.json> [layout=<layout.json>] [inset=6] [padding=6] [gap=8] [zone=3] [span=40] [corner=24]

With layout=, the expected inset comes from the seeded layout (docks[0].placement.edgeGapPt)
unless inset= is given; padding and gap come from docs/design.md tokens via the arguments.

Prints PASS/FAIL/INFO lines; exit 1 if any FAIL. Coordinates are top-left global points.
"""
import json
import sys

args = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
num = lambda k, d: float(args.get(k, d))
inset_default = 6
if "layout" in args:
    try:
        inset_default = json.load(open(args["layout"]))["docks"][0]["placement"]["edgeGapPt"]
    except (OSError, KeyError, IndexError, ValueError):
        print("WARN layout has no docks[0].placement.edgeGapPt; inset defaults to 6")
INSET, PAD, GAP, ZONE, SPAN, CORNER = (num("inset", inset_default), num("padding", 6), num("gap", 8),
                                       num("zone", 3), num("span", 40), num("corner", 24))
g = json.load(open(sys.argv[1]))
fails = 0


def gate(ok, label, detail):
    global fails
    print(f"{'PASS' if ok else 'FAIL'} {label}: {detail}")
    fails += 0 if ok else 1


def tl(r):  # [x, y, w, h] top-left
    return r["topLeft"]


near = lambda a, b, tol=0.51: abs(a - b) <= tol
screens = {s["id"]: s for s in g["screens"]}

for d in g["docks"]:
    s = screens[d["screen"]]
    fx, fy, fw, fh = tl(s["frame"])
    vx, vy, vw, vh = tl(s["visibleFrame"])
    cx, cy, cw, ch = tl(d["capsule"])
    edge, side = d["edge"], d["edge"] in ("left", "right")
    tag = f"{d['id']} {edge}"
    print(f"INFO {tag}: mode={d['mode']} state={d['state']} capsule={tl(d['capsule'])} visibleFrame={tl(s['visibleFrame'])}")

    # Placement: inset from the physical edge, centred on visibleFrame along the edge.
    if edge == "left":
        gate(near(cx - fx, INSET), f"{tag} edge inset", f"{cx - fx} pt (exp {INSET})")
    elif edge == "right":
        gate(near(fx + fw - (cx + cw), INSET), f"{tag} edge inset", f"{fx + fw - (cx + cw)} pt (exp {INSET})")
    elif edge == "bottom":
        gate(near(vy + vh - (cy + ch), INSET), f"{tag} edge inset (from visibleFrame)", f"{vy + vh - (cy + ch)} pt (exp {INSET})")
    else:
        gate(near(cy - vy, INSET), f"{tag} edge inset (below menu bar)", f"{cy - vy} pt (exp {INSET})")
    along_c = cy + ch / 2 if side else cx + cw / 2
    along_v = vy + vh / 2 if side else vx + vw / 2
    gate(near(along_c, along_v), f"{tag} centred on visibleFrame", f"capsule centre {along_c}, visibleFrame centre {along_v}")
    inside = cx >= vx - 0.01 and cy >= vy - 0.01 and cx + cw <= vx + vw + 0.01 and cy + ch <= vy + vh + 0.01
    gate(inside or edge in ("left", "right") and cy >= vy and cy + ch <= vy + vh,
         f"{tag} inside visibleFrame (never under the menu bar or native Dock)", f"capsule {tl(d['capsule'])}")
    maxlen = (vh if side else vw) - 32
    gate((ch if side else cw) <= maxlen + 0.01, f"{tag} max length", f"{ch if side else cw} ≤ visible length − 32 = {maxlen}")
    whole = all(float(v).is_integer() for v in tl(d["capsule"]) + tl(d["panel"]))
    gate(whole, f"{tag} pixel-aligned frames (1x display)", f"capsule {tl(d['capsule'])}, panel {tl(d['panel'])}")

    # Layout grammar: thickness, padding, gap, flow order.
    thick = cw if side else ch
    tiles = d["tiles"]
    for t in tiles:
        tx, ty, tw, th = tl(t["frame"])
        tt = tw if side else th
        gate(near(tt, thick - 2 * PAD), f"{tag} tile {t['id']} thickness", f"{tt} = capsule {thick} − 2×{PAD}")
        hr = tl(t.get("hitRect", t["frame"]))
        gate(hr == tl(t["frame"]), f"{tag} tile {t['id']} hit rect = target frame", f"{hr}")
    if tiles:
        pos = [tl(t["frame"])[1] if side else tl(t["frame"])[0] for t in tiles]
        lens = [tl(t["frame"])[3] if side else tl(t["frame"])[2] for t in tiles]
        gaps = [pos[i + 1] - (pos[i] + lens[i]) for i in range(len(pos) - 1)]
        gate(all(near(x, GAP) for x in gaps), f"{tag} tile gap", f"{gaps} (exp {GAP})")
        start = cy if side else cx
        end = (cy + ch) if side else (cx + cw)
        gate(near(pos[0] - start, PAD) and near(end - (pos[-1] + lens[-1]), PAD), f"{tag} end padding",
             f"{pos[0] - start} / {end - (pos[-1] + lens[-1])} (exp {PAD})")
        gate(pos == sorted(pos), f"{tag} flow order", "model order = visual order (top→bottom / leading→trailing)")

    # Trigger zones: at least one (an empty list means the dock can't be revealed from this edge,
    # REG-065), on the physical edge, thickness, span = content ± 40, corner exclusion.
    gate(bool(d.get("zones")), f"{tag} has a trigger zone", f"{len(d.get('zones', []))} zone(s)")
    for z in d.get("zones", []):
        zx, zy, zw, zh = tl(z["rect"])
        ztag = f"{tag} zone {z['id']} ({z['kind']})"
        if edge == "left":
            gate(near(zx, fx) and near(zw, ZONE), f"{ztag} on physical edge", f"x={zx} w={zw} (exp x={fx} w={ZONE})")
        elif edge == "right":
            gate(near(zx + zw, fx + fw) and near(zw, ZONE), f"{ztag} on physical edge", f"x={zx}..{zx + zw} (exp ..{fx + fw}, w={ZONE})")
        elif edge == "bottom":
            gate(near(zy + zh, fy + fh) and near(zh, ZONE), f"{ztag} on physical edge", f"y={zy}..{zy + zh}")
        else:
            gate(near(zy, fy) and near(zh, ZONE), f"{ztag} on physical edge", f"y={zy} h={zh}")
        if side:
            span_ok = near(zy, max(cy - SPAN, fy + CORNER)) and near(zy + zh, min(cy + ch + SPAN, fy + fh - CORNER))
            gate(span_ok, f"{ztag} span = capsule ± {SPAN}, clipped by {CORNER} pt corners", f"y {zy}..{zy + zh} vs capsule {cy}..{cy + ch}")
            gate(zy >= vy - 0.01, f"{ztag} below the menu bar", f"zone top {zy} ≥ visibleFrame top {vy}")
        elif edge == "top":
            # x-18: the content span ± 40 MINUS status items (and a notch): one or more strips, each inside it
            lo, hi = max(cx - SPAN, fx + CORNER), min(cx + cw + SPAN, fx + fw - CORNER)
            gate(zx >= lo - 0.51 and zx + zw <= hi + 0.51, f"{ztag} inside the content span ± {SPAN} (minus status items)", f"x {zx}..{zx + zw} within {lo}..{hi}")
        else:
            # bottom: content span ± 40; beside the native Dock (REG-065) the whole edge minus the Dock's
            # footprint and the corners. Strips stay inside the corners and off the Dock's footprint.
            nd = (d.get("nativeDock") or s.get("nativeDock") or {}).get("rect")
            gate(zx >= fx + CORNER - 0.51 and zx + zw <= fx + fw - CORNER + 0.51, f"{ztag} inside the {CORNER} pt corners", f"x {zx}..{zx + zw}")
            if nd:
                nx, ny, nw, nh = tl(nd)
                gate(zx + zw <= nx + 0.51 or zx >= nx + nw - 0.51, f"{ztag} off the native Dock's footprint", f"x {zx}..{zx + zw} vs Dock {nx}..{nx + nw}")
            else:
                span_ok = near(zx, max(cx - SPAN, fx + CORNER)) and near(zx + zw, min(cx + cw + SPAN, fx + fw - CORNER))
                gate(span_ok, f"{ztag} span = capsule ± {SPAN}, clipped by {CORNER} pt corners", f"x {zx}..{zx + zw} vs capsule {cx}..{cx + cw}")
    if edge == "bottom":
        nd = (d.get("nativeDock") or s.get("nativeDock") or {}).get("rect")
        if nd:
            nx, ny, nw, nh = tl(nd)
            zl = [tl(z["rect"]) for z in d.get("zones", [])]
            left_ok, right_ok = any(r[0] + r[2] <= nx + 0.51 for r in zl), any(r[0] >= nx + nw - 0.51 for r in zl)
            gate(left_ok and right_ok, f"{tag} zone reachable beside the native Dock (REG-065)",
                 f"strips left of the Dock: {sum(r[0] + r[2] <= nx + 0.51 for r in zl)}, right: {sum(r[0] >= nx + nw - 0.51 for r in zl)}")
        else:
            print(f"INFO {tag}: GEOM has no nativeDock footprint; 'zone reachable beside the native Dock' needs it")

sys.exit(1 if fails else 0)
