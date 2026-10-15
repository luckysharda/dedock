#!/bin/bash
# Runs `swift test`, retrying up to 3 times ONLY when the Command Line Tools toolchain fails to
# load swift-testing's macro plugin ("plugin for module 'TestingMacros' not found"), an
# intermittent build-system race seen with Swift 6.4 CLT. Any other failure fails at once.
# Usage: Scripts/test.sh [swift test args…]   Env: DEDOCK_SCRATCH_PATH (default .build)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRATCH="${DEDOCK_SCRATCH_PATH:-$ROOT/.build}"
LOG="$(mktemp -t dedock-test)"
trap 'rm -f "$LOG"' EXIT
for attempt in 1 2 3; do
    swift test --package-path "$ROOT" --scratch-path "$SCRATCH" "$@" 2>&1 | tee "$LOG"
    status=${PIPESTATUS[0]}
    [ "$status" -eq 0 ] && exit 0
    if grep -q "plugin for module 'TestingMacros' not found" "$LOG"; then
        echo "test.sh: TestingMacros plugin race (attempt $attempt), retrying…" >&2
        continue
    fi
    exit "$status"
done
exit "$status"
