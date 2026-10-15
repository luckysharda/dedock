#!/usr/bin/env bash
# Assemble build/Dedock.app via the implementer's Scripts/make-app.sh and zip it for upload.
# Usage: ci/build-app.sh [debug|release] [universal]
set -euo pipefail
cd "$(dirname "$0")/.."
config="${1:-release}"; arch="${2:-native}"
if [ ! -x Scripts/make-app.sh ]; then
  echo "::warning::Scripts/make-app.sh not present yet; skipping app assembly"
  exit 0
fi
CONFIGURATION="$config" ARCH="$arch" Scripts/make-app.sh
test -d build/Dedock.app || { echo "::error::Scripts/make-app.sh did not produce build/Dedock.app"; exit 1; }
codesign --verify --deep --strict build/Dedock.app
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' build/Dedock.app/Contents/Info.plist
ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/Dedock.app/Contents/Info.plist 2>/dev/null || echo 0.0.0)"
ditto -c -k --keepParent build/Dedock.app "build/Dedock-${ver}-${GITHUB_SHA:-local}.zip"
