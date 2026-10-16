#!/usr/bin/env python3
"""Z1 "Slider with stops" (M1 row 27): the Settings "Dock size" slider drives the live dock.

    z1.py points <ax-tree.jsonl>
        -> "x0 y x1": the slider's knob centre at tile 62 (M) and at 85 (between L and XL), from the
           AXSlider named "Dock size" (10 pt knob inset assumed; a press on the track moves the knob
           there anyway)
    z1.py judge <geom-mid.json> <geom-after.json> <layout.json> <layout-passes-mid>
        -> two lines "<0|1>\\t<detail>":
           live:    mid-drag the tile thickness is off M and between stops, the dock shown, and
                    layout passes happened during the drag;
           snapped: after release the tile thickness is the saved size's stop (48/62/76/92 ± 0.5)
                    and the capsule thickness is tile × (1 + 16/62) ± 1 pt (padding scales 8 × tile/62).
"""
import json, sys

STOPS = {"s": 48, "m": 62, "l": 76, "xl": 92}


def points(tree):
    for l in open(tree):
        e = json.loads(l)
        if e.get("role") == "AXSlider" and e.get("name") == "Dock size" and "x" in e:
            x, y, w, h = e["x"], e["y"], e["w"], e["h"]
            k = lambda v: x + 10 + (v - 48) / (92 - 48) * (w - 20)
            return f"{k(62):.1f} {y + h / 2:.1f} {k(85):.1f}"
    return ""


def sizes(p):
    d = json.load(open(p))["docks"][0]
    t, c = d["tiles"][0]["frame"]["topLeft"], d["capsule"]["topLeft"]
    vertical = d["edge"] in ("left", "right")
    return (t[2] if vertical else t[3]), (c[2] if vertical else c[3]), d.get("state", "?")


def judge(mid, after, layout, passes):
    try:
        mt, mc, ms = sizes(mid)
        at, ac, _ = sizes(after)
        size = json.load(open(layout))["docks"][0].get("appearance", {}).get("size", "?")
    except Exception as ex:
        return [(0, f"GEOM or layout unreadable: {type(ex).__name__}"), (0, "not judged")]
    live = abs(mt - 62) > 1 and min(abs(mt - s) for s in STOPS.values()) > 0.5
    r1 = (int(live and ms == "shown" and passes > 0),
          f"mid-drag: tile {mt:.1f} pt (exp between stops, off 62), capsule {mc:.1f}, dock {ms}; layout passes during the drag: {passes}")
    exp_c = at * (1 + 16 / 62)
    ok = size in STOPS and abs(at - STOPS[size]) <= 0.5 and abs(ac - exp_c) <= 1
    r2 = (int(ok), f"after release: tile {at:.1f} pt, saved size '{size}' ({STOPS.get(size, '?')} pt); capsule {ac:.1f} pt (exp {exp_c:.1f} ± 1)")
    return [r1, r2]


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["points"] and len(a) == 2:
        print(points(a[1]))
    elif a[:1] == ["judge"] and len(a) == 5:
        for ok, d in judge(a[1], a[2], a[3], int(a[4])):
            print(f"{ok}\t{d}")
    else:
        sys.exit("usage: z1.py points <ax-tree.jsonl> | judge <geom-mid.json> <geom-after.json> <layout.json> <passes>")
