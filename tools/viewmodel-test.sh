#!/usr/bin/env bash
#
# Exercises the app's real CipherViewModel + CipherEngine sources headlessly:
# validation, encrypt/decrypt flows, mode switching, error handling, clipboard,
# and clear. These are the exact state transitions ContentView binds to.
#
# Requires: swiftc
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$ROOT_DIR/FL2601/FL2601"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import AppKit
import Foundation

var pass = 0
var fail = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if condition {
        print("  PASS  \(name)")
        pass += 1
    } else {
        print("  FAIL  \(name) \(detail())")
        fail += 1
    }
}

@MainActor
func run() async {
    let vm = CipherViewModel()

    print("== Initial state ==")
    check("starts in encrypt mode", vm.mode == .encrypt)
    check("submit disabled while empty", !vm.canSubmit)
    check("no result shown", !vm.showResult)
    check("status idle", vm.status == .idle)

    print("\n== Validation ==")
    vm.passphrase = ""
    vm.inputText = "something"
    check("submit disabled without passphrase", !vm.canSubmit)
    await vm.process()
    check("passphrase required error", vm.status == .failed("Passphrase required."), "got \(vm.status)")

    vm.passphrase = "pw"
    vm.confirmPassphrase = "pw"
    vm.inputText = ""
    check("submit disabled without input", !vm.canSubmit)
    await vm.process()
    check("input required error", vm.status == .failed("Input text required."), "got \(vm.status)")

    print("\n== Passphrase confirmation (encrypt only) ==")
    vm.clearAll()
    vm.inputText = "secret plans"
    check("confirmation required in encrypt mode", vm.requiresConfirmation)
    check("indicator pending while confirm empty", vm.confirmation == .pending)

    vm.passphrase = "s3cret"
    check("still pending with only passphrase typed", vm.confirmation == .pending)
    check("submit blocked until confirmed", !vm.canSubmit)

    vm.confirmPassphrase = "s3cr"
    check("partial entry reads as mismatch", vm.confirmation == .mismatch)
    check("submit blocked on mismatch", !vm.canSubmit)
    await vm.process()
    check("mismatch error", vm.status == .failed("Passphrases do not match."), "got \(vm.status)")
    check("nothing encrypted on mismatch", !vm.showResult)

    vm.confirmPassphrase = "s3cret"
    check("indicator reports match", vm.confirmation == .match)
    check("submit enabled once matched", vm.canSubmit)

    print("\n== Encrypt flow ==")
    vm.passphrase = "s3cret"
    vm.confirmPassphrase = "s3cret"
    vm.inputText = "Attack at dawn — 🌅"
    check("submit enabled when both filled", vm.canSubmit)
    await vm.process()
    check("status ok", vm.status == .ok("Encryption successful."), "got \(vm.status)")
    check("result shown", vm.showResult)
    check("not left processing", !vm.isProcessing)
    let ciphertext = vm.result

    print("\n== Armored output ==")
    check("opens with the begin marker", ciphertext.hasPrefix(MessageArmor.beginMarker))
    check("closes with the end marker", ciphertext.hasSuffix(MessageArmor.endMarker))
    check("names the tool", ciphertext.contains("Encrypted with FL2601 Cipher Tool"))
    check("carries a link", ciphertext.contains("github.com/sevmorris/FL2601"))
    let payload = MessageArmor.unwrap(ciphertext)
    check("payload is valid base64", Data(base64Encoded: payload) != nil && !payload.isEmpty)
    check("payload is the raw format, not the envelope", !payload.contains("-----"))
    // Every line of the block must survive a mail client that balks at long lines.
    let longest = ciphertext.split(whereSeparator: \.isNewline).map(\.count).max() ?? 0
    check("no line exceeds 64 characters", longest <= 64, "longest was \(longest)")

    print("\n== Armor is a display convention, not the format ==")
    check("unwrap of bare base64 is a no-op", MessageArmor.unwrap(payload) == payload)
    check("wrap then unwrap round-trips", MessageArmor.unwrap(MessageArmor.wrap(payload)) == payload)

    print("\n== Payload readout ==")
    guard let info = vm.payloadInfo else {
        print("  FAIL  payloadInfo populated after encrypt"); fail += 1; return
    }
    check("magic version reported", info.version == 1)
    check("kdf reported", info.kdf == .pbkdf2HMACSHA256)
    check("iterations reported", info.iterations == CipherFormat.defaultIterations, "got \(info.iterations)")
    check("total matches the payload", info.totalBytes == Data(base64Encoded: payload)?.count)
    // GCM does not pad, so ciphertext length is the plaintext length exactly.
    check("plaintext size is exact",
          info.plaintextBytes == "Attack at dawn — 🌅".utf8.count,
          "got \(info.plaintextBytes) want \("Attack at dawn — 🌅".utf8.count)")
    check("overhead is the fixed 54 bytes",
          info.totalBytes - info.ciphertextBytes == CipherFormat.minimumPayloadLength)
    check("inspect needs no passphrase",
          (try? CipherEngine.inspect(ciphertext))?.totalBytes == info.totalBytes)
    check("inspect reads an armored block and a bare one alike",
          (try? CipherEngine.inspect(payload))?.totalBytes == info.totalBytes)

    print("\n== Input counters ==")
    check("character count", vm.inputCharacterCount == "Attack at dawn — 🌅".count)
    check("byte count differs from characters under unicode",
          vm.inputByteCount > vm.inputCharacterCount)
    check("working text names the real parameters",
          vm.workingDescription.contains("600,000") && vm.workingDescription.contains("PBKDF2"))

    print("\n== Mode switch ==")
    vm.mode = .decrypt
    check("payload readout cleared on switch", vm.payloadInfo == nil)
    check("output hidden after switch", !vm.showResult)
    check("status reset after switch", vm.status == .idle)
    check("labels follow mode", vm.mode.inputLabel == "Ciphertext (Base64)")
    check("action title follows mode", vm.mode.actionTitle == "Decrypt Text")
    check("no confirmation when decrypting", !vm.requiresConfirmation)
    check("confirmation value discarded", vm.confirmPassphrase.isEmpty)
    check("indicator hidden", vm.confirmation == .notShown)

    print("\n== Decrypt flow ==")
    vm.passphrase = "s3cret"
    vm.inputText = ciphertext
    check("decrypt submits without a confirmation", vm.canSubmit)
    await vm.process()
    check("status ok", vm.status == .ok("Decryption successful."), "got \(vm.status)")
    check("round-trips the plaintext", vm.result == "Attack at dawn — 🌅", "got \(vm.result)")

    // Anything encrypted before the envelope existed is bare base64 and must
    // keep opening.
    vm.inputText = payload
    await vm.process()
    check("bare base64 still decrypts", vm.result == "Attack at dawn — 🌅", "got \(vm.result)")

    // A block that has been forwarded, indented, or partially reflowed.
    vm.inputText = "  \n" + ciphertext.replacingOccurrences(of: "\n", with: "\n  ") + "\n\n"
    await vm.process()
    check("indented block still decrypts", vm.result == "Attack at dawn — 🌅", "got \(vm.result)")

    print("\n== Wrong passphrase ==")
    vm.passphrase = "wrong"
    vm.inputText = ciphertext
    await vm.process()
    check("status failed", vm.status == .failed("Decryption failed. Check passphrase and ciphertext."), "got \(vm.status)")
    check("result hidden on failure", !vm.showResult)
    check("stale result cleared", vm.result.isEmpty)
    check("stale payload readout cleared", vm.payloadInfo == nil)

    print("\n== Passphrase strength ==")
    check("nothing to report on an empty passphrase", PassphraseStrength.estimate("") == nil)
    check("short and single-class reads weak", PassphraseStrength.estimate("abc")?.band == .weak)
    check("longer and mixed beats shorter and mixed",
          PassphraseStrength.entropyBits("Tr0ub4dor&3xyz") > PassphraseStrength.entropyBits("Tr0ub4"))
    check("repetition earns less than novelty",
          PassphraseStrength.entropyBits("aaaaaaaaaaaaaaaa") < PassphraseStrength.entropyBits("qwfpgjluyarstd;x"))
    check("a long diverse passphrase reaches the top band",
          PassphraseStrength.estimate("correct-horse-Battery-staple-9x!")?.band == .veryStrong)
    check("meter fraction stays within bounds",
          (PassphraseStrength.estimate("x")?.fraction ?? 0) >= 0
          && (PassphraseStrength.estimate(String(repeating: "Aa1!", count: 40))?.fraction ?? 0) <= 1)
    // Rated only while encrypting; when decrypting the passphrase already exists.
    vm.mode = .encrypt
    vm.passphrase = "abc"
    check("rated in encrypt mode", vm.passphraseStrength != nil)
    vm.mode = .decrypt
    vm.passphrase = "abc"
    check("not rated in decrypt mode", vm.passphraseStrength == nil)

    print("\n== Copy to clipboard ==")
    vm.passphrase = "s3cret"
    vm.inputText = ciphertext
    await vm.process()
    vm.copyResult()
    check("copy flag set", vm.didJustCopy)
    let pasteboard = NSPasteboard.general.string(forType: .string)
    check("pasteboard matches result", pasteboard == vm.result, "got \(pasteboard ?? "nil")")

    print("\n== Clear ==")
    vm.mode = .encrypt
    vm.passphrase = "s3cret"
    vm.confirmPassphrase = "s3cret"
    vm.clearAll()
    check("passphrase cleared", vm.passphrase.isEmpty)
    check("confirmation cleared", vm.confirmPassphrase.isEmpty)
    check("input cleared", vm.inputText.isEmpty)
    check("result cleared", vm.result.isEmpty)
    check("payload readout cleared", vm.payloadInfo == nil)
    check("output hidden", !vm.showResult)
    check("status idle", vm.status == .idle)
    check("submit disabled again", !vm.canSubmit)
}

await run()

print("\npassed=\(pass) failed=\(fail)")
exit(fail == 0 ? 0 : 1)
SWIFT

echo "Compiling CipherEngine + CipherViewModel..."
swiftc -O \
    "$SRC/Services/MessageArmor.swift" \
    "$SRC/Services/PassphraseStrength.swift" \
    "$SRC/Services/CipherEngine.swift" \
    "$SRC/ViewModels/CipherViewModel.swift" \
    "$WORK_DIR/main.swift" \
    -o "$WORK_DIR/vmtest" || exit 1

echo
"$WORK_DIR/vmtest"
