#!/usr/bin/env python3
"""T25 drag-out to remove (evaluation row 43, design §2.3a): probe points and judging.

    t25.py plan <geometry.json> <layout.json> <tile-index>
        -> "edge along tx ty dx dy px py hide_ms dwell_ms id title" (top-left points; the title last,
           it has spaces): reveal at the middle of the widest zone strip, the tile's centre t, the
           drop point d (hysteresis + 120 pt inward from the capsule's inner side, at the tile),
           and p, a point on the capsule's own padding beside the tile (Dedock's window, no tile:
           the harness-owned "click elsewhere").
    t25.py ids <layout.json>      -> the item ids of the first profile, one line
    t25.py geomids <geometry.json> -> the tile ids in GEOM, one line
"""
import json, sys


def plan(geom, layout, k):
    d = json.load(open(geom))["docks"][0]
    rv = json.load(open(layout))["docks"][0].get("reveal", {})
    hyst = float(rv.get("hysteresisPt", 16))
    e, (x, y, w, h) = d["edge"], d["capsule"]["topLeft"]
    t = d["tiles"][k]
    tx, ty, tw, th = t["frame"]["topLeft"]
    c = (tx + tw / 2, ty + th / 2)
    zs = [z["rect"]["topLeft"] for z in d.get("zones", [])]
    vertical = e in ("left", "right")
    if zs:
        z = max(zs, key=lambda r: r[3] if vertical else r[2])
        along = int(z[1] + z[3] / 2) if vertical else int(z[0] + z[2] / 2)
    else:
        along = int(y + h / 2) if vertical else int(x + w / 2)
    off = hyst + 120
    drop = {"left": (x + w + off, c[1]), "right": (x - off, c[1]), "bottom": (c[0], y - off), "top": (c[0], y + h + off)}[e]
    # the capsule's padding on its inner side, 3 pt in from the capsule edge, at the tile: inside
    # Dedock's window, outside every tile cell
    pad = {"left": (x + w - 3, c[1]), "right": (x + 3, c[1]), "bottom": (c[0], y + 3), "top": (c[0], y + h - 3)}[e]
    if any(u["frame"]["topLeft"][0] <= pad[0] <= u["frame"]["topLeft"][0] + u["frame"]["topLeft"][2] and
           u["frame"]["topLeft"][1] <= pad[1] <= u["frame"]["topLeft"][1] + u["frame"]["topLeft"][3] for u in d["tiles"]):
        sys.exit("t25: the padding point falls in a tile cell")
    f = lambda v: f"{v:.1f}"
    title = f"Remove “{t['name']}” from the Edge Dock?"
    return " ".join([e, str(along), f(c[0]), f(c[1]), f(drop[0]), f(drop[1]), f(pad[0]), f(pad[1]),
                     str(int(rv.get("hideDelayMs", 400))), str(int(d.get("showDwellMs", 300))), t["id"], title])


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["plan"] and len(a) == 4:
        print(plan(a[1], a[2], int(a[3])))
    elif a[:1] == ["ids"] and len(a) == 2:
        print(" ".join(i["id"] for i in json.load(open(a[1]))["profiles"][0]["items"]))
    elif a[:1] == ["geomids"] and len(a) == 2:
        print(" ".join(t["id"] for t in json.load(open(a[1]))["docks"][0]["tiles"]))
    else:
        sys.exit("usage: t25.py plan <geometry.json> <layout.json> <tile-index> | ids <layout.json> | geomids <geometry.json>")
