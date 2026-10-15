#!/bin/zsh
# M1 Edge Dock end-to-end regression suite (Tests/E2E/regressions.md, docs/evaluation.md §5).
#
#   Scripts/e2e/regress.sh run <app-worktree> [id=<run-id>] [edges=L,R] [idle=1|0] [x06seeds=2,3,4] [padding=6] [gap=8] [dry=1]
#       shots=1: after the suite, one screenshot per edge of the PINNED dock over a harness-owned
#       neutral grey backdrop (capsule + 40 pt), kept locally in build/e2e/runs/<id>/shots/
#       (never committed; no user window is ever in the frame).
#       padding/gap: the design tokens geom-check expects (E1 Capsule: padding=8 gap=8); the inset
#       always comes from the seeded layout's edgeGapPt.
#       The whole M1 set in ONE desktop-lock take (the caller holds the lock and has announced
#       it): x-00 + REG-026 on an empty data dir, then per edge geom-check, log-contract checks
#       and x-01…x-05a, then x-05b and x-06 in a hide-delay-0 run, then 60 s idle; post-run
#       harness checks (cursor restored, no modifier held, no Dedock left). A contaminated
#       scenario is re-run once. Writes build/e2e/runs/<id>/scorecard.md. dry=1 prints the plan.
#   Scripts/e2e/regress.sh score <run-id> [baseline.json]
#   Scripts/e2e/regress.sh rescore <run-id> [baseline.json]   re-judge saved logs (analyzer changed), then score
#   Scripts/e2e/regress.sh baseline <run-id>                  write Tests/E2E/baseline/m1.json from a clean run
#   Scripts/e2e/regress.sh comment <run-id> <pr-number> [note.md]  attach the scorecard to an app PR (public repo:
#                                                             only on the orchestrator's go; refuses absolute paths)
#
# Exit: 0 PASS, 1 FAIL (a gate broke: blocks a merge), 3 VOID (real input got in twice: rerun).
# The app must be a DEBUG build (E2E hooks are debug-only). Needs the harness tools built
# (Tests/E2E/selftest/run.sh builds them).
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # never leave __pycache__ / *.pyc in the tree

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
comment)  # comment <run-id> <pr> [note.md]: optional human note above the scorecard
  card=$B/runs/${1:?run-id}/scorecard.md; pr=${2:?pr-number}; note=${3:-}
  [[ -f $card ]] || { echo "no scorecard: run 'regress.sh score $1' first" >&2; exit 2 }
  body=$B/runs/$1/comment.md
  { [[ -n $note ]] && { cat $note; print; print -- '---'; print }; cat $card } > $body
  grep -qE '/U[s]ers/|/h[o]me/' $body && { echo "refusing: the comment contains an absolute path" >&2; exit 2 }
  gh pr comment $pr --body-file $body; exit $? ;;
run) ;;
*) echo "unknown mode $mode" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------- run
app=${1:?usage: regress.sh run <app-worktree> [id=] [edges=L,R] [idle=1] [dry=1]}; shift
id=reg-$(date -u +%Y%m%dT%H%M%SZ) edges=L,R idle=1 dry=0 x06seeds= padding=6 gap=8 shots=0
for kv in "$@"; do case $kv in id=*) id=${kv#id=} ;; edges=*) edges=${kv#edges=} ;; idle=*) idle=${kv#idle=} ;; dry=*) dry=${kv#dry=} ;; x06seeds=*) x06seeds=${kv#x06seeds=} ;; padding=*) padding=${kv#padding=} ;; gap=*) gap=${kv#gap=} ;; shots=*) shots=${kv#shots=} ;; esac; done
extra_seeds=(${(s:,:)x06seeds})
bundle=$app/build/Dedock.app
bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $bundle/Contents/Info.plist 2>/dev/null)
# Self-test mode: the fake bundle id only, with DEDOCK_SELFTEST=1, no edges/idle/shots: it posts no
# input, runs no tccutil and launches no real app, so it may run under a private lock.
selftest=0
if [[ $bid == app.dedock.Fake && ${DEDOCK_SELFTEST:-0} == 1 ]]; then
  selftest=1
  [[ -z $edges && $idle == 0 && $shots == 0 ]] || { echo "self-test mode: edges= idle=0 shots=0 only (no input may be posted)" >&2; exit 2 }
elif [[ $bid != app.dedock.Dedock.debug ]]; then
  echo "need a DEBUG build at $bundle (found '${bid:-none}'): Scripts/make-app.sh debug" >&2; exit 2
fi

edge_list=(${(s:,:)edges})
# Calibrated on the first full run (2026-10-15: 489 s for edges L,R + idle): launches, settle
# waits and VOID re-runs make each edge ~200 s; each extra x-06 seed ~15 s.
est=$(( 15 + ${#edge_list} * (200 + ${#extra_seeds} * 15 + 25 + (shots ? 15 : 0)) + (idle ? 75 : 0) ))
echo "regress $id: app $(git -C $app rev-parse --short HEAD) edges=$edges idle=$idle — moves the cursor for about $est s"
if (( dry )); then
  echo "plan: x-00 + REG-026 (empty data dir); per edge: launch, geom-check (padding=$padding gap=$gap), cua checks C1–C8, contract, x-01 n=4, x-02 n=4, x-03 n=3, x-04 n=3, x-05a n=3; hideDelay 0 run: x-05b n=3, x-06 seed 1${x06seeds:+ + seeds $x06seeds}; idle 60 s$( (( shots )) && print -n '; E1 shots per edge (pinned, neutral backdrop)'); post checks"
  exit 0
fi

me=${DEDOCK_LOCK_OWNER:?set DEDOCK_LOCK_OWNER to your session name (no default: the lock must name its real holder)}
if (( selftest )); then
  holder=$($E/desktop-lock.sh status | sed -n 's/^owner=//p')
  [[ $holder == $me ]] || { echo "refusing: hold the (private) self-test lock as '$me' first" >&2; exit 2 }
else
  # HARD RULE: this run posts input, moves the cursor, runs tccutil and launches the real app.
  $E/desktop-lock.sh require $me || exit 2
fi

root=$B/runs/$id
[[ -e $root ]] && { echo "run exists: $root" >&2; exit 2 }
mkdir -p $root
: > $root/index.txt; : > $root/checks.jsonl; : > $root/run-metrics.jsonl; : > $root/tools.jsonl

# Fail closed (review of #12): every row this run must produce is listed up front; score.py FAILs
# any that is missing, and every tool's exit code is recorded (tools.jsonl, "tool health").
{
  print -l "x-00 UIElement" "x-00 status item" "x-00 no permission prompt" "x-00 starts hidden" "REG-026 first launch" \
           "REG-043 X" "REG-018 X" "REG-014 X" "contract X" "REG-006 X"
  for t in $edge_list; do
    print -l "geom $t (REG-013 …)" "REG-043 $t" "REG-018 $t" "REG-014 $t" "contract $t" "REG-006 $t" "REG-006 ${t}0" \
             "cua C1 panel window $t" "cua C2 cua-driver sees tiles $t" "cua C3 tiles in AX tree $t" "cua C3 REG-040 tiles are buttons $t" \
             "cua C3 REG-040 tiles pressable $t" "cua C4 status item $t" "cua C5 non-activating $t" "cua C6 click-through while hidden $t" \
             "cua C7 shown tile takes the hit $t" "cua C7 4 pt outside passes through $t" "cua C8 settings labelled $t"
    for scn in x-01 x-02 x-03 x-04 x-05a x-05b x-06; do print -r -- "$t.$scn-$t"; done
    for sd in $extra_seeds; do print -r -- "$t.x-06-$t-s$sd"; done
    (( shots )) && print -l "shot $t" "REG-006 S$t"
  done
  (( idle )) && print -l "I.idle-L" "REG-006 I"
  print -l "REG-016 cursor restored" "REG-017 no modifier held" "REG-015 no Dedock left running"
} > $root/expected.txt

tool() {  # tool <name> <rc> [ok-rcs…]: record a tool's exit code (default ok: 0 and 1 = "ran, gate failed")
  local name=$1 rc=$2; shift 2; local okrcs=(${@:-0 1})
  local ok=0; (( ${okrcs[(Ie)$rc]} )) && ok=1
  print -r -- "{\"tool\":\"$name\",\"rc\":$rc,\"ok\":$( (( ok )) && echo true || echo false)}" >> $root/tools.jsonl
  (( ok )) || print -r -- "FAIL tool $name exited $rc"
  return $(( ! ok ))
}

# Tear down on ANY exit path (review of #12): every sub-run launched by this run, plus held input.
subs=()
moved=0   # set once this run has posted pointer events; only then is the cursor restored
cleanup() {
  local s
  for s in $subs; do
    [[ -f $B/runs/$s/run.env && ! -f $B/runs/$s/teardown.txt ]] && $E/teardown.sh $s > $B/runs/$s/teardown.txt 2>&1
  done
  if (( moved )); then
    $B/pointer release > /dev/null 2>&1   # no modifier or mouse button left down (REG-017)
    (( ${#cursor0} == 2 )) && $B/pointer -q move ${cursor0[1]} ${cursor0[2]} 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'echo "interrupted: tearing down" >&2; exit 130' INT TERM

check() {  # check <id> <0|1|skip> <detail>
  python3 -c 'import json,sys; s=sys.argv[2]; print(json.dumps({"id": sys.argv[1], "ok": s == "1", "skip": s == "skip", "detail": sys.argv[3]}))' "$1" "$2" "$3" >> $root/checks.jsonl
  print -r -- "$(case $2 in 1) echo PASS ;; skip) echo SKIP ;; *) echo FAIL ;; esac) $1: $3"
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

(( selftest )) || $E/quit-refs.sh $id >/dev/null || true
cursor0=($($B/pointer pos | sed 's/[xy]=//g'))

launched() { grep -q '^PASS launched' $1 }
launch() {  # launch <sub-run> <launch.sh args…>: registers the sub-run for teardown whatever happens
  local sub=$1; shift; subs+=($sub)
  $E/launch.sh $sub "$@"
}
edge_ready_ms() { grep -o 'ms=[0-9.]*' $B/runs/$1/run.env | head -1 | cut -d= -f2 }

# Log contract on one launch (REG-018, REG-014, unknown values).
contract() {  # contract <sub-run> <tag>
  local R=$B/runs/$1
  python3 - $R/log.ndjson $R/data/e2e/geometry.json $(sed -n 's/^APP_PID=//p' $R/run.env) > $R/contract.txt 2> $R/contract.err <<'PY'
import json, sys
log, geom, pid = sys.argv[1], sys.argv[2], int(sys.argv[3])
ev = []
for line in open(log):
    if line.startswith("{"):
        try: o = json.loads(line)
        except ValueError: continue
        if o.get("processID") == pid and o.get("subsystem") == "app.dedock.Dedock":
            ev.append(o["eventMessage"])
priv = sum(1 for e in ev if "<private>" in e)
print(f"REG-043 {int(priv == 0)} debug log lines carrying <private>: {priv}/{len(ev)} (debug must log everything .public)")
ev = [e.replace("<private>", "") for e in ev]
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
  tool "contract-parser $2" $? 0
  while read -r rid ok rest; do check "$rid $2" $ok "$rest"; done < $R/contract.txt
  $B/analyze timing $R/log.ndjson > $R/contract-analyze.txt 2>&1; tool "analyze $2" $?
  local warns=$(grep -c '^WARN unrecognized' $R/contract-analyze.txt || true)
  check "contract $2" $(( warns == 0 )) "$warns unrecognized cause/kind/curve/state values"
}

# cua checks (Tests/E2E/regressions.md C1–C8): window list, AX tree and hit tests through cua-driver
# and the read-only axprobe. Never records another app's AX content (REG-041).
cua() {  # cua <sub-run> <L|R>
  local sub=$1 side=$2 R=$B/runs/$1
  local pid=$(sed -n 's/^APP_PID=//p' $R/run.env)
  local C=$R/cua; mkdir -p $C
  $B/axprobe windows $pid > $C/windows.jsonl; tool "axprobe windows $side" $? 0
  $B/axprobe tree $pid 6 > $C/tree.jsonl; tool "axprobe tree $side" $? 0
  local wid=$(python3 -c "import json,sys
ws=[json.loads(l) for l in open(sys.argv[1])]; ws=[w for w in ws if w['w']>50 and w['h']>50]
print(ws[0]['id'] if ws else '')" $C/windows.jsonl)
  if [[ -n $wid ]]; then
    cua-driver call get_window_state "{\"pid\":$pid,\"window_id\":$wid,\"include_screenshot\":false}" > $C/cua-state.json 2>&1; tool "cua-driver get_window_state $side" $? 0
  else
    tool "axprobe found no panel window $side" 1 0
  fi
  # C6: hidden dock lets clicks through at every tile centre.
  python3 -c "
import json; g=json.load(open('$R/data/e2e/geometry.json'))
for t in g['docks'][0]['tiles']:
  x,y,w,h=t['frame']['topLeft']; print(t['name'].replace(' ','_'), x+w/2, y+h/2)" > $C/tiles.txt
  : > $C/hit-hidden.jsonl
  while read -r name x y; do print -rn -- "{\"tile\":\"$name\",\"hit\":" >> $C/hit-hidden.jsonl; $B/axprobe at $x $y only=$pid | tr -d '\n' >> $C/hit-hidden.jsonl; print "}" >> $C/hit-hidden.jsonl; done < $C/tiles.txt
  $B/axprobe front > $C/front-launch.json
  # C7: reveal by dwell, pointer on a tile → Dedock gets the hit; 4 pt outside the capsule → other app.
  local probe_y=$(python3 -c "import json;d=json.load(open('$R/data/e2e/geometry.json'))['docks'][0];x,y,w,h=d['capsule']['topLeft'];print(int(y+h/2))")
  local first=($(head -1 $C/tiles.txt))
  local pts=($(python3 -c "import json;d=json.load(open('$R/data/e2e/geometry.json'))['docks'][0];x,y,w,h=d['capsule']['topLeft'];L=d['edge']=='left';print(x+w+4 if L else x-4, x+w+400 if L else x-400)"))
  local outside=${pts[1]} away=${pts[2]}
  local edge=left; [[ $side == R ]] && edge=right
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  print -l "edge $edge $probe_y" "wait 600" "glide ${first[2]} ${first[3]} 80" "wait 150" > $C/reveal.txt
  $B/pointer -q script $C/reveal.txt
  $B/axprobe at ${first[2]} ${first[3]} only=$pid > $C/hit-shown-tile.json
  $B/pointer -q move $outside ${first[3]}; sleep 0.15
  $B/axprobe at $outside ${first[3]} only=$pid > $C/hit-shown-outside.json
  $B/axprobe front > $C/front-shown.json
  $B/pointer -q move $away ${first[3]}   # leave: the dock hides before the next step
  sleep 1
  python3 $E/cua-eval.py $C $R/data/e2e/geometry.json $pid $side > $C/results.txt 2> $C/cua-eval.err; tool "cua-eval $side" $? 0
  while IFS=$'\t' read -r cid ok detail; do check "$cid" $ok "$detail"; done < $C/results.txt
  check "cua C8 settings labelled $side" skip "pending: needs the debug command openSettings"
}

run_scn() {  # run_scn <sub-run> <L|R> <scenario> [args]; re-runs once if contaminated (VOID)
  local sub=$1 side=$2 scn=$3; shift 3
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $E/scenario.sh $sub $side $scn "$@" > /dev/null; local rc=$?
  local tg=""; for kv in "$@"; do [[ $kv == tag=* ]] && tg=-${kv#tag=}; done
  local dir=$B/runs/$sub/$scn-$side$tg
  if (( rc == 3 )); then
    mv $dir $dir.void-1
    $E/scenario.sh $sub $side $scn "$@" > /dev/null; rc=$?
  fi
  tool "scenario $scn $side$tg" $rc 0 1 3   # 0 PASS, 1 FAIL, 3 VOID; anything else = the scenario itself broke
  echo "  $scn $side$tg: $(tail -1 $dir/report.txt 2>/dev/null | cut -d' ' -f2)"
}

teardown_check() {  # REG-006 after every launch
  $E/teardown.sh $1 > $B/runs/$1/teardown.txt 2>&1
  grep -q '^PASS REG-006' $B/runs/$1/teardown.txt
}

# x-00 and REG-026 on an empty data dir, with every TCC grant reset.
echo "x-00 / REG-026"
(( selftest )) || tccutil reset All app.dedock.Dedock.debug >/dev/null 2>&1   # real lock held (checked above)
X=$id-X
if launch $X --app $app --no-seed --timeout 8 > $B/runs/$id/launch-X.txt 2>&1 && launched $B/runs/$id/launch-X.txt; then
  sleep 2
  pid=$(sed -n 's/^APP_PID=//p' $B/runs/$X/run.env)
  check "x-00 UIElement" $(lsappinfo info -only ApplicationType -app $pid 2>/dev/null | grep -q UIElement && echo 1 || echo 0) "no Dock icon (LSUIElement)"
  si=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to get description of every menu bar item of menu bar 1" 2>/dev/null)
  check "x-00 status item" $([[ $si == *dedock* ]] && echo 1 || echo 0) "status item: ${si:-none}"
  if ! command -v cua-driver >/dev/null; then
    check "x-00 no permission prompt" 0 "cua-driver not installed: cannot check"
  else
    # Only prompts that appeared with this launch count; one left on screen from before (e.g. an old
    # universalAccessAuthWarn) is reported but is not an app result.
    started=$(sed -n 's/^STARTED=//p' $B/runs/$X/run.env)
    read prompts prior <<<$(cua-driver call list_windows '{}' 2>/dev/null | python3 -c '
import json, sys, subprocess, datetime
started = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
w = json.load(sys.stdin)["windows"]
new = old = 0
for x in w:
    if not (x["is_on_screen"] and x["app_name"] in ("UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "tccd")):
        continue
    lstart = subprocess.run(["ps", "-o", "lstart=", "-p", str(x["pid"])], capture_output=True, text=True).stdout.strip()
    try:
        t = datetime.datetime.strptime(lstart, "%a %b %d %H:%M:%S %Y").astimezone(datetime.timezone.utc)
    except ValueError:
        t = started
    if t >= started - datetime.timedelta(seconds=2): new += 1
    else: old += 1
print(new, old)' $started 2>/dev/null || echo "? ?")
    check "x-00 no permission prompt" $([[ $prompts == 0 ]] && echo 1 || echo 0) "new TCC/notification windows since launch: $prompts (pre-existing, not counted: ${prior:-?})"
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
  if launch $sub --app $app --frame-log $set_edge --timeout 8 > $root/launch-$tag.txt 2>&1 && launched $root/launch-$tag.txt; then
    print -r -- "$tag $sub" >> $root/index.txt
    sleep 1
    rmetric launch.${tag}_ms $(edge_ready_ms $sub)
    $E/geom-check.py $B/runs/$sub/data/e2e/geometry.json layout=$B/runs/$sub/data/layout.json padding=$padding gap=$gap > $B/runs/$sub/geom.txt 2>&1
    tool "geom-check $tag" $?
    gf=$(grep -c '^FAIL' $B/runs/$sub/geom.txt); gp=$(grep -c '^PASS' $B/runs/$sub/geom.txt)
    # fail closed: a crashed or empty geom-check has no PASS lines
    check "geom $tag (REG-013 …)" $(( gf == 0 && gp > 0 )) "$gp pass, $gf fail$( (( gf )) && print -r -- ": $(grep '^FAIL' $B/runs/$sub/geom.txt | head -2 | cut -c6-90 | tr '\n' ';')")"
    rmetric geom.${tag}_fails $gf
    cua $sub $side
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
  if launch $sub0 --app $app --frame-log $set_edge --set 'docks[0].reveal.hideDelayMs=0' --timeout 8 > $root/launch-${tag}0.txt 2>&1 && launched $root/launch-${tag}0.txt; then
    print -r -- "$tag $sub0" >> $root/index.txt
    sleep 1
    run_scn $sub0 $side x-05b n=3
    run_scn $sub0 $side x-06 seed=1
    for sd in $extra_seeds; do run_scn $sub0 $side x-06 seed=$sd tag=s$sd; done
    teardown_check $sub0; check "REG-006 ${tag}0" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch ${tag}0" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-${tag}0.txt)"
  fi
done

if (( idle )); then
  echo "idle"
  sub=$id-I
  if launch $sub --app $app --timeout 8 > $root/launch-I.txt 2>&1 && launched $root/launch-I.txt; then
    print -r -- "I $sub" >> $root/index.txt
    pid=$(sed -n 's/^APP_PID=//p' $B/runs/$sub/run.env)
    for attempt in 1 2; do
      O=$B/runs/$sub/idle-L; rm -rf $O; mkdir -p $O
      sleep 3
      $E/desktop-lock.sh touch $me >/dev/null
      $B/listen 64 > $O/listen.txt &
      lp=$!; sleep 0.5
      $H/Scripts/measure-idle.sh $pid 60 $O/perf.csv > $O/perf.txt 2>&1; tool "measure-idle" $?
      wait $lp 2>/dev/null
      {
        $B/analyze contamination $O/listen.txt idle=1 metrics=$O/metrics.jsonl; tool "analyze contamination idle" $? >&2
        cat $O/perf.txt
        grep -q '^cpu_avg_pct=' $O/perf.txt || echo "FAIL idle gate: measure-idle produced no numbers"
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

if (( shots )); then
  echo "shots"
  mkdir -p $root/shots
  for tag in $edge_list; do
    [[ $tag == R ]] && set_edge=(--set 'docks[0].edge="right"') || set_edge=()
    sub=$id-S$tag
    if launch $sub --app $app $set_edge --set 'docks[0].mode="pinned"' --timeout 8 > $root/launch-S$tag.txt 2>&1 && launched $root/launch-S$tag.txt; then
      sleep 1
      rect=($(python3 -c "import json;g=json.load(open('$B/runs/$sub/data/e2e/geometry.json'));d=g['docks'][0];x,y,w,h=d['capsule']['topLeft'];sx,sy,sw,sh=g['screens'][0]['frame']['topLeft'];m=40;X=max(sx,x-m);Y=max(sy,y-m);print(int(X),int(Y),int(min(sx+sw,x+w+m)-X),int(min(sy+sh,y+h+m)-Y))"))
      $B/backdrop ${rect[1]} ${rect[2]} ${rect[3]} ${rect[4]} 15 > /dev/null &
      local_bd=$!
      sleep 1
      screencapture -x -R ${rect[1]},${rect[2]},${rect[3]},${rect[4]} $root/shots/E1-$tag.png
      kill $local_bd 2>/dev/null
      check "shot $tag" $([[ -s $root/shots/E1-$tag.png ]] && echo 1 || echo 0) "pinned dock over a neutral backdrop, ${rect[3]}×${rect[4]} at ${rect[1]},${rect[2]} (local only)"
      teardown_check $sub; check "REG-006 S$tag" $(( $? == 0 )) "native Dock prefs unchanged"
    else
      check "shot $tag" 0 "pinned launch failed"
    fi
  done
fi

# Post-run harness checks (they gate the harness, not the app).
# A posted move lands asynchronously: reading the position right after posting can still return
# the old point. Post, then poll for up to 1 s (re-posting once) before judging.
if (( moved )); then
  $B/pointer -q move ${cursor0[1]} ${cursor0[2]}
  for i in {1..10}; do
    sleep 0.1
    now=($($B/pointer pos | sed 's/[xy]=//g'))
    python3 -c "import sys; sys.exit(not (abs(float(sys.argv[1])-float(sys.argv[3]))<=1 and abs(float(sys.argv[2])-float(sys.argv[4]))<=1))" ${cursor0[1]} ${cursor0[2]} ${now[1]} ${now[2]} && break
    (( i == 5 )) && $B/pointer -q move ${cursor0[1]} ${cursor0[2]}
  done
  check "REG-016 cursor restored" $(python3 -c "import sys; a=[float(x) for x in sys.argv[1:3]]; b=[float(x) for x in sys.argv[3:5]]; print(int(abs(a[0]-b[0])<=1 and abs(a[1]-b[1])<=1))" ${cursor0[1]} ${cursor0[2]} ${now[1]} ${now[2]}) "before ${cursor0[*]}, after ${now[*]}"
else
  check "REG-016 cursor restored" 1 "this run posted no pointer motion"
fi
mods=$($B/pointer mods)
check "REG-017 no modifier held" $([[ $mods == mods=0* ]] && echo 1 || echo 0) "$mods"
left=$(pgrep -x Dedock | tr '\n' ' ')
check "REG-015 no Dedock left running" $([[ -z $left ]] && echo 1 || echo 0) "${left:-none}"

echo
score $root
