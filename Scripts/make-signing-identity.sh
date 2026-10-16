#!/bin/bash
# Creates the self-signed code-signing identity that Scripts/make-app.sh uses when
# DEDOCK_SIGN_IDENTITY names it (plan T24, risk R2). With a stable identity the app's designated
# requirement stays the same across rebuilds, so an Accessibility grant survives a rebuild.
#
# The USER runs this once, on their own Mac. It writes a private key and a certificate into a
# keychain (default: the login keychain). Nothing here is ever run by CI or an agent.
#
# Usage: Scripts/make-signing-identity.sh [--name NAME] [--keychain PATH] [--days N] [--dry-run]
#   --name      certificate common name (default "Dedock Development")
#   --keychain  keychain to import into (default: the login keychain)
#   --days      validity in days (default 3650)
#   --dry-run   print what would be done; change nothing
# Afterwards: export DEDOCK_SIGN_IDENTITY="Dedock Development" before Scripts/make-app.sh.
# To remove it later: Keychain Access ▸ login ▸ My Certificates ▸ delete "Dedock Development".
set -euo pipefail

NAME="Dedock Development"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
DAYS=3650
DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --name) NAME="${2:?--name needs a value}"; shift 2 ;;
        --keychain) KEYCHAIN="${2:?--keychain needs a value}"; shift 2 ;;
        --days) DAYS="${2:?--days needs a value}"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
    esac
done
case "$DAYS" in ''|*[!0-9]*) echo "--days must be a positive number" >&2; exit 2 ;; esac
case "$NAME" in *[\"\\/+=]*) echo "--name must not contain quotes, slashes, backslashes, + or =" >&2; exit 2 ;; esac

# In a dry run the commands are printed with the throwaway p12 password masked.
run() { if [ "$DRY" = 1 ]; then echo "would run: ${*//$PASS/***}"; else "$@"; fi; }

if [ "$DRY" = 0 ]; then
    [ "$(uname -s)" = Darwin ] || { echo "macOS only" >&2; exit 1; }
    if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "\"$NAME\""; then
        echo "\"$NAME\" already exists in $KEYCHAIN; nothing to do." >&2
        exit 0
    fi
fi

umask 077                      # the key and the p12 are readable by this user only
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
# openssl reads the throwaway p12 password from the environment, not the command line (which
# other local processes can see in `ps`). `security import` has no such option: its -P is
# visible for the moment the import runs; the p12 and its password are deleted right after.
export DEDOCK_P12_PASS="$PASS"

# A code-signing certificate: digitalSignature + codeSigning, not a CA.
run /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning"
run /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout env:DEDOCK_P12_PASS
# -T: codesign is on the key's access list. The first signing may still ask once ("codesign
# wants to access key"); Always Allow ends it. The partition list is left alone on purpose:
# changing it needs the user's login password inside a script.
run /usr/bin/security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign

if [ "$DRY" = 1 ]; then
    echo "dry run: nothing changed. Identity \"$NAME\" would go into $KEYCHAIN."
else
    echo "created \"$NAME\" in $KEYCHAIN"
    echo "next: export DEDOCK_SIGN_IDENTITY=\"$NAME\" and run Scripts/make-app.sh"
fi
