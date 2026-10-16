#!/usr/bin/env python3
"""H4 hover label (M1 row 10) and row 20 (no relayout while the pointer moves): probe points and judging.

The label is AX-hidden (the tile's button carries name and state), so it is read with on-device OCR
(Scripts/e2e/ocr.swift) from a capture of Dedock's OWN panel window (screencapture -l <window id>).

    h4.py plan <geometry.json>
        -> "edge along ax ay fx fy wx wy" + the sweep: one "x y" pair per tile centre, in order.
           a: the first app tile's centre, f: the first folder tile's centre (or the second tile's
           when there is no folder), w: a point well away from the dock.
    h4.py judge <geometry.json> <window.json> <ocr-a.jsonl> <ocr-f.jsonl> <ax-tree.jsonl> <side>
        -> "H4 hover label <side>\\t<0|1>\\t<detail>": for each hovered tile, its name and its
           state ("Not running", "Running", "Hidden", "Folder", from GEOM) are recognised in the
           panel capture on the screen-centre side of the capsule; no AX static text carries a tile
           name (the label is AX-hidden).
"""
import json, sys

STATE = {"none": "Not running", "running": "Running", "frontmost": "Running", "hidden": "Hidden"}


def dock(geom):
    return json.load(open(geom))["docks"][0]


def pick(d):
    apps = [t for t in d["tiles"] if t.get("kind") == "app"]
    folders = [t for t in d["tiles"] if t.get("kind") == "folder"]
    a = apps[0] if apps else d["tiles"][0]
    f = folders[0] if folders else next(t for t in d["tiles"] if t is not a)
    return a, f


def centre(t):
    x, y, w, h = t["frame"]["topLeft"]
    return (x + w / 2, y + h / 2)


def expected(t):
    return "Folder" if t.get("kind") == "folder" else STATE.get(t.get("running", "none"), "Not running")


def plan(geom):
    d = dock(geom)
    e, (x, y, w, h) = d["edge"], d["capsule"]["topLeft"]
    zs = [z["rect"]["topLeft"] for z in d.get("zones", [])]
    vertical = e in ("left", "right")
    if zs:
        z = max(zs, key=lambda r: r[3] if vertical else r[2])
        along = int(z[1] + z[3] / 2) if vertical else int(z[0] + z[2] / 2)
    else:
        along = int(y + h / 2) if vertical else int(x + w / 2)
    a, f = pick(d)
    ca, cf = centre(a), centre(f)
    away = {"left": (x + w + 400, ca[1]), "right": (x - 400, ca[1]), "bottom": (ca[0], y - 400), "top": (ca[0], y + h + 400)}[e]
    out = [e, str(along)] + [f"{v:.1f}" for v in (*ca, *cf, *away)]
    for t in d["tiles"]:
        out += [f"{v:.1f}" for v in centre(t)]
    return " ".join(out)


def judge(geom, window, ocr_a, ocr_f, tree, side):
    d = dock(geom)
    e, (cx, cy, cw, ch) = d["edge"], d["capsule"]["topLeft"]
    try:
        win = json.load(open(window))
    except (OSError, ValueError):
        return 0, "no panel window recorded"
    centre_side = {"left": lambda p: p[0] > cx + cw, "right": lambda p: p[0] < cx,
                   "bottom": lambda p: p[1] < cy, "top": lambda p: p[1] > cy + ch}[e]
    notes, ok = [], True
    for t, f in zip(pick(d), (ocr_a, ocr_f)):
        try:
            lines = [json.loads(l) for l in open(f) if l.strip()]
        except OSError:
            lines = []
        def where(word):
            for l in lines:
                if word.lower() in l["text"].lower():
                    s = l["iw"] / win["w"]  # pixels per point
                    p = (win["x"] + (l["x"] + l["w"] / 2) / s, win["y"] + (l["y"] + l["h"] / 2) / s)
                    return p, centre_side(p)
            return None, False
        want = expected(t)
        pn, sn = where(t["name"])
        ps, ss = where(want)
        good = bool(pn and ps and sn and ss)
        ok &= good
        notes.append(f"'{t['name']}': name {'on the centre side' if sn else ('found, wrong side' if pn else 'not found')}, "
                     f"state '{want}' {'on the centre side' if ss else ('found, wrong side' if ps else 'not found')}")
    names = {t["name"] for t in d["tiles"]}
    try:
        st = [json.loads(l) for l in open(tree) if l.strip()]
    except OSError:
        st = []
    leaked = [n for n in names for x in st if x.get("role") == "AXStaticText" and n in (x.get("label") or "")]
    ok &= not leaked
    notes.append(f"AX static text with a tile name while hovering: {len(leaked)} (exp 0: the label is AX-hidden)")
    return int(ok), "; ".join(notes)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["plan"] and len(a) == 2:
        print(plan(a[1]))
    elif a[:1] == ["judge"] and len(a) == 7:
        ok, detail = judge(*a[1:])
        print(f"H4 hover label {a[6]}\t{ok}\t{detail}")
    else:
        sys.exit("usage: h4.py plan <geometry.json> | judge <geometry.json> <window.json> <ocr-a.jsonl> <ocr-f.jsonl> <ax-tree.jsonl> <side>")
