# FL2601 Cipher Tool

A native macOS app for password-based text encryption: PBKDF2-HMAC-SHA256 key
derivation and AES-256-GCM.

- Bundle ID: `io.github.sevmorris.FL2601`
- Minimum macOS: 15.0
- Signed with Developer ID, hardened runtime, App Sandbox enabled
- No dependencies beyond system frameworks

`cypher.html` is the earlier browser prototype, kept only for reference. It is
**not** interoperable with this app — the app uses a different, versioned
payload format and will reject anything the prototype produced.

## Layout

```
FL2601/                     Xcode project
  FL2601/
    FL2601App.swift         App entry point (single window)
    Services/
      CipherEngine.swift    Format definition, PBKDF2 + AES-GCM
    ViewModels/
      CipherViewModel.swift Observable UI state
    Views/
      ContentView.swift     Screen layout
      Components.swift      Fields, buttons, tabs
      Theme.swift           Palette
  make-icon.swift           Regenerates the app icon set
tools/
  differential-test.sh      Format tests, Swift vs. an independent impl
  viewmodel-test.sh         App logic tests
  reference-impl.mjs        WebCrypto implementation of the same format
build.sh                    Build + sign + verify
notarize.sh                 Submit to Apple and staple
distribute.sh               Build -> DMG -> notarize -> staple
```

## Build

```bash
./build.sh              # Release, Developer ID signed, verified
./build.sh --install    # ...and copy to /Applications
./build.sh --debug      # Ad-hoc signed Debug build, for fast iteration
```

`build.sh` reports the signature authority, whether the hardened runtime and
sandbox made it into the binary, and the Gatekeeper verdict.

## Distribute

One-time setup. **Run this yourself** — it prompts for an app-specific
password, which should not be pasted into a script or shared:

```bash
xcrun notarytool store-credentials "FL2601" --apple-id "YOUR_APPLE_ID" --team-id T9RLNAXPWU
```

Create the app-specific password at <https://account.apple.com> under
*Sign-In and Security → App-Specific Passwords*. It is not your Apple ID
password.

Then:

```bash
./distribute.sh
```

This builds, packages a DMG, signs it, submits it to Apple, waits for the
result, and staples the ticket. Output lands in `dist/`. Use
`./distribute.sh --no-notary` to package without submitting.

Until the app is notarized it runs fine on this Mac but shows a Gatekeeper
warning on other machines.

## Test

```bash
./tools/differential-test.sh   # Format and crypto (needs node)
./tools/viewmodel-test.sh      # Encrypt/decrypt flows, validation, clipboard
```

Both compile the app's real sources rather than copies, so they fail if the
shipping code drifts.

`differential-test.sh` cross-checks `CipherEngine.swift` against
`reference-impl.mjs`, a second implementation of the same format written
against WebCrypto instead of CryptoKit. Two independent libraries agreeing on
every byte is much stronger evidence than one implementation agreeing with
itself — it is how a payload-length off-by-one was caught during development.

## Format

Version 1 payloads are base64 over:

```
offset  size  field
     0     4  magic "FL26"
     4     1  format version
     5     1  KDF identifier (1 = PBKDF2-HMAC-SHA256)
     6     4  KDF iterations, big-endian UInt32
    10    16  salt
    26    12  AES-GCM nonce
    38     n  ciphertext
38 + n    16  AES-GCM authentication tag
```

The design point is that the payload is **self-describing**. The iteration
count travels with each message rather than living in a constant in the code,
so a decryptor reads how the key was derived instead of assuming. Raising the
work factor later therefore cannot strand messages encrypted today: old
payloads keep declaring their own count and keep opening. Adding a
memory-hard KDF later means allocating a new identifier for byte 5, with
existing messages unaffected.

Header bytes `0..<10` are passed to AES-GCM as additional authenticated data,
so the version and iteration count are covered by the tag and cannot be
altered without detection. The salt needs no explicit binding — it determines
the key, so changing it fails authentication on its own.

Parsed iteration counts are bounded to 10,000–10,000,000 **before** key
derivation runs. Derivation necessarily happens before the tag can be checked,
so without that bound a hostile payload could ask the app to grind on four
billion rounds; authentication would reject it eventually, but only after the
app had stopped responding.

## Security notes

- The sandbox grants **no** entitlements beyond `app-sandbox` itself — notably
  no network access, so the app cannot transmit anything even if compromised.
- Nothing is written to disk: no autosave, no preferences, no recent documents.
  Text moves in and out via the clipboard.
- A wrong password and a tampered message fail identically, by design. GCM
  authentication cannot distinguish them, and guessing would only mislead.
- Derived key bytes are zeroed after use. The password itself cannot be wiped:
  Swift's `String` offers no way to reach its storage. This is a partial
  measure, not a guarantee.
- 600,000 PBKDF2 iterations meets OWASP's current floor for SHA-256, and costs
  roughly 70 ms per operation on Apple silicon.

## Icon

```bash
cd FL2601 && swift make-icon.swift FL2601/Assets.xcassets/AppIcon.appiconset
```
