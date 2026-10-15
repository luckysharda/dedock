#!/usr/bin/env python3
"""Scores a regression run (Scripts/e2e/regress.sh) into a scorecard.

    Scripts/e2e/score.py <root-run-dir> [baseline.json]          -> scorecard.md, metrics.json, exit 0/1/3
    Scripts/e2e/score.py --write-baseline <root-run-dir> <out.json>  (after the user reviewed a clean run)

The root run dir holds index.txt ("<tag> <sub-run-id>" per line, e.g. "L L-run"), checks.jsonl
(run-level checks: {"id","ok","detail"}), env.json (provenance) and sub-run dirs under
build/e2e/runs/<sub-run-id>/<scenario>-<L|R>/ with report.txt (ends "VERDICT ...") and metrics.jsonl.

Verdicts: FAIL if any gate failed; VOID if nothing failed but a scenario was contaminated by real
input (rerun needed, not an app result); PASS otherwise. Drift: WARN when a metric moves more than
20 % from the baseline AND more than its absolute noise floor (floors live in the baseline file).
Exit: 0 PASS, 1 FAIL, 3 VOID. Paths in the scorecard are repo-relative (the repo is public).
"""
import json
import os
import re
import sys

DRIFT = 0.20
# Absolute noise floors by metric suffix: 20 % of a 1.2 ms latency is 0.24 ms, which is noise.
DEFAULT_FLOORS = {"_ms": 2.0, "_pt": 1.0, "cpu_pct": 0.05, "wakeups_per_s": 0.2, "_mb": 5.0}
# Counts describe the run, not the app's quality: never drift-checked.
# Harness checks (Tests/E2E/regressions.md "gates: harness") never decide an app PR's verdict.
HARNESS_IDS = ("REG-015", "REG-016", "REG-017", "REG-041")
COUNTS = ("_trials", "reversals", "foreign_events", "leave_before_dwell", "hide_cancelled", "_n")


def rel(path):
    """Repo-relative path for the scorecard (never an absolute /Users path)."""
    path = os.path.abspath(path)
    marker = os.sep + "build" + os.sep + "e2e" + os.sep
    return "build/e2e/" + path.split(marker, 1)[1] if marker in path else os.path.basename(path)


def load_jsonl(path):
    out = []
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if line:
                out.append(json.loads(line))
    return out


def collect(root):
    runs_dir = os.path.dirname(root.rstrip("/"))
    scenarios, metrics = [], {}
    for line in open(os.path.join(root, "index.txt")):
        if not line.strip():
            continue
        tag, sub = line.split()
        sub_dir = os.path.join(runs_dir, sub)
        if not os.path.isdir(sub_dir):
            continue
        for name in sorted(os.listdir(sub_dir)):
            d = os.path.join(sub_dir, name)
            report = os.path.join(d, "report.txt")
            if not (os.path.isdir(d) and os.path.exists(report)) or ".void-" in name:
                continue  # *.void-N: a contaminated attempt that was re-run; the re-run is the result
            text = open(report).read()
            m = re.search(r"^VERDICT (\w+)", text, re.M)
            if m:
                verdict = m.group(1)
            elif re.search(r"^FAIL input contamination", text, re.M):
                verdict = "VOID"  # report from before verdict lines: contamination is a rerun, not an app failure
            else:
                verdict = "FAIL" if re.search(r"^FAIL", text, re.M) else "PASS"
            fails = re.findall(r"^FAIL (.*)$", text, re.M)
            key = f"{tag}.{name}"
            scenarios.append({"key": key, "verdict": verdict, "fails": fails, "report": rel(report)})
            for row in load_jsonl(os.path.join(d, "metrics.jsonl")):
                metrics[f"{key}.{row['metric']}"] = row["value"]
    for row in load_jsonl(os.path.join(root, "run-metrics.jsonl")):
        metrics[row["metric"]] = row["value"]
    checks = load_jsonl(os.path.join(root, "checks.jsonl"))
    return scenarios, metrics, checks


def floor_for(name, floors):
    for suffix, value in floors.items():
        if name.endswith(suffix):
            return value
    return None


def drift(metrics, baseline):
    warns = []
    if not baseline:
        return warns
    floors = {**DEFAULT_FLOORS, **baseline.get("floors", {})}
    for name, base in baseline.get("metrics", {}).items():
        if name not in metrics or any(name.endswith(c) for c in COUNTS):
            continue
        now, delta = metrics[name], metrics[name] - base
        floor = floor_for(name, floors)
        if floor is None:
            continue
        if abs(delta) > abs(base) * DRIFT and abs(delta) > floor:
            warns.append((name, base, now, delta))
    return warns


def write_scorecard(root, baseline_path):
    scenarios, metrics, checks = collect(root)
    baseline = json.load(open(baseline_path)) if baseline_path and os.path.exists(baseline_path) else None
    env = json.load(open(os.path.join(root, "env.json"))) if os.path.exists(os.path.join(root, "env.json")) else {}
    warns = drift(metrics, baseline)

    is_harness = lambda c: c["id"].startswith(HARNESS_IDS)
    harness_failed = [c for c in checks if not c["ok"] and is_harness(c)]
    live = [c for c in checks if not c.get("skip")]
    failed = [s for s in scenarios if s["verdict"] == "FAIL"] + [c for c in live if not c["ok"] and not is_harness(c)]
    void = [s for s in scenarios if s["verdict"] == "VOID"]
    verdict = "FAIL" if failed else ("VOID" if void else "PASS")
    res = lambda c: "SKIP" if c.get("skip") else ("PASS" if c["ok"] else "FAIL")
    if not scenarios and not checks:
        verdict = "FAIL"

    L = []
    L.append(f"## Regression scorecard: M1 Edge Dock — {verdict}")
    L.append("")
    L.append(f"App: `{env.get('app_commit', '?')}` ({env.get('config', '?')}) · Harness: `{env.get('harness_commit', '?')}` · "
             f"Date: {env.get('date', '?')} · Run: `{rel(root)}`")
    L.append(f"Machine: macOS {env.get('macos', '?')}, {env.get('display', '?')}, native Dock {env.get('native_dock', '?')}, "
             f"reference apps running: {env.get('refs_running', '?')}")
    if baseline:
        p = baseline.get("provenance", {})
        L.append(f"Baseline: `{rel(baseline_path) if os.path.isabs(baseline_path) else baseline_path}` "
                 f"(app `{p.get('app_commit', '?')}`, {p.get('config', '?')}, edges {p.get('edges', '?')}"
                 f"{', PARTIAL' if p.get('partial') else ''})")
    else:
        L.append("Baseline: none (drift not checked)")
    L.append("")
    L.append(f"**{verdict}** — scenarios: {sum(s['verdict'] == 'PASS' for s in scenarios)} pass, "
             f"{len([s for s in scenarios if s['verdict'] == 'FAIL'])} fail, {len(void)} void (contaminated, rerun); "
             f"run checks: {sum(c['ok'] for c in live)}/{len(live)} pass ({len(checks) - len(live)} skipped); drift warnings: {len(warns)}"
             + (f"; HARNESS checks failing: {', '.join(c['id'] for c in harness_failed)} (harness bug, not an app result)" if harness_failed else ""))
    L.append("")
    key = [c for c in checks if "REG-040" in c["id"] or c["id"].startswith("cua C2")]
    if key:
        L.append("Key gates (REG-040, tile accessibility: AXButton role, AXPress, cua-driver sees the tiles): "
                 + ", ".join(f"{c['id']} **{res(c)}**" for c in key))
        L.append("")
    L.append("| Scenario | Verdict | Failed gates | Report |")
    L.append("|---|---|---|---|")
    for s in scenarios:
        L.append(f"| {s['key']} | {s['verdict']} | {'; '.join(s['fails'])[:200] or '—'} | `{s['report']}` |")
    L.append("")
    for title, group in (("Check", [c for c in checks if not c["id"].startswith("cua ")]),
                         ("cua check (window list, AX tree, hit tests)", [c for c in checks if c["id"].startswith("cua ")])):
        if not group:
            continue
        L.append(f"| {title} | Result | Detail |")
        L.append("|---|---|---|")
        for c in group:
            L.append(f"| {c['id']}{' (harness)' if is_harness(c) else ''} | {res(c)} | {c['detail']} |")
        L.append("")
    if warns:
        L.append("Drift > 20 % from baseline (and above the noise floor) — inside the gate, but look:")
        L.append("")
        L.append("| Metric | Baseline | Now | Δ |")
        L.append("|---|---|---|---|")
        for name, base, now, delta in warns:
            L.append(f"| {name} | {base:.3f} | {now:.3f} | {delta:+.3f} ({delta / base * 100 if base else 0:+.0f} %) |")
        L.append("")
    key_metrics = [k for k in sorted(metrics) if re.search(
        r"(dwell_late_p95_ms|nfr4_p95_ms|hide_late_p95_ms|push_ms_max|reveal99_ms|hide_motion_ms|reversal_offset_max_pt|"
        r"max_step_pt|idle\.|launch\.|geom\.)", k)]
    if key_metrics:
        L.append("<details><summary>Numbers</summary>")
        L.append("")
        L.append("| Metric | Value | Baseline |")
        L.append("|---|---|---|")
        for k in key_metrics:
            b = (baseline or {}).get("metrics", {}).get(k)
            L.append(f"| {k} | {metrics[k]:.3f} | {'' if b is None else f'{b:.3f}'} |")
        L.append("")
        L.append("</details>")
    out = "\n".join(L) + "\n"
    open(os.path.join(root, "scorecard.md"), "w").write(out)
    json.dump({"verdict": verdict, "metrics": metrics, "env": env}, open(os.path.join(root, "metrics.json"), "w"), indent=1, sort_keys=True)
    print(out)
    return {"PASS": 0, "FAIL": 1, "VOID": 3}[verdict]


def write_baseline(root, out_path):
    scenarios, metrics, checks = collect(root)
    env = json.load(open(os.path.join(root, "env.json"))) if os.path.exists(os.path.join(root, "env.json")) else {}
    bad = [s["key"] for s in scenarios if s["verdict"] != "PASS"] + [c["id"] for c in checks if not c["ok"] and not c.get("skip")]
    if bad:
        print("refusing: a baseline must come from a fully clean run; not PASS: " + ", ".join(bad))
        return 1
    edges = sorted({s["key"].split(".")[0] for s in scenarios if s["key"].split(".")[0] in ("L", "R")})
    doc = {
        "provenance": {
            "app_commit": env.get("app_commit"), "config": env.get("config"), "harness_commit": env.get("harness_commit"),
            "macos": env.get("macos"), "display": env.get("display"), "date": env.get("date"),
            "edges": edges, "partial": edges != ["L", "R"], "source_run": rel(root),
        },
        "rule": "WARN when |now - baseline| > 20 % of baseline AND > the floor for the metric's suffix; counts are not drift-checked",
        "floors": DEFAULT_FLOORS,
        "metrics": {k: round(v, 3) for k, v in sorted(metrics.items()) if not any(k.endswith(c) for c in COUNTS)},
    }
    json.dump(doc, open(out_path, "w"), indent=1, sort_keys=False)
    open(out_path, "a").write("\n")
    print(f"wrote {out_path}: {len(doc['metrics'])} metrics, edges {edges}{' (PARTIAL)' if doc['provenance']['partial'] else ''}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "--write-baseline":
        sys.exit(write_baseline(sys.argv[2], sys.argv[3]))
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(write_scorecard(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None))
