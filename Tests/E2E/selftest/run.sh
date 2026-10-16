#!/bin/zsh
# Builds every harness tool into build/e2e/ and checks it against known answers.
# Needs no app and never moves the cursor. Run after any change under Scripts/ or Tests/E2E/.
#
#   Tests/E2E/selftest/run.sh
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1   # never leave __pycache__ / *.pyc in the tree

# Run from the harness root with relative paths: `check` re-parses commands with eval,
# and the absolute path contains a space ("Dedock app").
cd ${0:A:h:h:h:h}
H=.
B=build/e2e
T=$B/selftest
mkdir -p $B $T
rm -rf $T/* $B/runs/selftest-*
fails=0
# Never leak an app or a log stream, even if a check or a teardown fails midway.
cleanup() {
  for env in $B/runs/selftest-*/run.env(N); do
    kill $(sed -n 's/^\(APP_PID\|LOG_PID\)=//p' $env) 2>/dev/null
  done
}
trap cleanup EXIT
# Never alongside a real run: the self-test launches fake apps and listens to input, which would
# muddle an E2E run's logs and process checks (2026-10-15). Refuse while ANYONE holds the real lock.
if holder=$(Scripts/e2e/desktop-lock.sh real-holder); then
  echo "selftest: refusing — the real desktop lock is held ($holder); run it when the desktop is free"
  exit 2
fi
export DEDOCK_LOCK_OWNER=selftest-owner   # no default owner anywhere (review of #12)
export DEDOCK_SELFTEST=1                  # fake bundle ids and private locks only; never posts input
# REG-055: regress.sh refuses while OS pointer sharing is on. Stub that one `defaults` read so the
# self-test does not depend on this Mac's setting (DEDOCK_STUB_PSHARING=on|off); everything else
# goes to the real defaults.
mkdir -p $T/stubbin
print -r -- '#!/bin/zsh
if [[ "$*" == "-currentHost read com.apple.universalcontrol Disable" ]]; then [[ ${DEDOCK_STUB_PSHARING:-off} == off ]] && echo 1 || echo 0; exit 0; fi
exec /usr/bin/defaults "$@"' > $T/stubbin/defaults; chmod +x $T/stubbin/defaults
export PATH=${T:A}/stubbin:$PATH
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi }
skipped=0
skip() { echo "SKIP $1 ($2)"; skipped=$((skipped + 1)); }   # a skipped check is never a PASS

echo "-- build"
for src in Scripts/e2e/pointer.swift Scripts/e2e/listen.swift Scripts/e2e/analyze.swift Scripts/e2e/axprobe.swift Scripts/e2e/backdrop.swift Scripts/e2e/notify.swift Scripts/e2e/axpress.swift Scripts/measure-pixels.swift Tests/E2E/selftest/fake-dock.swift; do
  out=$B/${${src:t}%.swift}
  check "compile ${src:t}" "swiftc -O $src -o $out 2>$T/${src:t}.err"
done

echo "-- pointer (no events posted)"
check "screen size" "$B/pointer screen | grep -q 'w='"
check "script: full-line comments are skipped, not executed" "printf '# x-01 left probe\\nmark ok # trailing comment\\n' | $B/pointer script - > $T/comment.txt 2>&1 && grep -q 'label=ok' $T/comment.txt"
check "help lists every command" "$B/pointer help | grep -q crossings && $B/pointer help | grep -q nudge"

echo "-- measure-pixels (exact on RGB images)"
ffmpeg -loglevel error -y -f lavfi -i color=c=0x404040:s=200x100,format=rgb24 \
  -vf "drawbox=x=40:y=20:w=80:h=60:color=0xff0000:t=fill,drawbox=x=70:y=20:w=10:h=60:color=0x404040:t=fill,format=rgb24" \
  -frames:v 1 -pix_fmt rgb24 $T/a.png
mkdir -p $T/series
for i in 0 1 2 3; do
  ffmpeg -loglevel error -y -f lavfi -i color=c=0x404040:s=200x100,format=rgb24 \
    -vf "drawbox=x=$((10 + i * 15)):y=20:w=50:h=60:color=0xff0000:t=fill,format=rgb24" -frames:v 1 -pix_fmt rgb24 $T/series/f$i.png
done
check "rgba" "$B/measure-pixels rgba $T/a.png 0,0 50,50 | tail -2 | tr '\n' ' ' | grep -q '0,0,64,64,64,255 50,50,255,0,0,255'"
check "edge left/right/top" "[[ \$($B/measure-pixels edge $T/a.png row=50 from=left) == 40 && \$($B/measure-pixels edge $T/a.png row=50 from=right) == 119 && \$($B/measure-pixels edge $T/a.png col=50 from=top) == 20 ]]"
check "runs" "$B/measure-pixels run $T/a.png row=50 from=left | tail -2 | tr '\n' ' ' | grep -q '40,69,30 80,119,40'"
check "series" "$B/measure-pixels series $T/series row=50 from=left | cut -d, -f3 | tail -4 | tr '\n' ' ' | grep -q '10 25 40 55'"
check "diff identical passes" "$B/measure-pixels diff $T/a.png $T/a.png | grep -q verdict=PASS"
check "diff different fails" "$B/measure-pixels diff $T/a.png $T/series/f0.png | grep -q verdict=FAIL"

echo "-- analyze (fake-dock good passes, bad fails on its seeded defects)"
for m in good bad; do
  /usr/bin/log stream --style ndjson --level debug --predicate 'subsystem == "app.dedock.Dedock" AND process == "fake-dock"' > $T/$m.ndjson 2>&1 &
  lp=$!; sleep 1.5; $B/fake-dock $m; sleep 1.5; kill $lp
  $B/analyze timing $T/$m.ndjson > $T/$m-timing.txt; echo $? > $T/$m-timing.rc
  $B/analyze frames $T/$m.ndjson > $T/$m-frames.txt; echo $? > $T/$m-frames.rc
done
check "good: timing passes" "[[ \$(cat $T/good-timing.rc) == 0 ]]"
check "good: frames pass" "[[ \$(cat $T/good-frames.rc) == 0 ]]"
check "bad: late dwell caught" "grep -q '^FAIL dwell' $T/bad-timing.txt"
check "bad: NFR-4 caught" "grep -q '^FAIL NFR-4' $T/bad-timing.txt"
check "bad: reversal jump caught" "grep -q '^FAIL DD-928 continuity' $T/bad-frames.txt"
check "bad: frames exit 1" "[[ \$(cat $T/bad-frames.rc) == 1 ]]"
check "bad: overshoot caught" "grep -q '^FAIL anim 0 reveal/spring.*overshoot 3.0 pt' $T/bad-frames.txt"
check "good: no contract warnings" "! grep -q '^WARN' $T/good-timing.txt $T/good-frames.txt"
printf '{"subsystem":"app.dedock.Dedock","machTimestamp":1,"category":"reveal","eventMessage":"reveal.transition edge=left from=arming to=revealing cause=timer inh=-"}\n' > $T/drift.ndjson
$B/analyze timing $T/drift.ndjson > $T/drift.txt  # exits 1 (no gates): only the warning matters
check "drift: unknown cause warned" "grep -q 'WARN unrecognized cause=timer' $T/drift.txt"
check "bad: hide delay still passes" "grep -q '^PASS hide delay' $T/bad-timing.txt"
printf 'ready mach=0\nmach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1\n' > $T/clean.txt
printf 'ready mach=0\nmach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1\nmach=2 ev=move x=3 y=1 dx=2 dy=0 mods=0 syn=0\n' > $T/dirty.txt
printf 'ready mach=0\nmach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0\n' > $T/untagged.txt
check "contamination: clean passes" "$B/analyze contamination $T/clean.txt >/dev/null"
check "contamination: foreign input fails" "! $B/analyze contamination $T/dirty.txt >/dev/null"
printf 'ready mach=0\n' > $T/empty.txt
check "contamination: idle run with no input passes" "$B/analyze contamination $T/empty.txt idle=1 >/dev/null"
check "contamination: pointer run with no input fails" "! $B/analyze contamination $T/empty.txt >/dev/null"
: > $T/noready.txt; tail -n +2 $T/clean.txt > $T/noready-move.txt
$B/analyze contamination $T/noready.txt idle=1 > $T/noready-out.txt   # exits 1; read the file (pipefail)
check "contamination: listener that never started fails, idle too" "! $B/analyze contamination $T/noready.txt idle=1 >/dev/null && ! $B/analyze contamination $T/noready-move.txt >/dev/null && grep -q 'listener never started' $T/noready-out.txt"
check "contamination: untagged fails" "! $B/analyze contamination $T/untagged.txt >/dev/null"
printf 'ready mach=0\nmach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1\nmach=2 ev=move x=3 y=1 dx=2 dy=0 mods=0 syn=0 src=945\nmach=3 ev=move x=4 y=1 dx=1 dy=0 mods=0 syn=0 src=945\n' > $T/srcs.txt
$B/analyze contamination $T/srcs.txt > $T/srcs-out.txt   # exits 1 (foreign input)
check "REG-055 contamination names the foreign source pid" "grep -q 'foreign sources: pid 945 x2' $T/srcs-out.txt"

echo "-- score.py (verdicts, drift with noise floors, baseline, repo-relative paths)"
SR=$B/runs
mkfix() {  # mkfix <root> <verdict> <dwell_ms> [check_ok]
  rm -rf $SR/$1 $SR/$1-L; mkdir -p $SR/$1 $SR/$1-L/x-01-L
  print "L $1-L" > $SR/$1/index.txt
  print "PASS dwell\nVERDICT $2 x-01 left" > $SR/$1-L/x-01-L/report.txt
  [[ $2 == FAIL ]] && print "FAIL dwell: late\nVERDICT FAIL x-01 left" > $SR/$1-L/x-01-L/report.txt
  print "{\"metric\":\"dwell_late_p95_ms\",\"value\":$3}\n{\"metric\":\"dwell_trials\",\"value\":4}" > $SR/$1-L/x-01-L/metrics.jsonl
  print "{\"id\":\"REG-006 L\",\"ok\":${4:-true},\"detail\":\"prefs\"}" > $SR/$1/checks.jsonl
  print '{"app_commit":"abc1234","config":"debug","date":"t"}' > $SR/$1/env.json
}
mkfix selftest-sbase PASS 1.2
python3 Scripts/e2e/score.py --write-baseline $SR/selftest-sbase $T/m1.json > /dev/null
check "score: baseline written, counts excluded" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not ('L.x-01-L.dwell_late_p95_ms' in d['metrics'] and 'L.x-01-L.dwell_trials' not in d['metrics'] and d['provenance']['partial']))\" $T/m1.json"
mkfix selftest-spass PASS 1.6
python3 Scripts/e2e/score.py $SR/selftest-spass $T/m1.json > $T/s-pass.txt; echo $? > $T/s-pass.rc
check "score: PASS exits 0" "[[ \$(cat $T/s-pass.rc) == 0 ]]"
check "score: +33 % under the 2 ms floor is not drift" "grep -q 'drift warnings: 0' $T/s-pass.txt"
mkfix selftest-sdrift PASS 9.0
python3 Scripts/e2e/score.py $SR/selftest-sdrift $T/m1.json > $T/s-drift.txt; echo $? > $T/s-drift.rc
check "score: drift above floor warns but still passes" "[[ \$(cat $T/s-drift.rc) == 0 ]] && grep -q 'drift warnings: 1' $T/s-drift.txt"
mkfix selftest-sfail FAIL 1.2
python3 Scripts/e2e/score.py $SR/selftest-sfail $T/m1.json > /dev/null; echo $? > $T/s-fail.rc
check "score: FAIL exits 1" "[[ \$(cat $T/s-fail.rc) == 1 ]]"
mkfix selftest-svoid VOID 1.2
python3 Scripts/e2e/score.py $SR/selftest-svoid $T/m1.json > /dev/null; echo $? > $T/s-void.rc
check "score: VOID exits 3" "[[ \$(cat $T/s-void.rc) == 3 ]]"
mkfix selftest-scheck PASS 1.2 false
python3 Scripts/e2e/score.py $SR/selftest-scheck $T/m1.json > /dev/null; echo $? > $T/s-check.rc
check "score: a failed run check exits 1" "[[ \$(cat $T/s-check.rc) == 1 ]]"
python3 Scripts/e2e/score.py --write-baseline $SR/selftest-sfail $T/m1-bad.json > $T/s-refuse.txt  # exits 1 by design
check "score: refuses a baseline from an unclean run" "grep -q refusing $T/s-refuse.txt && [[ ! -e $T/m1-bad.json ]]"
check "score: scorecards hold no absolute paths" "! grep -lE '/U[s]ers/' $SR/selftest-s*/scorecard.md"
rm -rf $SR/selftest-s*

echo "-- cua checks (fixture shaped like the real c7fb642 inspection)"
python3 Scripts/e2e/cua-eval.py Tests/E2E/selftest/cua-fixture Tests/E2E/selftest/cua-geom.json 99 L > $T/cua.txt
check "cua-eval: REG-040 fails on AXUnknown tiles" "grep -q \$'^cua C3 REG-040 tiles are buttons L\t0' $T/cua.txt"
check "cua-eval: C1 C3 C4 C5 C6 C7 (incl. cell edge) pass on the fixture" "[[ \$(grep -cE \$'^cua C(1|3 tiles|4|5|6|7)[^\t]*\t1' $T/cua.txt) == 8 ]]"
# C7 cell edge: a hit on another app inside the cell fails; a missing probe fails (fails closed)
rm -rf $T/cua-cell; cp -R Tests/E2E/selftest/cua-fixture $T/cua-cell
print -r -- '{"pid":7,"role":"","label":"","other_app":true}' > $T/cua-cell/hit-shown-cell.json
python3 Scripts/e2e/cua-eval.py $T/cua-cell Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-cell.txt
rm $T/cua-cell/hit-shown-cell.json
python3 Scripts/e2e/cua-eval.py $T/cua-cell Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-cell-missing.txt
check "cua-eval: C7 cell edge fails when another app takes the hit, or when not probed" "grep -q \$'^cua C7 tile cell edge stays in the dock L\t0' $T/cua-cell.txt && grep -q \$'^cua C7 tile cell edge stays in the dock L\t0\tnot probed' $T/cua-cell-missing.txt"
# C3 lower bound: a degenerate 2x2 AX frame at the tile centre is inside and centred, but must fail
rm -rf $T/cua-tiny; cp -R Tests/E2E/selftest/cua-fixture $T/cua-tiny
python3 -c "
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for r in rows:
    if r.get('depth', 0) >= 1 and 'w' in r and r.get('role') != 'AXMenuBarItem':
        r['x'] += r['w'] / 2 - 1; r['y'] += r['h'] / 2 - 1; r['w'] = r['h'] = 2
open(sys.argv[1], 'w').write(''.join(json.dumps(r) + '\\n' for r in rows))" $T/cua-tiny/tree.jsonl
python3 Scripts/e2e/cua-eval.py $T/cua-tiny Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-tiny.txt
check "cua-eval: C3 fails on a degenerate (2x2) AX tile frame" "grep -q \$'^cua C3 tiles in AX tree L\t0' $T/cua-tiny.txt"
# C1/C3 paired snapshot: GEOM copied with the window list wins over a later (relayouted) GEOM file
rm -rf $T/cua-pair; cp -R Tests/E2E/selftest/cua-fixture $T/cua-pair
python3 -c "
import json, sys
g = json.load(open(sys.argv[1])); g['docks'][0]['panel']['topLeft'][1] -= 1; json.dump(g, open(sys.argv[2], 'w'))" Tests/E2E/selftest/cua-geom.json $T/cua-geom-moved.json
python3 Scripts/e2e/cua-eval.py $T/cua-pair $T/cua-geom-moved.json 99 L > $T/cua-race.txt
cp Tests/E2E/selftest/cua-geom.json $T/cua-pair/geom-pair.json; print 'relayout during step (GEOM changed after the snapshot; C1/C3 use the paired GEOM)' > $T/cua-pair/pair.txt
python3 Scripts/e2e/cua-eval.py $T/cua-pair $T/cua-geom-moved.json 99 L > $T/cua-paired.txt
check "cua-eval: C1 unpaired race fails, paired snapshot passes and says so" "grep -q \$'^cua C1 panel window L\t0' $T/cua-race.txt && grep -q \$'^cua C1 panel window L\t1.*paired snapshot.*relayout during step' $T/cua-paired.txt"
# C8 (settings=1): SKIP without the files; with a fixture Settings window: pass, an unnamed control
# (a slider with only a value) fails "labelled", a close that never released the hold fails
rm -rf $T/cua-c8; cp -R Tests/E2E/selftest/cua-fixture $T/cua-c8
{ print -r -- '{"depth": 0, "role": "AXWindow", "subrole": "AXFloatingWindow", "label": "Edge Dock", "name": "Edge Dock"}'
  print -r -- '{"depth": 0, "role": "AXWindow", "subrole": "AXStandardWindow", "label": "Dedock Settings", "name": "Dedock Settings"}'
  print -r -- '{"depth": 1, "role": "AXButton", "subrole": "AXCloseButton", "label": "", "name": ""}'
  print -r -- '{"depth": 4, "role": "AXButton", "subrole": "AXIncrementPage", "label": "", "name": ""}'
  print -r -- '{"depth": 4, "role": "AXButton", "subrole": "AXDecrementArrow", "label": "", "name": ""}'
  print -r -- '{"depth": 3, "role": "AXCheckBox", "subrole": "", "label": "Show on the left edge", "name": "Show on the left edge"}'
  print -r -- '{"depth": 3, "role": "AXSlider", "subrole": "", "label": "Show delay", "name": "Show delay"}' } > $T/cua-c8/settings-tree.jsonl
print -r -- '{"id": 7, "layer": 0, "x": 400, "y": 200, "w": 700, "h": 500, "alpha": 1, "onscreen": true, "name": ""}' > $T/cua-c8/settings-windows.jsonl
: > $T/cua-c8/settings-windows-after.jsonl
print -r -- '1 in order: debug.command → inhibitor → reveal.transition' > $T/cua-c8/c8-open.txt
print -r -- '1 in order: debug.command → inhibitor → inhibitor → reveal.transition' > $T/cua-c8/c8-close.txt
python3 Scripts/e2e/cua-eval.py $T/cua-c8 Tests/E2E/selftest/cua-geom.json 99 L > $T/c8-good.txt
sed -i '' 's/"label": "Show delay", "name": "Show delay"/"label": "0.5", "name": ""/' $T/cua-c8/settings-tree.jsonl
print -r -- "0 missing '^inhibitor .*token=editing on=false' after: debug.command → inhibitor" > $T/cua-c8/c8-close.txt
python3 Scripts/e2e/cua-eval.py $T/cua-c8 Tests/E2E/selftest/cua-geom.json 99 L > $T/c8-bad.txt
check "cua-eval: C8 SKIPs without Settings, passes on a good fixture, fails an unnamed control and a held dock" "[[ \$(grep -c \$'^cua C8 .*\tskip\t' $T/cua.txt) == 4 && \$(grep -c \$'^cua C8 .*\t1\t' $T/c8-good.txt) == 4 ]] && grep -q \$'^cua C8 settings controls labelled L\t0\t2 controls, 1 without a label (AXSlider)' $T/c8-bad.txt && grep -q \$'^cua C8 closing Settings releases the hold L\t0' $T/c8-bad.txt"
python3 -c "
import json, sys
g = json.load(open(sys.argv[1])); g['docks'][0].update(style='darkGlass', material='hudWindow'); json.dump(g, open(sys.argv[2] + '/geom-pair.json', 'w'))
g['docks'][0].update(style='lightGlass', material='hudWindow'); json.dump(g, open(sys.argv[2] + '/geom-bad.json', 'w'))" Tests/E2E/selftest/cua-geom.json $T/cua-c8
python3 Scripts/e2e/cua-eval.py $T/cua-c8 Tests/E2E/selftest/cua-geom.json 99 L > $T/c9-good.txt
cp $T/cua-c8/geom-bad.json $T/cua-c8/geom-pair.json; python3 Scripts/e2e/cua-eval.py $T/cua-c8 Tests/E2E/selftest/cua-geom.json 99 L > $T/c9-bad.txt
# C9 live switch: SKIP without the switch files; pass with lightGlass/popover after the switch line
print -r -- '1 in order: debug.command → settings.changed key=dd.dock.style → docks.sync reason=settings' > $T/cua-c8/c9-switch.txt
python3 -c "
import json, sys
g = json.load(open(sys.argv[1])); g['docks'][0].update(style='lightGlass', material='popover'); json.dump(g, open(sys.argv[2], 'w'))" Tests/E2E/selftest/cua-geom.json $T/cua-c8/geom-style.json
python3 Scripts/e2e/cua-eval.py $T/cua-c8 Tests/E2E/selftest/cua-geom.json 99 L > $T/c9-switch.txt
check "cua-eval: C9 style switch SKIPs without a switch, passes when the log and GEOM agree" "grep -q \$'^cua C9 style switch in Settings reaches GEOM L\tskip' $T/cua.txt && grep -q \$'^cua C9 style switch in Settings reaches GEOM L\t1' $T/c9-switch.txt"
check "cua-eval: C9 style SKIP without GEOM style, PASS darkGlass/hudWindow, FAIL otherwise" "grep -q \$'^cua C9 dock style tokens L\tskip' $T/cua.txt && grep -q \$'^cua C9 dock style tokens L\t1' $T/c9-good.txt && grep -q \$'^cua C9 dock style tokens L\t0' $T/c9-bad.txt"
# axpress (REG-051): refuses without the REAL lock, even for the harness-owned fake bundle; the
# bundle refusal is then the second guard. (The real lock is free here: the self-test refused otherwise.)
DEDOCK_LOCK_OWNER=selftest-owner $B/notify $$ openSettings > /dev/null 2> $T/notify-lock.err; echo $? > $T/notify-lock.rc
$B/notify openSettings > /dev/null 2> $T/notify-usage.err; echo $? > $T/notify-usage.rc
check "REG-051 notify refuses without the REAL lock, and needs a target pid" "[[ \$(cat $T/notify-lock.rc) == 2 && \$(cat $T/notify-usage.rc) == 2 ]] && grep -q 'does not hold the REAL desktop lock' $T/notify-lock.err && grep -q 'usage: notify <pid> <cmd>' $T/notify-usage.err"
$B/axprobe focus $$ > $T/focus.json 2>&1
check "axprobe focus reports pids and booleans only" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not (set(d) == {'pid','source','front','app_focus'} and isinstance(d['pid'], int) and isinstance(d['app_focus'], bool)))\" $T/focus.json"
check "axpress refuses a process that is not a harness-owned Dedock build" "! $B/axpress close $$ 'Dedock Settings' 2> $T/axpress.err && grep -q 'refusing' $T/axpress.err"
# REG-061 gates (DEDOCK_REG061=1): C3 = whole cell; C7 cell edge = AXButton with the tile label
DEDOCK_REG061=1 python3 Scripts/e2e/cua-eval.py Tests/E2E/selftest/cua-fixture Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-061.txt
DEDOCK_REG061=1 python3 Scripts/e2e/cua-eval.py $T/cua-tiny Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-061-tiny.txt
rm -rf $T/cua-061b; cp -R Tests/E2E/selftest/cua-fixture $T/cua-061b
print -r -- '{"pid":99,"role":"AXButton","label":"Calculator","other_app":false}' > $T/cua-061b/hit-shown-cell.json
DEDOCK_REG061=1 python3 Scripts/e2e/cua-eval.py $T/cua-061b Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-061b.txt
check "cua-eval: REG-061 gates (C3 whole cell; C7 cell edge needs the tile's AXButton)" "grep -q \$'^cua C3 tiles in AX tree L\t1.*REG-061' $T/cua-061.txt && grep -q \$'^cua C3 tiles in AX tree L\t0' $T/cua-061-tiny.txt && grep -q \$'^cua C7 tile cell edge stays in the dock L\t0' $T/cua-061.txt && grep -q \$'^cua C7 tile cell edge stays in the dock L\t1' $T/cua-061b.txt && grep -q \$'^cua C7 tile cell edge stays in the dock L\t1.*REG-061 pending' $T/cua.txt"
# Occlusion (cand-95411f2c: another app's window above the dock over the top centre): a row probed
# under one is VOID (never PASS); with no clear tile centre on the edge it FAILs as unverifiable.
mkocc() {  # mkocc <dir> <occluded tiles: all|first>
  rm -rf $1; cp -R Tests/E2E/selftest/cua-fixture $1
  python3 -c "
import json, sys
d, mode = sys.argv[1], sys.argv[2]
rows = [json.loads(l) for l in open(d + '/hit-hidden.jsonl') if l.strip()]
occ = {'occluded': True, 'layer': 1500, 'x': 0, 'y': 0, 'w': 400, 'h': 200}
with open(d + '/occl.jsonl', 'w') as f:
    for i, r in enumerate(rows): f.write(json.dumps({'tile': r['tile'], 'occl': occ if mode == 'all' or i == 0 else {'occluded': False}}) + '\n')
for k in ('tile', 'cell', 'outside'):
    json.dump(occ, open(f'{d}/occl-{k}.json', 'w')); json.dump({'pid': 5, 'role': '', 'label': '', 'other_app': True}, open(f'{d}/hit-shown-{k}.json', 'w'))
open(d + '/probe-tile.txt', 'w').write(rows[1 if mode == 'first' else 0]['tile'] + '\n')" $1 $2
}
mkocc $T/cua-occ first; python3 Scripts/e2e/cua-eval.py $T/cua-occ Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-occ.txt
mkocc $T/cua-occall all; python3 Scripts/e2e/cua-eval.py $T/cua-occall Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-occall.txt
check "cua-eval: occluded C7 probes are VOID (never PASS), C6 counts only clear tiles" "[[ \$(grep -cE \$'^cua C7 [^\t]*\tvoid\t.*layer 1500' $T/cua-occ.txt) == 3 ]] && grep -q \$'^cua C6 click-through while hidden L\t1\t.*1 occluded' $T/cua-occ.txt && grep -q \$'^cua C7 shown tile takes the hit L\tvoid\tpointer on .Notes.' $T/cua-occ.txt"
check "cua-eval: every tile centre occluded → C6 and C7 FAIL as unverifiable" "[[ \$(grep -cE \$'^cua C(6|7) [^\t]*\t0\t.*unverifiable' $T/cua-occall.txt) == 4 ]] && ! grep -qE \$'^cua C(6|7) [^\t]*\t(1|void)\t' $T/cua-occall.txt"
mkfix selftest-socc PASS 1.2; print '{"id":"cua C7 shown tile takes the hit T","ok":false,"skip":false,"void":true,"detail":"occluded"}' >> $SR/selftest-socc/checks.jsonl
python3 Scripts/e2e/score.py $SR/selftest-socc $T/m1.json > $T/s-occ.txt; echo $? > $T/s-occ.rc
check "score: a VOID check makes the card VOID (exit 3), shown as VOID, not FAIL" "[[ \$(cat $T/s-occ.rc) == 3 ]] && grep -q '1 void (occluded, rerun)' $T/s-occ.txt && grep -q '| cua C7 shown tile takes the hit T | VOID |' $T/s-occ.txt"
# REG-056 gate: the fixture's window has no subrole/label (fails); with the fixed identity it passes
check "cua-eval: REG-056 fails without the panel AX identity" "grep -q \$'^cua C1 REG-056 panel AX identity L\t0' $T/cua.txt"
rm -rf $T/cua-id; cp -R Tests/E2E/selftest/cua-fixture $T/cua-id
python3 -c "
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
for r in rows:
    if r.get('depth') == 0 and r.get('role') == 'AXWindow': r['subrole'] = 'AXFloatingWindow'; r['label'] = 'Edge Dock'
open(sys.argv[1], 'w').write(''.join(json.dumps(r) + '\\n' for r in rows))" $T/cua-id/tree.jsonl
python3 Scripts/e2e/cua-eval.py $T/cua-id Tests/E2E/selftest/cua-geom.json 99 L > $T/cua-id.txt
check "cua-eval: REG-056 passes with AXFloatingWindow 'Edge Dock'" "grep -q \$'^cua C1 REG-056 panel AX identity L\t1' $T/cua-id.txt"
# log-order (REG-057 notices, REG-059): in order passes; notice before the dock, missing, other pid fail
lo() { print -r -- "{\"subsystem\":\"app.dedock.Dedock\",\"processID\":${2:-5},\"eventMessage\":\"$1\"}" }
{ lo 'settings.recovered source=backup'; lo 'launch.edgeReady ms=300'; lo 'settings.notice kind=recovered' } > $T/lo-good.ndjson
{ lo 'settings.recovered source=backup'; lo 'settings.notice kind=recovered'; lo 'launch.edgeReady ms=9000' } > $T/lo-modal.ndjson
{ lo 'settings.recovered source=backup' 6; lo 'launch.edgeReady ms=300' 6; lo 'settings.notice kind=recovered' 6 } > $T/lo-other.ndjson
LOP=('^settings[.]recovered' '^launch[.]edgeReady' '^settings[.]notice .*kind=recovered')
check "log-order: launch notices in order pass" "python3 Scripts/e2e/log-order.py $T/lo-good.ndjson pid=5 \$LOP | grep -q '^1 '"
check "log-order: a notice before launch.edgeReady fails (REG-057)" "python3 Scripts/e2e/log-order.py $T/lo-modal.ndjson pid=5 \$LOP | grep -q '^0 missing'"
check "log-order: another process's lines do not count" "python3 Scripts/e2e/log-order.py $T/lo-other.ndjson pid=5 \$LOP | grep -q '^0 '"
check "log-order: unreadable log fails closed" "python3 Scripts/e2e/log-order.py $T/no-such.ndjson '^x' | grep -q '^0 log unreadable'"
$B/axprobe at 960 540 only=1 > $T/axp.json 2>&1
check "REG-041 axprobe never records another app's AX text" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); sys.exit(not (d.get('other_app') is True and d.get('label')=='' and d.get('role')=='' and 'app' not in d))\" $T/axp.json"

echo "-- launch / teardown (fake-dock serve)"
echo '{"schemaVersion":1,"docks":[{"id":"dock-0","edge":"left","reveal":{"showDwellMs":120,"hideDelayMs":400}}]}' > $T/seed.json
check "launch" "Scripts/e2e/launch.sh selftest-launch --bin $B/fake-dock --seed $T/seed.json --set 'docks[0].edge=\"right\"' --frame-log >$T/launch.txt"
R=$B/runs/selftest-launch
check "seed patched" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d['docks'][0]['edge'] != 'right')\" $R/data/layout.json"
check "GEOM written" "python3 -c \"import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d['docks'][0]['edge'] != 'right')\" $R/data/e2e/geometry.json"
check "frame-log switch passed" "grep -q 'frameLog=1' $T/launch.txt"
# (to a file, not a pipe: grep -q would close the pipe early and pipefail would report SIGPIPE)
check "teardown + REG-006" "Scripts/e2e/teardown.sh selftest-launch > $T/teardown.txt && grep -q 'PASS REG-006' $T/teardown.txt"
check "processes stopped" "! pgrep -f 'fake-dock serve|runs/selftest-launch' >/dev/null"
check "x-06 refuses a run without hideDelay 0" "Scripts/e2e/launch.sh selftest-x06 --bin $B/fake-dock >/dev/null && ! Scripts/e2e/scenario.sh selftest-x06 L x-06 dry=1 >/dev/null 2>&1; Scripts/e2e/teardown.sh selftest-x06 >/dev/null"
check "x-06 accepts hideDelayMs 0 from the seed" "Scripts/e2e/launch.sh selftest-x06ok --bin $B/fake-dock --seed $T/seed.json --set 'docks[0].reveal.hideDelayMs=0' >/dev/null && Scripts/e2e/scenario.sh selftest-x06ok L x-06 dry=1 | grep -q 'hide=0'; Scripts/e2e/teardown.sh selftest-x06ok >/dev/null"
check "scenario refuses a lock held by someone else" "Scripts/e2e/launch.sh selftest-lock --bin $B/fake-dock >/dev/null && DEDOCK_LOCKS=$T/locks Scripts/e2e/desktop-lock.sh acquire someone-else e2e test >/dev/null && DEDOCK_LOCKS=$T/locks DEDOCK_LOCK_OWNER=dedock-app-f1 Scripts/e2e/scenario.sh selftest-lock L x-01 n=1 2>&1 | grep -q \"held by 'someone-else'\"; DEDOCK_LOCKS=$T/locks Scripts/e2e/desktop-lock.sh release someone-else >/dev/null; Scripts/e2e/teardown.sh selftest-lock >/dev/null"
# quit-refs: a FAKE CoolDock.app (the listener binary in a bundle) and a private lock dir;
# the pattern override keeps the real reference apps out of reach.
mkdir -p $T/Fake/CoolDock.app/Contents/MacOS $T/qlocks $B/runs/selftest-refs
cp $B/listen $T/Fake/CoolDock.app/Contents/MacOS/CoolDock
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>CoolDock</string><key>CFBundleIdentifier</key><string>app.dedock.selftest.fakeref</string><key>LSUIElement</key><true/></dict></plist>' > $T/Fake/CoolDock.app/Contents/Info.plist
$T/Fake/CoolDock.app/Contents/MacOS/CoolDock 30 >/dev/null & fakepid=$!
sleep 1.5
QP="selftest/Fake/CoolDock\\.app/Contents/MacOS/"
DEDOCK_LOCKS=$T/qlocks DEDOCK_REFS_PATTERN=$QP Scripts/e2e/quit-refs.sh selftest-refs > $T/qr-nolock.txt 2>&1
check "quit-refs refuses without the lock" "grep -q '^refusing: desktop lock' $T/qr-nolock.txt && kill -0 $fakepid"
DEDOCK_LOCKS=$T/qlocks Scripts/e2e/desktop-lock.sh acquire $DEDOCK_LOCK_OWNER e2e selftest >/dev/null
check "quit-refs quits a running reference app politely and logs it" "DEDOCK_LOCKS=$T/qlocks DEDOCK_REFS_PATTERN=$QP Scripts/e2e/quit-refs.sh selftest-refs >/dev/null && ! kill -0 $fakepid 2>/dev/null && grep -q 'not relaunched' $B/runs/selftest-refs/refs-quit.txt"
DEDOCK_LOCKS=$T/qlocks Scripts/e2e/desktop-lock.sh release $DEDOCK_LOCK_OWNER >/dev/null
kill $fakepid 2>/dev/null
mkdir -p $T/Fake/Dedock.app/Contents/MacOS && cp $B/fake-dock $T/Fake/Dedock.app/Contents/MacOS/Dedock
DEDOCK_LOCK_OWNER=selftest-owner DEDOCK_LOCKS=$T/glocks Scripts/e2e/launch.sh selftest-guard --bin $T/Fake/Dedock.app/Contents/MacOS/Dedock > $T/guard.txt 2>&1
check "launch refuses a real Dedock without the REAL lock" "grep -q 'refusing: launching Dedock needs the REAL desktop lock' $T/guard.txt && [[ ! -e $B/runs/selftest-guard ]]"
# REG-042: app text with "<private>" and shell metacharacters must never break or execute.
rm -f $T/pwned1 $T/pwned2
FAKE_READY_SUFFIX="<private> \$(touch $T/pwned1) \`touch $T/pwned2\` ;|& >x" Scripts/e2e/launch.sh selftest-hostile --bin $B/fake-dock > $T/hostile-launch.txt 2>&1
hpid=$(sed -n 's/^APP_PID=//p' $B/runs/selftest-hostile/run.env)
Scripts/e2e/teardown.sh selftest-hostile > $T/hostile-teardown.txt 2>&1
check "REG-042 hostile edgeReady text: launch passes" "grep -q '^PASS launched' $T/hostile-launch.txt"
check "REG-042 teardown stops the app anyway" "grep -q 'PASS REG-006' $T/hostile-teardown.txt && ! kill -0 $hpid 2>/dev/null"
check "REG-042 nothing in the app text was executed" "[[ ! -e $T/pwned1 && ! -e $T/pwned2 && ! -e x ]]"
echo "-- fail-closed and teardown (REG-049 / REG-050, review of #12)"
# judge: analyze cannot read the log → not judged → FAIL, never PASS
J=$T/judge-missing; mkdir -p $J; print "scn=x-01 edge=left show=120 hide=400 n=1 run=selftest" > $J/params.env
print 'ready mach=0\nmach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1' > $J/listen.txt
Scripts/e2e/judge.sh $J > /dev/null 2>&1; echo $? > $T/judge-missing.rc
check "REG-049 judge: analyze that cannot run is FAIL" "[[ \$(cat $T/judge-missing.rc) == 1 ]] && grep -q '^FAIL tool analyze timing exited 2' $J/report.txt"
J=$T/judge-nogate; mkdir -p $J; print "scn=perf-move edge=left show=120 hide=400 n=1 run=selftest" > $J/params.env
cp $T/judge-missing/listen.txt $J/; : > $J/log.ndjson; : > $J/perf.txt
Scripts/e2e/judge.sh $J > /dev/null 2>&1
check "REG-049 judge: no gate evaluated is FAIL" "grep -q '^FAIL no gate was evaluated' $J/report.txt && grep -q '^VERDICT FAIL' $J/report.txt"
# score: missing expected row and a failed tool → FAIL, tool health NOT OK
mkfix selftest-sexp PASS 1.2
print -l "REG-006 L" "L.x-01-L" "REG-018 L" > $SR/selftest-sexp/expected.txt
print '{"tool":"geom-check L","rc":0,"ok":true}' > $SR/selftest-sexp/tools.jsonl
python3 Scripts/e2e/score.py $SR/selftest-sexp > $T/s-exp.txt; echo $? > $T/s-exp.rc
check "REG-049 score: a missing expected row is FAIL" "[[ \$(cat $T/s-exp.rc) == 1 ]] && grep -q 'REG-018 L | FAIL | MISSING' $SR/selftest-sexp/scorecard.md && grep -q 'Tool health: \*\*NOT OK' $T/s-exp.txt"
print -l "REG-006 L" "L.x-01-L" > $SR/selftest-sexp/expected.txt
print '{"tool":"geom-check L","rc":139,"ok":false}' > $SR/selftest-sexp/tools.jsonl
python3 Scripts/e2e/score.py $SR/selftest-sexp > $T/s-tool.txt; echo $? > $T/s-tool.rc
check "REG-049 score: a crashed tool is FAIL" "[[ \$(cat $T/s-tool.rc) == 1 ]] && grep -q 'geom-check L rc=139' $T/s-tool.txt"
print '{"tool":"geom-check L","rc":0,"ok":true}' > $SR/selftest-sexp/tools.jsonl
python3 Scripts/e2e/score.py $SR/selftest-sexp > $T/s-ok.txt; echo $? > $T/s-ok.rc
check "score: complete rows + healthy tools PASS" "[[ \$(cat $T/s-ok.rc) == 0 ]] && grep -q 'Tool health: \*\*OK' $T/s-ok.txt"
# --retool (REG-052): re-derive tool health from raw exit codes; original scorecard untouched
print -l "REG-006 L" "L.x-01-L" > $SR/selftest-sexp/expected.txt
print '{"tool":"analyze X","rc":1,"ok":false}' > $SR/selftest-sexp/tools.jsonl
python3 Scripts/e2e/score.py $SR/selftest-sexp > /dev/null; cp $SR/selftest-sexp/scorecard.md $T/orig-card.md
python3 Scripts/e2e/score.py --retool abc1234 $SR/selftest-sexp > $T/retool.txt; echo $? > $T/retool.rc
check "REG-052 --retool accepts analyze exit 1, says so, keeps the original" "[[ \$(cat $T/retool.rc) == 0 ]] && grep -q 'Re-scored with harness .abc1234.: tool() ok-codes fix (REG-052); raw data unchanged' $SR/selftest-sexp/scorecard-rescored.md && grep -q 'Tool health: \*\*NOT OK' $SR/selftest-sexp/scorecard.md && cmp -s $T/orig-card.md $SR/selftest-sexp/scorecard.md"
rm -rf $SR/selftest-sexp $SR/selftest-sexp-L
# measure-idle: no top samples → FAIL (not zeros that pass)
: > $T/empty-top.txt
DEDOCK_TOP_OVERRIDE=$T/empty-top.txt Scripts/measure-idle.sh $$ 5 > $T/idle-empty.txt 2>&1
check "REG-049 measure-idle: no samples is FAIL" "grep -q '^FAIL top gave 0 samples' $T/idle-empty.txt && grep -q '^verdict=FAIL' $T/idle-empty.txt"
# launch.sh: the app never becomes ready → FAIL, and nothing is left running
FAKE_NO_READY=1 Scripts/e2e/launch.sh selftest-noready --bin $B/fake-dock --timeout 2 > $T/noready.txt 2>&1
nr_app=$(sed -n 's/^APP_PID=//p' $B/runs/selftest-noready/run.env); nr_log=$(sed -n 's/^LOG_PID=//p' $B/runs/selftest-noready/run.env)
check "REG-050 failed launch leaves nothing running" "grep -q '^FAIL no launch.edgeReady' $T/noready.txt && ! kill -0 $nr_app 2>/dev/null && ! kill -0 $nr_log 2>/dev/null"
# regress.sh killed mid-run: the trap tears down what it launched (fake debug bundle, private lock)
FA=$T/fakeapp; mkdir -p $FA/build/Dedock.app/Contents/MacOS; cp $B/fake-dock $FA/build/Dedock.app/Contents/MacOS/FakeDock
# Fake bundle id: launch.sh treats it as a non-real app, regress.sh runs it in self-test mode
# (no input, no tccutil, no scenarios), so this is safe even while a real Dedock or a demo runs.
printf '%s' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>FakeDock</string><key>CFBundleIdentifier</key><string>app.dedock.Fake</string><key>LSUIElement</key><true/></dict></plist>' > $FA/build/Dedock.app/Contents/Info.plist
$FA/build/Dedock.app/Contents/MacOS/FakeDock good > /dev/null 2>&1 & fpid=$!
sleep 0.5
if kill -0 $fpid 2>/dev/null && [[ $(lsappinfo info -only bundleid -app $fpid 2>/dev/null) == *app.dedock.Fake* || -n $(ps -o comm= -p $fpid) ]]; then
  DEDOCK_LOCK_OWNER=selftest-owner $B/axpress close $fpid 'Dedock Settings' > /dev/null 2> $T/axpress-lock.err; echo $? > $T/axpress-lock.rc
  check "REG-051 axpress refuses the fake bundle without the REAL lock (exit 2, nothing pressed)" "[[ \$(cat $T/axpress-lock.rc) == 2 ]] && grep -q 'does not hold the REAL desktop lock' $T/axpress-lock.err"
else
  skip "REG-051 axpress refuses the fake bundle without the REAL lock" "the fake app did not start"
fi
kill $fpid 2>/dev/null; wait $fpid 2>/dev/null
export DEDOCK_LOCKS=$T/rlocks; Scripts/e2e/desktop-lock.sh acquire $DEDOCK_LOCK_OWNER e2e selftest > /dev/null
rm -rf $B/runs/selftest-trap*
# Synthetic events are tagged by the driver: the listener tells "the harness posted input" apart
# from "the user moved the mouse" (a cursor-position comparison cannot, e.g. during a demo).
$B/listen 12 > $T/trap-listen.txt & tl=$!
sleep 0.3
Scripts/e2e/regress.sh run $FA id=selftest-trap edges= idle=0 > $T/trap.txt 2>&1 &
rp=$!
for i in {1..80}; do [[ -f $B/runs/selftest-trap-X/run.env ]] && break; sleep 0.1; done
sleep 0.5; kill -TERM $rp; wait $rp 2>/dev/null
tr_app=$(sed -n 's/^APP_PID=//p' $B/runs/selftest-trap-X/run.env 2>/dev/null)
check "REG-050 regress trap tears down on interrupt" "[[ -n '$tr_app' ]] && ! kill -0 ${tr_app:-0} 2>/dev/null && [[ -f $B/runs/selftest-trap-X/teardown.txt ]]"
sleep 1; kill $tl 2>/dev/null; wait $tl 2>/dev/null
check "REG-051 self-test mode posted no input" "grep -q '^ready ' $T/trap-listen.txt && ! grep -q ' syn=1' $T/trap-listen.txt"
DEDOCK_SELFTEST=0 Scripts/e2e/regress.sh run ../e2e-target id=selftest-nolock edges= idle=0 > $T/nolock.txt 2>&1   # exits 2 by design
# REG-052: a complete self-test-mode run; the contract's analyze legitimately exits 1 on a
# launch-only log, which must be recorded as a healthy tool run, not a tool failure.
rm -rf $B/runs/selftest-full*
Scripts/e2e/regress.sh run $FA id=selftest-full edges= idle=0 > $T/full.txt 2>&1
check "REG-052 exit code 1 (gate failed) is a healthy tool run" "grep -q '\"tool\":\"analyze X\",\"rc\":1,\"ok\":true' $B/runs/selftest-full/tools.jsonl && ! grep -q 'FAIL tool analyze' $T/full.txt"
check "REG-055 self-test run lists the hand-off check and SKIPs it (no input posted)" "grep -qx 'REG-055 no pointer hand-off' $B/runs/selftest-full/expected.txt && grep -q '\"id\": \"REG-055 no pointer hand-off\", \"ok\": false, \"skip\": true' $B/runs/selftest-full/checks.jsonl"
check "REG-050 a completed run leaves nothing running" "! kill -0 \$(sed -n 's/^APP_PID=//p' $B/runs/selftest-full-X/run.env) 2>/dev/null"
check "REG-057 rows run: corrupt layout written, notice + REG-006 rows recorded, the reveal row SKIPs (no input)" "! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' $B/runs/selftest-full-C/data/layout.json 2>/dev/null && [[ \$(grep -cE '\"id\": \"(REG-057 (corrupt|unreadable) layout|REG-006 [CU])' $B/runs/selftest-full/checks.jsonl) == 5 ]] && grep -q '\"id\": \"REG-057 corrupt layout: dock reveals while the alert is up\", \"ok\": false, \"skip\": true' $B/runs/selftest-full/checks.jsonl && ! kill -0 \$(sed -n 's/^APP_PID=//p' $B/runs/selftest-full-C/run.env) \$(sed -n 's/^APP_PID=//p' $B/runs/selftest-full-U/run.env) 2>/dev/null"
# REG-055 (review of #22): pointer sharing ON → refuse before any input, no run dir; allow → runs, recorded
rm -rf $B/runs/selftest-ps*
$B/listen 6 > $T/ps-listen.txt & pl=$!
sleep 0.3
DEDOCK_STUB_PSHARING=on Scripts/e2e/regress.sh run $FA id=selftest-pson edges= idle=0 > $T/pson.txt 2>&1; echo $? > $T/pson.rc
sleep 0.5; kill $pl 2>/dev/null; wait $pl 2>/dev/null
check "REG-055 pointer sharing on: refuses (exit 2) before any input, no run" "[[ \$(cat $T/pson.rc) == 2 ]] && grep -q 'refusing: OS pointer sharing across devices is ON' $T/pson.txt && [[ ! -e $B/runs/selftest-pson && ! -e $B/runs/selftest-pson-X ]] && grep -q '^ready ' $T/ps-listen.txt && ! grep -q ' syn=1' $T/ps-listen.txt"
DEDOCK_STUB_PSHARING=on Scripts/e2e/regress.sh run $FA id=selftest-psallow edges= idle=0 psharing=allow > $T/psallow.txt 2>&1
check "REG-055 psharing=allow runs and is recorded in env.json and on the scorecard" "grep -q '\"pointer_sharing\": \"on (psharing=allow)\"' $B/runs/selftest-psallow/env.json && grep -q 'OS pointer sharing: on (psharing=allow)' $B/runs/selftest-psallow/scorecard.md"
rm -rf $B/runs/selftest-ps*
rm -rf $B/runs/selftest-full*
check "REG-051 regress refuses a real build without the REAL lock" "grep -q 'does not hold the REAL desktop lock' $T/nolock.txt && [[ ! -e $B/runs/selftest-nolock ]]"
Scripts/e2e/desktop-lock.sh release $DEDOCK_LOCK_OWNER > /dev/null; unset DEDOCK_LOCKS
rm -rf $B/runs/selftest-trap*
# owner-checked touch; pointer release with nothing held posts nothing harmful
DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh acquire owner-a e2e t > /dev/null
check "a private lock dir never counts as the real lock" "! DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh real-holder > /dev/null && ! DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh require owner-a 2> /dev/null"
check "touch is owner-checked" "! DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh touch owner-b > /dev/null && DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh touch owner-a > /dev/null"
DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh release owner-a > /dev/null
check "pointer release with nothing held" "$B/pointer release | grep -q 'label=released' && $B/pointer mods | grep -q '^mods=0'"
# x-18 bottom/top: geom-check zone rules beside the native Dock (REG-065), empty zones FAIL
python3 - $T <<'PY'
import json, sys
T = sys.argv[1]
def geom(zones, nd=True):
    return {"screens": [{"id": 1, "main": True, "scale": 1, "frame": {"topLeft": [0, 0, 1920, 1080]}, "visibleFrame": {"topLeft": [0, 30, 1920, 972]}}],
            "docks": [{"id": "dock-0", "screen": 1, "edge": "bottom", "mode": "reveal", "state": "hidden", "showDwellMs": 120,
                       "capsule": {"topLeft": [832, 916, 256, 78]}, "panel": {"topLeft": [808, 672, 304, 330]}, "tiles": [],
                       "zones": [{"id": f"z{i}", "kind": "wall", "rect": {"topLeft": r}} for i, r in enumerate(zones)],
                       "nativeDock": {"edge": "bottom", "autohide": False, "rect": {"topLeft": [540, 1074, 840, 6]}} if nd else None}]}
json.dump(geom([[24, 1074, 516, 6], [1380, 1074, 516, 6]]), open(f"{T}/g-both.json", "w"))
json.dump(geom([[24, 1074, 516, 6]]), open(f"{T}/g-left.json", "w"))
json.dump(geom([]), open(f"{T}/g-none.json", "w"))
json.dump(geom([[24, 1074, 600, 6]]), open(f"{T}/g-under.json", "w"))
PY
for f in both left none under; do python3 Scripts/e2e/geom-check.py $T/g-$f.json padding=8 gap=8 inset=8 zone=6 > $T/gc-$f.txt; done
check "x-18 geom-check: zone strips on both sides of the native Dock PASS 'reachable'; one side, none, or under the Dock FAIL" "grep -q '^PASS dock-0 bottom zone reachable beside the native Dock' $T/gc-both.txt && grep -q '^FAIL dock-0 bottom zone reachable beside the native Dock' $T/gc-left.txt && grep -q '^FAIL dock-0 bottom has a trigger zone' $T/gc-none.txt && grep -q \"^FAIL dock-0 bottom zone z0 (wall) off the native Dock's footprint\" $T/gc-under.txt"
# scenario: a GEOM with zones = [] is a FAIL report (no probe), not a skip or a broken run
Scripts/e2e/launch.sh selftest-nozone --bin $B/fake-dock --set 'docks[0].edge="bottom"' > /dev/null 2>&1
sleep 0.3; cp $T/g-none.json $B/runs/selftest-nozone/data/e2e/geometry.json
Scripts/e2e/scenario.sh selftest-nozone B x-01 n=1 dry=1 > $T/nozone.txt 2>&1; echo $? > $T/nozone.rc
Scripts/e2e/teardown.sh selftest-nozone > /dev/null 2>&1
check "x-18 scenario: no trigger zone in GEOM gives a FAIL report (exit 1), never a probe" "[[ \$(cat $T/nozone.rc) == 1 ]] && grep -q 'FAIL trigger zone: GEOM has no zone on the bottom edge' $T/nozone.txt && grep -q 'VERDICT FAIL x-01 bottom' $T/nozone.txt"
# hide delay: an armingHide that follows the reveal's animationEnd (the pointer left while revealing)
# is not a lateness sample; a normal leave still is
{ print -r -- '{"subsystem":"app.dedock.Dedock","machTimestamp":998000000,"category":"edge","eventMessage":"edge.zoneExit edge=top zone=z-0 x=960.00 y=1052.00"}'
  print -r -- '{"subsystem":"app.dedock.Dedock","machTimestamp":1000000000,"category":"reveal","eventMessage":"reveal.transition edge=top from=revealing to=armingHide cause=animationEnd inh=-"}'
  print -r -- '{"subsystem":"app.dedock.Dedock","machTimestamp":1008600000,"category":"reveal","eventMessage":"reveal.transition edge=top from=armingHide to=hiding cause=hideDelay inh=-"}'
  print -r -- '{"subsystem":"app.dedock.Dedock","machTimestamp":2000000000,"category":"reveal","eventMessage":"reveal.transition edge=top from=shown to=armingHide cause=leave inh=-"}'
  print -r -- '{"subsystem":"app.dedock.Dedock","machTimestamp":2009600000,"category":"reveal","eventMessage":"reveal.transition edge=top from=armingHide to=hiding cause=hideDelay inh=-"}' } > $T/hide-reveal.ndjson
$B/analyze timing $T/hide-reveal.ndjson show=300 hide=400 > $T/hide-reveal.txt 2>&1
sed 's/"machTimestamp":998000000/"machTimestamp":990000000/' $T/hide-reveal.ndjson > $T/hide-reveal-late.ndjson
python3 -c "
import sys; t = open(sys.argv[1]).read().replace('1008600000', '1015000000'); open(sys.argv[1], 'w').write(t)" $T/hide-reveal-late.ndjson
$B/analyze timing $T/hide-reveal-late.ndjson show=300 hide=400 > $T/hide-reveal-late.txt 2>&1
check "hide delay: a hide after leaving during the reveal is timed from the zone exit (on time PASS, 200 ms late FAIL); a normal leave as before" "grep -q 'INFO hide delay: 1 hide' $T/hide-reveal.txt && grep -q 'PASS hide delay: n=1' $T/hide-reveal.txt && grep -q '^PASS hide delay after a leave during the reveal' $T/hide-reveal.txt && grep -q '^FAIL hide delay after a leave during the reveal' $T/hide-reveal-late.txt"
check "scenario dry run" "Scripts/e2e/launch.sh selftest-dry --bin $B/fake-dock >/dev/null && Scripts/e2e/scenario.sh selftest-dry L x-01 n=2 dry=1 | grep -q 'edge left' ; Scripts/e2e/teardown.sh selftest-dry >/dev/null"

echo
(( skipped )) && echo "selftest: $skipped check(s) SKIPPED (not counted as passed)"
(( fails == 0 )) && echo "selftest: all checks passed" || echo "selftest: $fails check(s) FAILED (details in $T)"
exit $(( fails > 0 ))
