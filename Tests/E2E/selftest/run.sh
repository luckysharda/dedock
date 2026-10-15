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
if [[ -d $HOME/dedock/.locks/desktop.lock ]]; then
  echo "selftest: refusing — the real desktop lock is held ($(sed -n 's/^owner=//p' $HOME/dedock/.locks/desktop.lock/info 2>/dev/null || echo '?')); run it when the desktop is free"
  exit 2
fi
export DEDOCK_LOCK_OWNER=selftest-owner   # no default owner anywhere (review of #12)
export DEDOCK_SELFTEST=1                  # fake bundle ids and private locks only; never posts input
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi }
skipped=0
skip() { echo "SKIP $1 ($2)"; skipped=$((skipped + 1)); }   # a skipped check is never a PASS

echo "-- build"
for src in Scripts/e2e/pointer.swift Scripts/e2e/listen.swift Scripts/e2e/analyze.swift Scripts/e2e/axprobe.swift Scripts/e2e/backdrop.swift Scripts/measure-pixels.swift Tests/E2E/selftest/fake-dock.swift; do
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
printf 'mach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1\n' > $T/clean.txt
printf 'mach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1\nmach=2 ev=move x=3 y=1 dx=2 dy=0 mods=0 syn=0\n' > $T/dirty.txt
printf 'mach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0\n' > $T/untagged.txt
check "contamination: clean passes" "$B/analyze contamination $T/clean.txt >/dev/null"
check "contamination: foreign input fails" "! $B/analyze contamination $T/dirty.txt >/dev/null"
: > $T/empty.txt
check "contamination: idle run with no input passes" "$B/analyze contamination $T/empty.txt idle=1 >/dev/null"
check "contamination: pointer run with no input fails" "! $B/analyze contamination $T/empty.txt >/dev/null"
check "contamination: untagged fails" "! $B/analyze contamination $T/untagged.txt >/dev/null"

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
check "cua-eval: C1 C3 C4 C5 C6 C7 pass on the fixture" "[[ \$(grep -cE \$'^cua C(1|3 tiles|4|5|6|7)[^\t]*\t1' $T/cua.txt) == 7 ]]"
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
print 'mach=1 ev=move x=1 y=1 dx=0 dy=0 mods=0 syn=1' > $J/listen.txt
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
check "REG-051 self-test mode posted no input" "! grep -q ' syn=1' $T/trap-listen.txt"
DEDOCK_SELFTEST=0 Scripts/e2e/regress.sh run ../e2e-target id=selftest-nolock edges= idle=0 > $T/nolock.txt 2>&1   # exits 2 by design
# REG-052: a complete self-test-mode run; the contract's analyze legitimately exits 1 on a
# launch-only log, which must be recorded as a healthy tool run, not a tool failure.
rm -rf $B/runs/selftest-full*
Scripts/e2e/regress.sh run $FA id=selftest-full edges= idle=0 > $T/full.txt 2>&1
check "REG-052 exit code 1 (gate failed) is a healthy tool run" "grep -q '\"tool\":\"analyze X\",\"rc\":1,\"ok\":true' $B/runs/selftest-full/tools.jsonl && ! grep -q 'FAIL tool analyze' $T/full.txt"
check "REG-050 a completed run leaves nothing running" "! kill -0 \$(sed -n 's/^APP_PID=//p' $B/runs/selftest-full-X/run.env) 2>/dev/null"
rm -rf $B/runs/selftest-full*
check "REG-051 regress refuses a real build without the REAL lock" "grep -q 'does not hold the REAL desktop lock' $T/nolock.txt && [[ ! -e $B/runs/selftest-nolock ]]"
Scripts/e2e/desktop-lock.sh release $DEDOCK_LOCK_OWNER > /dev/null; unset DEDOCK_LOCKS
rm -rf $B/runs/selftest-trap*
# owner-checked touch; pointer release with nothing held posts nothing harmful
DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh acquire owner-a e2e t > /dev/null
check "touch is owner-checked" "! DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh touch owner-b > /dev/null && DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh touch owner-a > /dev/null"
DEDOCK_LOCKS=$T/tlocks Scripts/e2e/desktop-lock.sh release owner-a > /dev/null
check "pointer release with nothing held" "$B/pointer release | grep -q 'label=released' && $B/pointer mods | grep -q '^mods=0'"
check "scenario dry run" "Scripts/e2e/launch.sh selftest-dry --bin $B/fake-dock >/dev/null && Scripts/e2e/scenario.sh selftest-dry L x-01 n=2 dry=1 | grep -q 'edge left' ; Scripts/e2e/teardown.sh selftest-dry >/dev/null"

echo
(( skipped )) && echo "selftest: $skipped check(s) SKIPPED (not counted as passed)"
(( fails == 0 )) && echo "selftest: all checks passed" || echo "selftest: $fails check(s) FAILED (details in $T)"
exit $(( fails > 0 ))
