# Signing identity (plan T24, risk R2)

Ad hoc signatures (`codesign --sign -`) change on every build, so macOS treats each rebuild
as a new app and forgets permissions such as Accessibility. A stable, self-signed identity
keeps the app's designated requirement the same across rebuilds.

## One-time setup (you run this; no agent or CI does)

```sh
Scripts/make-signing-identity.sh --dry-run   # shows what it would do, changes nothing
Scripts/make-signing-identity.sh             # creates "Dedock Development" in your login keychain
```

It creates a self-signed certificate (code signing only, not a CA, valid 10 years) and its
private key, and imports both into the login keychain, letting `codesign` use the key without
a prompt. Running it again does nothing if the identity already exists.

## Building with it

```sh
export DEDOCK_SIGN_IDENTITY="Dedock Development"
Scripts/make-app.sh
```

`make-app.sh` uses the identity only when it is in the keychain; otherwise it warns and signs
ad hoc, as CI always does. To check that two rebuilds keep the same requirement:

```sh
codesign -d -r- build/Dedock.app    # run after each build; the output should be identical
```

## Removing it

Keychain Access ▸ login ▸ My Certificates ▸ delete "Dedock Development". Builds fall back to
ad hoc signing.
