#!/usr/bin/env bash
# Print and check the CI toolchain. CI deliberately builds with the runner's Swift (6.2.x),
# the minimum dedock supports, so code that needs a newer compiler fails here.
set -euo pipefail
sw_vers
xcodebuild -version || true
swift --version
need="$(sed -n 's#^// swift-tools-version: *\([0-9.]*\).*#\1#p' Package.swift)"
have="$(swift --version 2>&1 | sed -n 's/.*Swift version \([0-9]*\.[0-9]*\).*/\1/p' | head -1)"
echo "Package tools-version: $need, compiler: $have"
if [ "$(printf '%s\n%s\n' "$need" "$have" | sort -V | head -1)" != "$need" ]; then
  echo "::error::Swift $have is older than swift-tools-version $need"
  exit 1
fi
