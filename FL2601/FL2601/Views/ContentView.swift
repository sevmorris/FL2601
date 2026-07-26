import SwiftUI

struct ContentView: View {
    @State private var model = CipherViewModel()

    var body: some View {
        ScrollView {
            panel
                .frame(maxWidth: 800)
                .padding(.horizontal, 16)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .scrollBounceBehavior(.basedOnSize)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            // Mode selection sits above the fields it governs. The confirm
            // field appears only when encrypting, so anything below the tabs
            // shifts when the mode changes — keeping the tabs above that point
            // means the control you just clicked stays put.
            TabNav(selection: $model.mode)
                .padding(.bottom, 24)

            passwordFields
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: model.mode.inputLabel)
                TerminalTextEditor(prompt: model.mode.inputPrompt, text: $model.inputText)
            }
            .padding(.bottom, 24)

            actions

            if model.showResult {
                resultSection
                    .padding(.top, 32)
            }

            statusLine

            instructions
        }
        .padding(32)
        .background(Theme.panel)
        .overlay(Rectangle().strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 15, y: 10)
    }

    private var passwordFields: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                FieldLabel(text: "Access Password")
                TerminalSecureField(prompt: "Enter password...", text: $model.password)
            }

            if model.requiresConfirmation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        FieldLabel(text: "Confirm Password")
                        Spacer()
                        confirmationIndicator
                    }
                    TerminalSecureField(prompt: "Re-enter password...", text: $model.confirmPassword)
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.requiresConfirmation)
    }

    @ViewBuilder
    private var confirmationIndicator: some View {
        switch model.confirmation {
        case .match:
            Text("[ MATCH ]")
                .font(Theme.mono(Theme.Size.label, weight: .bold))
                .foregroundStyle(Theme.green)
                .accessibilityLabel("Passwords match")
        case .mismatch:
            Text("[ NO MATCH ]")
                .font(Theme.mono(Theme.Size.label, weight: .bold))
                .foregroundStyle(Theme.error)
                .accessibilityLabel("Passwords do not match")
        case .pending, .notShown:
            EmptyView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FL2601 — CIPHER TOOL")
                .font(Theme.mono(Theme.Size.title, weight: .bold))
                .kerning(2)
                .foregroundStyle(Theme.green)
            Rectangle()
                .fill(Theme.greenLo)
                .frame(height: 1)
        }
        .padding(.bottom, 32)
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button(model.mode.actionTitle.uppercased()) {
                Task { await model.process() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canSubmit)
            .keyboardShortcut(.return, modifiers: .command)

            Button("CLEAR") {
                model.clearAll()
            }
            .buttonStyle(SecondaryButtonStyle())
            .keyboardShortcut(.delete, modifiers: .command)

            if model.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.green)
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                FieldLabel(text: "Result")
                Spacer()
                Button(model.didJustCopy ? "COPIED!" : "COPY TO CLIPBOARD") {
                    model.copyResult()
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }

            ScrollView {
                Text(model.result)
                    .font(Theme.mono(Theme.Size.result))
                    .foregroundStyle(Theme.green)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.resultBackground)
            .overlay(Rectangle().strokeBorder(Theme.greenLo, lineWidth: 1))
        }
    }

    private var statusLine: some View {
        Text(model.status.message)
            .font(Theme.mono(Theme.Size.result))
            .foregroundStyle(statusColor)
            .frame(minHeight: 19, alignment: .leading)
            .padding(.top, 16)
            .accessibilityHidden(model.status.message.isEmpty)
    }

    private var statusColor: Color {
        switch model.status {
        case .idle: .clear
        case .working: Theme.text
        case .ok: Theme.green
        case .failed: Theme.error
        }
    }

    private var instructions: some View {
        // Read from the format constant rather than hardcoded, so the copy
        // cannot drift from what the app actually does.
        Text("This tool uses PBKDF2 for key derivation (\(CipherFormat.defaultIterations.formatted()) iterations, SHA-256) and AES-256-GCM for encryption.")
            .font(Theme.mono(Theme.Size.label))
            .foregroundStyle(Theme.footnote)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 48)
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 900)
}
