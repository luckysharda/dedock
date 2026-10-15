#!/bin/zsh
# Builds every harness tool into build/e2e/ and checks it against known answers.
# Needs no app and never moves the cursor. Run after any change under Scripts/ or Tests/E2E/.
#
#   Tests/E2E/selftest/run.sh
set -uo pipefail

# Run from the harness root with relative paths: `check` re-parses commands with eval,
# and the absolute path contains a space ("Dedock app").
cd ${0:A:h:h:h:h}
H=.
B=build/e2e
T=$B/selftest
mkdir -p $B $T
rm -rf $T/* $B/runs/selftest-*
fails=0
check() { if eval "$2"; then echo "PASS $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi }

echo "-- build"
for src in Scripts/e2e/pointer.swift Scripts/e2e/listen.swift Scripts/e2e/analyze.swift Scripts/measure-pixels.swift Tests/E2E/selftest/fake-dock.swift; do
  out=$B/${${src:t}%.swift}
  check "compile ${src:t}" "swiftc -O $src -o $out 2>$T/${src:t}.err"
done

echo "-- pointer (no events posted)"
check "screen size" "$B/pointer screen | grep -q 'w='"
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
  /usr/bin/log stream --style ndjson --level debug --predicate 'subsystem == "app.dedock.Dedock"' > $T/$m.ndjson 2>&1 &
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
check "contamination: untagged fails" "! $B/analyze contamination $T/untagged.txt >/dev/null"

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
check "scenario dry run" "Scripts/e2e/launch.sh selftest-dry --bin $B/fake-dock >/dev/null && Scripts/e2e/scenario.sh selftest-dry L x-01 n=2 dry=1 | grep -q 'edge left' ; Scripts/e2e/teardown.sh selftest-dry >/dev/null"

echo
(( fails == 0 )) && echo "selftest: all checks passed" || echo "selftest: $fails check(s) FAILED (details in $T)"
exit $(( fails > 0 ))
