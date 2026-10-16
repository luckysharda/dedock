#!/bin/zsh
# Runs one synthetic-pointer (SYN) scenario from docs/evaluation.md §7.3 against a
# dedock instance started by launch.sh, then analyzes it.
#
#   Scripts/e2e/scenario.sh <run-id> <L|R> <scenario> [n=<trials>] [seed=<n>]
#
# Scenarios: x-01 dwell reveal · x-02 leave before dwell · x-03 push-through (and
# pull-away) · x-04 hide delay (and return at 300 ms) · x-05a reverse a hide ·
# x-05b reverse a reveal (launch with --set 'docks[0].reveal.hideDelayMs=0') ·
# x-06 rapid crossings (launch with --frame-log) · perf-move (60 s circles + CPU).
#
# The caller must hold the desktop lock as $DEDOCK_LOCK_OWNER (default dedock-app-f1;
# Scripts/e2e/desktop-lock.sh): this moves
# the real cursor. A listener records every input event during the scenario; any
# input the driver did not post fails the run as contaminated.
# Output: build/e2e/runs/<run-id>/<scenario>-<edge>/ (driver.txt, listen.txt, report.txt)
set -euo pipefail

HARNESS=${0:A:h:h:h}
B=$HARNESS/build/e2e
run=${1:?usage: scenario.sh <run-id> <L|R|B|T> <scenario> [n=] [seed=]}
side=${2:?L or R}
scn=${3:?scenario}
shift 3
n=10 seed=1 dry=0 tag=
for kv in "$@"; do case $kv in n=*) n=${kv#n=} ;; seed=*) seed=${kv#seed=} ;; dry=*) dry=${kv#dry=} ;; tag=*) tag=${kv#tag=} ;; esac; done

R=$B/runs/$run
[[ -f $R/run.env ]] || { echo "no run $run: start it with launch.sh" >&2; exit 2 }
# run.env is read, never sourced: it holds app-provided text (e.g. a "<private>" log value once
# broke `source` and left an instance running).
envv() { sed -n "s/^$1=//p" $R/run.env | head -1 | sed 's/\\ / /g' }
APP_PID=$(envv APP_PID); LOG_PID=$(envv LOG_PID); RUN_DIR=$R; DATA_DIR=$R/data; GEOM=$R/data/e2e/geometry.json
if (( ! dry )); then
  kill -0 $APP_PID 2>/dev/null || { echo "app (pid $APP_PID) is not running" >&2; exit 2 }
  # The lock must be held by THIS session, not merely by someone.
  me=${DEDOCK_LOCK_OWNER:?set DEDOCK_LOCK_OWNER to your session name}
  # Moves the real cursor: only under the REAL desktop lock (a DEDOCK_LOCKS override never counts).
  if ! $HARNESS/Scripts/e2e/desktop-lock.sh require $me 2>/dev/null; then
    lock_owner=$($HARNESS/Scripts/e2e/desktop-lock.sh status | sed -n 's/^owner=//p')
    echo "desktop lock is held by '${lock_owner:-nobody}', not '$me' (or not the real lock): acquire it first (desktop-lock.sh acquire $me e2e ...)" >&2; exit 2
  fi
fi

for tool in pointer listen analyze; do
  [[ -x $B/$tool ]] || { echo "build $tool first: Tests/E2E/selftest/run.sh builds every tool" >&2; exit 2 }
done

# Geometry (evaluation.md §7.1): from GEOM when the app wrote it, else the fallback numbers.
read W H <<<$($B/pointer screen | sed 's/.*w=\([0-9.]*\) h=\([0-9.]*\)/\1 \2/')
W=${W%.*} H=${H%.*}
# along: the probe position along the edge (y on left/right, x on bottom/top); (in_x, in_y): the
# "inward" resting point, off the edge and outside the capsule + 16 pt hysteresis.
case $side in
  L) edge=left;   along=$(( H / 2 )); in_x=600;            in_y=$along ;;
  R) edge=right;  along=$(( H / 2 )); in_x=$(( W - 601 )); in_y=$along ;;
  B) edge=bottom; along=$(( W / 2 )); in_x=$along;         in_y=$(( H - 400 )) ;;
  T) edge=top;    along=$(( W / 2 )); in_x=$along;         in_y=400 ;;
  *) echo "side must be L, R, B or T" >&2; exit 2 ;;
esac
if [[ -f ${GEOM:-/nonexistent} ]]; then
  read along in_x in_y nozone depth <<<$(python3 - $GEOM $edge $along $in_x $in_y <<'EOF'
import json, sys
g, edge, al, ix, iy = json.load(open(sys.argv[1])), sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
d = next((d for d in g.get("docks", []) if d.get("edge") == edge), None)
nozone, depth = 0, 120
if d and "capsule" in d:
    x, y, w, h = d["capsule"]["topLeft"]
    off = 16 + 60                                        # outside capsule + hysteresis
    vert = edge in ("left", "right")
    # Probe the middle of the widest trigger-zone strip (beside the native Dock on the bottom,
    # between status items on top); on left/right that is the capsule centre (span = capsule ± 40).
    zs = [z["rect"]["topLeft"] for z in d.get("zones", [])]
    if "zones" in d and not zs:
        nozone = 1
    if zs:
        z = max(zs, key=lambda r: r[3] if vert else r[2])
        mid = int(z[1] + z[3] / 2) if vert else int(z[0] + z[2] / 2)
    else:
        mid = int(y + h / 2) if vert else int(x + w / 2)
    if vert:
        al = iy = mid
        ix = int(x + w + off) if edge == "left" else int(x - off)
    else:
        al = ix = mid
        iy = int(y - off) if edge == "bottom" else int(y + h + off)
    # x-06 crossing amplitude: past the capsule's far side + 16 pt hysteresis + 30 pt, measured from
    # the screen edge (the top capsule sits below the menu bar, so a fixed 120 pt never left it).
    sw, sh = max(s["frame"]["topLeft"][0] + s["frame"]["topLeft"][2] for s in g["screens"]), max(s["frame"]["topLeft"][1] + s["frame"]["topLeft"][3] for s in g["screens"])
    far = {"left": x + w, "right": sw - x, "top": y + h, "bottom": sh - y}[edge]
    depth = int(far + 16 + 30)
print(al, ix, iy, nozone, depth)
EOF
)
fi
probe_y=$along   # kept for the header line below

O=$R/$scn-$side${tag:+-$tag}   # tag=: repeat the same scenario (e.g. x-06 seeds) into separate dirs
mkdir -p $O
# No trigger zone in GEOM: nothing to probe, and the dock can't be revealed from this edge. A FAIL
# (an app finding, e.g. REG-065), never a skip and never a broken run.
if [[ ${nozone:-0} == 1 && $scn != perf-move ]]; then
  { echo "== $scn $edge ($run)"; echo "FAIL trigger zone: GEOM has no zone on the $edge edge (the dock cannot be revealed from it)"; echo "VERDICT FAIL $scn $edge"; } > $O/report.txt
  cat $O/report.txt; exit 1
fi
S=$O/driver-script.txt
# Delays from the seeded layout (schema keys reveal.showDwellMs / reveal.hideDelayMs, in ms).
show=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(int(d['docks'][0].get('reveal',{}).get('showDwellMs',120)))" $DATA_DIR/layout.json 2>/dev/null || echo 120)
# The EFFECTIVE dwell when GEOM reports it (derived per edge: the top edge's minimum is 300 ms, REG-062);
# the stored value is only the user's setting.
if [[ -f ${GEOM:-/nonexistent} ]]; then
  gshow=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]))['docks'][0];print(int(d['showDwellMs']))" $GEOM 2>/dev/null) && show=$gshow
fi
hide=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(int(d['docks'][0].get('reveal',{}).get('hideDelayMs',400)))" $DATA_DIR/layout.json 2>/dev/null || echo 400)
settle=$(( hide + 180 + 400 ))   # wait for a full hide before the next trial

{
  echo "# $scn $edge along=$along in=$in_x,$in_y show=$show hide=$hide n=$n seed=$seed"
  echo "move $in_x $in_y"; echo "wait 500"
  case $scn in
    x-01) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $along"; echo "wait $(( show + 400 ))"; echo "glide $in_x $in_y 60"; echo "wait $settle"; done ;;
    x-02) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $along"; echo "wait 80"; echo "move $in_x $in_y"; echo "wait 300"; done ;;
    x-03) for i in {1..$n}; do
            echo "mark push$i"; echo "edge $edge $along"; echo "push $edge $along 10 5 50"; echo "wait 400"; echo "glide $in_x $in_y 60"; echo "wait $settle"
            echo "mark pull$i"; echo "edge $edge $along"; echo "pull $edge $along 10 5 50"; echo "wait 400"; echo "glide $in_x $in_y 60"; echo "wait $settle"
          done ;;
    x-04) for i in {1..$n}; do
            echo "mark hide$i"; echo "edge $edge $along"; echo "wait $(( show + 400 ))"; echo "glide $in_x $in_y 60"; echo "wait $settle"
            echo "mark return$i"; echo "edge $edge $along"; echo "wait $(( show + 400 ))"; echo "glide $in_x $in_y 60"; echo "wait 300"; echo "edge $edge $along"; echo "wait 600"; echo "glide $in_x $in_y 60"; echo "wait $settle"
          done ;;
    x-05a) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $along"; echo "wait $(( show + 400 ))"; echo "glide $in_x $in_y 60"; echo "wait $(( hide + 90 - 60 ))"; echo "edge $edge $along"; echo "wait 600"; echo "glide $in_x $in_y 60"; echo "wait $settle"; done ;;
    x-05b) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $along"; echo "wait $(( show + 100 ))"; echo "move $in_x $in_y"; echo "wait 800"; done ;;
    x-06) # Legs average 50 ms, far below the dwell, so the dock must already be shown and the
          # hide must start at once (hideDelayMs 0): each outbound leg starts a hide and each
          # inbound leg reverses it. Prime with a dwell reveal.
          if (( hide != 0 )); then echo "x-06 needs a run launched with --set 'docks[0].reveal.hideDelayMs=0'" >&2; exit 2; fi
          echo "mark prime"; echo "edge $edge $along"; echo "wait $(( show + 400 ))"
          echo "mark crossings"; echo "crossings $edge $along 20 2000 ${depth:-120} $seed"; echo "glide $in_x $in_y 60"; echo "wait $settle" ;;
    perf-move) echo "mark circles"; echo "circles $(( W / 2 )) $(( H / 2 )) 150 60 60" ;;
    *) echo "unknown scenario $scn" >&2; exit 2 ;;
  esac
  echo "mark end"
} > $S

# Duration estimate for the listener window (+3 s margin).
secs=$(awk '/^wait/{t+=$2} /^glide/{t+=$4} /^push|^pull/{t+=$6} /^crossings/{t+=$5} /^circles/{t+=$5*1000} END{printf "%d", t/1000+3}' $S)
if (( dry )); then
  cat $S; echo "# estimated duration ${secs} s (moves the cursor; runs > 10 s need a heads-up to the orchestrator)"
  exit 0
fi
$B/listen $secs > $O/listen.txt &
lpid=$!
sleep 0.5
(( dry )) || $HARNESS/Scripts/e2e/desktop-lock.sh touch $me >/dev/null
if [[ $scn == perf-move ]]; then
  $HARNESS/Scripts/measure-idle.sh $APP_PID 58 $R/perf.csv > $O/perf.txt &
  ppid=$!
fi
$B/pointer -q script $S > $O/driver.txt
[[ -n ${ppid:-} ]] && wait $ppid || true
wait $lpid 2>/dev/null || true
# REG-055: name the processes behind foreign input now, while their pids still exist. LOCAL ONLY:
# this file is never copied into a scorecard (another process's name can be the user's own app).
{ grep -oE 'syn=0 src=-?[0-9]+' $O/listen.txt 2>/dev/null || true; } | sed 's/.*src=//' | sort | uniq -c | while read -r n spid; do
  print -r -- "pid=$spid events=$n process=$( (( spid > 0 )) && ps -o comm= -p $spid 2>/dev/null | xargs basename 2>/dev/null || echo '(HID device or gone)')"
done > $O/foreign-sources.txt
[[ -s $O/foreign-sources.txt ]] || rm -f $O/foreign-sources.txt
sleep 0.5

# Only this scenario's log lines: between the driver's first and last marks (+1 s for trailing hides).
# Only this run's process: another session's Dedock logs to the same subsystem.
python3 - $RUN_DIR/log.ndjson $O/driver.txt $O/log.ndjson $APP_PID > $O/slice.txt <<'EOF'
import json, re, sys
marks = [int(m) for m in re.findall(r"^mach=(\d+) .*ev=mark", open(sys.argv[2]).read(), re.M)]
lo, hi = marks[0], marks[-1] + 24_000_000  # 1 s of mach ticks (24 MHz)
pid, other = int(sys.argv[4]), set()
with open(sys.argv[3], "w") as out:
    for line in open(sys.argv[1]):
        if line.startswith("{"):
            try: o = json.loads(line)
            except ValueError: continue
            if not lo <= o.get("machTimestamp", 0) <= hi: continue
            if o.get("processID") != pid: other.add(o.get("processID")); continue
            out.write(line)
if other: print(f"WARN other Dedock processes logged during the scenario: {sorted(other)} (excluded; they may also have reacted to the pointer)")
EOF


# Judge it (also re-runnable later on the saved files: regress.sh rescore).
print -r -- "scn=$scn edge=$edge show=$show hide=$hide n=$n run=$run" > $O/params.env
exec $HARNESS/Scripts/e2e/judge.sh $O
