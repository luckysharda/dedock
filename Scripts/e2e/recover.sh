#!/bin/zsh
# T27 recovery actions that touch the system. They run only for the holder of the REAL desktop lock
# (REG-051 pattern: checked here, not only by the caller), inside a window the user confirmed for
# exactly this. Never changes a setting.
#
#   Scripts/e2e/recover.sh killdock       restart the native Dock (killall Dock); prints the old and new pid
#   Scripts/e2e/recover.sh sleepcheck     exit 0 only when display sleep cannot lock the session
#                                         (screen lock off); 3 otherwise or when unknown (read-only)
#
# Display sleep/wake itself is not offered: on a Mac that locks at display sleep, waking would land
# on the lock screen, and the harness never posts input to a possibly locked session.
set -u
E=${0:A:h}
me=${DEDOCK_LOCK_OWNER:-}
case ${1:-} in
killdock)
  [[ -n $me ]] && $E/desktop-lock.sh require $me || { echo "recover: refusing: not the holder of the REAL desktop lock (REG-051)" >&2; exit 2 }
  old=$(pgrep -x Dock | head -1)
  killall Dock || exit 2
  for i in {1..50}; do sleep 0.1; new=$(pgrep -x Dock | head -1); [[ -n $new && $new != $old ]] && break; done
  echo "old=${old:-none} new=${new:-none}"
  [[ -n ${new:-} && $new != $old ]] ;;
sleepcheck)
  st=$(sysadminctl -screenLock status 2>&1)
  if [[ $st == *"screenLock is off"* ]]; then echo "screen lock off"; exit 0; fi
  echo "${st##*] }"; exit 3 ;;
*)
  echo "usage: recover.sh killdock | sleepcheck" >&2; exit 2 ;;
esac
