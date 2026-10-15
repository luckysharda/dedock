#!/usr/bin/env bash
# Regression layer 1 (docs/evaluation.md §5.1): run only the `.regression` unit tests, so a
# failure is reported under its REG id. Usage: ci/regression.sh [swift test args...]
# Convention: regression tests live in suites whose type name ends in `Regression`
# (e.g. `@Suite("Regression", .tags(.regression)) struct EdgeDockRegression`), one @Test per REG id.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp)"
set +e
swift test "$@" --filter Regression 2>&1 | tee "$out"
status=${PIPESTATUS[0]}
set -e
if grep -q "No matching test cases were run" "$out"; then
  if [ "${REGRESSION_REQUIRED:-false}" = "true" ]; then
    echo "::error::No regression tests found (REGRESSION_REQUIRED=true)"; exit 1
  fi
  echo "::notice::No regression tests yet; layer 1 is empty"; exit 0
fi
exit "$status"
