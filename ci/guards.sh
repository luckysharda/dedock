#!/usr/bin/env bash
# Repo guards that need no toolchain. Spec: docs/ci-cd.md §2.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
# 1. Notchy is out of scope: no code, assets or bundle ids.
if git ls-files | grep -i notchy; then echo "::error::Notchy-related file tracked"; fail=1; fi
if [ -d Sources ] && grep -rIl -i 'notchy' Sources Tests 2>/dev/null; then echo "::error::Notchy reference in code"; fail=1; fi
# 2. Worktrees and build products never get committed.
if git ls-files | grep -E '^(\.worktrees|\.build|build)/'; then echo "::error::worktree/build output tracked"; fail=1; fi
# 3. No large binaries (>5 MB).
while IFS= read -r f; do
  [ -f "$f" ] && [ "$(wc -c <"$f")" -gt 5242880 ] && { echo "::error::$f is larger than 5 MB"; fail=1; }
done < <(git ls-files)
# 4. Module dependency rules (architecture.md D4/D5/D8), once the implementer adds the checker.
if [ -x Scripts/check-deps.sh ]; then Scripts/check-deps.sh || fail=1; fi
# 5. Clean-room string guard: DockDoor UI strings must not appear verbatim (plan.md R9).
#    The list lives outside the repo; CI uses the copy in ci/clean-room-strings.txt when present.
if [ -f ci/clean-room-strings.txt ] && [ -d Sources ]; then
  if grep -rIF -f ci/clean-room-strings.txt Sources; then echo "::error::reference UI string copied verbatim"; fail=1; fi
fi
exit "$fail"
