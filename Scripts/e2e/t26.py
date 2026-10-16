#!/usr/bin/env python3
"""T26 separators and spacers, SP3 Islands (DD-966): GEOM rows and the gap probe points.

The run seeds, in its own data dir: Calculator, a spacer, TextEdit, a separator, Notes
(regress.sh t26=1). A separator splits the dock into two capsules 8 pt apart that are still ONE
dock (one zone, one reveal, one click-through region); a spacer is half an app cell of empty glass.

    t26.py geom <geometry.json>
        -> two rows "<id>\\t<0|1>\\t<detail>":
           islands: 2 islands, the gap between them 8 ± 0.5 pt, the capsule = their union, one zone;
           spacer:  the spacer's cell is half an app cell (appCellLength / 2 ± 0.5) along the axis.
    t26.py gap <geometry.json>
        -> "edge along gx gy ax ay bx by wx wy": the reveal point, the island gap's midpoint g, the
           centres of the tiles on either side (a, b) and a point well away from the dock.
"""
import json, sys

SPACER, SEPARATOR = "s-spacer", "s-separator"


def dock(geom):
    return json.load(open(geom))["docks"][0]


def tl(r):
    return r["topLeft"] if isinstance(r, dict) else r


def axis(d):
    return d["edge"] in ("left", "right")  # vertical dock: islands stack along y


def geom_rows(geom):
    d = dock(geom)
    v = axis(d)
    isl = sorted((tl(r) for r in d.get("islands", [])), key=lambda r: r[1] if v else r[0])
    cap = tl(d["capsule"])
    zones = d.get("zones", [])
    rows = []
    if len(isl) == 2:
        a, b = isl
        gap = (b[1] - (a[1] + a[3])) if v else (b[0] - (a[0] + a[2]))
        lo = min(r[1] if v else r[0] for r in isl)
        hi = max((r[1] + r[3]) if v else (r[0] + r[2]) for r in isl)
        span = (cap[1], cap[1] + cap[3]) if v else (cap[0], cap[0] + cap[2])
        union_ok = abs(lo - span[0]) <= 0.5 and abs(hi - span[1]) <= 0.5
        ok = abs(gap - 8) <= 0.5 and union_ok and len(zones) == 1
        rows.append(("T26 separator makes two islands 8 pt apart, one dock", int(ok),
                     f"islands: 2; gap {gap:.1f} pt (exp 8); capsule = their union: {'yes' if union_ok else 'no'}; trigger zones: {len(zones)} (exp 1)"))
    else:
        rows.append(("T26 separator makes two islands 8 pt apart, one dock", 0, f"islands in GEOM: {len(isl)} (exp 2)"))
    tiles = {t["id"]: tl(t["frame"]) for t in d.get("tiles", [])}
    apps = [tl(t["frame"]) for t in d.get("tiles", []) if t.get("kind") == "app"]
    cell = (apps[0][3] if v else apps[0][2]) if apps else None
    if SPACER in tiles and cell:
        s = tiles[SPACER]
        length = s[3] if v else s[2]
        rows.append(("T26 spacer is half an app cell", int(abs(length - cell / 2) <= 0.5),
                     f"spacer cell {length:.1f} pt along the dock (exp {cell / 2:.1f}, half of {cell:.1f})"))
    else:
        rows.append(("T26 spacer is half an app cell", 0, "the spacer is not in GEOM tiles"))
    return rows


def gap_points(geom):
    d = dock(geom)
    v = axis(d)
    isl = sorted((tl(r) for r in d.get("islands", [])), key=lambda r: r[1] if v else r[0])
    if len(isl) != 2:
        return ""
    a, b = isl
    g = ((a[0] + a[2] / 2), (a[1] + a[3] + b[1]) / 2) if v else ((a[0] + a[2] + b[0]) / 2, a[1] + a[3] / 2)
    apps = [tl(t["frame"]) for t in d["tiles"] if t.get("kind") in ("app", "folder")]
    c = lambda r: (r[0] + r[2] / 2, r[1] + r[3] / 2)
    before = max((r for r in apps if (c(r)[1] if v else c(r)[0]) < (g[1] if v else g[0])), key=lambda r: c(r)[1] if v else c(r)[0])
    after = min((r for r in apps if (c(r)[1] if v else c(r)[0]) > (g[1] if v else g[0])), key=lambda r: c(r)[1] if v else c(r)[0])
    cap = tl(d["capsule"])
    zs = [tl(z["rect"]) for z in d.get("zones", [])]
    z = max(zs, key=lambda r: r[3] if v else r[2]) if zs else cap
    along = int(z[1] + z[3] / 2) if v else int(z[0] + z[2] / 2)
    e = d["edge"]
    away = {"left": (cap[0] + cap[2] + 400, g[1]), "right": (cap[0] - 400, g[1]),
            "bottom": (g[0], cap[1] - 400), "top": (g[0], cap[1] + cap[3] + 400)}[e]
    f = lambda x: f"{x:.1f}"
    return " ".join([e, str(along), *map(f, (*g, *c(before), *c(after), *away))])


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["geom"] and len(a) == 2:
        for cid, ok, detail in geom_rows(a[1]):
            print(f"{cid}\t{ok}\t{detail}")
    elif a[:1] == ["gap"] and len(a) == 2:
        print(gap_points(a[1]))
    else:
        sys.exit("usage: t26.py geom <geometry.json> | gap <geometry.json>")
