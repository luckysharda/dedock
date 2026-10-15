#!/bin/bash
# Architecture rule checks (docs/architecture.md §3) that Package.swift alone cannot enforce:
#   D4  DedockCore imports Foundation / CoreGraphics only (no AppKit, SwiftUI, os).
#   D5  Sources/EdgeDock/Logic imports Foundation / CoreGraphics / DedockCore only.
#   D8  No private API or network in v0: no dlopen/dlsym, SkyLight, CoreDock, URLSession, NWConnection.
# Run by CI's guards job; exits non-zero with one line per violation.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
fail=0

check_imports() { # <dir> <allowed regex> <rule>
    while IFS= read -r line; do
        file="${line%%:*}"; mod="$(echo "${line#*:}" | sed -E 's/^[[:space:]]*(@[a-zA-Z_]+[[:space:]]+)*import[[:space:]]+([A-Za-z_]+).*/\2/')"
        if ! [[ "$mod" =~ $2 ]]; then echo "$3: $file imports $mod"; fail=1; fi
    done < <(grep -rEn --include='*.swift' '^[[:space:]]*(@[a-zA-Z_]+[[:space:]]+)*import[[:space:]]' "$1" | sed -E 's/:[0-9]+:/:/')
}

check_imports Sources/DedockCore '^(Foundation|CoreGraphics)$' D4
check_imports Sources/EdgeDock/Logic '^(Foundation|CoreGraphics|DedockCore)$' D5

if grep -rEn --include='*.swift' '\b(dlopen|dlsym|SkyLight|CoreDock|CGS[A-Z][A-Za-z]+|URLSession|NWConnection)\b' Sources; then
    echo "D8: private API or network use above (none allowed in v0)"; fail=1
fi

[ "$fail" -eq 0 ] && echo "check-deps: D4, D5, D8 OK"
exit "$fail"
