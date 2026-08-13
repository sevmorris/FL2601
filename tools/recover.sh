#!/usr/bin/env bash
#
# Recovery and diagnosis for FL2601 blocks.
#
#   ./tools/recover.sh inspect <file>
#       Reports the structure of a block. Needs no passphrase and decrypts
#       nothing, so it is safe to run first and safe to share the output.
#
#   ./tools/recover.sh try <file> [output-file]
#       Prompts for a passphrase (never echoed, never placed in the command
#       line) and attempts every format this project has ever produced:
#       the current v1 format, and the legacy layout used by cypher.html and
#       the earliest builds. Writes recovered plaintext to output-file if
#       given, otherwise prints a short preview only.
#
# Formats attempted:
#   v1      FL26 | ver | kdf | iters(4) | salt(16) | nonce(12) | ct | tag(16)
#           key = PBKDF2-SHA256(pw, salt, iters), AAD = first 10 bytes
#   legacy  salt(16) | nonce(12) | ct | tag(16)
#           key = PBKDF2-SHA256(pw, salt, 100000), no AAD
#
# Requires: swiftc
#
set -uo pipefail

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

MODE="${1:-}"
BLOCK="${2:-}"
OUTFILE="${3:-}"

if [ -z "$MODE" ] || [ -z "$BLOCK" ]; then
    sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi
if [ ! -f "$BLOCK" ]; then
    echo "No such file: $BLOCK" >&2
    exit 1
fi

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import CommonCrypto
import CryptoKit
import Foundation

// MARK: - Shared primitives

func derive(_ passphrase: String, salt: Data, iterations: UInt32) -> SymmetricKey? {
    let pw = Array(passphrase.utf8)
    var out = [UInt8](repeating: 0, count: 32)
    let status = pw.withUnsafeBytes { p in
        salt.withUnsafeBytes { s in
            out.withUnsafeMutableBufferPointer { o in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    p.baseAddress?.assumingMemoryBound(to: CChar.self), pw.count,
                    s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                    o.baseAddress, o.count
                )
            }
        }
    }
    return status == kCCSuccess ? SymmetricKey(data: Data(out)) : nil
}

/// Strips a BEGIN/END envelope and any "Name: value" headers, then whitespace.
func payloadBytes(_ text: String) -> Data? {
    var body = text
    if let b = text.range(of: "-----BEGIN FL2601 MESSAGE-----") {
        let after = text[b.upperBound...]
        let inner = after.range(of: "-----END FL2601 MESSAGE-----")
            .map { after[..<$0.lowerBound] } ?? after
        body = inner.split(whereSeparator: \.isNewline)
            .filter { !$0.contains(":") }
            .joined()
    }
    return Data(base64Encoded: body.filter { !$0.isWhitespace })
}

func looksLikeFL2601(_ s: String) -> Bool {
    if s.contains("-----BEGIN FL2601 MESSAGE-----") { return true }
    guard let d = payloadBytes(s), d.count >= 4 else { return false }
    return Array(d[0 ..< 4]) == Array("FL26".utf8)
}

// MARK: - Format attempts

struct Attempt {
    let label: String
    let plaintext: String
}

func tryV1(_ blob: Data, _ passphrase: String) -> Attempt? {
    let b = [UInt8](blob)
    guard b.count >= 54, Array(b[0 ..< 4]) == Array("FL26".utf8) else { return nil }
    let iterations = b[6 ... 9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard iterations >= 1, iterations <= 20_000_000 else { return nil }
    guard let key = derive(passphrase, salt: Data(b[10 ..< 26]), iterations: iterations) else { return nil }
    guard let box = try? AES.GCM.SealedBox(combined: Data(b[26...])),
          let pt = try? AES.GCM.open(box, using: key, authenticating: Data(b[0 ..< 10])),
          let s = String(data: pt, encoding: .utf8)
    else { return nil }
    return Attempt(label: "v1 (\(iterations) iterations, header authenticated)", plaintext: s)
}

func tryLegacy(_ blob: Data, _ passphrase: String, _ iterations: UInt32) -> Attempt? {
    let b = [UInt8](blob)
    guard b.count >= 44 else { return nil }
    guard let key = derive(passphrase, salt: Data(b[0 ..< 16]), iterations: iterations) else { return nil }
    guard let box = try? AES.GCM.SealedBox(combined: Data(b[16...])),
          let pt = try? AES.GCM.open(box, using: key),
          let s = String(data: pt, encoding: .utf8)
    else { return nil }
    return Attempt(label: "legacy cypher.html layout (\(iterations) iterations, no AAD)", plaintext: s)
}

// MARK: - Entry

let args = Array(CommandLine.arguments.dropFirst())
let mode = args[0]
let text = (try? String(contentsOfFile: args[1], encoding: .utf8)) ?? ""

guard let blob = payloadBytes(text) else {
    print("  The file does not decode as base64, even after removing any envelope.")
    print("  It may be truncated, or may not be an encrypted block at all.")
    exit(2)
}

let b = [UInt8](blob)
let armored = text.contains("-----BEGIN FL2601 MESSAGE-----")
let isV1 = b.count >= 4 && Array(b[0 ..< 4]) == Array("FL26".utf8)

if mode == "inspect" {
    print("  envelope           : \(armored ? "present" : "none (bare base64)")")
    print("  decoded size       : \(b.count) bytes")
    if isV1 {
        let iterations = b[6 ... 9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        print("  format             : v1 (magic FL26 present)")
        print("  version byte       : \(b[4])")
        print("  KDF id             : \(b[5])")
        print("  declared iterations: \(iterations)")
        print("  overhead           : 54 bytes")
        print("  => plaintext was   : \(b.count - 54) bytes")
    } else {
        print("  format             : no FL26 magic - legacy layout, or not an FL2601 block")
        print("  overhead if legacy : 44 bytes")
        print("  => plaintext was   : \(max(0, b.count - 44)) bytes (if legacy)")
    }
    print("")
    print("  The plaintext size above is exact and needs no passphrase: it is")
    print("  the block length minus a fixed overhead. If it does not match the")
    print("  message you expected, this block is not that message.")
    exit(0)
}

// mode == "try": passphrase arrives on stdin so it never reaches the argv list.
guard let passphrase = readLine(strippingNewline: true), !passphrase.isEmpty else {
    print("  No passphrase supplied.")
    exit(1)
}

var attempts: [Attempt] = []
if let a = tryV1(blob, passphrase) { attempts.append(a) }
for iterations in [UInt32(100_000), 600_000, 10_000, 250_000] {
    if let a = tryLegacy(blob, passphrase, iterations) { attempts.append(a); break }
}

guard let hit = attempts.first else {
    print("  No format decrypted this block with that passphrase.")
    print("  Authentication failed under every layout, which means either the")
    print("  passphrase is wrong or the block has been altered in transit.")
    exit(3)
}

print("  DECRYPTED under: \(hit.label)")
print("  plaintext length: \(hit.plaintext.count) characters")

if looksLikeFL2601(hit.plaintext) {
    print("")
    print("  NOTE: the recovered text is itself another FL2601 block.")
    print("  This message was encrypted twice. Run this tool again on the")
    print("  recovered output to get to the original text.")
}

if args.count > 2 {
    try? hit.plaintext.write(toFile: args[2], atomically: true, encoding: .utf8)
    print("  written to: \(args[2])")
} else {
    let preview = hit.plaintext.prefix(160)
    print("  preview: \(preview)\(hit.plaintext.count > 160 ? "..." : "")")
    print("")
    print("  Pass an output file as the third argument to save the full text")
    print("  instead of previewing it here.")
}
SWIFT

swiftc -O "$WORK_DIR/main.swift" -o "$WORK_DIR/recover" 2>&1 | head -20 || exit 1

case "$MODE" in
    inspect)
        echo "Inspecting $BLOCK (no passphrase used, nothing decrypted)"
        echo
        "$WORK_DIR/recover" inspect "$BLOCK"
        ;;
    try)
        echo "Attempting every historical format on $BLOCK"
        echo
        printf "Passphrase (not echoed): "
        read -rs PASSPHRASE
        echo
        echo
        printf '%s\n' "$PASSPHRASE" | "$WORK_DIR/recover" try "$BLOCK" ${OUTFILE:+"$OUTFILE"}
        # Capture before unset, whose success would otherwise mask a failed
        # recovery and report exit 0 to anything scripting this.
        status=${PIPESTATUS[1]}
        unset PASSPHRASE
        exit "$status"
        ;;
    *)
        echo "Unknown mode: $MODE (expected 'inspect' or 'try')" >&2
        exit 1
        ;;
esac
