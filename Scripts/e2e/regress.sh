#!/bin/zsh
# M1 Edge Dock end-to-end regression suite (Tests/E2E/regressions.md, docs/evaluation.md §5).
#
#   Scripts/e2e/regress.sh run <app-worktree> [id=<run-id>] [edges=L,R] [idle=1|0] [dry=1]
#       The whole M1 set in ONE desktop-lock take (the caller holds the lock and has announced
#       it): x-00 + REG-026 on an empty data dir, then per edge geom-check, log-contract checks
#       and x-01…x-05a, then x-05b and x-06 in a hide-delay-0 run, then 60 s idle; post-run
#       harness checks (cursor restored, no modifier held, no Dedock left). A contaminated
#       scenario is re-run once. Writes build/e2e/runs/<id>/scorecard.md. dry=1 prints the plan.
#   Scripts/e2e/regress.sh score <run-id> [baseline.json]
#   Scripts/e2e/regress.sh rescore <run-id> [baseline.json]   re-judge saved logs (analyzer changed), then score
#   Scripts/e2e/regress.sh baseline <run-id>                  write Tests/E2E/baseline/m1.json from a clean run
#   Scripts/e2e/regress.sh comment <run-id> <pr-number>       attach the scorecard to an app PR (public repo:
#                                                             only on the orchestrator's go; refuses absolute paths)
#
# Exit: 0 PASS, 1 FAIL (a gate broke: blocks a merge), 3 VOID (real input got in twice: rerun).
# The app must be a DEBUG build (E2E hooks are debug-only). Needs the harness tools built
# (Tests/E2E/selftest/run.sh builds them).
set -uo pipefail

H=${0:A:h:h:h}
B=$H/build/e2e
E=$H/Scripts/e2e
BASELINE_DEFAULT=$H/Tests/E2E/baseline/m1.json
mode=${1:?usage: regress.sh run|score|rescore|baseline ...}; shift

score() { python3 $E/score.py $1 ${2:-$BASELINE_DEFAULT} }

case $mode in
score)
  score $B/runs/${1:?run-id} ${2:-}; exit $? ;;
rescore)
  root=$B/runs/${1:?run-id}
  for sub in $(awk '{print $2}' $root/index.txt); do
    for d in $B/runs/$sub/*(/N); do [[ -f $d/params.env ]] && $E/judge.sh $d > /dev/null; done
  done
  score $root ${2:-}; exit $? ;;
baseline)
  python3 $E/score.py --write-baseline $B/runs/${1:?run-id} $BASELINE_DEFAULT; exit $? ;;
comment)
  card=$B/runs/${1:?run-id}/scorecard.md; pr=${2:?pr-number}
  [[ -f $card ]] || { echo "no scorecard: run 'regress.sh score $1' first" >&2; exit 2 }
  grep -qE '/U[s]ers/|/h[o]me/' $card && { echo "refusing: the scorecard contains an absolute path" >&2; exit 2 }
  gh pr comment $pr --body-file $card; exit $? ;;
run) ;;
*) echo "unknown mode $mode" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- run
app=${1:?usage: regress.sh run <app-worktree> [id=] [edges=L,R] [idle=1] [dry=1]}; shift
id=reg-$(date -u +%Y%m%dT%H%M%SZ) edges=L,R idle=1 dry=0
for kv in "$@"; do case $kv in id=*) id=${kv#id=} ;; edges=*) edges=${kv#edges=} ;; idle=*) idle=${kv#idle=} ;; dry=*) dry=${kv#dry=} ;; esac; done
bundle=$app/build/Dedock.app
bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $bundle/Contents/Info.plist 2>/dev/null)
[[ $bid == app.dedock.Dedock.debug ]] || { echo "need a DEBUG build at $bundle (found '${bid:-none}'): Scripts/make-app.sh debug" >&2; exit 2 }

edge_list=(${(s:,:)edges})
est=$(( 15 + ${#edge_list} * 95 + (idle ? 75 : 0) ))
echo "regress $id: app $(git -C $app rev-parse --short HEAD) edges=$edges idle=$idle — moves the cursor for about $est s"
if (( dry )); then
  echo "plan: x-00 + REG-026 (empty data dir); per edge: launch, geom-check, contract, x-01 n=4, x-02 n=4, x-03 n=3, x-04 n=3, x-05a n=3; hideDelay 0 run: x-05b n=3, x-06; idle 60 s; post checks"
  exit 0
fi

me=${DEDOCK_LOCK_OWNER:-dedock-app-f1}
holder=$($E/desktop-lock.sh status | sed -n 's/^owner=//p')
[[ $holder == $me ]] || { echo "refusing: hold the desktop lock as '$me' first (holder: '${holder:-nobody}')" >&2; exit 2 }

root=$B/runs/$id
[[ -e $root ]] && { echo "run exists: $root" >&2; exit 2 }
mkdir -p $root
: > $root/index.txt; : > $root/checks.jsonl; : > $root/run-metrics.jsonl

check() {  # check <id> <0|1 ok> <detail>
  python3 -c 'import json,sys; print(json.dumps({"id": sys.argv[1], "ok": sys.argv[2] == "1", "detail": sys.argv[3]}))' "$1" "$2" "$3" >> $root/checks.jsonl
  print -r -- "$([[ $2 == 1 ]] && echo PASS || echo FAIL) $1: $3"
}
rmetric() { print -r -- "{\"metric\":\"$1\",\"value\":$2}" >> $root/run-metrics.jsonl }

# Provenance.
python3 - $root/env.json <<EOF
import json, sys
json.dump({
  "app_commit": "$(git -C $app rev-parse --short HEAD)$(git -C $app diff --quiet HEAD -- Sources Package.swift 2>/dev/null || echo '-dirty')",
  "harness_commit": "$(git -C $H rev-parse --short HEAD)", "config": "debug",
  "macos": "$(sw_vers -productVersion) ($(sw_vers -buildVersion))",
  "display": "$($B/pointer screen | sed 's/x=[0-9.]* y=[0-9.]* //')",
  "native_dock": "$(defaults read com.apple.dock orientation 2>/dev/null), autohide=$(defaults read com.apple.dock autohide 2>/dev/null)",
  "refs_running": "$(pgrep -lf 'CoolDock|DockDoor' | wc -l | tr -d ' ')",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
}, open(sys.argv[1], "w"), indent=1)
EOF

$E/quit-refs.sh $id >/dev/null || true
cursor0=($($B/pointer pos | sed 's/[xy]=//g'))

launched() { grep -q '^PASS launched' $1 }
edge_ready_ms() { grep -o 'ms=[0-9.]*' $B/runs/$1/run.env | head -1 | cut -d= -f2 }

# Log contract on one launch (REG-018, REG-014, unknown values).
contract() {  # contract <sub-run> <tag>
  local R=$B/runs/$1
  python3 - $R/log.ndjson $R/data/e2e/geometry.json $(sed -n 's/^APP_PID=//p' $R/run.env) > $R/contract.txt <<'PY'
import json, sys
log, geom, pid = sys.argv[1], sys.argv[2], int(sys.argv[3])
ev = []
for line in open(log):
    if line.startswith("{"):
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("processID") == pid and o.get("subsystem") == "app.dedock.Dedock":
            ev.append(o["eventMessage"])
names = [e.split(" ", 1)[0] for e in ev]
ready = [i for i, n in enumerate(names) if n == "launch.edgeReady"]
prep = [i for i, n in enumerate(names) if n in ("layout.pass", "docks.sync")]
ok18 = len(ready) == 1 and prep and min(prep) < ready[0]
print(f"REG-018 {int(bool(ok18))} launch.edgeReady x{len(ready)}, after layout.pass/docks.sync: {bool(prep and ready and min(prep) < ready[0])}; launch.firstArm x{names.count('launch.firstArm')}")
try:
    tiles = {t.get("bundleId") or t.get("bundleID") for d in json.load(open(geom))["docks"] for t in d["tiles"]}
except (OSError, ValueError, KeyError):
    tiles = None
ind = {kv.split("=", 1)[1] for e in ev if e.startswith("tile.indicator ") for kv in e.split() if kv.startswith("bundle=")}
if tiles is None:
    print("REG-014 0 no GEOM to compare indicator bundles against")
else:
    stray = sorted(ind - tiles)
    print(f"REG-014 {int(not stray)} tile.indicator bundles outside the dock: {len(stray)}")
PY
  while read -r rid ok rest; do check "$rid $2" $ok "$rest"; done < $R/contract.txt
  local warns=$($B/analyze timing $R/log.ndjson 2>/dev/null | grep -c '^WARN unrecognized' || true)
  check "contract $2" $(( warns == 0 )) "$warns unrecognized cause/kind/curve/state values"
}

run_scn() {  # run_scn <sub-run> <L|R> <scenario> [args]; re-runs once if contaminated (VOID)
  local sub=$1 side=$2 scn=$3; shift 3
  $E/desktop-lock.sh touch >/dev/null
  $E/scenario.sh $sub $side $scn "$@" > /dev/null; local rc=$?
  if (( rc == 3 )); then
    mv $B/runs/$sub/$scn-$side $B/runs/$sub/$scn-$side.void-1
    $E/scenario.sh $sub $side $scn "$@" > /dev/null; rc=$?
  fi
  echo "  $scn $side: $(tail -1 $B/runs/$sub/$scn-$side/report.txt 2>/dev/null | cut -d' ' -f2)"
}

teardown_check() {  # REG-006 after every launch
  $E/teardown.sh $1 > $B/runs/$1/teardown.txt 2>&1
  grep -q '^PASS REG-006' $B/runs/$1/teardown.txt
}

# x-00 and REG-026 on an empty data dir, with every TCC grant reset.
echo "x-00 / REG-026"
tccutil reset All app.dedock.Dedock.debug >/dev/null 2>&1
X=$id-X
if $E/launch.sh $X --app $app --no-seed --timeout 8 > $B/runs/$id/launch-X.txt 2>&1 && launched $B/runs/$id/launch-X.txt; then
  sleep 2
  pid=$(sed -n 's/^APP_PID=//p' $B/runs/$X/run.env)
  check "x-00 UIElement" $(lsappinfo info -only ApplicationType -app $pid 2>/dev/null | grep -q UIElement && echo 1 || echo 0) "no Dock icon (LSUIElement)"
  si=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to get description of every menu bar item of menu bar 1" 2>/dev/null)
  check "x-00 status item" $([[ $si == *dedock* ]] && echo 1 || echo 0) "status item: ${si:-none}"
  if command -v cua-driver >/dev/null; then
    prompts=$(cua-driver call list_windows '{}' 2>/dev/null | python3 -c 'import json,sys
w=json.load(sys.stdin)["windows"]
print(sum(1 for x in w if x["is_on_screen"] and x["app_name"] in ("UserNotificationCenter","universalAccessAuthWarn","SecurityAgent","tccd")))' 2>/dev/null || echo "?")
    check "x-00 no permission prompt" $([[ $prompts == 0 ]] && echo 1 || echo 0) "TCC/notification windows on screen: $prompts"
  fi
  state=$(python3 -c "import json;print(json.load(open('$B/runs/$X/data/e2e/geometry.json'))['docks'][0]['state'])" 2>/dev/null)
  check "x-00 starts hidden" $([[ $state == hidden ]] && echo 1 || echo 0) "GEOM state: ${state:-?}"
  r26=$(python3 - $B/runs/$X/data <<'PY'
import json, sys, os
d = sys.argv[1]
if not os.path.exists(f"{d}/layout.json"): print("0 layout.json not written on first launch"); sys.exit()
gap = json.load(open(f"{d}/layout.json"))["docks"][0].get("placement", {}).get("edgeGapPt")
g = json.load(open(f"{d}/e2e/geometry.json")); dk = g["docks"][0]; s = next(x for x in g["screens"] if x["id"] == dk["screen"])
cx, cy, cw, ch = dk["capsule"]["topLeft"]; fx, fy, fw, fh = s["frame"]["topLeft"]
inset = {"left": cx - fx, "right": fx + fw - (cx + cw)}.get(dk["edge"])
print(f"{int(gap is not None and inset is not None and abs(gap - inset) < 0.51)} layout.json written; edgeGapPt={gap}, GEOM inset={inset}")
PY
)
  check "REG-026 first launch" ${r26%% *} "${r26#* }"
  contract $X X
  rmetric launch.first_ms $(edge_ready_ms $X)
  teardown_check $X; check "REG-006 X" $(( $? == 0 )) "native Dock prefs unchanged"
else
  check "x-00 launch" 0 "app did not reach launch.edgeReady (see build/e2e/runs/$id/launch-X.txt)"
fi

for tag in $edge_list; do
  side=$tag; [[ $tag == R ]] && set_edge=(--set 'docks[0].edge="right"') || set_edge=()
  echo "edge $tag"
  sub=$id-$tag
  if $E/launch.sh $sub --app $app --frame-log $set_edge --timeout 8 > $root/launch-$tag.txt 2>&1 && launched $root/launch-$tag.txt; then
    print -r -- "$tag $sub" >> $root/index.txt
    sleep 1
    rmetric launch.${tag}_ms $(edge_ready_ms $sub)
    $E/geom-check.py $B/runs/$sub/data/e2e/geometry.json layout=$B/runs/$sub/data/layout.json > $B/runs/$sub/geom.txt
    gf=$(grep -c '^FAIL' $B/runs/$sub/geom.txt); gp=$(grep -c '^PASS' $B/runs/$sub/geom.txt)
    check "geom $tag (REG-013 …)" $(( gf == 0 )) "$gp pass, $gf fail$( (( gf )) && print -r -- ": $(grep '^FAIL' $B/runs/$sub/geom.txt | head -2 | cut -c6-90 | tr '\n' ';')")"
    rmetric geom.${tag}_fails $gf
    run_scn $sub $side x-01 n=4
    run_scn $sub $side x-02 n=4
    run_scn $sub $side x-03 n=3
    run_scn $sub $side x-04 n=3
    run_scn $sub $side x-05a n=3
    contract $sub $tag
    teardown_check $sub; check "REG-006 $tag" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch $tag" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-$tag.txt)"
  fi
  sub0=$id-${tag}0
  if $E/launch.sh $sub0 --app $app --frame-log $set_edge --set 'docks[0].reveal.hideDelayMs=0' --timeout 8 > $root/launch-${tag}0.txt 2>&1 && launched $root/launch-${tag}0.txt; then
    print -r -- "$tag $sub0" >> $root/index.txt
    sleep 1
    run_scn $sub0 $side x-05b n=3
    run_scn $sub0 $side x-06 seed=1
    teardown_check $sub0; check "REG-006 ${tag}0" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch ${tag}0" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-${tag}0.txt)"
  fi
done

if (( idle )); then
  echo "idle"
  sub=$id-I
  if $E/launch.sh $sub --app $app --timeout 8 > $root/launch-I.txt 2>&1 && launched $root/launch-I.txt; then
    print -r -- "I $sub" >> $root/index.txt
    pid=$(sed -n 's/^APP_PID=//p' $B/runs/$sub/run.env)
    for attempt in 1 2; do
      O=$B/runs/$sub/idle-L; rm -rf $O; mkdir -p $O
      sleep 3
      $E/desktop-lock.sh touch >/dev/null
      $B/listen 64 > $O/listen.txt &
      lp=$!; sleep 0.5
      $H/Scripts/measure-idle.sh $pid 60 $O/perf.csv > $O/perf.txt
      wait $lp 2>/dev/null
      {
        $B/analyze contamination $O/listen.txt idle=1 metrics=$O/metrics.jsonl
        cat $O/perf.txt
      } > $O/report.raw.txt
      tail -1 $O/perf.csv | awk -F, '{printf "{\"metric\":\"idle.cpu_pct\",\"value\":%s}\n{\"metric\":\"idle.wakeups_per_s\",\"value\":%s}\n{\"metric\":\"idle.footprint_mb\",\"value\":%s}\n{\"metric\":\"idle.rss_mb\",\"value\":%s}\n", $6, $8, $9, $10}' >> $O/metrics.jsonl
      if grep -q '^FAIL input contamination' $O/report.raw.txt; then v=VOID
      elif grep -q '^verdict=FAIL\|^FAIL' $O/report.raw.txt; then v=FAIL; else v=PASS; fi
      sed 's/^verdict=FAIL/FAIL idle gate (NFR-1\/NFR-2)/' $O/report.raw.txt > $O/report.txt
      echo "VERDICT $v idle left" >> $O/report.txt; rm $O/report.raw.txt
      [[ $v != VOID ]] && break
      mv $O $O.void-$attempt
    done
    echo "  idle: $v"
    teardown_check $sub; check "REG-006 I" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch I" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-I.txt)"
  fi
fi

# Post-run harness checks (they gate the harness, not the app).
$B/pointer -q move ${cursor0[1]} ${cursor0[2]}
now=($($B/pointer pos | sed 's/[xy]=//g'))
check "REG-016 cursor restored" $(python3 -c "import sys; a=[float(x) for x in sys.argv[1:3]]; b=[float(x) for x in sys.argv[3:5]]; print(int(abs(a[0]-b[0])<=1 and abs(a[1]-b[1])<=1))" ${cursor0[1]} ${cursor0[2]} ${now[1]} ${now[2]}) "before ${cursor0[*]}, after ${now[*]}"
mods=$($B/pointer mods)
check "REG-017 no modifier held" $([[ $mods == mods=0* ]] && echo 1 || echo 0) "$mods"
left=$(pgrep -x Dedock | tr '\n' ' ')
check "REG-015 no Dedock left running" $([[ -z $left ]] && echo 1 || echo 0) "${left:-none}"

echo
score $root
