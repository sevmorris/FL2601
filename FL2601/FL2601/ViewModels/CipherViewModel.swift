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

    var mode: Mode = .encrypt {
        didSet {
            guard mode != oldValue else { return }
            // Hide output when switching modes to avoid confusion.
            showResult = false
            status = .idle
        }
    }

    var password = ""
    var inputText = ""
    var result = ""
    var showResult = false
    var status: Status = .idle
    var isProcessing = false
    var didJustCopy = false

    var canSubmit: Bool {
        !isProcessing && !password.isEmpty && !inputText.isEmpty
    }

    private let engine = CipherEngine()
    private var copyResetTask: Task<Void, Never>?

    func process() async {
        guard !isProcessing else { return }

        guard !password.isEmpty else {
            return fail(CipherError.passwordRequired)
        }
        guard !inputText.isEmpty else {
            return fail(CipherError.inputRequired)
        }

        isProcessing = true
        status = .working("Processing...")
        defer { isProcessing = false }

        let mode = mode
        let password = password
        let inputText = inputText

        do {
            let output: String
            switch mode {
            case .encrypt:
                output = try await engine.encrypt(inputText, password: password)
            case .decrypt:
                output = try await engine.decrypt(inputText, password: password)
            }
            result = output
            showResult = true
            status = .ok(mode.successMessage)
        } catch {
            fail(error)
        }
    }

    func clearAll() {
        password = ""
        inputText = ""
        result = ""
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
        showResult = false
    }
}
