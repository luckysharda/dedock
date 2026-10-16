#!/bin/zsh
# M1 Edge Dock end-to-end regression suite (Tests/E2E/regressions.md, docs/evaluation.md §5).
#
#   Scripts/e2e/regress.sh run <app-worktree> [id=<run-id>] [edges=L,R] [idle=1|0] [x06seeds=2,3,4] [padding=8] [gap=8] [psharing=allow] [reg061=1] [settings=1] [reg067=1] [t25=1] [h4=1] [z1=1] [t26=1] [dry=1]
#       reg061=1: gate REG-061 (the tile's AX element is the whole cell): C3 AX frame = GEOM cell ±1 pt,
#       C7 cell edge = AXButton with the tile's label. Off until a build carries the fix.
#       settings=1: run C8 (open Settings over the debug channel, labels, the editing hold, close via its
#       own AX close button). Needs a build with the Settings window; without it C8 is SKIP.
#       reg067=1: x-19 "gap hold" per edge (REG-067, the reveal corridor): 1 s in the band between
#       the zone and the capsule keeps the dock shown; after the first capsule visit, leaving through
#       the band hides it on time. SKIP on edges where the capsule meets its zone (left, right).
#       t25=1: T25 drag-out to remove, in its own launch on the right edge: the non-activating
#       confirm, Keep (AX press), a click elsewhere (Dedock's own capsule padding), Remove (layout
#       persisted), a second drag-out ignored, the 8 s timeout. Needs a build with T25.
#       h4=1: H4 hover label per edge (name + state OCR'd from a capture of Dedock's OWN panel window,
#       on the screen-centre side; AX-hidden) and row 20 (no layout.pass through a reveal and a sweep).
#       z1=1: Z1 size slider, own launch: a real drag of Settings' "Dock size" slider drives the
#       live dock; release snaps to a stop, saved, capsule = tile × (1 + 16/62) ± 1 pt.
#       t26=1: T26 SP3 Islands, own launch with a spacer and a separator seeded in its data dir:
#       two islands 8 pt apart as one dock, the spacer half a cell, fillers AX-hidden, and the gap
#       between the islands inside the dock (no leave or hide, gate open).
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
id=reg-$(date -u +%Y%m%dT%H%M%SZ) edges=L,R idle=1 dry=0 x06seeds= padding=8 gap=8 shots=0 psharing= reg061=0 settings=0 toprule=primary reg067=0 t25=0 h4=0 z1=0 t26=0
for kv in "$@"; do case $kv in id=*) id=${kv#id=} ;; t26=*) t26=${kv#t26=} ;; reg067=*) reg067=${kv#reg067=} ;; t25=*) t25=${kv#t25=} ;; h4=*) h4=${kv#h4=} ;; z1=*) z1=${kv#z1=} ;; edges=*) edges=${kv#edges=} ;; idle=*) idle=${kv#idle=} ;; dry=*) dry=${kv#dry=} ;; x06seeds=*) x06seeds=${kv#x06seeds=} ;; padding=*) padding=${kv#padding=} ;; gap=*) gap=${kv#gap=} ;; shots=*) shots=${kv#shots=} ;; psharing=*) psharing=${kv#psharing=} ;; reg061=*) reg061=${kv#reg061=} ;; settings=*) settings=${kv#settings=} ;; toprule=*) toprule=${kv#toprule=} ;; esac; done
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
# Calibrated on the 82d2d69 candidate (edges L,R + 3 extra x-06 seeds + shots + idle: 293 s measured).
est=$(( 15 + ${#edge_list} * (85 + ${#extra_seeds} * 8 + 10 + (shots ? 8 : 0) + (reg067 ? 8 : 0) + (h4 ? 8 : 0)) + (idle ? 70 : 0) + (t25 ? 45 : 0) + (z1 ? 15 : 0) + (t26 ? 15 : 0) ))
echo "regress $id: app $(git -C $app rev-parse --short HEAD) edges=$edges idle=$idle — moves the cursor for about $est s"
if (( dry )); then
  echo "plan: x-00 + REG-026 (empty data dir); per edge: launch, geom-check (padding=$padding gap=$gap), cua checks C1–C8, contract, x-01 n=4, x-02 n=4, x-03 n=3, x-04 n=3, x-05a n=3; hideDelay 0 run: x-05b n=3, x-06 seed 1${x06seeds:+ + seeds $x06seeds}$( (( reg067 )) && print -n '; x-19 gap hold (REG-067) per edge')$( (( h4 )) && print -n '; H4 hover label + row 20 per edge')$( (( t25 )) && print -n '; T25 drag-out (own launch, right edge)')$( (( t26 )) && print -n '; T26 islands (own launch)')$( (( z1 )) && print -n '; Z1 size slider (own launch)'); idle 60 s$( (( shots )) && print -n '; E1 shots per edge (pinned, neutral backdrop)'); post checks"
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

# REG-055 preflight, before ANY input: OS pointer sharing across devices has edge zones, so the
# harness's edge pushes can hand the pointer to another device, and everything it posts next (glides,
# clicks, presses, drags) then lands there. Same class as REG-051: refuse. It is a user setting and is
# never changed here; psharing=allow runs anyway (no other device nearby) and is shown on the card.
psallow=0; [[ $psharing == allow ]] && psallow=1
psharing=on
[[ $(defaults -currentHost read com.apple.universalcontrol Disable 2>/dev/null) == 1 ]] && psharing=off
if [[ $psharing == on ]]; then
  if (( ! psallow )); then
    echo "refusing: OS pointer sharing across devices is ON (REG-055): turn it off for this window, or pass psharing=allow if no other device is nearby" >&2
    exit 2
  fi
  echo "WARN REG-055 OS pointer sharing across devices is ON; running anyway (psharing=allow): recorded on the scorecard"
fi

root=$B/runs/$id
[[ -e $root ]] && { echo "run exists: $root" >&2; exit 2 }
mkdir -p $root
: > $root/index.txt; : > $root/checks.jsonl; : > $root/run-metrics.jsonl; : > $root/tools.jsonl
run_start=$(date '+%Y-%m-%d %H:%M:%S')   # local time, for the REG-055 system-log query

# Fail closed (review of #12): every row this run must produce is listed up front; score.py FAILs
# any that is missing, and every tool's exit code is recorded (tools.jsonl, "tool health").
{
  print -l "x-00 UIElement" "x-00 status item" "x-00 no permission prompt" "x-00 starts hidden" "REG-026 first launch" \
           "REG-043 X" "REG-018 X" "REG-059 X" "REG-014 X" "contract X" "REG-006 X" \
           "REG-057 corrupt layout: dock up, notice after, no input" "REG-057 corrupt layout: dock reveals while the alert is up" "REG-057 the notice does not take focus" "REG-006 C" \
           ${${(M)edges:#*L*}:+"REG-062 edge change re-derives the dwell (top 300 → left 120)"} \
           "REG-057 unreadable layout: dock up read-only, notice after, no input" "REG-006 U"
  for t in $edge_list; do
    print -l "geom $t (REG-013 …)" "REG-043 $t" "REG-018 $t" "REG-059 $t" "REG-014 $t" "contract $t" "REG-006 $t" "REG-006 ${t}0" \
             "cua C1 panel window $t" "cua C1 REG-056 panel AX identity $t" "cua C2 cua-driver sees tiles $t" "cua C3 tiles in AX tree $t" "cua C3 REG-040 tiles are buttons $t" \
             "cua C3 REG-040 tiles pressable $t" "cua C4 status item $t" "cua C5 non-activating $t" "cua C6 click-through while hidden $t" \
             "cua C7 shown tile takes the hit $t" "cua C7 tile cell edge stays in the dock $t" "cua C7 4 pt outside passes through $t" \
             "cua C9 dock style tokens $t"
    # Settings rows (C8, the C9 live switch) once per run, on the left launch (x-18 plan)
    [[ $t == B ]] && print -l "B native Dock span never triggers"
    [[ $t == T ]] && print -l "T status item area never triggers" "T menu draws above the top dock"
    [[ $t == L ]] && print -l "cua C8 Settings window opens $t" "cua C8 settings controls labelled $t" "cua C8 dock held shown while Settings is open $t" \
                              "cua C8 closing Settings releases the hold $t" "cua C9 style switch in Settings reaches GEOM $t"
    (( reg067 )) && print -l "x-19 REG-067 gap hold keeps the dock shown $t" "x-19 REG-067 corridor ends after the first capsule visit $t"
    (( h4 )) && print -l "H4 hover label $t" "row 20 no relayout during a pointer sweep $t"
    for scn in x-01 x-02 x-03 x-04 x-05a x-05b x-06; do print -r -- "$t.$scn-$t"; done
    for sd in $extra_seeds; do print -r -- "$t.x-06-$t-s$sd"; done
    (( shots )) && print -l "shot $t" "REG-006 S$t"
  done
  (( t25 )) && print -l "T25 drag-out asks without taking focus R" "T25 Keep keeps the tile R" "T25 a click elsewhere in Dedock keeps the tile (local-monitor path) R" \
                        "T25 Remove removes the tile and persists it R" "T25 a new drag answers Keep, and its drop asks again R" \
                        "T25 no answer in 8 s keeps the tile R" "REG-006 D"
  (( t26 )) && print -l "T26 separator makes two islands 8 pt apart, one dock" "T26 spacer is half an app cell" \
                        "T26 separators and spacers are hidden from accessibility" "T26 crossing the island gap keeps the dock shown, gate open" "REG-006 P"
  (( z1 )) && print -l "Z1 size slider drives the live dock while dragged" "Z1 release snaps to a stop and persists" "REG-006 Z"
  (( idle )) && print -l "I.idle-L" "REG-006 I"
  print -l "REG-016 cursor restored" "REG-017 no modifier held" "REG-015 no Dedock left running" "REG-055 no pointer hand-off"
} > $root/expected.txt

tool() {  # tool <name> <rc> [ok-rcs…]: record a tool's exit code (default ok: 0 and 1 = "ran, gate failed")
  local name=$1 rc=$2; shift 2
  local okrcs=("$@"); (( ${#okrcs} )) || okrcs=(0 1)   # NOT (${@:-0 1}): that is ONE word "0 1" (REG-052)
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

check() {  # check <id> <0|1|skip|void|env> <detail>
  # void: the probe point was occluded, rerun (never a PASS). env: unverifiable in this environment
  # (every tile centre on the edge occluded by another app's window): reported, never a PASS, and
  # not an app failure, so a third-party overlay cannot block a card.
  python3 -c 'import json,sys; s=sys.argv[2]; print(json.dumps({"id": sys.argv[1], "ok": s == "1", "skip": s == "skip", "void": s == "void", "env": s == "env", "detail": sys.argv[3]}))' "$1" "$2" "$3" >> $root/checks.jsonl
  print -r -- "$(case $2 in 1) echo PASS ;; skip) echo SKIP ;; void) echo VOID ;; env) echo ENV ;; *) echo FAIL ;; esac) $1: $3"
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
  "reg061_gates": "$reg061", "settings_c8": "$settings",
  "pointer_sharing": "$psharing$( [[ $psharing == on ]] && print -n ' (psharing=allow)')",
  "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
}, open(sys.argv[1], "w"), indent=1)
EOF

(( selftest )) || $E/quit-refs.sh $id >/dev/null || true
cursor0=($($B/pointer pos | sed 's/[xy]=//g'))

launched() { grep -q '^PASS launched' $1 }
edge_of() { case $1 in L) print left ;; R) print right ;; B) print bottom ;; T) print top ;; esac }
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
syncs = [e for e in ev if e.startswith("docks.sync ")]
first = next((kv for kv in (syncs[0].split() if syncs else []) if kv.startswith("reason=")), "none")
print(f"REG-059 {int(first == 'reason=launch')} first docks.sync after launch: {first} (exp reason=launch)")
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
  # Runs after the scenarios: wait (≤ 3 s) for the dock to be hidden again before the hidden-state checks.
  for k in {1..30}; do
    [[ $(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['docks'][0]['state'])" $R/data/e2e/geometry.json 2>/dev/null) == hidden ]] && break
    sleep 0.1
  done
  # The window list and AX tree are compared with GEOM (C1, C3): snapshot them as a PAIR with GEOM.
  # A relayout between the two (a display change mid-step, e.g. the visibleFrame moving) compared an
  # old window frame with a new GEOM (a726ee1 R). Copy GEOM before and after the snapshot; if it
  # changed in between, retake (up to 3 times) and say so.
  local G=$R/data/e2e/geometry.json k
  : > $C/pair.txt
  for k in 1 2 3; do
    cp $G $C/geom-before.json 2>/dev/null
    $B/axprobe windows $pid > $C/windows.jsonl; tool "axprobe windows $side" $? 0
    $B/axprobe tree $pid 6 > $C/tree.jsonl; tool "axprobe tree $side" $? 0
    cp $G $C/geom-pair.json 2>/dev/null
    cmp -s $C/geom-before.json $C/geom-pair.json && break
    print "relayout during snapshot $k: retaken" >> $C/pair.txt
  done
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
  # Occlusion: another app's window above the dock's level that takes the click at a tile centre
  # (a top-centre overlay, cand-95411f2c) makes a hit there say nothing about the dock. Rows probed
  # under one are VOID, never PASS; C7 probes the first tile that is not occluded.
  : > $C/occl.jsonl
  while read -r name x y; do print -rn -- "{\"tile\":\"$name\",\"occl\":" >> $C/occl.jsonl; $B/axprobe occluder $x $y $pid | tr -d '\n' >> $C/occl.jsonl; print "}" >> $C/occl.jsonl; done < $C/tiles.txt
  $B/axprobe front > $C/front-launch.json
  # C7: reveal by dwell, pointer on a tile → Dedock gets the hit; 4 pt outside the capsule → other app.
  # Probe points per edge (top-left global): along = the capsule centre along the edge; for the
  # probe tile (the first un-occluded one), "outside" = 4 pt past the capsule's inner side and
  # "away" = 400 pt past it.
  local first=($(python3 -c "
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
clear = [r['tile'] for r in rows if not r['occl'].get('occluded')]
pick = clear[0] if clear else (rows[0]['tile'] if rows else None)
print(next((l for l in open(sys.argv[2]) if l.split() and l.split()[0] == pick), '').strip())" $C/occl.jsonl $C/tiles.txt))
  print -r -- ${first[1]-} > $C/probe-tile.txt
  # No tile to probe (an empty dock in GEOM): C7 is not probed and its rows FAIL as "not probed".
  if (( ${#first} != 3 )); then tool "cua C7 no tile to probe $side" 1 0; else
  local pts=($(python3 -c "
import json, sys; d = json.load(open(sys.argv[1]))['docks'][0]; x, y, w, h = d['capsule']['topLeft']; e = d['edge']
tx, ty = float(sys.argv[2]), float(sys.argv[3])
# reveal at the middle of the widest trigger-zone strip (beside the native Dock on the bottom)
zs = [z['rect']['topLeft'] for z in d.get('zones', [])]
if zs:
    z = max(zs, key=lambda r: r[3] if e in ('left', 'right') else r[2])
    al = int(z[1] + z[3] / 2) if e in ('left', 'right') else int(z[0] + z[2] / 2)
else:
    al = int(y + h / 2) if e in ('left', 'right') else int(x + w / 2)
o = {'left': (x + w + 4, ty), 'right': (x - 4, ty), 'bottom': (tx, y - 4), 'top': (tx, y + h + 4)}[e]
a = {'left': (x + w + 400, ty), 'right': (x - 400, ty), 'bottom': (tx, y - 400), 'top': (tx, y + h + 400)}[e]
print(e, al, *o, *a)" $R/data/e2e/geometry.json ${first[2]} ${first[3]}))
  local edge=${pts[1]} along=${pts[2]} out=(${pts[3]} ${pts[4]}) awy=(${pts[5]} ${pts[6]})
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  print -l "edge $edge $along" "wait 600" "glide ${first[2]} ${first[3]} 80" "wait 150" > $C/reveal.txt
  $B/pointer -q script $C/reveal.txt
  $B/axprobe at ${first[2]} ${first[3]} only=$pid > $C/hit-shown-tile.json
  $B/axprobe occluder ${first[2]} ${first[3]} $pid > $C/occl-tile.json
  # C7 cell edge: inside the probe tile's GEOM cell but outside its (smaller) icon/AX frame, 2 pt in
  # from the cell's edge on the side away from the screen edge (along x on left/right docks, along y on
  # bottom/top docks): still the dock, never the window under it.
  local cell=($(python3 -c "
import json, sys; d = json.load(open(sys.argv[1]))['docks'][0]
x, y, w, h = next(t for t in d['tiles'] if t['name'].replace(' ', '_') == sys.argv[2])['frame']['topLeft']
print(*{'left': (x + w - 2, y + h / 2), 'right': (x + 2, y + h / 2), 'bottom': (x + w / 2, y + 2), 'top': (x + w / 2, y + h - 2)}[d['edge']])" $R/data/e2e/geometry.json ${first[1]}))
  $B/pointer -q move ${cell[1]} ${cell[2]}; sleep 0.15
  $B/axprobe at ${cell[1]} ${cell[2]} only=$pid > $C/hit-shown-cell.json
  $B/axprobe occluder ${cell[1]} ${cell[2]} $pid > $C/occl-cell.json
  # Probe 4 pt outside only once the mouse gate has closed (gate.mouse ignores=true after the move),
  # up to 1 s: an AX hit taken before the app processed the move measured timing, not click-through.
  local g0=$(wc -l < $R/log.ndjson) k gated=0 lo
  # A listener around the move tells "the move event never reached the system" (not seen) from
  # "it arrived but the app didn't act on it" (seen, gate unchanged): e7's question, 95411f2.
  $B/listen 2 > $C/listen-outside.txt & lo=$!; sleep 0.3
  $B/pointer -q move ${out[1]} ${out[2]}
  for k in {1..20}; do sleep 0.05; (( $(log_count $R/log.ndjson $pid '^gate[.]mouse .*ignores=true' $g0) > 0 )) && { gated=1; break }; done
  wait $lo 2>/dev/null
  local seen=$(grep -c "ev=move x=${out[1]%.*}" $C/listen-outside.txt 2>/dev/null || true)
  print -r -- "gate closed after the move: $( (( gated )) && echo "yes ($(( k * 50 )) ms)" || echo 'no (1 s)'); move event seen by the listener: $( (( ${seen:-0} > 0 )) && echo yes || echo no)" > $C/gate-outside.txt
  $B/axprobe at ${out[1]} ${out[2]} only=$pid > $C/hit-shown-outside.json
  $B/axprobe occluder ${out[1]} ${out[2]} $pid > $C/occl-outside.json
  $B/axprobe front > $C/front-shown.json
  $B/pointer -q move ${awy[1]} ${awy[2]}   # leave: the dock hides before the next step
  sleep 1
  fi
  # C8 (settings=1, a build with Settings): openSettings over the debug channel → a titled Settings
  # window from our pid, every control labelled, the dock held shown (editing) while it is open; its
  # own close button (AX press, our window only) releases the hold and the dock hides (pointer away).
  if (( settings )) && [[ $side == L ]]; then   # once per run (x-18 plan): Settings is not per edge
    local SP=$R/log.ndjson
    $B/notify $pid openSettings > /dev/null; tool "notify openSettings $side" $? 0
    sleep 1.5
    $B/axprobe windows $pid > $C/settings-windows.jsonl
    $B/axprobe tree $pid 14 > $C/settings-tree.jsonl; tool "axprobe settings tree $side" $? 0
    python3 $E/log-order.py $SP pid=$pid '^debug[.]command cmd=openSettings ok=true' '^inhibitor .*token=editing on=true' '^reveal[.]transition .*to=shown' > $C/c8-open.txt
    $B/axprobe front > $C/front-settings.json
    # C9 live style switch: press "Light Glass" in the Style segment → settings.changed key=dd.dock.style
    # → docks.sync reason=settings → GEOM style/material; then back to Dark Glass (the seeded default).
    $B/axpress press $pid "Dedock Settings" "Light Glass" > $C/c9-press.txt 2>&1; echo "rc=$?" >> $C/c9-press.txt
    sleep 1
    python3 $E/log-order.py $SP pid=$pid '^debug[.]command cmd=openSettings ok=true' '^settings[.]changed key=dd[.]dock[.]style value=lightGlass' '^docks[.]sync reason=settings' > $C/c9-switch.txt
    cp $R/data/e2e/geometry.json $C/geom-style.json 2>/dev/null
    $B/axpress press $pid "Dedock Settings" "Dark Glass" > /dev/null 2>&1; sleep 0.6
    # well away from the dock before the close (≥ 60 pt past the capsule + 16 pt hysteresis), so a
    # dock that stays shown can only be the app's doing (review of #27)
    $B/pointer -q move ${awy[1]} ${awy[2]}; sleep 0.2
    $B/axpress close $pid "Dedock Settings" > $C/c8-close-press.txt 2>&1; tool "axpress close Settings $side" $? 0
    sleep 1.2
    python3 $E/log-order.py $SP pid=$pid '^debug[.]command cmd=openSettings ok=true' '^inhibitor .*token=editing on=true' '^inhibitor .*token=editing on=false' '^reveal[.]transition .*to=hidden' > $C/c8-close.txt
    $B/axprobe windows $pid > $C/settings-windows-after.jsonl
  fi
  [[ $side == L ]] && reg062 $R $pid
  [[ $side == B || $side == T ]] && edge_rows $R $pid $side
  (( reg067 )) && gap_hold $R $pid $side
  (( h4 )) && h4_rows $R $pid $side
  cmp -s $C/geom-pair.json $G || print "relayout during step (GEOM changed after the snapshot; C1/C3 use the paired GEOM)" >> $C/pair.txt
  DEDOCK_REG061=$reg061 python3 $E/cua-eval.py $C $R/data/e2e/geometry.json $pid $side > $C/results.txt 2> $C/cua-eval.err; tool "cua-eval $side" $? 0
  while IFS=$'\t' read -r cid ok detail; do check "$cid" $ok "$detail"; done < $C/results.txt
}

# REG-062: edge-derived reveal values are derived when the dock is mapped, never stored, so an edge
# change re-derives them: setEdge=top → effective showDwellMs 300 (the top edge's minimum); then
# setEdge=left → 120 with a 3 pt zone (the native Dock is not on the left). Debug channel only, no
# input; once per run (left launch). SKIP when the build's GEOM has no showDwellMs or settings=0.
reg062() {  # reg062 <run dir> <pid>
  local R=$1 pid=$2 cid="REG-062 edge change re-derives the dwell (top 300 → left 120)" t l
  if (( ! settings )) || ! grep -q '"showDwellMs"' $R/data/e2e/geometry.json 2>/dev/null; then
    check "$cid" skip "needs settings=1 and a build whose GEOM reports showDwellMs"; return
  fi
  geom_at() {  # geom_at <edge>: wait (≤ 3 s) for GEOM edge, print "dwell thickness"
    local k
    for k in {1..30}; do
      python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))['docks'][0]
if d['edge'] != sys.argv[2]: sys.exit(1)
z = [q['rect']['topLeft'] for q in d.get('zones', [])]
th = min((r[2] if d['edge'] in ('left', 'right') else r[3]) for r in z) if z else -1
print(d.get('showDwellMs', -1), th)" $R/data/e2e/geometry.json $1 2>/dev/null && return
      sleep 0.1
    done
    print -- "-1 -1"
  }
  $B/notify $pid setEdge=top > /dev/null; t=($(geom_at top))
  $B/notify $pid setEdge=left > /dev/null; l=($(geom_at left))
  sleep 0.5
  # zone thickness 3 pt, or 6 pt where the native Dock shares the edge (derived, never stored)
  local nd=$(defaults read com.apple.dock orientation 2>/dev/null || echo bottom) lt=3
  [[ $nd == left ]] && lt=6
  check "$cid" $(( t[1] == 300 && l[1] == 120 && l[2] == lt )) "top: showDwellMs ${t[1]}, zone ${t[2]} pt; left: showDwellMs ${l[1]}, zone ${l[2]} pt (exp 300 → 120, $lt pt with the native Dock at the $nd)"
}

# x-18 rows for the bottom and top edges. Absence checks count our pid's log lines in a window.
log_count() {  # log_count <log.ndjson> <pid> <regex> [from-line]: matching lines of that pid after from-line
  python3 -c "
import json, re, sys
rx, pid, start = re.compile(sys.argv[3]), int(sys.argv[2]), int(sys.argv[4]) if len(sys.argv) > 4 else 0
n = 0
for i, l in enumerate(open(sys.argv[1])):
    if i < start or not l.startswith('{'): continue
    r = json.loads(l)
    if r.get('processID') == pid and rx.search(r.get('eventMessage', '')): n += 1
print(n)" "$@" 2>/dev/null || echo -1
}
edge_rows() {  # edge_rows <run dir> <pid> <B|T>
  local R=$1 pid=$2 side=$3 L=$1/log.ndjson G=$1/data/e2e/geometry.json n0 hits
  if [[ $side == B ]]; then
    # "native Dock span never triggers": a short dwell + push on the bottom edge at the native Dock's
    # centre must give no zone entry. Brief: the native Dock may magnify (not ours to judge).
    local cid="B native Dock span never triggers"
    local nx=$(python3 -c "
import json, sys; g = json.load(open(sys.argv[1])); d = g['docks'][0]
nd = (d.get('nativeDock') or g['screens'][0].get('nativeDock') or {}).get('rect')
print(int(nd['topLeft'][0] + nd['topLeft'][2] / 2) if nd else '')" $G 2>/dev/null)
    if [[ -z $nx ]]; then check "$cid" skip "GEOM reports no native Dock footprint on this screen"; return; fi
    n0=$(wc -l < $L)
    # starts and ends off the edge (y 400), so no zone strip is touched on the way in or out
    print -l "move $nx 400" "wait 200" "edge bottom $nx" "wait 400" "push bottom $nx 6 5 60" "wait 300" "move $nx 400" "wait 300" > $R/ndock-probe.txt
    $B/pointer -q script $R/ndock-probe.txt
    hits=$(log_count $L $pid '^edge[.]zoneEnter' $n0)
    check "$cid" $(( hits == 0 )) "zone entries while dwelling and pushing over the native Dock: $hits"
  else
    # "status item area never triggers": a dwell on the top edge over Dedock's OWN status item
    local cid="T status item area never triggers"
    local sx=$(python3 -c "
import json, sys
for l in open(sys.argv[1]):
    e = json.loads(l)
    if e.get('role') == 'AXMenuBarItem' and (e.get('label') or '').lower() == 'dedock' and 'x' in e: print(int(e['x'] + e['w'] / 2)); break" $R/cua/tree.jsonl 2>/dev/null)
    # The candidate span along the top edge before exclusions (zones.computed span=a..b; else the
    # capsule ± 40). Outside it, no zone could exist anyway, so the row would prove nothing: SKIP.
    local span=($(python3 -c "
import json, re, sys
sp = None
for l in open(sys.argv[1]):
    if l.startswith('{'):
        r = json.loads(l)
        if r.get('processID') == int(sys.argv[2]):
            m = re.match(r'zones[.]computed edge=top .*span=(-?[0-9]+)[.][.](-?[0-9]+)', r.get('eventMessage', ''))
            if m: sp = (m.group(1), m.group(2))
if not sp:
    d = json.load(open(sys.argv[3]))['docks'][0]; x, y, w, h = d['capsule']['topLeft']; sp = (int(x - 40), int(x + w + 40))
print(*sp)" $L $pid $G 2>/dev/null))
    if [[ -z $sx ]]; then check "$cid" 0 "Dedock's status item not found in the AX tree"
    elif (( ${#span} == 2 )) && (( sx < span[1] || sx > span[2] )); then
      check "$cid" skip "Dedock's status item (x $sx) is outside the top zone's candidate span ${span[1]}..${span[2]}: nothing to prove here"
    else
      n0=$(wc -l < $L)
      print -l "edge top $sx" "wait 700" "move $sx 400" "wait 300" > $R/status-probe.txt
      $B/pointer -q script $R/status-probe.txt
      hits=$(log_count $L $pid '^edge[.]zoneEnter' $n0)
      check "$cid" $(( hits == 0 )) "zone entries while dwelling over Dedock's status item: $hits"
    fi
    # "menu draws above the top dock": dock shown (debug reveal), our status menu opened through AX;
    # its window must sit above the dock's level 24. Closed again with AXCancel; dock hidden.
    cid="T menu draws above the top dock"
    $B/notify $pid reveal > /dev/null; sleep 0.6
    $B/axpress menu $pid > $R/menu-open.txt 2>&1; local mrc=$?
    sleep 0.4
    $B/axprobe windows $pid > $R/menu-windows.jsonl
    $B/axpress menu-cancel $pid > /dev/null 2>&1
    $B/notify $pid hide > /dev/null; sleep 0.5
    local lv=$(python3 -c "
import json, sys
ws = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
m = [w['layer'] for w in ws if w.get('onscreen') and w['layer'] not in (0, 24) and w['w'] > 20]
print(max(m) if m else -1)" $R/menu-windows.jsonl 2>/dev/null || echo -1)
    check "$cid" $(( mrc == 0 && lv > 24 )) "status menu opened: $( (( mrc == 0 )) && echo yes || echo no); its window layer: $lv (dock 24)"
  fi
}

press_ok() {  # press_ok <x> <y> <pid> [role] [label]: REG-068, the hit at a point is Dedock's own element
  # (and that role/label) right now; every pointer press in this harness is sent only after this.
  $B/axprobe at $1 $2 only=$3 | python3 -c "
import json, sys
d = json.load(sys.stdin); pid, role, label = int(sys.argv[1]), sys.argv[2], sys.argv[3]
# the hit element or one of its parents (a slider's knob is its AXValueIndicator child)
els = [d] + d.get('chain', [])
fits = lambda e: (not role or e.get('role') == role) and (not label or e.get('label') == label)
sys.exit(not (d.get('pid') == pid and any(fits(e) for e in els)))" $3 "${4:-}" "${5:-}"
}

gap_hold() {  # gap_hold <run dir> <pid> <side>: x-19 "gap hold" (REG-067, reg067=1)
  # Zone dwell → reveal; 1 s in the band between the zone and the capsule ± hysteresis (the top
  # edge's menu-bar band; the diagonal over the native Dock beside it) → still shown (the reveal
  # corridor); into the capsule; back to the band and hold → the hide starts hideDelay ± 16 ms after
  # the leave (the corridor is gone after the first visit). Edges where the capsule meets its zone
  # have no band: SKIP. Real input during the probe makes both rows VOID.
  local R=$1 pid=$2 side=$3 L=$1/log.ndjson n0 n1 n2 lp cid ok detail
  local p=($(python3 $E/gap-hold.py plan $R/data/e2e/geometry.json $R/data/layout.json 2>&1))
  local ids=("x-19 REG-067 gap hold keeps the dock shown $side" "x-19 REG-067 corridor ends after the first capsule visit $side")
  if [[ ${p[1]} == skip ]]; then
    for cid in $ids; do check "$cid" skip "${p[2,-1]}"; done; return
  elif (( ${#p} != 10 )); then
    tool "gap-hold plan $side" 2 0; for cid in $ids; do check "$cid" 0 "no plan: ${p[*]}"; done; return
  fi
  local e=${p[1]} al=${p[2]} t=(${p[3]} ${p[4]}) g=(${p[5]} ${p[6]}) aw=(${p[7]} ${p[8]}) hide=${p[9]} dwell=${p[10]}
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $B/pointer -q move ${aw[1]} ${aw[2]}; sleep 0.8   # start hidden, away from the dock
  $B/listen 8 > $R/gap-listen.txt & lp=$!; sleep 0.3
  n0=$(wc -l < $L)
  print -l "edge $e $al" "wait $(( dwell + 500 ))" "glide ${g[1]} ${g[2]} 600" "wait 1000" > $R/gap-1.txt
  $B/pointer -q script $R/gap-1.txt; sleep 0.3
  n1=$(wc -l < $L)
  print -l "glide ${t[1]} ${t[2]} 200" "wait 400" "glide ${g[1]} ${g[2]} 150" "wait $(( hide + 500 ))" "move ${aw[1]} ${aw[2]}" "wait 600" > $R/gap-2.txt
  $B/pointer -q script $R/gap-2.txt; sleep 0.5
  n2=$(wc -l < $L)
  wait $lp 2>/dev/null
  $B/analyze contamination $R/gap-listen.txt > $R/gap-contam.txt 2>&1; tool "analyze contamination gap $side" $? 0 1
  python3 $E/gap-hold.py judge $L $pid $n0 $n1 $n2 $hide $side > $R/gap-results.txt 2> $R/gap-judge.err; tool "gap-hold judge $side" $? 0
  local foreign=$(grep -c '^FAIL input contamination' $R/gap-contam.txt)
  while IFS=$'\t' read -r cid ok detail; do
    if (( foreign )); then check "$cid" void "real input during the probe (rerun): $detail"; else check "$cid" $ok "$detail"; fi
  done < $R/gap-results.txt
}

h4_rows() {  # h4_rows <run dir> <pid> <side>: H4 hover label (row 10) and row 20 (h4=1)
  # Reveal, rest on the first app tile and then the first folder tile, capturing Dedock's OWN panel
  # window (screencapture -l: no other app's pixels) each time; OCR (ocr.swift) must find the
  # tile's name and its state on the screen-centre side of the capsule, and no AX static text may
  # carry a tile name (the label is AX-hidden). Then a sweep over every tile and away: row 20 wants
  # no layout.pass from the reveal to the end. Captures stay in the run dir (build/, never posted).
  local R=$1 pid=$2 side=$3 L=$1/log.ndjson G=$1/data/e2e/geometry.json n0 n1 lp wid k
  local p=($(python3 $E/h4.py plan $G 2>/dev/null))
  if (( ${#p} < 10 )); then
    tool "h4 plan $side" 2 0; check "H4 hover label $side" 0 "no plan from GEOM"; check "row 20 no relayout during a pointer sweep $side" 0 "no plan from GEOM"; return
  fi
  local e=${p[1]} al=${p[2]} a=(${p[3]} ${p[4]}) f=(${p[5]} ${p[6]}) aw=(${p[7]} ${p[8]}) sw=(${p[9,-1]})
  local dwell=$(python3 -c "import json,sys; print(int(json.load(open(sys.argv[1]))['docks'][0].get('showDwellMs', 300)))" $G)
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $B/pointer -q move ${aw[1]} ${aw[2]}; sleep 0.8
  $B/listen 12 > $R/h4-listen.txt & lp=$!; sleep 0.3
  n0=$(wc -l < $L)
  print -l "edge $e $al" "wait $(( dwell + 500 ))" "glide ${a[1]} ${a[2]} 120" "wait 150" > $R/h4-1.txt
  $B/pointer -q script $R/h4-1.txt
  $B/axprobe windows $pid | python3 -c "
import json, sys
ws = [json.loads(l) for l in sys.stdin if l.strip()]
w = next((w for w in ws if w['layer'] == 24 and w['w'] > 50 and w['h'] > 50), None)
json.dump(w or {}, open(sys.argv[1], 'w'))" $R/h4-window.json
  wid=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('id', ''))" $R/h4-window.json)
  [[ -n $wid ]] && screencapture -x -o -l $wid $R/h4-a.png; tool "screencapture panel $side" $? 0
  # A blank capture (no Screen Recording for the host, or no panel) is a harness fault, not an H4
  # result: tool health fails, so it cannot read as an app FAIL.
  $B/ocr stats $R/h4-a.png > $R/h4-a-stats.json 2>&1; tool "h4 capture not blank $side" $? 0
  $B/axprobe tree $pid 8 > $R/h4-tree.jsonl
  $B/pointer -q glide ${f[1]} ${f[2]} 150; sleep 0.15
  [[ -n $wid ]] && screencapture -x -o -l $wid $R/h4-f.png
  : > $R/h4-sweep.txt
  for (( k = 1; k < ${#sw}; k += 2 )); do print -r -- "glide ${sw[k]} ${sw[k+1]} 120" >> $R/h4-sweep.txt; done
  for (( k = ${#sw} - 1; k >= 1; k -= 2 )); do print -r -- "glide ${sw[k]} ${sw[k+1]} 120" >> $R/h4-sweep.txt; done
  print -l "move ${aw[1]} ${aw[2]}" "wait 800" >> $R/h4-sweep.txt
  $B/pointer -q script $R/h4-sweep.txt; sleep 0.3
  n1=$(wc -l < $L)
  wait $lp 2>/dev/null
  for k in a f; do
    # Vision can fail transiently (an e5rt compute error in cand-7a34887b): up to 3 tries on exit 2
    if [[ -s $R/h4-$k.png ]]; then
      local orc=2 try
      for try in 1 2 3; do $B/ocr $R/h4-$k.png > $R/h4-ocr-$k.jsonl 2>> $R/h4-ocr.err; orc=$?; (( orc != 2 )) && break; sleep 0.5; done
      tool "ocr $k $side" $orc 0
    else : > $R/h4-ocr-$k.jsonl; fi
  done
  $B/analyze contamination $R/h4-listen.txt > $R/h4-contam.txt 2>&1; tool "analyze contamination h4 $side" $? 0 1
  python3 $E/h4.py judge $G $R/h4-window.json $R/h4-ocr-a.jsonl $R/h4-ocr-f.jsonl $R/h4-tree.jsonl $side > $R/h4-results.txt 2> $R/h4-judge.err; tool "h4 judge $side" $? 0
  local passes=$(log_count $L $pid '^layout[.]pass' $n0) shown=$(log_count $L $pid '^reveal[.]transition .*to=shown' $n0)
  local foreign=$(grep -c '^FAIL input contamination' $R/h4-contam.txt) cid ok detail
  { cat $R/h4-results.txt
    print -r -- "row 20 no relayout during a pointer sweep $side	$(( passes == 0 && shown > 0 ))	layout passes from the reveal through a sweep over all $(( ${#sw} / 2 )) tiles and away: $passes (exp 0); revealed: $( (( shown )) && echo yes || echo no)"
  } | while IFS=$'\t' read -r cid ok detail; do
    if (( foreign )); then check "$cid" void "real input during the probe (rerun): $detail"; else check "$cid" $ok "$detail"; fi
  done
}

t26_rows() {  # t26_rows <run dir> <pid>: T26 SP3 Islands (t26=1), own launch on the left edge
  # GEOM: two islands 8 pt apart, the capsule their union, one zone; the spacer half an app cell.
  # AX: only the three apps are buttons (fillers hidden). Probe: reveal, rest on the tile before the
  # separator, glide into the gap between the islands and hold 0.7 s (> the hide delay), on to the
  # tile after it: the gap is INSIDE the dock (no leave, no hide, the mouse gate stays open, the hit
  # in the gap is Dedock). Real input during the probe: VOID.
  local R=$1 pid=$2 L=$1/log.ndjson G=$1/data/e2e/geometry.json n0 n1 lp cid ok detail
  python3 $E/t26.py geom $G > $R/t26-geom.txt 2> $R/t26.err; tool "t26 geom" $? 0
  while IFS=$'\t' read -r cid ok detail; do check "$cid" $ok "$detail"; done < $R/t26-geom.txt
  $B/axprobe tree $pid 6 > $R/t26-tree.jsonl
  local ax=$(python3 -c "
import json, sys
els = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
names = {t['name'] for t in json.load(open(sys.argv[2]))['docks'][0]['tiles'] if t.get('kind') in ('app', 'folder')}
buttons = sorted(e.get('label', '') for e in els if e.get('role') == 'AXButton' and e.get('depth', 0) >= 1)
fill = [e for e in els if e.get('depth', 0) >= 1 and (e.get('label') or '').lower() in ('spacer', 'separator')]
print(int(set(buttons) == names and len(buttons) == len(names) and not fill), '|'.join(buttons) or '-', len(fill))" $R/t26-tree.jsonl $G 2>/dev/null)
  local axv=(${(s: :)ax})
  check "T26 separators and spacers are hidden from accessibility" ${axv[1]:-0} "tile buttons in the AX tree: ${axv[2]:-?} (exp the 3 apps only); filler elements: ${axv[3]:-?} (exp 0)"
  local p=($(python3 $E/t26.py gap $G 2>/dev/null))
  cid="T26 crossing the island gap keeps the dock shown, gate open"
  if (( ${#p} != 10 )); then check "$cid" 0 "no gap probe points from GEOM: ${p[*]}"; return; fi
  local e=${p[1]} al=${p[2]} g=(${p[3]} ${p[4]}) a=(${p[5]} ${p[6]}) b=(${p[7]} ${p[8]}) aw=(${p[9]} ${p[10]}) hit=0
  local dwell=$(python3 -c "import json,sys; print(int(json.load(open(sys.argv[1]))['docks'][0].get('showDwellMs', 300)))" $G)
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $B/pointer -q move ${aw[1]} ${aw[2]}; sleep 0.8
  $B/listen 8 > $R/t26-listen.txt & lp=$!; sleep 0.3
  print -l "edge $e $al" "wait $(( dwell + 500 ))" "glide ${a[1]} ${a[2]} 120" "wait 200" > $R/t26-1.txt
  $B/pointer -q script $R/t26-1.txt
  n0=$(wc -l < $L)
  $B/pointer -q glide ${g[1]} ${g[2]} 150; sleep 0.15
  press_ok ${g[1]} ${g[2]} $pid && hit=1
  sleep 0.55
  $B/pointer -q glide ${b[1]} ${b[2]} 150; sleep 0.2
  n1=$(wc -l < $L)
  $B/pointer -q move ${aw[1]} ${aw[2]}; sleep 0.8
  wait $lp 2>/dev/null
  $B/analyze contamination $R/t26-listen.txt > $R/t26-contam.txt 2>&1; tool "analyze contamination t26" $? 0 1
  # only the probe's own lines (n0..n1): from the first tile, through the gap, to the next tile
  local leaves closed
  leaves=$(python3 -c "
import json, re, sys
n = 0
for i, l in enumerate(open(sys.argv[1])):
    if i < int(sys.argv[2]) or i >= int(sys.argv[3]) or not l.startswith('{'): continue
    r = json.loads(l.rstrip().rstrip(','))
    if r.get('processID') == int(sys.argv[4]) and re.search(sys.argv[5], r.get('eventMessage', '')): n += 1
print(n)" $L $n0 $n1 $pid '^reveal[.]transition .*to=(armingHide|hiding)')
  closed=$(python3 -c "
import json, re, sys
n = 0
for i, l in enumerate(open(sys.argv[1])):
    if i < int(sys.argv[2]) or i >= int(sys.argv[3]) or not l.startswith('{'): continue
    r = json.loads(l.rstrip().rstrip(','))
    if r.get('processID') == int(sys.argv[4]) and re.search(sys.argv[5], r.get('eventMessage', '')): n += 1
print(n)" $L $n0 $n1 $pid '^gate[.]mouse .*ignores=true')
  detail="tile → island gap (held 0.7 s) → next tile: leave/hide transitions $leaves (exp 0); mouse gate closed $closed time(s) (exp 0); AX hit in the gap is Dedock: $( (( hit )) && echo yes || echo no)"
  if grep -q '^FAIL input contamination' $R/t26-contam.txt; then check "$cid" void "real input during the probe (rerun): $detail"
  else check "$cid" $(( leaves == 0 && closed == 0 && hit )) "$detail"; fi
}

z1_rows() {  # z1_rows <run dir> <pid>: Z1 size slider (row 27), z1=1, own launch on the left edge
  # Settings over the debug channel; a real drag of its "Dock size" slider (our own window) from
  # M toward XL, held: mid-drag GEOM shows a live, non-stop tile thickness with the dock shown and
  # layout passes during the drag; on release the tile thickness snaps to a stop (48/62/76/92), the
  # saved size matches it, and the capsule thickness is tile × (1 + 16/62) ± 1 pt. Settings is closed
  # with its own close button. Only this launch's isolated data dir is touched.
  local R=$1 pid=$2 L=$1/log.ndjson G=$1/data/e2e/geometry.json Y=$1/data/layout.json n0 n1 dp lp
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $B/notify $pid openSettings > /dev/null; tool "notify openSettings Z" $? 0
  sleep 1.5
  # REG-068: the slider may sit below the screen in a tall pane: scroll it into view through AX on
  # our own control, then press only where the hit is Dedock's AXSlider "Dock size" (start and end).
  $B/axpress scroll $pid "Dedock Settings" "Dock size" > $R/z1-scroll.txt 2>&1; tool "axpress scroll Dock size" $? 0
  sleep 0.6
  $B/axprobe tree $pid 14 > $R/z1-tree.jsonl
  local sl=($(python3 $E/z1.py points $R/z1-tree.jsonl 2>/dev/null))
  local r1="0	the Settings slider 'Dock size' was not found in the AX tree" r2="0	not reached"
  if (( ${#sl} == 3 )) && ! { press_ok ${sl[1]} ${sl[2]} $pid AXSlider "Dock size" && press_ok ${sl[3]} ${sl[2]} $pid AXSlider "Dock size" }; then
    r1="0	not reachable: the hit at the slider's knob (${sl[1]}, ${sl[2]}) or drag end is not Dedock's AXSlider 'Dock size' (off screen or covered); nothing pressed"
    r2="0	not reached (nothing pressed)"
  elif (( ${#sl} == 3 )); then
    $B/listen 8 > $R/z1-listen.txt & lp=$!; sleep 0.3
    n0=$(wc -l < $L)
    $B/pointer -q drag ${sl[1]} ${sl[2]} ${sl[3]} ${sl[2]} 600 1200 & dp=$!   # travel 0.6 s, then hold 1.2 s  (guarded: press_ok)
    sleep 1.2
    cp $G $R/z1-mid.json 2>/dev/null
    local passes_mid=$(log_count $L $pid '^layout[.]pass' $n0)
    wait $dp
    sleep 1.2
    n1=$(wc -l < $L)
    wait $lp 2>/dev/null
    cp $G $R/z1-after.json 2>/dev/null
    $B/analyze contamination $R/z1-listen.txt > $R/z1-contam.txt 2>&1; tool "analyze contamination z1" $? 0 1
    local out=("${(@f)$(python3 $E/z1.py judge $R/z1-mid.json $R/z1-after.json $Y $passes_mid 2> $R/z1-judge.err)}")
    r1="${out[1]}" r2="${out[2]}"
    local foreign=$(grep -c '^FAIL input contamination' $R/z1-contam.txt)
    if (( foreign )); then r1="void	real input during the drag (rerun): ${r1#*	}"; r2="void	real input during the drag (rerun): ${r2#*	}"; fi
  fi
  $B/axpress close $pid "Dedock Settings" > /dev/null 2>&1; tool "axpress close Settings Z" $? 0
  sleep 0.5
  check "Z1 size slider drives the live dock while dragged" ${r1%%	*} "${r1#*	}"
  check "Z1 release snaps to a stop and persists" ${r2%%	*} "${r2#*	}"
}

t25_rows() {  # t25_rows <run dir> <pid>: T25 drag-out to remove (row 43), t25=1, own launch on the right edge
  # ⌘-drag a tile out past the capsule + hysteresis → the non-activating confirm (non-key, frontmost
  # unchanged, popoverOpen hold); Keep (AX press) and a click elsewhere keep it. The click lands on
  # Dedock's own capsule padding, so it exercises the confirm's LOCAL event monitor; the global
  # monitor (a click in another app) stays untested by design: the harness never clicks other apps.
  # Remove removes it and persists the layout. A new drag while asking: its mouse-down is a click
  # elsewhere, so question 1 answers Keep first and the new drop asks again (never two questions,
  # no hide in between; e9's ruling). No answer in 8 s keeps it. Every drag starts only after an AX
  # hit on the tile's own button (REG-068). Only this launch's isolated data dir is touched;
  # every press is on Dedock's own windows. Real input during the probe makes every row VOID.
  local R=$1 pid=$2 L=$1/log.ndjson G=$1/data/e2e/geometry.json Y=$1/data/layout.json lp n f0 f1 fc w k
  local -A row
  local pl ids0 ids1
  t25_plan() { pl=($(python3 $E/t25.py plan $G $Y $1)); (( ${#pl} >= 12 )) }
  t25_title() { print -r -- "${pl[12,-1]}" }
  t25_reveal_drag() {  # reveal at the zone, onto tile pl, ⌘-drag it out; leaves the question open
    print -l "edge ${pl[1]} ${pl[2]}" "wait $(( ${pl[10]} + 500 ))" "glide ${pl[3]} ${pl[4]} 80" "wait 200" > $R/t25-reveal.txt
    $B/pointer -q script $R/t25-reveal.txt
    t25_drag
  }
  t25_drag() {  # ⌘-drag tile pl out, only once the hit at its centre is Dedock's own tile button (REG-068)
    # Move onto the tile first: away from the capsule the dock's mouse gate is closed and the hit
    # there is the window underneath. Then poll the AX hit for up to 1 s before pressing.
    local name=$(python3 -c "import json,sys; print(next(t['name'] for t in json.load(open(sys.argv[1]))['docks'][0]['tiles'] if t['id'] == sys.argv[2]))" $G ${pl[11]}) ok=0 k
    $B/pointer -q move ${pl[3]} ${pl[4]}
    for k in {1..10}; do sleep 0.1; press_ok ${pl[3]} ${pl[4]} $pid AXButton "$name" && { ok=1; break }; done
    if (( ok )); then
      $B/pointer -q drag ${pl[3]} ${pl[4]} ${pl[5]} ${pl[6]} 300 100 cmd; tool "pointer drag t25" $? 0   # guarded: press_ok
    else
      tool "t25 drag start is not Dedock's tile: not pressed" 2 0
    fi
    sleep 0.6
  }
  t25_questions() { $B/axprobe tree $pid 1 | python3 -c "import json,sys; print(sum(1 for l in sys.stdin if l.strip() and json.loads(l).get('role') == 'AXWindow' and (json.loads(l).get('label') or '').startswith('Remove ')))" }
  t25_asked() { $B/axprobe tree $pid 1 | python3 -c "import json,sys; t=sys.argv[1]; sys.exit(not any(json.loads(l).get('role') == 'AXWindow' and json.loads(l).get('label') == t for l in sys.stdin if l.strip()))" "$(t25_title)" }
  t25_result() { log_count $L $pid "^tile[.]removeConfirm .*id=$1 .*result=$2|^tile[.]removeConfirm .*result=$2 .*id=$1" $3 }
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  $B/listen 60 > $R/t25-listen.txt & lp=$!; sleep 0.3
  t25_plan 0 || { tool "t25 plan" 2 0; row[ask]="0	no plan: ${pl[*]}" }
  if (( ${#pl} >= 12 )); then
    ids0=$(python3 $E/t25.py ids $Y)
    f0=$($B/axprobe front | python3 -c "import json,sys; print(json.load(sys.stdin)['pid'])")
    # 1. ask, non-key, frontmost unchanged, the dock held shown; 2. Keep (AX press)
    n=$(wc -l < $L); t25_reveal_drag
    t25_asked; w=$(( $? == 0 ))
    f1=$($B/axprobe front | python3 -c "import json,sys; print(json.load(sys.stdin)['pid'])")
    k=$($B/axprobe focus $pid | python3 -c "import json,sys; print(int(json.load(sys.stdin)['app_focus']))")
    local held=$(log_count $L $pid '^inhibitor .*token=popoverOpen on=true' $n)
    row[ask]="$(( w && f1 == f0 && f1 != pid && k == 0 && held > 0 ))	question window '$(t25_title)': $( (( w )) && echo up || echo missing); frontmost unchanged: $( (( f1 == f0 )) && echo yes || echo no) (not Dedock: $( (( f1 != pid )) && echo yes || echo no)); key window in Dedock: $( (( k )) && echo yes || echo no); popoverOpen hold: $held"
    n=$(wc -l < $L)
    $B/axpress press $pid "$(t25_title)" Keep > $R/t25-keep.txt 2>&1; tool "axpress Keep" $? 0
    sleep 0.6; ids1=$(python3 $E/t25.py ids $Y)
    local r=$(t25_result ${pl[11]} keep $n); t25_asked; local gone=$(( $? != 0 ))
    row[keep]="$(( r == 1 && gone ))	Keep pressed: result=keep logged $r time(s); question closed: $( (( gone )) && echo yes || echo no); layout items unchanged: $([[ $ids1 == $ids0 ]] && echo yes || echo no)"
    [[ $ids1 == $ids0 ]] || row[keep]="0	${row[keep]#*	}"
    $B/pointer -q move ${pl[5]} $(( ${pl[6]%.*} + 300 )); sleep 0.8   # away: the dock hides
    # 3. a click elsewhere (Dedock's own capsule padding, no tile) keeps it
    n=$(wc -l < $L); t25_reveal_drag
    # Click only once the hit at the padding point is Dedock's (its mouse gate open): a click that
    # could pass through to the window underneath is never sent.
    $B/pointer -q move ${pl[7]} ${pl[8]}
    local mine=0
    for k in {1..10}; do sleep 0.1
      press_ok ${pl[7]} ${pl[8]} $pid && { mine=1; break }
    done
    (( mine )) && $B/pointer -q click ${pl[7]} ${pl[8]}; sleep 0.6   # guarded: press_ok
    ids1=$(python3 $E/t25.py ids $Y); r=$(t25_result ${pl[11]} keep $n); t25_asked; gone=$(( $? != 0 ))
    (( mine )) || r=0
    row[click]="$(( r == 1 && gone ))	click on the capsule's own padding$( (( mine )) || print -n ' NOT SENT (the hit there was not Dedock within 1 s)'): result=keep logged $r time(s); question closed: $( (( gone )) && echo yes || echo no); layout items unchanged: $([[ $ids1 == $ids0 ]] && echo yes || echo no)"
    [[ $ids1 == $ids0 ]] || row[click]="0	${row[click]#*	}"
    $B/pointer -q move ${pl[5]} $(( ${pl[6]%.*} + 300 )); sleep 0.8
    # 4. Remove: gone from the layout file (persisted at once) and from GEOM
    n=$(wc -l < $L); t25_reveal_drag
    $B/axpress press $pid "$(t25_title)" Remove > $R/t25-remove.txt 2>&1; tool "axpress Remove" $? 0
    sleep 1.2
    ids1=$(python3 $E/t25.py ids $Y); r=$(t25_result ${pl[11]} remove $n)
    local gids=$(python3 $E/t25.py geomids $G)
    local inl=0 ing=0; [[ " $ids1 " == *" ${pl[11]} "* ]] && inl=1; [[ " $gids " == *" ${pl[11]} "* ]] && ing=1
    row[remove]="$(( r == 1 && !inl && !ing ))	Remove pressed: result=remove logged $r time(s); '${pl[11]}' in the saved layout: $( (( inl )) && echo yes || echo no); in GEOM: $( (( ing )) && echo yes || echo no) (items $(print -r -- $ids0 | wc -w | tr -d ' ') → $(print -r -- $ids1 | wc -w | tr -d ' '))"
    $B/pointer -q move ${pl[5]} $(( ${pl[6]%.*} + 300 )); sleep 0.8
    # 5. a new drag while asking: question 1 answers Keep (its mouse-down is a click elsewhere)
    #    before question 2 appears; never two question windows; no hide in between.
    # 6. no answer in 8 s keeps the tile (question 2, left unanswered).
    ids0=$ids1
    if t25_plan 0; then
      local first_id=${pl[11]}
      n=$(wc -l < $L); t25_reveal_drag
      local wins0=$(t25_questions)
      local wins1=-1 second_id=-
      if t25_plan 1; then
        second_id=${pl[11]}
        t25_drag   # the dock is held shown by question 1
        wins1=$(t25_questions)
      fi
      local order=($(python3 -c "
import json, re, sys
log, pid, start, q1, q2 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
ev = []
for i, l in enumerate(open(log)):
    if i < start or not l.startswith('{'): continue
    r = json.loads(l.rstrip().rstrip(','))
    if r.get('processID') == pid: ev.append(r.get('eventMessage', ''))
on = [i for i, m in enumerate(ev) if re.search(r'^inhibitor .*token=popoverOpen on=true', m)]
k1 = next((i for i, m in enumerate(ev) if re.search(r'^tile[.]removeConfirm .*id=' + re.escape(q1) + r' .*result=keep|^tile[.]removeConfirm .*result=keep .*id=' + re.escape(q1), m)), None)
q2on = next((i for i in on if k1 is not None and i > k1), None)
hid = any(re.search(r'^reveal[.]transition .*to=hiding', m) for m in ev[(on[0] if on else 0):(q2on or 0)])
print(int(k1 is not None and q2on is not None and not hid), 'yes' if k1 is not None else 'no', 'yes' if q2on is not None else 'no', 'yes' if hid else 'no')" $L $pid $n $first_id $second_id))
      row[second]="$(( ${order[1]} && wins0 == 1 && wins1 == 1 ))	question 1 ('$first_id') answered Keep at the new drag: ${order[2]}, before question 2 ('$second_id') opened: ${order[3]}; question windows before / after the new drop: $wins0 / $wins1 (exp 1 / 1); a hide between the questions: ${order[4]}"
      sleep 8.6
      ids1=$(python3 $E/t25.py ids $Y)
      local rt=$(t25_result $second_id timeout $n); gone=$(( $(t25_questions) == 0 ))
      row[timeout]="$(( rt == 1 && gone ))	question 2 ('$second_id') unanswered: result=timeout logged $rt time(s) within 8.6 s; question closed: $( (( gone )) && echo yes || echo no); layout items unchanged: $([[ $ids1 == $ids0 ]] && echo yes || echo no)"
      [[ $ids1 == $ids0 ]] || row[timeout]="0	${row[timeout]#*	}"
    fi
    $B/pointer -q move ${pl[5]} $(( ${pl[6]%.*} + 300 )); sleep 0.6
  fi
  kill $lp 2>/dev/null; wait $lp 2>/dev/null
  $B/analyze contamination $R/t25-listen.txt > $R/t25-contam.txt 2>&1; tool "analyze contamination t25" $? 0 1
  local foreign=$(grep -c '^FAIL input contamination' $R/t25-contam.txt) key cid v
  for key cid in ask "T25 drag-out asks without taking focus R" keep "T25 Keep keeps the tile R" click "T25 a click elsewhere in Dedock keeps the tile (local-monitor path) R" \
                 remove "T25 Remove removes the tile and persists it R" second "T25 a new drag answers Keep, and its drop asks again R" \
                 timeout "T25 no answer in 8 s keeps the tile R"; do
    v=${row[$key]:-"0	not reached"}
    if (( foreign )); then check "$cid" void "real input during the probe (rerun): ${v#*	}"; else check "$cid" ${v%%	*} "${v#*	}"; fi
  done
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
# x-00 prompt baseline: window ids of permission/notification prompts already on screen BEFORE this
# launch. A prompt the launch causes can appear in an already-running UserNotificationCenter or
# SecurityAgent (whose process start predates the launch), so new = window id not in this snapshot.
PROMPT_APPS='("UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "tccd")'
command -v cua-driver >/dev/null && cua-driver call list_windows '{}' 2>/dev/null | python3 -c "
import json, sys
for x in json.load(sys.stdin)['windows']:
    if x['is_on_screen'] and x['app_name'] in $PROMPT_APPS: print(x['window_id'])" > $B/runs/$id/prompts-before.txt 2>/dev/null \
  || echo ERR > $B/runs/$id/prompts-before.txt
if launch $X --app $app --no-seed --timeout 8 > $B/runs/$id/launch-X.txt 2>&1 && launched $B/runs/$id/launch-X.txt; then
  sleep 2
  pid=$(sed -n 's/^APP_PID=//p' $B/runs/$X/run.env)
  check "x-00 UIElement" $(lsappinfo info -only ApplicationType -app $pid 2>/dev/null | grep -q UIElement && echo 1 || echo 0) "no Dock icon (LSUIElement)"
  si=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $pid) to get description of every menu bar item of menu bar 1" 2>/dev/null)
  check "x-00 status item" $([[ ${si:l} == *dedock* ]] && echo 1 || echo 0) "status item: ${si:-none}"   # any case: the UI name becomes "Dedock"
  if ! command -v cua-driver >/dev/null; then
    check "x-00 no permission prompt" 0 "cua-driver not installed: cannot check"
  else
    # Only prompt windows that appeared with this launch count (window id not in the pre-launch
    # snapshot); one left on screen from before is reported but is not an app result. Fails closed:
    # without a snapshot every prompt on screen counts as new, and unreadable output is "?".
    read prompts prior <<<$(cua-driver call list_windows '{}' 2>/dev/null | python3 -c "
import json, sys
before = open(sys.argv[1]).read().split()
if 'ERR' in before: before = []
new = old = 0
for x in json.load(sys.stdin)['windows']:
    if not (x['is_on_screen'] and x['app_name'] in $PROMPT_APPS): continue
    if str(x['window_id']) in before: old += 1
    else: new += 1
print(new, old)" $B/runs/$id/prompts-before.txt 2>/dev/null || echo "? ?")
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

# REG-057: a broken layout.json must not block the launch on a modal alert. The dock comes up
# (launch.edgeReady) with NO input, and the notice is posted after it. Corrupt → recovered from the
# seed; unreadable → runs read-only. The alert stays on screen (the app's own window, never clicked);
# teardown quits the app.
# While the recovery alert is on screen, an x-01-style reveal (pointer to the edge, dwell) must still
# work: a modal run loop can stall default-mode work (review of #23/#24). Fails closed when the
# alert is not on screen (then nothing was proven).
alert_reveal() {  # alert_reveal <sub-run> <pid>
  local S=$1 spid=$2 cid="REG-057 corrupt layout: dock reveals while the alert is up"
  if (( selftest )); then check "$cid" skip "self-test mode posts no input"; check "REG-057 the notice does not take focus" skip "self-test mode"; return; fi
  local G=$B/runs/$S/data/e2e/geometry.json
  $B/axprobe front > $B/runs/$S/front-notice.json
  $B/axprobe focus $spid > $B/runs/$S/focus-notice.json
  local alerts=$($B/axprobe windows $spid | python3 -c "import json,sys; print(sum(1 for l in sys.stdin if l.strip() and (w := json.loads(l))['onscreen'] and w['layer'] != 24 and w['w'] > 50))" 2>/dev/null || echo 0)
  local pts=($(python3 -c "import json;d=json.load(open('$G'))['docks'][0];x,y,w,h=d['capsule']['topLeft'];L=d['edge']=='left';print(d['edge'], int(y+h/2), x+w+400 if L else x-400)" 2>/dev/null))
  if (( ${#pts} != 3 )); then check "$cid" 0 "no GEOM for the recovered dock"; check "REG-057 the notice does not take focus" 0 "not probed (no GEOM)"; return; fi
  $E/desktop-lock.sh touch $me >/dev/null
  moved=1
  print -l "edge ${pts[1]} ${pts[2]}" "wait 700" > $B/runs/$S/reveal.txt
  $B/pointer -q script $B/runs/$S/reveal.txt
  sleep 0.2
  local r=$(python3 $E/log-order.py $B/runs/$S/log.ndjson pid=$spid '^settings[.]notice .*kind=recovered' '^reveal[.]transition .*to=shown' 2>/dev/null || echo "0 log-order did not run")
  $B/pointer -q move ${pts[3]} ${pts[2]}   # leave, so the dock hides before teardown
  sleep 0.5
  check "$cid" $(( ${r%% *} == 1 && alerts >= 1 )) "alert windows on screen: $alerts; ${r#* }"
  # KEY focus, not just the frontmost app: a key non-activating panel leaves another app frontmost
  # while it takes the keys (review of #28). Fails closed when the focus holder is unknown.
  # The system-wide focus holder when the system answers; otherwise (it may refuse with "cannot
  # complete") Dedock must be neither frontmost nor holding a focused element of its own.
  local fr=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1])); me = int(sys.argv[2])
if d.get('pid', -1) > 0:
    ok = d['pid'] != me; how = 'system-wide ' + d.get('source', '?') + ': ' + ('Dedock' if not ok else 'another app')
else:
    ok = d.get('front', -1) not in (-1, me) and not d.get('app_focus', True)
    how = 'system-wide focus unavailable; frontmost ' + ('Dedock' if d.get('front') == me else 'another app') + ', Dedock focused element ' + ('yes' if d.get('app_focus') else 'none')
print(int(ok), how)" $B/runs/$S/focus-notice.json $spid 2>/dev/null || echo "0 focus probe unreadable")
  check "REG-057 the notice does not take focus" $(( ${fr%% *} == 1 && alerts >= 1 )) "key focus while the notice is up: ${fr#* }"
}

notice_run() {  # notice_run <tag> <launch flag> <check id> <regex…>
  local tag=$1 flag=$2 cid=$3; shift 3
  local S=$id-$tag
  if launch $S --app $app $flag --timeout 8 > $B/runs/$id/launch-$tag.txt 2>&1 && launched $B/runs/$id/launch-$tag.txt; then
    local spid=$(sed -n 's/^APP_PID=//p' $B/runs/$S/run.env) r
    for i in {1..30}; do grep -q '"eventMessage":"settings.notice' $B/runs/$S/log.ndjson && break; sleep 0.1; done
    sleep 0.3
    r=$(python3 $E/log-order.py $B/runs/$S/log.ndjson pid=$spid "$@" 2>/dev/null || echo "0 log-order did not run")
    check "$cid" ${r%% *} "${r#* }"
    [[ $tag == C ]] && alert_reveal $S $spid
  else
    check "$cid" 0 "app did not reach launch.edgeReady within 8 s without input (a modal alert before the dock?): see build/e2e/runs/$id/launch-$tag.txt"
  fi
  teardown_check $S; check "REG-006 $tag" $(( $? == 0 )) "native Dock prefs unchanged"
  chmod 644 $B/runs/$S/data/layout.json 2>/dev/null   # keep the run dir readable after the read-only case
}
notice_run C --corrupt-layout "REG-057 corrupt layout: dock up, notice after, no input" \
  '^settings\.recovered' '^launch\.edgeReady' '^settings\.notice .*kind=recovered'
notice_run U --unreadable-layout "REG-057 unreadable layout: dock up read-only, notice after, no input" \
  '^settings\.readFailed' '^launch\.edgeReady' '^settings\.notice .*kind=readOnly'

for tag in $edge_list; do
  side=$tag; [[ $tag == L ]] && set_edge=() || set_edge=(--set "docks[0].edge=\"$(edge_of $tag)\"")
  echo "edge $tag"
  sub=$id-$tag
  if launch $sub --app $app --frame-log $set_edge --timeout 8 > $root/launch-$tag.txt 2>&1 && launched $root/launch-$tag.txt; then
    print -r -- "$tag $sub" >> $root/index.txt
    sleep 1
    rmetric launch.${tag}_ms $(edge_ready_ms $sub)
    # zone thickness 3 pt, 6 pt on the native Dock's edge (derived, REG-062)
    local zt=3; [[ $(defaults read com.apple.dock orientation 2>/dev/null || echo bottom) == $(edge_of $tag) ]] && zt=6
    $E/geom-check.py $B/runs/$sub/data/e2e/geometry.json layout=$B/runs/$sub/data/layout.json padding=$padding gap=$gap zone=$zt toprule=$toprule > $B/runs/$sub/geom.txt 2>&1
    tool "geom-check $tag" $?
    gf=$(grep -c '^FAIL' $B/runs/$sub/geom.txt); gp=$(grep -c '^PASS' $B/runs/$sub/geom.txt)
    # fail closed: a crashed or empty geom-check has no PASS lines
    check "geom $tag (REG-013 …)" $(( gf == 0 && gp > 0 )) "$gp pass, $gf fail$( (( gf )) && print -r -- ": $(grep '^FAIL' $B/runs/$sub/geom.txt | head -2 | cut -c6-90 | tr '\n' ';')")"
    rmetric geom.${tag}_fails $gf
    run_scn $sub $side x-01 n=4
    run_scn $sub $side x-02 n=4
    run_scn $sub $side x-03 n=3
    run_scn $sub $side x-04 n=3
    run_scn $sub $side x-05a n=3
    # cua checks AFTER the scenarios: C8 opens Settings, which switches Dedock to a regular
    # (activating) app; nothing timed may run after that in this launch (review of #27: C5 before C8).
    cua $sub $side
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

if (( t25 )); then
  echo "t25"
  sub=$id-D
  if launch $sub --app $app --set 'docks[0].edge="right"' --timeout 8 > $root/launch-D.txt 2>&1 && launched $root/launch-D.txt; then
    print -r -- "D $sub" >> $root/index.txt
    sleep 1
    t25_rows $B/runs/$sub $(sed -n 's/^APP_PID=//p' $B/runs/$sub/run.env)
    teardown_check $sub; check "REG-006 D" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch D" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-D.txt)"
  fi
fi

if (( t26 )); then
  echo "t26"
  sub=$id-P
  # Seeded in this launch's own data dir: Calculator, a spacer, TextEdit, a separator, Notes.
  if launch $sub --app $app --timeout 8 \
       --set 'profiles[0].items[1]={"id":"s-spacer","kind":"spacer"}' \
       --set 'profiles[0].items[2]={"bundleID":"com.apple.TextEdit","id":"t-textedit","kind":"app","path":"/System/Applications/TextEdit.app"}' \
       --set 'profiles[0].items[3]={"id":"s-separator","kind":"separator"}' \
       --set 'profiles[0].items[4]={"bundleID":"com.apple.Notes","id":"t-notes","kind":"app","path":"/System/Applications/Notes.app"}' \
       > $root/launch-P.txt 2>&1 && launched $root/launch-P.txt; then
    print -r -- "P $sub" >> $root/index.txt
    sleep 1
    t26_rows $B/runs/$sub $(sed -n 's/^APP_PID=//p' $B/runs/$sub/run.env)
    teardown_check $sub; check "REG-006 P" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch P" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-P.txt)"
  fi
fi

if (( z1 )); then
  echo "z1"
  sub=$id-Z
  if launch $sub --app $app --timeout 8 > $root/launch-Z.txt 2>&1 && launched $root/launch-Z.txt; then
    print -r -- "Z $sub" >> $root/index.txt
    sleep 1
    z1_rows $B/runs/$sub $(sed -n 's/^APP_PID=//p' $B/runs/$sub/run.env)
    teardown_check $sub; check "REG-006 Z" $(( $? == 0 )) "native Dock prefs unchanged"
  else
    check "launch Z" 0 "no launch.edgeReady (build/e2e/runs/$id/launch-Z.txt)"
  fi
fi

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
      (( attempt < 2 )) && mv $O $O.void-$attempt   # the last attempt stays: a VOID idle is a VOID row, never missing
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
    [[ $tag == L ]] && set_edge=() || set_edge=(--set "docks[0].edge=\"$(edge_of $tag)\"")
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
# REG-055: did the pointer leave this Mac through OS pointer sharing during the run? Read from the
# system log (the feature's process logs each hand-off). Fails closed if the log cannot be read.
if (( selftest )); then
  check "REG-055 no pointer hand-off" skip "self-test mode posts no input"
elif /usr/bin/log show --start "$run_start" --style compact --predicate \
    'process == "UniversalControl" AND (eventMessage CONTAINS "Move Pointer to IDS" OR eventMessage CONTAINS "Move Target to Local" OR eventMessage CONTAINS "Hot Zone: Activating")' \
    > $root/pointer-sharing.log 2>/dev/null; then
  handoffs=$(grep -cE 'Move Pointer to IDS|Move Target to Local' $root/pointer-sharing.log || true)
  zones=$(grep -c 'Hot Zone: Activating' $root/pointer-sharing.log || true)
  if [[ $psharing == on ]] && (( handoffs == 0 && zones == 0 )); then
    # With the feature on and edge pushes made, no message at all is suspicious (e.g. reworded by an
    # OS update): unverifiable, never a PASS (review of #22).
    check "REG-055 no pointer hand-off" 0 "unverifiable: OS pointer sharing is ON (psharing=allow) and the system log shows no zone or hand-off messages"
  else
    check "REG-055 no pointer hand-off" $(( handoffs == 0 )) "OS pointer sharing across devices: $psharing at start; hand-offs during the run: $handoffs; edge-zone activations: $zones"
  fi
else
  check "REG-055 no pointer hand-off" 0 "could not read the system log: hand-offs unknown"
fi

echo
score $root
