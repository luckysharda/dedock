#!/usr/bin/env python3
"""Checks that app log events appear in a given order (REG-057 launch notices, REG-059 first sync).

    Scripts/e2e/log-order.py <log.ndjson> [pid=<n>] <event-regex> [<event-regex> ...]

Each regex is matched against eventMessage, in log order; each must match AFTER the previous one's
first match. Prints "<1|0> <detail>": 1 if all matched in order, 0 otherwise (fails closed on an
unreadable or empty log).
"""
import json
import re
import sys

path, pats = sys.argv[1], sys.argv[2:]
pid = int(pats.pop(0)[4:]) if pats and pats[0].startswith("pid=") else None  # only that process's lines
try:
    rows = [json.loads(l) for l in open(path) if l.lstrip().startswith("{")]
    msgs = [r.get("eventMessage", "") for r in rows
            if r.get("subsystem") == "app.dedock.Dedock" and (pid is None or r.get("processID") == pid)]
except (OSError, ValueError) as ex:
    print(f"0 log unreadable: {type(ex).__name__}")
    sys.exit()
i, found = 0, []
for p in pats:
    rx = re.compile(p)
    while i < len(msgs) and not rx.search(msgs[i]):
        i += 1
    if i == len(msgs):
        got = " → ".join(found) or "nothing"
        print(f"0 missing '{p}' after: {got}")
        sys.exit()
    found.append(msgs[i].split(" ")[0] + (f" {m.group(0)}" if (m := re.search(r"(kind|reason)=\S+", msgs[i])) else ""))
    i += 1
print("1 in order: " + " → ".join(found))
