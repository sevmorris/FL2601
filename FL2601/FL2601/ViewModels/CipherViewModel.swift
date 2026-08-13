import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class CipherViewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case encrypt
        case decrypt

        var id: String { rawValue }

        var tabTitle: String {
            switch self {
            case .encrypt: "Encrypt"
            case .decrypt: "Decrypt"
            }
        }

        var inputLabel: String {
            switch self {
            case .encrypt: "Plaintext Letter"
            case .decrypt: "Ciphertext (Base64)"
            }
        }

        var actionTitle: String {
            switch self {
            case .encrypt: "Encrypt Text"
            case .decrypt: "Decrypt Text"
            }
        }

        var inputPrompt: String {
            switch self {
            case .encrypt: "Type or paste text here..."
            case .decrypt: "Paste base64 ciphertext here..."
            }
        }

        var successMessage: String {
            switch self {
            case .encrypt: "Encryption successful."
            case .decrypt: "Decryption successful."
            }
        }
    }

    enum Status: Equatable {
        case idle
        case working(String)
        case ok(String)
        case failed(String)

        var message: String {
            switch self {
            case .idle: ""
            case .working(let text), .ok(let text), .failed(let text): text
            }
        }
    }

    /// Whether the confirmation field currently agrees with the passphrase.
    /// `notShown` while decrypting, `pending` until the user has typed
    /// something, so the UI does not flash a mismatch on the first keystroke.
    enum Confirmation {
        case notShown
        case pending
        case match
        case mismatch
    }

    var mode: Mode = .encrypt {
        didSet {
            guard mode != oldValue else { return }
            // Hide output when switching modes to avoid confusion.
            showResult = false
            status = .idle
            payloadInfo = nil
            // Decrypt has no confirmation field; drop the value rather than
            // leave it to reappear stale when the user switches back.
            confirmPassphrase = ""
        }
    }

    var passphrase = ""
    var confirmPassphrase = ""
    var inputText = ""
    var result = ""
    var showResult = false
    var status: Status = .idle
    var isProcessing = false
    var didJustCopy = false

    /// Only encryption confirms. When decrypting, a mistyped passphrase simply
    /// fails to decrypt, so a second field would add friction and catch
    /// nothing.
    var requiresConfirmation: Bool {
        mode == .encrypt
    }

    var confirmation: Confirmation {
        guard requiresConfirmation else { return .notShown }
        if confirmPassphrase.isEmpty { return .pending }
        return passphrase == confirmPassphrase ? .match : .mismatch
    }

    var canSubmit: Bool {
        guard !isProcessing, !passphrase.isEmpty, !inputText.isEmpty else { return false }
        guard requiresConfirmation else { return true }
        return passphrase == confirmPassphrase
    }

    /// Structure of the payload most recently produced or read. Populated from
    /// the header alone, so it costs nothing and discloses nothing.
    private(set) var payloadInfo: PayloadInfo?

    /// Only shown while encrypting. When decrypting you are typing a passphrase
    /// that already exists, and rating it would be noise.
    var passphraseStrength: PassphraseStrength.Estimate? {
        guard requiresConfirmation else { return nil }
        return PassphraseStrength.estimate(passphrase)
    }

    var inputCharacterCount: Int { inputText.count }
    var inputByteCount: Int { inputText.utf8.count }

    /// What the app is actually doing, named rather than described as
    /// "processing". The pause has a cause and the cause is interesting.
    var workingDescription: String {
        "deriving key · \(CipherFormat.defaultIterations.formatted()) rounds · PBKDF2-HMAC-SHA256"
    }

    private let engine = CipherEngine()
    private var copyResetTask: Task<Void, Never>?

    func process() async {
        guard !isProcessing else { return }

        guard !passphrase.isEmpty else {
            return fail(CipherError.passphraseRequired)
        }
        guard !requiresConfirmation || passphrase == confirmPassphrase else {
            return fail(CipherError.passphraseMismatch)
        }
        guard !inputText.isEmpty else {
            return fail(CipherError.inputRequired)
        }

        isProcessing = true
        status = .working(workingDescription)
        defer { isProcessing = false }

        let mode = mode
        let passphrase = passphrase
        let inputText = inputText

        do {
            let output: String
            let inspected: String
            switch mode {
            case .encrypt:
                // The engine returns the payload; the envelope is added here
                // because it is presentation, not format.
                let payload = try await engine.encrypt(inputText, passphrase: passphrase)
                output = MessageArmor.wrap(payload)
                inspected = payload
            case .decrypt:
                output = try await engine.decrypt(inputText, passphrase: passphrase)
                // Report the structure of what was read, not of the plaintext.
                inspected = inputText
            }
            result = output
            // Never let a failure to describe the payload sink a successful
            // operation: this is a readout, not part of the result.
            payloadInfo = try? CipherEngine.inspect(inspected)
            showResult = true
            status = .ok(mode.successMessage)
        } catch {
            fail(error)
        }
    }

    func clearAll() {
        passphrase = ""
        confirmPassphrase = ""
        inputText = ""
        result = ""
        payloadInfo = nil
        showResult = false
        status = .idle
    }

    func copyResult() {
        guard !result.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)

        didJustCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.didJustCopy = false
        }
    }

    private func fail(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        status = .failed(message)
        result = ""
        payloadInfo = nil
        showResult = false
    }
}
