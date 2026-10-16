#!/bin/bash
# Builds build/Dedock.app from the SwiftPM `Dedock` product (architecture.md §5).
# Usage: Scripts/make-app.sh [debug|release]
# Env:   CONFIGURATION         debug|release, used when no argument is given (CI)
#        ARCH                  native (default) | universal (arm64 + x86_64) | arm64 | x86_64
#        DEDOCK_SIGN_IDENTITY  codesign identity name, e.g. "Dedock Development" (made once by
#                              Scripts/make-signing-identity.sh). Used only when it is in the
#                              keychain; otherwise ad hoc ("-"). CI leaves it unset (ad hoc).
#        DEDOCK_SCRATCH_PATH   SwiftPM scratch dir (default .build); use your own when several
#                              sessions build the same worktree.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-${CONFIGURATION:-debug}}"
CONFIG="$(echo "$CONFIG" | tr '[:upper:]' '[:lower:]')"
ARCH="${ARCH:-native}"
case "$CONFIG" in debug|release) ;; *) echo "usage: $0 [debug|release]" >&2; exit 2 ;; esac

SCRATCH="${DEDOCK_SCRATCH_PATH:-$ROOT/.build}"
if [ "$CONFIG" = debug ]; then BUNDLE_ID="app.dedock.Dedock.debug"; else BUNDLE_ID="app.dedock.Dedock"; fi

ARCH_ARGS=()
case "$ARCH" in
    native) ;;
    universal) ARCH_ARGS=(--arch arm64 --arch x86_64) ;;
    arm64|x86_64) ARCH_ARGS=(--arch "$ARCH") ;;
    *) echo "unknown ARCH=$ARCH" >&2; exit 2 ;;
esac
BUILD=(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c "$CONFIG" ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"})
"${BUILD[@]}" --product Dedock
BIN_DIR="$("${BUILD[@]}" --show-bin-path)"

APP="$ROOT/build/Dedock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Dedock" "$APP/Contents/MacOS/Dedock"

VERSION="$(git -C "$ROOT" describe --tags --always --dirty 2>/dev/null || echo 0.0.0)"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT="$(echo "$VERSION" | sed -E 's/^v//; s/-dirty$//')"
case "$SHORT" in [0-9]*.[0-9]*) ;; *) SHORT="0.1.0" ;; esac
sed -e "s/__BUNDLE_ID__/$BUNDLE_ID/" -e "s/__VERSION__/$SHORT/" -e "s/__BUILD__/$BUILD/" \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"

# Resource bundles, once any target declares resources.
for b in "$BIN_DIR"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

# A stable identity keeps the designated requirement the same across rebuilds, so TCC grants
# (Accessibility) survive a rebuild (R2). Ad hoc signatures change with every build.
IDENTITY="-"
if [ -n "${DEDOCK_SIGN_IDENTITY:-}" ] && [ "$DEDOCK_SIGN_IDENTITY" != "-" ]; then
    # Without -v: a self-signed identity is "not trusted" but still signs.
    if security find-identity -p codesigning 2>/dev/null | grep -qF "\"$DEDOCK_SIGN_IDENTITY\""; then
        IDENTITY="$DEDOCK_SIGN_IDENTITY"
    else
        echo "warning: identity \"$DEDOCK_SIGN_IDENTITY\" not in the keychain; signing ad hoc" >&2
    fi
fi
SIGN_ARGS=(--force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none)
# Debug only: get-task-allow so `leaks`/`vmmap` can inspect the app. Release never gets it.
[ "$CONFIG" = debug ] && SIGN_ARGS+=(--entitlements "$ROOT/Support/Debug.entitlements")
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP ($BUNDLE_ID $SHORT, $CONFIG, $ARCH: $(lipo -archs "$APP/Contents/MacOS/Dedock"), signed: $IDENTITY)"
