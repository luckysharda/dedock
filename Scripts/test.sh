#!/bin/bash
# Runs `swift test`. With the Command Line Tools toolchain (Swift 6.4) the explicit-module
# dependency scan intermittently omits swift-testing's macro plugin ("plugin for module
# 'TestingMacros' not found"), so the plugin directory is passed explicitly when it exists.
# A retry on that exact error remains as a fallback. Any other failure fails at once.
# Usage: Scripts/test.sh [swift test args…]   Env: DEDOCK_SCRATCH_PATH (default .build)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${DEDOCK_SCRATCH_PATH:-$ROOT/.build}"
LOG="$(mktemp -t dedock-test)"
trap 'rm -f "$LOG"' EXIT
EXTRA=()
CLT_TESTING_PLUGINS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
[ -d "$CLT_TESTING_PLUGINS" ] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$CLT_TESTING_PLUGINS")
for attempt in 1 2 3; do
    swift test --package-path "$ROOT" --scratch-path "$SCRATCH" ${EXTRA[@]+"${EXTRA[@]}"} "$@" 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
    [ "$status" -eq 0 ] && exit 0
    if grep -q "plugin for module 'TestingMacros' not found" "$LOG"; then
        echo "test.sh: TestingMacros plugin race (attempt $attempt), retrying…" >&2
        continue
    fi
    exit "$status"
done
exit "$status"
