#!/usr/bin/env python3
"""T27 Dock relaunch (killall Dock): judging from the app log and GEOM.

    recovery.py relaunch <log.ndjson> <pid> <from-line> <geom-before.json> <geom-after.json> <side>
        -> "T27 Dock relaunch: logged and zones rebuilt within 1 s <side>\\t<0|1>\\t<detail>":
           dock.relaunch logged after from-line; the first zones rebuild after it (zones.computed or
           layout.pass) within 1000 ms; GEOM zones present after, as many as before.
           Also prints "repair=<n>" on a second line: space.repair lines seen (reported, not gated).
"""
import json, re, sys
from datetime import datetime


def events(log, pid, start):
    out = []
    for i, l in enumerate(open(log)):
        if i < start or not l.startswith("{"):
            continue
        try:
            r = json.loads(l.rstrip().rstrip(","))
        except ValueError:
            continue
        if r.get("processID") != pid:
            continue
        try:
            t = datetime.strptime(r.get("timestamp", ""), "%Y-%m-%d %H:%M:%S.%f%z").timestamp() * 1000
        except ValueError:
            t = None
        out.append((t, r.get("eventMessage", "")))
    return out


def zones(p):
    try:
        return len(json.load(open(p))["docks"][0].get("zones", []))
    except (OSError, ValueError, KeyError, IndexError):
        return -1


def relaunch(log, pid, start, before, after, side):
    ev = events(log, int(pid), int(start))
    rl = next((i for i, (_, m) in enumerate(ev) if m.startswith("dock.relaunch")), None)
    zb, za = zones(before), zones(after)
    repair = sum(1 for _, m in ev if m.startswith("space.repair"))
    cid = f"T27 Dock relaunch: logged and zones rebuilt within 1 s {side}"
    if rl is None:
        return (cid, 0, f"no dock.relaunch logged after killall Dock; zones before/after {zb}/{za}"), repair
    t0 = ev[rl][0]
    rb = next(((t, m) for t, m in ev[rl + 1:] if re.match(r"zones[.]computed|layout[.]pass", m)), None)
    if rb is None or t0 is None or rb[0] is None:
        return (cid, 0, f"dock.relaunch logged, but no zones rebuild after it; zones before/after {zb}/{za}"), repair
    dt = rb[0] - t0
    ok = dt <= 1000 and za > 0 and za == zb
    return (cid, int(ok), f"dock.relaunch → {rb[1].split()[0]} in {dt:.0f} ms (exp ≤ 1000); GEOM zones before/after {zb}/{za}; space.repair lines: {repair}"), repair


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["relaunch"] and len(a) == 7:
        (cid, ok, detail), repair = relaunch(*a[1:])
        print(f"{cid}\t{ok}\t{detail}")
        print(f"repair={repair}")
    else:
        sys.exit("usage: recovery.py relaunch <log> <pid> <from-line> <geom-before> <geom-after> <side>")
