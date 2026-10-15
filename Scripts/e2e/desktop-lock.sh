#!/bin/zsh
# Desktop lock for sessions that drive the mouse/keyboard (docs/organization.md §6.1).
# Atomic: mkdir succeeds for exactly one taker.
#
#   desktop-lock.sh acquire <owner> <lane> <purpose>   exit 1 if held by someone else
#   desktop-lock.sh touch <owner>                      refresh (every 5 min while held); only the owner
#   desktop-lock.sh release <owner>                    only the owner may release
#   desktop-lock.sh require <owner>                    exit 0 only if <owner> holds the REAL lock (the
#                                                      default path; a DEDOCK_LOCKS override never counts).
#                                                      Every step that can post input, move the cursor,
#                                                      run tccutil or launch a real-bundle-id app calls it.
#   desktop-lock.sh status
#
# Messaging the other sessions before taking and after releasing is still required;
# this script only guards the lock itself.
set -euo pipefail

LOCKS=${DEDOCK_LOCKS:-$HOME/dedock/.locks}  # shared by every checkout of the repo
LOCK=$LOCKS/desktop.lock
now() { date -u +%Y-%m-%dT%H:%M:%SZ }

case ${1:-status} in
acquire)
  owner=${2:?owner} lane=${3:?lane} purpose=${4:?purpose}
  mkdir -p $LOCKS
  if mkdir $LOCK 2>/dev/null; then
    printf 'owner=%s\nlane=%s\npurpose=%s\nstarted=%s\n' $owner $lane $purpose "$(now)" > $LOCK/info
    echo "acquired"
  else
    echo "held:"; cat $LOCK/info $LOCK/owner 2>/dev/null; exit 1
  fi ;;
touch)
  owner=${2:?owner}
  [[ -d $LOCK ]] || { echo "not held"; exit 1 }
  grep -qx "owner=$owner" $LOCK/info 2>/dev/null || { echo "held by someone else:"; cat $LOCK/info $LOCK/owner 2>/dev/null; exit 1 }
  touch $LOCK/info; echo "touched $(now)" ;;
release)
  owner=${2:?owner}
  [[ -d $LOCK ]] || { echo "not held"; exit 0 }
  if grep -qx "owner=$owner" $LOCK/info 2>/dev/null || grep -qx "$owner" $LOCK/owner 2>/dev/null; then
    rm -r $LOCK; echo "released"
  else
    echo "held by someone else:"; cat $LOCK/info; exit 1
  fi ;;
require)
  owner=${2:?owner}
  REAL=$HOME/dedock/.locks/desktop.lock
  if [[ -d $REAL ]] && grep -qx "owner=$owner" $REAL/info 2>/dev/null; then exit 0; fi
  echo "refusing: '$owner' does not hold the REAL desktop lock ($([[ -d $REAL ]] && sed -n 's/^owner=//p' $REAL/info 2>/dev/null || echo free))" >&2
  exit 1 ;;
status)
  if [[ -d $LOCK ]]; then
    # Holders write `info` (this script) or `owner` (other sessions' tooling); show whichever exists.
    f=$LOCK/info; [[ -f $f ]] || f=$LOCK/owner; [[ -f $f ]] || f=$LOCK
    [[ -f $f ]] && { cat $f; echo } || echo "owner=unknown (no info/owner file)"
    echo "age_s=$(( $(date +%s) - $(stat -f %m $f) ))"
  else
    echo "free"
  fi ;;
*) echo "usage: $0 acquire|touch|release|status"; exit 2 ;;
esac
