#!/usr/bin/env python3
"""T37a/T37b dock styles and window material: judging from GEOM, the log and pixel means.

    t37.py style <geometry.json> <dark|liquidGlass> <macos-major> [reduce-transparency 0|1]
        -> "<0|1>\\t<detail>": GEOM style; material solid for Dark, glass for Liquid Glass on macOS 26+
           (hudWindow/popover stand-in before 26, solid under Reduce Transparency is reported);
           liquidTint dark|light present only for Liquid Glass.
    t37.py tint <log.ndjson> <pid> <from-line> [reading-from-line]
        -> "<0|1>\\t<detail>" (smoke): the lines from from-line hold a reveal; no `dock.tint tint=` change
           between its shown and the next leave; at least one `dock.tint.reading` (or unavailable=1)
           since reading-from-line (the switch to Liquid Glass).
    t37.py materials <mean-json-file>
        -> "<0|1>\\t<detail>": one line per material "<material> <sidebar r g b> <content r g b>"; every pair
           of materials differs by more than 4 (0-255, max channel) in the sidebar AND in the content
           (or the pair has a stated reason in REASONS for an equal content column).
"""
import json, re, sys
from itertools import combinations


def style(geom, want, major, rt="0"):
    d = json.load(open(geom))["docks"][0]
    st, mat, tint = d.get("style"), d.get("material"), d.get("liquidTint")
    if want == "liquidGlass" and rt == "1":
        # Reduce Transparency: Liquid Glass is the solid Dark style, not adaptive (design §7.2a)
        ok = st == "liquidGlass" and mat == "solid" and tint is None
        return int(ok), (f"GEOM style {st!r}, material {mat!r}, liquidTint {tint!r} (Reduce Transparency is ON: Liquid Glass "
                         f"correctly draws as the solid Dark style; exp liquidGlass / solid, no liquidTint)")
    if want == "dark":
        ok = st == "dark" and mat == "solid" and tint is None
        exp = "dark / solid, no liquidTint"
    else:
        mats = {"glass"} if int(major) >= 26 else {"hudWindow", "popover"}
        ok = st == "liquidGlass" and mat in mats and tint in ("dark", "light")
        exp = f"liquidGlass / {'|'.join(sorted(mats))} (macOS {major}), liquidTint dark|light"
    return int(ok), f"GEOM style {st!r}, material {mat!r}, liquidTint {tint!r} (exp {exp})"


def tint(log, pid, start, reading_from=None):
    ev, since = [], []
    rf = int(reading_from) if reading_from is not None else int(start)
    for i, l in enumerate(open(log)):
        if i < min(int(start), rf) or not l.startswith("{"):
            continue
        try:
            r = json.loads(l.rstrip().rstrip(","))
        except ValueError:
            continue
        if r.get("processID") == int(pid):
            if i >= rf:
                since.append(r.get("eventMessage", ""))
            if i >= int(start):
                ev.append(r.get("eventMessage", ""))
    shown = next((i for i, m in enumerate(ev) if re.search(r"^reveal[.]transition .*to=shown", m)), None)
    leave = next((i for i, m in enumerate(ev) if shown is not None and i > shown and re.search(r"^reveal[.]transition .*from=shown", m)), None)
    if shown is None:
        return 0, "no reveal in the probe"
    during = ev[shown:leave if leave is not None else len(ev)]
    changes = sum(1 for m in during if m.startswith("dock.tint tint="))
    readings = [m for m in since if m.startswith("dock.tint.reading")]
    unavailable = sum(1 for m in readings if "unavailable=1" in m)
    applied = [m for m in ev if m.startswith("dock.tint tint=")]
    # smoke: a static wallpaper cannot change the tint, so this can only catch a change made while
    # shown for some other reason; a real test needs a debug reading command from the implementer
    return int(changes == 0 and len(readings) > 0), (
        f"(smoke) tint changes while shown: {changes} (exp 0); dock.tint.reading lines since Liquid Glass: {len(readings)} "
        f"(exp ≥ 1; unavailable=1: {unavailable}); tint lines: {', '.join(a.split()[1] for a in applied) or 'none'}")


# Material pairs whose content column may legitimately look the same, with the reason (none yet).
REASONS: dict = {}


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
        # every pair must differ in the sidebar AND in the content column; a pair whose content
        # cannot differ needs a stated reason in REASONS (none today), shown on the card
        why = REASONS.get(frozenset((a, b)))
        ok &= ds > 4 and (dc > 4 or why is not None)
        notes.append(f"{a}/{b}: sidebar Δ{ds:.1f}, content Δ{dc:.1f}" + (f" (content waived: {why})" if why and dc <= 4 else ""))
    return int(ok), "; ".join(notes) + " (exp each pair: sidebar Δ > 4 AND content Δ > 4, or a stated reason)"


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["style"] and len(a) in (4, 5):
        r = style(*a[1:])
    elif a[:1] == ["tint"] and len(a) in (4, 5):
        r = tint(*a[1:])
    elif a[:1] == ["materials"] and len(a) == 2:
        r = materials(a[1])
    else:
        sys.exit("usage: t37.py style <geom> <dark|liquidGlass> <macos-major> | tint <log> <pid> <from> | materials <file>")
    print(f"{r[0]}\t{r[1]}")
