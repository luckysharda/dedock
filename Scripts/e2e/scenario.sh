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
# The caller must hold the desktop lock (Scripts/e2e/desktop-lock.sh): this moves
# the real cursor. A listener records every input event during the scenario; any
# input the driver did not post fails the run as contaminated.
# Output: build/e2e/runs/<run-id>/<scenario>-<edge>/ (driver.txt, listen.txt, report.txt)
set -euo pipefail

HARNESS=${0:A:h:h:h}
B=$HARNESS/build/e2e
run=${1:?usage: scenario.sh <run-id> <L|R> <scenario> [n=] [seed=]}
side=${2:?L or R}
scn=${3:?scenario}
shift 3
n=10 seed=1 dry=0
for kv in "$@"; do case $kv in n=*) n=${kv#n=} ;; seed=*) seed=${kv#seed=} ;; dry=*) dry=${kv#dry=} ;; esac; done

R=$B/runs/$run
[[ -f $R/run.env ]] || { echo "no run $run: start it with launch.sh" >&2; exit 2 }
source $R/run.env
if (( ! dry )); then
  kill -0 $APP_PID 2>/dev/null || { echo "app (pid $APP_PID) is not running" >&2; exit 2 }
  lock_owner=$($HARNESS/Scripts/e2e/desktop-lock.sh status | sed -n 's/^owner=//p')
  [[ -n $lock_owner ]] || { echo "take the desktop lock first (desktop-lock.sh acquire ...)" >&2; exit 2 }
fi

for tool in pointer listen analyze; do
  [[ -x $B/$tool ]] || { echo "build $tool first: Tests/E2E/selftest/run.sh builds every tool" >&2; exit 2 }
done

# Geometry (evaluation.md §7.1): from GEOM when the app wrote it, else the fallback numbers.
read W H <<<$($B/pointer screen | sed 's/.*w=\([0-9.]*\) h=\([0-9.]*\)/\1 \2/')
W=${W%.*} H=${H%.*}
if [[ $side == L ]]; then edge=left; in_x=600; else edge=right; in_x=$(( W - 601 )); fi
probe_y=$(( H / 2 ))
if [[ -f ${GEOM:-/nonexistent} ]]; then
  read probe_y in_x <<<$(python3 - $GEOM $edge $probe_y $in_x <<'EOF'
import json, sys
g, edge, py, ix = json.load(open(sys.argv[1])), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
d = next((d for d in g.get("docks", []) if d.get("edge") == edge), None)
if d and "capsule" in d:
    x, y, w, h = d["capsule"]["topLeft"]
    py = int(y + h / 2)                                  # zone span centre = capsule centre
    ix = int(x + w + 16 + 60) if edge == "left" else int(x - 16 - 60)  # outside capsule + hysteresis
print(py, ix)
EOF
)
fi

O=$R/$scn-$side
mkdir -p $O
S=$O/driver-script.txt
# Delays from the seeded layout (schema keys reveal.showDwellMs / reveal.hideDelayMs, in ms).
show=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(int(d['docks'][0].get('reveal',{}).get('showDwellMs',120)))" $DATA_DIR/layout.json 2>/dev/null || echo 120)
hide=$(python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(int(d['docks'][0].get('reveal',{}).get('hideDelayMs',400)))" $DATA_DIR/layout.json 2>/dev/null || echo 400)
settle=$(( hide + 180 + 400 ))   # wait for a full hide before the next trial

{
  echo "# $scn $edge probe_y=$probe_y in_x=$in_x show=$show hide=$hide n=$n seed=$seed"
  echo "move $in_x $probe_y"; echo "wait 500"
  case $scn in
    x-01) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $probe_y"; echo "wait $(( show + 400 ))"; echo "glide $in_x $probe_y 60"; echo "wait $settle"; done ;;
    x-02) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $probe_y"; echo "wait 80"; echo "move $in_x $probe_y"; echo "wait 300"; done ;;
    x-03) for i in {1..$n}; do
            echo "mark push$i"; echo "edge $edge $probe_y"; echo "push $edge $probe_y 10 5 50"; echo "wait 400"; echo "glide $in_x $probe_y 60"; echo "wait $settle"
            echo "mark pull$i"; echo "edge $edge $probe_y"; echo "pull $edge $probe_y 10 5 50"; echo "wait 400"; echo "glide $in_x $probe_y 60"; echo "wait $settle"
          done ;;
    x-04) for i in {1..$n}; do
            echo "mark hide$i"; echo "edge $edge $probe_y"; echo "wait $(( show + 400 ))"; echo "glide $in_x $probe_y 60"; echo "wait $settle"
            echo "mark return$i"; echo "edge $edge $probe_y"; echo "wait $(( show + 400 ))"; echo "glide $in_x $probe_y 60"; echo "wait 300"; echo "edge $edge $probe_y"; echo "wait 600"; echo "glide $in_x $probe_y 60"; echo "wait $settle"
          done ;;
    x-05a) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $probe_y"; echo "wait $(( show + 400 ))"; echo "glide $in_x $probe_y 60"; echo "wait $(( hide + 90 - 60 ))"; echo "edge $edge $probe_y"; echo "wait 600"; echo "glide $in_x $probe_y 60"; echo "wait $settle"; done ;;
    x-05b) for i in {1..$n}; do echo "mark trial$i"; echo "edge $edge $probe_y"; echo "wait $(( show + 100 ))"; echo "move $in_x $probe_y"; echo "wait 800"; done ;;
    x-06) # Legs average 50 ms, far below the dwell, so the dock must already be shown and the
          # hide must start at once (hideDelayMs 0): each outbound leg starts a hide and each
          # inbound leg reverses it. Prime with a dwell reveal.
          if (( hide != 0 )); then echo "x-06 needs a run launched with --set 'docks[0].reveal.hideDelayMs=0'" >&2; exit 2; fi
          echo "mark prime"; echo "edge $edge $probe_y"; echo "wait $(( show + 400 ))"
          echo "mark crossings"; echo "crossings $edge $probe_y 20 2000 120 $seed"; echo "glide $in_x $probe_y 60"; echo "wait $settle" ;;
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
$HARNESS/Scripts/e2e/desktop-lock.sh touch >/dev/null
if [[ $scn == perf-move ]]; then
  $HARNESS/Scripts/measure-idle.sh $APP_PID 58 $R/perf.csv > $O/perf.txt &
  ppid=$!
fi
$B/pointer -q script $S > $O/driver.txt
[[ -n ${ppid:-} ]] && wait $ppid || true
wait $lpid 2>/dev/null || true
sleep 0.5

# Only this scenario's log lines: between the driver's first and last marks (+1 s for trailing hides).
python3 - $RUN_DIR/log.ndjson $O/driver.txt $O/log.ndjson <<'EOF'
import json, re, sys
marks = [int(m) for m in re.findall(r"^mach=(\d+) .*ev=mark", open(sys.argv[2]).read(), re.M)]
lo, hi = marks[0], marks[-1] + 24_000_000  # 1 s of mach ticks (24 MHz)
with open(sys.argv[3], "w") as out:
    for line in open(sys.argv[1]):
        if line.startswith("{"):
            try: t = json.loads(line).get("machTimestamp", 0)
            except ValueError: continue
            if lo <= t <= hi: out.write(line)
EOF

{
  echo "== $scn $edge ($run) $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  $B/analyze contamination $O/listen.txt || true
  case $scn in
    x-01|x-02|x-03|x-04) $B/analyze timing $O/log.ndjson show=$show hide=$hide || true ;;
    x-05a|x-05b|x-06) $B/analyze timing $O/log.ndjson show=$show hide=$hide || true; $B/analyze frames $O/log.ndjson || true
      # A reversal scenario in which nothing reversed tested nothing: fail it explicitly.
      case $scn in
        x-05a) pat='"eventMessage":"reveal.transition[^"]*from=hiding to=revealing'; need=$n ;;
        x-05b) pat='"eventMessage":"reveal.transition[^"]*from=revealing to=hiding'; need=$n ;;
        x-06)  pat='"eventMessage":"reveal.transition[^"]*from=(hiding to=revealing|revealing to=hiding)'; need=1 ;;
      esac
      got=$(grep -cE "$pat" $O/log.ndjson || true)
      if (( got >= need )); then echo "PASS reversals occurred: $got (need ≥ $need)"; else echo "FAIL expected reversals: $got occurred (need ≥ $need); the scenario did not exercise reverse-in-place"; fi ;;
    perf-move) cat $O/perf.txt ;;
  esac
} | tee $O/report.txt
grep -q '^FAIL' $O/report.txt && exit 1 || exit 0
