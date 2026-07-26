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
    vm.password = ""
    vm.inputText = "something"
    check("submit disabled without password", !vm.canSubmit)
    await vm.process()
    check("password required error", vm.status == .failed("Password required."), "got \(vm.status)")

    vm.password = "pw"
    vm.confirmPassword = "pw"
    vm.inputText = ""
    check("submit disabled without input", !vm.canSubmit)
    await vm.process()
    check("input required error", vm.status == .failed("Input text required."), "got \(vm.status)")

    print("\n== Password confirmation (encrypt only) ==")
    vm.clearAll()
    vm.inputText = "secret plans"
    check("confirmation required in encrypt mode", vm.requiresConfirmation)
    check("indicator pending while confirm empty", vm.confirmation == .pending)

    vm.password = "s3cret"
    check("still pending with only password typed", vm.confirmation == .pending)
    check("submit blocked until confirmed", !vm.canSubmit)

    vm.confirmPassword = "s3cr"
    check("partial entry reads as mismatch", vm.confirmation == .mismatch)
    check("submit blocked on mismatch", !vm.canSubmit)
    await vm.process()
    check("mismatch error", vm.status == .failed("Passwords do not match."), "got \(vm.status)")
    check("nothing encrypted on mismatch", !vm.showResult)

    vm.confirmPassword = "s3cret"
    check("indicator reports match", vm.confirmation == .match)
    check("submit enabled once matched", vm.canSubmit)

    print("\n== Encrypt flow ==")
    vm.password = "s3cret"
    vm.confirmPassword = "s3cret"
    vm.inputText = "Attack at dawn — 🌅"
    check("submit enabled when both filled", vm.canSubmit)
    await vm.process()
    check("status ok", vm.status == .ok("Encryption successful."), "got \(vm.status)")
    check("result shown", vm.showResult)
    check("result is non-empty base64", Data(base64Encoded: vm.result) != nil && !vm.result.isEmpty)
    check("not left processing", !vm.isProcessing)
    let ciphertext = vm.result

    print("\n== Mode switch ==")
    vm.mode = .decrypt
    check("output hidden after switch", !vm.showResult)
    check("status reset after switch", vm.status == .idle)
    check("labels follow mode", vm.mode.inputLabel == "Ciphertext (Base64)")
    check("action title follows mode", vm.mode.actionTitle == "Decrypt Text")
    check("no confirmation when decrypting", !vm.requiresConfirmation)
    check("confirmation value discarded", vm.confirmPassword.isEmpty)
    check("indicator hidden", vm.confirmation == .notShown)

    print("\n== Decrypt flow ==")
    vm.password = "s3cret"
    vm.inputText = ciphertext
    check("decrypt submits without a confirmation", vm.canSubmit)
    await vm.process()
    check("status ok", vm.status == .ok("Decryption successful."), "got \(vm.status)")
    check("round-trips the plaintext", vm.result == "Attack at dawn — 🌅", "got \(vm.result)")

    print("\n== Wrong password ==")
    vm.password = "wrong"
    vm.inputText = ciphertext
    await vm.process()
    check("status failed", vm.status == .failed("Decryption failed. Check password and ciphertext."), "got \(vm.status)")
    check("result hidden on failure", !vm.showResult)
    check("stale result cleared", vm.result.isEmpty)

    print("\n== Copy to clipboard ==")
    vm.password = "s3cret"
    vm.inputText = ciphertext
    await vm.process()
    vm.copyResult()
    check("copy flag set", vm.didJustCopy)
    let pasteboard = NSPasteboard.general.string(forType: .string)
    check("pasteboard matches result", pasteboard == vm.result, "got \(pasteboard ?? "nil")")

    print("\n== Clear ==")
    vm.mode = .encrypt
    vm.password = "s3cret"
    vm.confirmPassword = "s3cret"
    vm.clearAll()
    check("password cleared", vm.password.isEmpty)
    check("confirmation cleared", vm.confirmPassword.isEmpty)
    check("input cleared", vm.inputText.isEmpty)
    check("result cleared", vm.result.isEmpty)
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
    "$SRC/Services/CipherEngine.swift" \
    "$SRC/ViewModels/CipherViewModel.swift" \
    "$WORK_DIR/main.swift" \
    -o "$WORK_DIR/vmtest" || exit 1

echo
"$WORK_DIR/vmtest"
