#!/usr/bin/env python3
"""T37a/T37b dock styles and window material: judging from GEOM, the log and pixel means.

    t37.py style <geometry.json> <dark|liquidGlass> <macos-major>
        -> "<0|1>\\t<detail>": GEOM style; material solid for Dark, glass for Liquid Glass on macOS 26+
           (hudWindow/popover stand-in before 26, solid under Reduce Transparency is reported);
           liquidTint dark|light present only for Liquid Glass.
    t37.py tint <log.ndjson> <pid> <from-line>
        -> "<0|1>\\t<detail>": the lines from from-line hold a reveal; no `dock.tint tint=` change between
           the reveal's shown and the next leave (a reading never changes a shown dock); readings counted.
    t37.py materials <mean-json-file>
        -> "<0|1>\\t<detail>": one line per material "<material> <sidebar r g b> <content r g b>"; every pair
           of materials differs by more than 4 (0-255, max channel) in the sidebar or in the content.
"""
import json, re, sys
from itertools import combinations


def style(geom, want, major):
    d = json.load(open(geom))["docks"][0]
    st, mat, tint = d.get("style"), d.get("material"), d.get("liquidTint")
    if want == "dark":
        ok = st == "dark" and mat == "solid" and tint is None
        exp = "dark / solid, no liquidTint"
    else:
        mats = {"glass"} if int(major) >= 26 else {"hudWindow", "popover"}
        ok = st == "liquidGlass" and mat in mats and tint in ("dark", "light")
        exp = f"liquidGlass / {'|'.join(sorted(mats))} (macOS {major}), liquidTint dark|light"
    return int(ok), f"GEOM style {st!r}, material {mat!r}, liquidTint {tint!r} (exp {exp})"


def tint(log, pid, start):
    ev = []
    for i, l in enumerate(open(log)):
        if i < int(start) or not l.startswith("{"):
            continue
        try:
            r = json.loads(l.rstrip().rstrip(","))
        except ValueError:
            continue
        if r.get("processID") == int(pid):
            ev.append(r.get("eventMessage", ""))
    shown = next((i for i, m in enumerate(ev) if re.search(r"^reveal[.]transition .*to=shown", m)), None)
    leave = next((i for i, m in enumerate(ev) if shown is not None and i > shown and re.search(r"^reveal[.]transition .*from=shown", m)), None)
    if shown is None:
        return 0, "no reveal in the probe"
    during = ev[shown:leave if leave is not None else len(ev)]
    changes = sum(1 for m in during if m.startswith("dock.tint tint="))
    readings = sum(1 for m in ev if m.startswith("dock.tint.reading"))
    applied = [m for m in ev if m.startswith("dock.tint tint=")]
    return int(changes == 0), (f"tint changes while shown: {changes} (exp 0); readings in the probe: {readings}; "
                               f"tint lines: {', '.join(a.split()[1] for a in applied) or 'none'}")


def materials(path):
    rows = {}
    for l in open(path):
        p = l.split()
        if len(p) != 7 or p[0] not in ("frosted", "liquidGlass", "solid"):
            continue  # e.g. a tool-health line printed into the same file
        try:
            rows[p[0]] = ([float(x) for x in p[1:4]], [float(x) for x in p[4:7]])
        except ValueError:
            continue
    if len(rows) < 3:
        return 0, f"captures for {len(rows)} material(s) (exp 3)"
    diff = lambda a, b: max(abs(x - y) for x, y in zip(a, b))
    notes, ok = [], True
    for a, b in combinations(sorted(rows), 2):
        ds, dc = diff(rows[a][0], rows[b][0]), diff(rows[a][1], rows[b][1])
        ok &= ds > 4 or dc > 4
        notes.append(f"{a}/{b}: sidebar Δ{ds:.0f}, content Δ{dc:.0f}")
    return int(ok), "; ".join(notes) + " (exp each pair > 4 in the sidebar or the content)"


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["style"] and len(a) == 4:
        r = style(*a[1:])
    elif a[:1] == ["tint"] and len(a) == 4:
        r = tint(*a[1:])
    elif a[:1] == ["materials"] and len(a) == 2:
        r = materials(a[1])
    else:
        sys.exit("usage: t37.py style <geom> <dark|liquidGlass> <macos-major> | tint <log> <pid> <from> | materials <file>")
    print(f"{r[0]}\t{r[1]}")
