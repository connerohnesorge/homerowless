# Stable dev signing identity (fixes TCC losing Accessibility on every rebuild)

TCC keys the Accessibility grant to bundle id + code-signing designated requirement.
Ad-hoc signing (`codesign -s -`) makes that requirement a `cdhash`, which changes every
build, so the app looks granted in System Settings while `AXIsProcessTrusted()` is false.

Create a self-signed Code Signing certificate once:

1. Keychain Access → Keychain Access menu → Certificate Assistant → Create a Certificate…
2. Name: `HomerowlessDev`
3. Identity Type: Self Signed Root
4. Certificate Type: Code Signing
5. Create. It lands in the login keychain.

Verify: `security find-identity -v -p codesigning | grep HomerowlessDev`

Then build with:

```sh
CODESIGN_IDENTITY=HomerowlessDev scripts/build-app.sh
```

Or from the CLI without Keychain Access:

```sh
scripts/make-signing-cert.sh
```

Releases are ad-hoc signed; end users never rebuild, so the cdhash is stable for them.
