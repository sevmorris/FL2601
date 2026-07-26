# FL2601 Cipher Tool

A small macOS app that encrypts text with a passphrase. Paste in a message,
enter a passphrase, and get back a block of base64 you can send over any
channel — email, chat, a screenshot, a printed page. Paste that base64 back in
with the same passphrase to recover the original.

![The FL2601 Cipher Tool window](docs/screenshot.png)

## Why a native app

Browser-based "encrypt this text" tools ask you to trust that the page you
loaded today is the page you audited yesterday, and that it isn't quietly
sending your plaintext somewhere.

FL2601 runs under the App Sandbox with **no entitlements beyond the sandbox
itself** — in particular, no network access. It cannot open a connection even
if it wanted to; the sandbox forbids it. Nothing is written to disk either: no
preferences, no autosave, no recent-documents list. Text goes in through the
window, and out through the clipboard.

Requires macOS 15.0 or later. Universal — Apple silicon and Intel.

## Install

Download the DMG from the [Releases](../../releases) page, open it, and drag
the app to Applications. Builds are signed with a Developer ID certificate and
notarized by Apple, so they open without a Gatekeeper warning.

To build it yourself instead, see [Building](#building) below.

## Using it

**To encrypt:** enter a passphrase, confirm it in the second field, type or
paste your message, and press *Encrypt Text*. Copy the base64 result and send
it however you like.

**To decrypt:** switch to the *Decrypt* tab, enter the passphrase, paste the
base64, and press *Decrypt Text*. The confirmation field disappears here — a
mistyped passphrase simply fails to decrypt, so there is nothing for a second
field to catch.

| Shortcut | Action |
| --- | --- |
| <kbd>⌘</kbd><kbd>↩</kbd> | Encrypt or decrypt |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd> | Copy the result |
| <kbd>⌘</kbd><kbd>⌫</kbd> | Clear everything |

Base64 pasted back in may contain line breaks or stray whitespace — from an
email client that wrapped it, for example. That is handled.

**There is no passphrase recovery.** The passphrase is never stored anywhere,
by design. If you lose it, the message is gone. That is the point of the tool,
and it applies to you as much as to anyone else.

## How it works

Keys are derived with PBKDF2-HMAC-SHA256 at 600,000 iterations (OWASP's
current floor for SHA-256, about 70 ms per operation on Apple silicon).
Encryption is AES-256-GCM, which authenticates as well as encrypts: a modified
message fails to decrypt rather than decrypting to garbage.

For the full design — the threat model, why the format describes itself, and
the ordering constraint that makes the iteration bound necessary — see
**[Theory of Operation](docs/THEORY-OF-OPERATION.md)**.

A version 1 payload is base64 over:

```
offset  size  field
     0     4  magic "FL26"
     4     1  format version
     5     1  KDF identifier (1 = PBKDF2-HMAC-SHA256)
     6     4  KDF iterations, big-endian uint32
    10    16  salt
    26    12  AES-GCM nonce
    38     n  ciphertext
38 + n    16  AES-GCM authentication tag
```

The payload is **self-describing**: the iteration count travels with each
message rather than living in a constant in the source. A decryptor reads how
the key was derived instead of assuming, so the work factor can be raised in a
future release without stranding messages encrypted today — they keep
declaring their own count, and keep opening. Adding a memory-hard KDF later
means allocating a new identifier for byte 5, with existing messages
unaffected.

Three details worth knowing if you are auditing this:

- **The header is authenticated.** Bytes `0..<10` are passed to AES-GCM as
  additional authenticated data, so the version and iteration count are
  covered by the tag and cannot be altered without detection. The salt needs
  no explicit binding — it determines the key, so changing it fails
  authentication on its own.
- **Iteration counts are bounded before use.** A parsed count outside
  10,000–10,000,000 is rejected *before* key derivation runs. Derivation
  necessarily happens before the tag can be checked, so without that bound a
  hostile payload could ask the app to grind on four billion rounds.
- **Wrong passphrase and tampered message fail identically.** GCM
  authentication cannot distinguish them, and guessing would only mislead.

Derived key bytes are zeroed after use. The passphrase itself cannot be wiped —
Swift's `String` offers no way to reach its storage — so that is a partial
measure, not a guarantee.

## Building

Requires Xcode 26 or later.

```bash
./build.sh              # Release build, signed, verified
./build.sh --install    # ...and copy to /Applications
./build.sh --debug      # Ad-hoc signed Debug build, for fast iteration
```

`build.sh` reports the signing authority, confirms the hardened runtime and
sandbox made it into the binary, and fails the build if the debug
`get-task-allow` entitlement is present, since Apple rejects notarization when
it is.

Signing uses a Developer ID certificate. Without one, `--debug` still produces
a runnable app.

## Tests

```bash
./tools/differential-test.sh   # Format and crypto (requires node)
./tools/viewmodel-test.sh      # Encrypt/decrypt flows, validation, clipboard
```

Both compile the app's real sources rather than copies, so they fail if the
shipping code drifts.

`differential-test.sh` cross-checks `Services/CipherEngine.swift` against
`tools/reference-impl.mjs`, a second implementation of the same format written
against WebCrypto instead of CryptoKit. Two independent crypto libraries
agreeing on every byte is much stronger evidence than one implementation
agreeing with itself — it is how a payload-length off-by-one was caught during
development.

## License

[GPL-3.0](LICENSE). If you distribute a modified version, you must publish
your source under the same terms — for a tool people are asked to trust with
their plaintext, that seems like the right default.
