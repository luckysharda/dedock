#!/usr/bin/env bash
# Developer ID signing + notarization + DMG. Without secrets it produces an unsigned
# (ad-hoc) zip and says so; nothing fails, so staging builds work before an Apple account exists.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/dist
app=build/Dedock.app
[ -d "$app" ] || { echo "::error::$app missing"; exit 1; }
if [ -z "${DEVELOPER_ID_P12_BASE64:-}" ]; then
  echo "::warning::No Developer ID secrets: shipping an ad-hoc signed zip (not notarized)"
  ditto -c -k --keepParent "$app" build/dist/Dedock-unsigned.zip
  exit 0
fi
kc="$RUNNER_TEMP/dedock.keychain-db"; kcpw="$(uuidgen)"
security create-keychain -p "$kcpw" "$kc"
security set-keychain-settings -lut 21600 "$kc"
security unlock-keychain -p "$kcpw" "$kc"
echo "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/id.p12"
security import "$RUNNER_TEMP/id.p12" -k "$kc" -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$kcpw" "$kc"
security list-keychains -d user -s "$kc" $(security list-keychains -d user | tr -d '"')
ent_args=()
for ent in Sources/Dedock/Dedock.entitlements Scripts/Dedock.entitlements; do
  [ -f "$ent" ] && { ent_args=(--entitlements "$ent"); break; }
done
codesign --force --deep --options runtime --timestamp ${ent_args[@]+"${ent_args[@]}"} --sign "$DEVELOPER_ID_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
dmg=build/dist/Dedock.dmg
hdiutil create -volname dedock -srcfolder "$app" -ov -format UDZO "$dmg"
codesign --force --timestamp --sign "$DEVELOPER_ID_IDENTITY" "$dmg"
xcrun notarytool submit "$dmg" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
  --password "$NOTARY_APP_PASSWORD" --wait
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
