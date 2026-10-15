#!/bin/zsh
# End an E2E run started by launch.sh (docs/evaluation.md §7.2 step 7).
#
#   Scripts/e2e/teardown.sh <run-id>
#
# Stops the app and the log stream, checks REG-006 (the native Dock's prefs were
# never written) and reports reference apps whose running state changed.
# Exit 1 if REG-006 fails.
set -euo pipefail

HARNESS=${0:A:h:h:h}
run=${1:?usage: teardown.sh <run-id>}
R=$HARNESS/build/e2e/runs/$run
[[ -f $R/run.env ]] || { echo "no run.env in $R" >&2; exit 2 }
source $R/run.env

for pid in $APP_PID $LOG_PID; do
  kill $pid 2>/dev/null || true
done
for i in {1..30}; do kill -0 $APP_PID 2>/dev/null || break; sleep 0.1; done
kill -0 $APP_PID 2>/dev/null && { kill -9 $APP_PID 2>/dev/null || true; echo "WARN app needed SIGKILL" }

rc=0
defaults read com.apple.dock > $R/dock-after.plist
if diff -q $R/dock-before.plist $R/dock-after.plist >/dev/null; then
  echo "PASS REG-006 native Dock prefs unchanged"
else
  echo "FAIL REG-006 native Dock prefs changed:"; diff $R/dock-before.plist $R/dock-after.plist | head -20
  rc=1
fi

pgrep -lf "CoolDock|DockDoor" > $R/after-apps.txt || true
if ! diff -q <(awk '{print $2}' $R/before-apps.txt | sort) <(awk '{print $2}' $R/after-apps.txt | sort) >/dev/null; then
  echo "WARN reference apps changed during the run: before=[$(awk '{print $2}' $R/before-apps.txt | xargs)] after=[$(awk '{print $2}' $R/after-apps.txt | xargs)]"
fi
echo "INFO run dir $R ($(grep -c '"app.dedock.Dedock"' $R/log.ndjson 2>/dev/null || echo 0) log events)"
exit $rc
