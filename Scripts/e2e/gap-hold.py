#!/usr/bin/env python3
"""x-19 "gap hold" (REG-067): the band between a trigger zone and the shown capsule.

On the top edge (the menu-bar band) and on the bottom edge beside the native Dock (the diagonal
from a side strip over the Dock), the shown capsule does not touch its zone. The reveal corridor
counts the path from the zone entry to the capsule as inside until the pointer first reaches the
capsule; after that visit the band is outside again.

    gap-hold.py plan <geometry.json> [layout.json]
        -> "edge along tx ty gx gy ax ay hide_ms dwell_ms" (top-left points), or "skip <reason>"
           entry: the zone point nearest the first tile (2 pt in from the strip's ends);
           g: the midpoint between that entry and the nearest point of capsule ± hysteresis (the gap);
           t: the first tile's centre; a: a point well away from the dock (the final leave).
    gap-hold.py judge <log.ndjson> <pid> <n0> <n1> <n2> <hide_ms> <side>
        -> two rows "<check id>\\t<0|1>\\t<detail>":
           hold:     lines n0..n1 (zone dwell, then a 1 s hold at g): revealed, and no hide began;
           corridor: lines n1..n2 (into the capsule, back to g, hold): the leave starts a hide
                     hide_ms ± 16 ms later (the corridor is gone after the visit).
"""
import json, re, sys
from datetime import datetime

HYST = 16  # capsule hysteresis default (design §4.2); the seeded layout's reveal.hysteresisPt wins
TOL_MS = 16


def rect_near(r, p):
    x, y, w, h = r
    return (min(max(p[0], x), x + w), min(max(p[1], y), y + h))


def inside(r, p, pad=0):
    x, y, w, h = r
    return x - pad <= p[0] <= x + w + pad and y - pad <= p[1] <= y + h + pad


def plan(geom, layout=None):
    d = json.load(open(geom))["docks"][0]
    rv = {}
    if layout:
        try:
            rv = json.load(open(layout))["docks"][0].get("reveal", {})
        except (OSError, ValueError, KeyError, IndexError):
            pass
    hyst, hide = float(rv.get("hysteresisPt", HYST)), int(rv.get("hideDelayMs", 400))
    e, cap = d["edge"], d["capsule"]["topLeft"]
    zones = [z["rect"]["topLeft"] for z in d.get("zones", [])]
    if not zones:
        return "skip no trigger zone in GEOM"
    if not d.get("tiles"):
        return "skip no tile in GEOM"
    tx, ty, tw, th = d["tiles"][0]["frame"]["topLeft"]
    t = (tx + tw / 2, ty + th / 2)
    vertical = e in ("left", "right")

    def entry(z):
        x, y, w, h = z
        if vertical:
            return (x + w / 2, min(max(t[1], y + 2), y + h - 2))
        return (min(max(t[0], x + 2), x + w - 2), y + h / 2)

    z = min(zones, key=lambda r: (entry(r)[0] - t[0]) ** 2 + (entry(r)[1] - t[1]) ** 2)
    en = entry(z)
    capp = (cap[0] - hyst, cap[1] - hyst, cap[2] + 2 * hyst, cap[3] + 2 * hyst)
    near = rect_near(capp, en)
    g = ((en[0] + near[0]) / 2, (en[1] + near[1]) / 2)
    if inside(cap, g, hyst) or any(inside(r, g) for r in zones):
        return f"skip no gap between the zone and the capsule on the {e} edge (the capsule ± {hyst:g} meets the zone)"
    along = int(round(en[1] if vertical else en[0]))
    away = {"left": (cap[0] + cap[2] + 400, t[1]), "right": (cap[0] - 400, t[1]),
            "bottom": (t[0], cap[1] - 400), "top": (t[0], cap[1] + cap[3] + 400)}[e]
    dwell = int(d.get("showDwellMs", 300))
    f = lambda v: f"{v:.1f}"
    return " ".join([e, str(along), f(t[0]), f(t[1]), f(g[0]), f(g[1]), f(away[0]), f(away[1]), str(hide), str(dwell)])


def events(log, pid, a, b):
    out = []
    for i, l in enumerate(open(log)):
        if i < a or i >= b or not l.startswith("{"):
            continue
        try:
            r = json.loads(l.rstrip().rstrip(","))
        except ValueError:
            continue
        if r.get("processID") != pid:
            continue
        ts = r.get("timestamp", "")
        try:
            t = datetime.strptime(ts, "%Y-%m-%d %H:%M:%S.%f%z").timestamp() * 1000
        except ValueError:
            t = None
        out.append((t, r.get("eventMessage", "")))
    return out


def judge(log, pid, n0, n1, n2, hide_ms, side):
    rows = []
    ev1 = events(log, pid, n0, n1)
    shown = [m for _, m in ev1 if re.search(r"^reveal[.]transition .*to=shown", m)]
    hides = [m for _, m in ev1 if re.search(r"^reveal[.]transition .*to=hiding", m)]
    arms = [m for _, m in ev1 if re.search(r"^reveal[.]transition .*to=armingHide", m)]
    rows.append((f"x-19 REG-067 gap hold keeps the dock shown {side}", int(bool(shown) and not hides),
                 f"zone dwell then 1 s in the gap: revealed {'yes' if shown else 'no'}; hides begun {len(hides)} "
                 f"(armingHide {len(arms)})"))
    ev2 = events(log, pid, n1, n2)
    leave = next(((t, i) for i, (t, m) in enumerate(ev2) if re.search(r"^reveal[.]transition .*from=shown to=armingHide cause=leave", m)), None)
    ok, detail = False, "no leave (shown → armingHide) after the capsule visit"
    if leave:
        lt, li = leave
        hid = next((t for t, m in ev2[li + 1:] if re.search(r"^reveal[.]transition .*from=armingHide to=hiding", m)), None)
        ret = next((m for _, m in ev2[li + 1:] if re.search(r"^reveal[.]transition .*from=armingHide to=shown", m)), None)
        if hid is None or lt is None:
            detail = "the leave started no hide" + (" (armingHide → shown: the band still counted as inside)" if ret else "")
        else:
            dt = hid - lt
            ok = abs(dt - hide_ms) <= TOL_MS
            detail = f"leaving through the gap after the capsule visit: hide began {dt:.0f} ms after the leave (exp {hide_ms} ± {TOL_MS})"
    rows.append((f"x-19 REG-067 corridor ends after the first capsule visit {side}", int(ok), detail))
    return rows


if __name__ == "__main__":
    a = sys.argv[1:]
    if a and a[0] == "plan" and len(a) >= 2:
        print(plan(a[1], a[2] if len(a) > 2 else None))
    elif a and a[0] == "judge" and len(a) == 8:
        for cid, ok, detail in judge(a[1], int(a[2]), int(a[3]), int(a[4]), int(a[5]), int(a[6]), a[7]):
            print(f"{cid}\t{ok}\t{detail}")
    else:
        sys.exit("usage: gap-hold.py plan <geometry.json> [layout.json] | judge <log> <pid> <n0> <n1> <n2> <hide_ms> <side>")
