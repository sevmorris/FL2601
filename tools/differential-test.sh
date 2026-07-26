#!/usr/bin/env bash
#
# Differential tests for the FL2601 v1 format.
#
# Compiles the app's real Services/CipherEngine.swift and cross-checks it
# against tools/reference-impl.mjs, an independent WebCrypto implementation.
# Two libraries agreeing on every byte is far stronger evidence than one
# implementation agreeing with itself.
#
# Requires: swiftc, node
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENGINE_SRC="$ROOT_DIR/FL2601/FL2601/Services/CipherEngine.swift"
ARMOR_SRC="$ROOT_DIR/FL2601/FL2601/Services/MessageArmor.swift"
REFERENCE="$SCRIPT_DIR/reference-impl.mjs"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

command -v node >/dev/null 2>&1 || { echo "node is required." >&2; exit 1; }

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import Foundation

let engine = CipherEngine()
let args = Array(CommandLine.arguments.dropFirst())

do {
    switch args[0] {
    case "encrypt":
        if args.count > 3, let iterations = UInt32(args[3]) {
            print(try await engine.encrypt(args[2], password: args[1], iterations: iterations))
        } else {
            print(try await engine.encrypt(args[2], password: args[1]))
        }
    case "decrypt":
        print(try await engine.decrypt(args[2], password: args[1]))
    default:
        fatalError("unknown mode")
    }
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write("ERROR: \(message)\n".data(using: .utf8)!)
    exit(1)
}
SWIFT

echo "Compiling CipherEngine..."
swiftc -O "$ARMOR_SRC" "$ENGINE_SRC" "$WORK_DIR/main.swift" -o "$WORK_DIR/engine" || exit 1

E="$WORK_DIR/engine"
JS=(node "$REFERENCE")
DECRYPT_ERR='ERROR: Decryption failed. Check password and ciphertext.'
MALFORMED_ERR='ERROR: This does not look like an FL2601 message.'

pass=0
fail=0

check() { # name expected actual
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1"
        pass=$((pass + 1))
    else
        echo "  FAIL  $1"
        echo "        expected: $2"
        echo "        actual:   $3"
        fail=$((fail + 1))
    fi
}

# Rewrites one byte of a base64 payload and re-encodes it.
patch_byte() { # base64 offset newvalue
    node -e '
        const [b64, off, val] = process.argv.slice(1);
        const b = Buffer.from(b64, "base64");
        b[Number(off)] = Number(val);
        process.stdout.write(b.toString("base64"));
    ' "$1" "$2" "$3"
}

field() { # base64 -> prints "magic version kdf iterations"
    # shellcheck disable=SC2016  # ${...} here is a JS template literal, not shell
    node -e '
        const b = Buffer.from(process.argv[1], "base64");
        const magic = b.subarray(0, 4).toString("latin1");
        const iterations = b.readUInt32BE(6);
        process.stdout.write(`${magic} ${b[4]} ${b[5]} ${iterations}`);
    ' "$1"
}

echo
echo "== Cross-implementation agreement =="
JS_CT=$("${JS[@]}" encrypt 'correct horse battery staple' 'unicode ok: café 日本語 🔐')
check "WebCrypto -> Swift" \
    'unicode ok: café 日本語 🔐' \
    "$($E decrypt 'correct horse battery staple' "$JS_CT")"

SWIFT_CT=$($E encrypt 'p@ss w/ spaces & ünïcode' 'Round trip to the other implementation.')
check "Swift -> WebCrypto" \
    'Round trip to the other implementation.' \
    "$("${JS[@]}" decrypt 'p@ss w/ spaces & ünïcode' "$SWIFT_CT")"

CT=$($E encrypt 'hunter2' 'self round trip')
check "Swift -> Swift" 'self round trip' "$($E decrypt 'hunter2' "$CT")"

echo
echo "== Header is well-formed =="
check "Swift header fields"    'FL26 1 1 600000' "$(field "$CT")"
check "WebCrypto header fields" 'FL26 1 1 600000' "$(field "$JS_CT")"

echo
echo "== The point of the format: work factor travels with the message =="
# Encrypt at a deliberately low count, then decrypt with an engine whose
# default is 600000. This only works because the count is read from the
# payload rather than assumed - the exact failure that made raising the work
# factor unsafe in the previous format.
LEGACY=$($E encrypt 'hunter2' 'encrypted at a lower work factor' 10000)
check "declares the count it used" 'FL26 1 1 10000' "$(field "$LEGACY")"
check "decrypts without being told" 'encrypted at a lower work factor' "$($E decrypt 'hunter2' "$LEGACY")"
check "and the other implementation agrees" \
    'encrypted at a lower work factor' \
    "$("${JS[@]}" decrypt 'hunter2' "$LEGACY")"

HIGH=$($E encrypt 'hunter2' 'encrypted at a higher work factor' 900000)
check "higher count also round-trips" 'encrypted at a higher work factor' "$($E decrypt 'hunter2' "$HIGH")"

echo
echo "== Header is authenticated (AAD) =="
# Byte 9 is the low byte of the iteration count. Changing it must fail the tag
# check, not merely derive a different key.
ORIG_LOW=$(node -e 'process.stdout.write(String(Buffer.from(process.argv[1],"base64")[9]))' "$CT")
NEW_LOW=$(( (ORIG_LOW + 1) % 256 ))
check "tampered iteration count rejected" \
    "$DECRYPT_ERR" \
    "$($E decrypt 'hunter2' "$(patch_byte "$CT" 9 "$NEW_LOW")" 2>&1 >/dev/null)"

echo
echo "== Malformed input is rejected specifically =="
check "wrong magic"    "$MALFORMED_ERR" "$($E decrypt 'hunter2' "$(patch_byte "$CT" 0 88)" 2>&1 >/dev/null)"
check "short payload"  "$MALFORMED_ERR" "$($E decrypt 'hunter2' 'AAAA' 2>&1 >/dev/null)"
check "not base64"     "$MALFORMED_ERR" "$($E decrypt 'hunter2' 'not base64!!' 2>&1 >/dev/null)"
check "future version" \
    'ERROR: Message uses format version 2; this app supports version 1.' \
    "$($E decrypt 'hunter2' "$(patch_byte "$CT" 4 2)" 2>&1 >/dev/null)"
check "unknown KDF" \
    'ERROR: Message uses an unknown key derivation function (id 9).' \
    "$($E decrypt 'hunter2' "$(patch_byte "$CT" 5 9)" 2>&1 >/dev/null)"

# A hostile payload must not be able to make the app grind on a huge count.
# Byte 6 is the high byte of the iteration count; 0xFF makes it ~4.2 billion.
HUGE=$(patch_byte "$CT" 6 255)
START=$(date +%s)
HUGE_OUT=$($E decrypt 'hunter2' "$HUGE" 2>&1 >/dev/null)
ELAPSED=$(( $(date +%s) - START ))
check "implausible iteration count rejected" \
    'ERROR: Message declares 4278790080 iterations, outside the accepted range.' \
    "$HUGE_OUT"
if [ "$ELAPSED" -le 2 ]; then
    echo "  PASS  rejected before deriving (${ELAPSED}s)"
    pass=$((pass + 1))
else
    echo "  FAIL  took ${ELAPSED}s - bound is being checked too late"
    fail=$((fail + 1))
fi

echo
echo "== Authentication failures =="
check "wrong password"      "$DECRYPT_ERR" "$($E decrypt 'nope' "$CT" 2>&1 >/dev/null)"
if [ "${CT: -2:1}" = "A" ]; then FLIP="B"; else FLIP="A"; fi
check "tampered ciphertext" "$DECRYPT_ERR" "$($E decrypt 'hunter2' "${CT:0:${#CT}-2}$FLIP${CT: -1}" 2>&1 >/dev/null)"

echo
echo "== Edge cases =="
check "base64 wrapped in newlines" 'self round trip' "$($E decrypt 'hunter2' "$(echo "$CT" | fold -w 20)")"

EMPTY_CT=$($E encrypt 'k' '')
if EMPTY_OUT=$($E decrypt 'k' "$EMPTY_CT" 2>/dev/null) && [ -z "$EMPTY_OUT" ]; then
    echo "  PASS  empty plaintext"
    pass=$((pass + 1))
else
    echo "  FAIL  empty plaintext"
    fail=$((fail + 1))
fi
check "empty plaintext cross-checked" '' "$("${JS[@]}" decrypt 'k' "$EMPTY_CT")"

BIG=$(head -c 20000 /dev/urandom | base64 | tr -d '\n')
check "27KB payload" "$BIG" "$($E decrypt 'k' "$($E encrypt 'k' "$BIG")")"

A=$($E encrypt 'k' 'same input')
B=$($E encrypt 'k' 'same input')
if [ "$A" != "$B" ]; then
    echo "  PASS  salt and nonce randomized per call"
    pass=$((pass + 1))
else
    echo "  FAIL  salt and nonce randomized per call - identical ciphertexts"
    fail=$((fail + 1))
fi

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
