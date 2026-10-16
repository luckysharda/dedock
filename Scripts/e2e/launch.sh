#!/bin/zsh
# Launch the dedock debug build for one E2E run (docs/evaluation.md §7.2, Tests/E2E/contract.md).
#
#   Scripts/e2e/launch.sh <run-id> [options]
#     --app <worktree>       worktree whose build/Dedock.app to run (default: $DEDOCK_APP_WORKTREE)
#     --bin <executable>     run this executable instead of the bundle (harness self-test)
#     --seed <layout.json>   seed layout (default: <worktree>/Tests/E2E/fixtures/layout-seed.json if present)
#     --no-seed              start on an empty data dir (first-launch behaviour, REG-026)
#     --set <path>=<json>    patch the seeded layout, e.g. --set 'docks[0].edge="right"'
#                            --set 'docks[0].reveal.showDwellMs=120' (repeatable)
#     --frame-log            also set DEDOCK_FRAME_LOG=1
#     --corrupt-layout       replace layout.json with invalid JSON (REG-036/REG-057 recovery path)
#     --unreadable-layout    make layout.json unreadable (chmod 000; REG-057 read-only path)
#     --timeout <s>          wait this long for launch.edgeReady (default 5)
#
# Creates build/e2e/runs/<run-id>/ in the harness worktree:
#   data/            DEDOCK_E2E_HOME (layout.json, e2e/geometry.json)
#   log.ndjson       log stream of subsystem app.dedock.Dedock
#   dock-before.plist, before-apps.txt, run.env (APP_PID, LOG_PID, paths)
# Does not move the cursor, but a real Dedock shows a dock and reacts to the pointer, so it
# refuses unless this session holds the desktop lock and no other Dedock runs. Does not quit CoolDock or
# DockDoor: it records them and warns, because quitting them is the user's call.
# Stop everything with Scripts/e2e/teardown.sh <run-id>.
set -euo pipefail

HARNESS=${0:A:h:h:h}
run=${1:?usage: launch.sh <run-id> [options]}; shift
app=${DEDOCK_APP_WORKTREE:-} bin= seed= noseed=0 frame=0 timeout=5 corrupt=0 unreadable=0
sets=()
while (( $# )); do
  case $1 in
    --app) app=$2; shift 2 ;;
    --bin) bin=$2; shift 2 ;;
    --seed) seed=$2; shift 2 ;;
    --no-seed) noseed=1; shift ;;
    --set) sets+=$2; shift 2 ;;
    --frame-log) frame=1; shift ;;
    --corrupt-layout) corrupt=1; shift ;;
    --unreadable-layout) unreadable=1; shift ;;
    --timeout) timeout=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ -z $bin ]]; then
  [[ -n $app ]] || { echo "need --app <worktree> or DEDOCK_APP_WORKTREE" >&2; exit 2 }
  exe=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" $app/build/Dedock.app/Contents/Info.plist 2>/dev/null || echo Dedock)
  bin=$app/build/Dedock.app/Contents/MacOS/$exe
  [[ -z $seed && $noseed == 0 && -f $app/Tests/E2E/fixtures/layout-seed.json ]] && seed=$app/Tests/E2E/fixtures/layout-seed.json
fi
[[ -x $bin ]] || { echo "not executable: $bin (run Scripts/make-app.sh debug in the app worktree)" >&2; exit 2 }

# A real Dedock puts a dock on screen and reacts to the pointer, so launching one counts as
# driving the desktop: only while THIS session holds the lock, and never next to another
# Dedock (two instances react to the same pointer and share one log subsystem).
# The self-test's fake app (not named Dedock) shows nothing and is exempt.
# Real bundle ids (or an unbundled binary named Dedock) count; self-tests use app.dedock.Fake.
plist=${bin:h:h}/Info.plist
bid=""   # (set -e: a failing $(...) in an assignment would abort the script)
[[ -f $plist ]] && bid=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" $plist 2>/dev/null || true)
if [[ $bid == app.dedock.Dedock || $bid == app.dedock.Dedock.debug || ( -z $bid && ${bin:t} == Dedock ) ]]; then
  me=${DEDOCK_LOCK_OWNER:?set DEDOCK_LOCK_OWNER to your session name}
  $HARNESS/Scripts/e2e/desktop-lock.sh require $me || { echo "refusing: launching Dedock needs the REAL desktop lock held by '$me'" >&2; exit 2 }
  others=$(pgrep -x Dedock || true)
  [[ -z $others ]] || { echo "refusing: another Dedock is running (pid $others); quit it first" >&2; exit 2 }
fi

R=$HARNESS/build/e2e/runs/$run
[[ -e $R ]] && { echo "run dir exists: $R (pick a new run id)" >&2; exit 2 }
mkdir -p $R/data

# Preconditions recorded, not changed (§7.2 steps 2-3).
pgrep -lf "CoolDock|DockDoor" > $R/before-apps.txt || true
if [[ -s $R/before-apps.txt ]]; then
  echo "WARN reference apps running (they compete for screen edges; results near edges are suspect):"
  sed 's/^/     /' $R/before-apps.txt
fi
defaults read com.apple.dock > $R/dock-before.plist

# Seed and patch the layout.
if [[ -n $seed ]]; then
  cp $seed $R/data/layout.json
fi
if (( ${#sets} )); then
  [[ -f $R/data/layout.json ]] || echo '{}' > $R/data/layout.json
  python3 - $R/data/layout.json $sets <<'EOF'
import json, re, sys
path, patches = sys.argv[1], sys.argv[2:]
doc = json.load(open(path))
for p in patches:
    key, _, raw = p.partition("=")
    value = json.loads(raw)
    parts = re.findall(r"[^.\[\]]+|\[\d+\]", key)
    node = doc
    for i, part in enumerate(parts):
        last = i == len(parts) - 1
        nxt = parts[i + 1] if not last else None
        if part.startswith("["):
            idx = int(part[1:-1])
            while len(node) <= idx: node.append({})
            if last: node[idx] = value
            else: node = node[idx]
        else:
            if last: node[part] = value
            else: node = node.setdefault(part, [] if nxt.startswith("[") else {})
json.dump(doc, open(path, "w"), indent=2)
EOF
fi

# Broken layouts for the launch-notice paths (REG-057): after seeding, before the app starts.
(( corrupt )) && print -r -- '{ "schema": 1, "docks": [ not json' > $R/data/layout.json
if (( unreadable )); then
  [[ -f $R/data/layout.json ]] || echo '{}' > $R/data/layout.json
  chmod 000 $R/data/layout.json
fi

# Log capture first, so launch.edgeReady is not missed. (/usr/bin/log: zsh has a `log` builtin.)
/usr/bin/log stream --style ndjson --level debug --predicate 'subsystem == "app.dedock.Dedock"' > $R/log.ndjson 2>&1 &
log_pid=$!
sleep 1

exec_mach=$($HARNESS/build/e2e/pointer now 2>/dev/null | sed -n 's/^mach=\([0-9]*\).*/\1/p')
env DEDOCK_E2E=1 DEDOCK_E2E_HOME=$R/data DEDOCK_FRAME_LOG=$frame $bin > $R/app-stdout.txt 2>&1 &
app_pid=$!
# Values shell-quoted: worktree paths contain spaces ("Dedock app").
{
  print -r -- "RUN_DIR=${(q)R}"
  print -r -- "APP_PID=$app_pid"
  print -r -- "LOG_PID=$log_pid"
  print -r -- "DATA_DIR=${(q)R}/data"
  print -r -- "GEOM=${(q)R}/data/e2e/geometry.json"
  print -r -- "BIN=${(q)bin}"
  print -r -- "STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  print -r -- "EXEC_MACH=${exec_mach:-0}"
} > $R/run.env

deadline=$(( SECONDS + timeout ))
while (( SECONDS < deadline )); do
  if ! kill -0 $app_pid 2>/dev/null; then
    kill $log_pid 2>/dev/null
    echo "FAIL app exited during launch (see $R/app-stdout.txt); log stream stopped"; exit 1
  fi
  # Only OUR process's line counts (REG-069): another Dedock process logging to the same subsystem
  # (another session's run or unit tests) once made a launch that never became ready read as ready.
  line=$(grep '"eventMessage":"launch.edgeReady' $R/log.ndjson | grep -E "\"processID\" ?: ?${app_pid}[,}]" | head -1 || true)
  if [[ -n $line ]]; then
    ready=$(print -r -- $line | grep -o '"eventMessage":"launch.edgeReady[^"]*' | sed 's/.*launch.edgeReady //')
    # External cross-check: mach clock just before exec -> machTimestamp of the event (24 MHz ticks).
    ready_mach=$(print -r -- $line | grep -o '"machTimestamp":[0-9]*' | cut -d: -f2)
    ext=""
    [[ -n $ready_mach && ${exec_mach:-0} -gt 0 ]] && ext=" external=$(( (ready_mach - exec_mach) / 24000 ))ms"
    print -r -- "EDGE_READY=${(q)ready}${(q)ext}" >> $R/run.env   # app text: quoted (may hold "<private>")
    echo "PASS launched pid=$app_pid run=$R ($ready$ext)"
    exit 0
  fi
  sleep 0.1
done
# A failed launch never leaves anything behind (review of #12): stop the app and the log stream.
kill $app_pid $log_pid 2>/dev/null
for i in {1..30}; do kill -0 $app_pid 2>/dev/null || break; sleep 0.1; done
kill -9 $app_pid 2>/dev/null || true
echo "FAIL no launch.edgeReady within ${timeout}s (app and log stream stopped)"
exit 1
