#!/bin/bash
# Build, quit a running copy, then run dedock in the foreground so logs stream here.
# Extra environment (DEDOCK_E2E=1, DEDOCK_E2E_HOME=…, DEDOCK_FRAME_LOG=1) passes through.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/make-app.sh" "${1:-debug}"
pkill -x Dedock 2>/dev/null && sleep 0.5 || true
exec "$ROOT/build/Dedock.app/Contents/MacOS/Dedock"
