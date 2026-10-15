#!/bin/bash
# Architecture rule checks (docs/architecture.md §3) that Package.swift alone cannot enforce:
#   D4  DedockCore imports Foundation / CoreGraphics only (no AppKit, SwiftUI, os).
#   D5  Sources/EdgeDock/Logic imports Foundation / CoreGraphics / DedockCore only.
#   D8  No private API or network in v0: no dlopen/dlsym, SkyLight, CoreDock, URLSession, NWConnection.
# Run by CI's guards job; exits non-zero with one line per violation. A checked directory that
# is missing (e.g. after a rename) is itself a failure, so the check never passes vacuously.
# CHECK_DEPS_ROOT points it at another tree (its self-test, REG-060).
set -uo pipefail
ROOT="${CHECK_DEPS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 2
fail=0

check_imports() { # <dir> <allowed regex> <rule>
    if [ ! -d "$1" ]; then echo "$3: $1 missing"; fail=1; return; fi
    while IFS= read -r line; do
        # `import struct Foundation.URL` imports from module Foundation.
        file="${line%%:*}"; mod="$(echo "${line#*:}" | sed -E 's/^[[:space:]]*(@[a-zA-Z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|let|var|func)[[:space:]]+)?([A-Za-z_]+).*/\4/')"
        if ! [[ "$mod" =~ $2 ]]; then echo "$3: $file imports $mod"; fail=1; fi
    done < <(grep -rEn --include='*.swift' '^[[:space:]]*(@[a-zA-Z_]+[[:space:]]+)*import[[:space:]]' "$1" | sed -E 's/:[0-9]+:/:/')
}

check_imports Sources/DedockCore '^(Foundation|CoreGraphics)$' D4
check_imports Sources/EdgeDock/Logic '^(Foundation|CoreGraphics|DedockCore)$' D5

if [ ! -d Sources ]; then echo "D8: Sources missing"; fail=1
elif grep -rEn --include='*.swift' '\b(dlopen|dlsym|SkyLight|CoreDock|CGS[A-Z][A-Za-z]+|URLSession|NWConnection)\b' Sources; then
    echo "D8: private API or network use above (none allowed in v0)"; fail=1
fi

[ "$fail" -eq 0 ] && echo "check-deps: D4, D5, D8 OK"
exit "$fail"
