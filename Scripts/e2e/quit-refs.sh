#!/bin/zsh
# Quit CoolDock / DockDoor before an edge-test run (user decision 2026-10-15).
#
#   Scripts/e2e/quit-refs.sh <run-id>
#
# Rules this enforces:
#   - only while THIS session holds the desktop lock ($DEDOCK_LOCK_OWNER, default dedock-app-f1)
#   - only processes that are already running are asked to quit (by pid, through
#     NSRunningApplication.terminate, so nothing is ever launched by name)
#   - every action is logged in <run>/refs-quit.txt
#   - nothing is ever relaunched: the user relaunches them
#   - nothing about them is observed or timed beyond "was running / has quit"
set -euo pipefail

HARNESS=${0:A:h:h:h}
run=${1:?usage: quit-refs.sh <run-id>}
R=$HARNESS/build/e2e/runs/$run
[[ -d $R ]] || { echo "no run dir $R" >&2; exit 2 }

me=${DEDOCK_LOCK_OWNER:-dedock-app-f1}
holder=$($HARNESS/Scripts/e2e/desktop-lock.sh status | sed -n 's/^owner=//p')
[[ $holder == $me ]] || { echo "refusing: desktop lock is held by '${holder:-nobody}', not '$me'" >&2; exit 2 }

log=$R/refs-quit.txt
stamp() { date -u +%Y-%m-%dT%H:%M:%SZ }
# DEDOCK_REFS_PATTERN exists only so the self-test can target a fake bundle, never the real apps.
pids=($(pgrep -f "${DEDOCK_REFS_PATTERN:-/(CoolDock|DockDoor)\.app/Contents/MacOS/}" || true))
if (( ! ${#pids} )); then
  echo "$(stamp) none running" >> $log; echo "none running"; exit 0
fi

rc=0
for pid in $pids; do
  exe=$(ps -o comm= -p $pid || true)  # not `path`: zsh ties it to $PATH
  echo "$(stamp) quit requested pid=$pid $exe (lock holder $me)" >> $log
  # Polite quit of that exact process (like Quit from its menu); JXA calls a zero-argument
  # Objective-C method by property access, so `a.terminate` sends -terminate.
  osascript -l JavaScript -e "ObjC.import('AppKit'); var a = \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid); if (!a.isNil()) { a.terminate }" >/dev/null 2>&1 || true
  for i in {1..50}; do kill -0 $pid 2>/dev/null || break; sleep 0.1; done
  if kill -0 $pid 2>/dev/null; then
    echo "$(stamp) still running after 5 s pid=$pid (not forced)" >> $log
    echo "WARN pid $pid ($exe) did not quit within 5 s; not forcing it"; rc=1
  else
    echo "$(stamp) quit pid=$pid" >> $log
    echo "quit pid $pid ($exe)"
  fi
done
echo "$(stamp) not relaunched: the user relaunches reference apps" >> $log
exit $rc
