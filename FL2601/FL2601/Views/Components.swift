import SwiftUI

// MARK: - Labels

struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(Theme.Size.label))
            .foregroundStyle(Theme.greenLo)
            .kerning(0.5)
    }
}

// MARK: - Inputs

/// Shared chrome for the text inputs: black field, hairline border that lifts
/// to green on focus.
private struct TerminalFieldChrome: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(Theme.mono(Theme.Size.body))
            .foregroundStyle(Theme.greenHi)
            .tint(Theme.green)
            .padding(12)
            .background(Theme.inputBackground)
            .overlay(
                Rectangle()
                    .strokeBorder(isFocused ? Theme.greenLo : Theme.border, lineWidth: 1)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

struct TerminalSecureField: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField("", text: $text, prompt: promptView)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .modifier(TerminalFieldChrome(isFocused: isFocused))
    }

    private var promptView: Text {
        Text(prompt)
            .font(Theme.mono(Theme.Size.body))
            .foregroundColor(Theme.inactiveTab)
    }
}

struct TerminalTextEditor: View {
    let prompt: String
    @Binding var text: String

    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 200)
            .focused($isFocused)
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(prompt)
                        .font(Theme.mono(Theme.Size.body))
                        .foregroundStyle(Theme.inactiveTab)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                }
            }
            .modifier(TerminalFieldChrome(isFocused: isFocused))
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(Theme.Size.label, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(isEnabled ? .black : Theme.inactiveTab.opacity(0.6))
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(background(configuration))
            .shadow(
                color: isEnabled && isHovered ? Theme.greenLo : .clear,
                radius: 10
            )
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
    }

    private func background(_ configuration: Configuration) -> Color {
        guard isEnabled else { return Theme.border }
        if configuration.isPressed { return Theme.greenHi }
        return isHovered ? Theme.green : Theme.greenLo
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var compact = false

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let accent: Color = !isEnabled
            ? Theme.border
            : (isHovered || configuration.isPressed ? Theme.green : Theme.greenLo)

        return configuration.label
            .font(Theme.mono(compact ? Theme.Size.micro : Theme.Size.label, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(accent)
            .padding(.vertical, compact ? 4 : 12)
            .padding(.horizontal, compact ? 12 : 24)
            .overlay(Rectangle().strokeBorder(accent, lineWidth: 1))
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Tabs

struct TabNav: View {
    @Binding var selection: CipherViewModel.Mode

    var body: some View {
        HStack(spacing: 32) {
            ForEach(CipherViewModel.Mode.allCases) { mode in
                TabItem(
                    title: mode.tabTitle,
                    isActive: selection == mode
                ) {
                    selection = mode
                }
            }
            Spacer()
        }
    }

    private struct TabItem: View {
        let title: String
        let isActive: Bool
        let select: () -> Void

        @State private var isHovered = false

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.mono(Theme.Size.body))
                    .foregroundStyle(color)
                Rectangle()
                    .fill(isActive ? Theme.green : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
            .contentShape(.rect)
            .onTapGesture(perform: select)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isActive)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(title)
        }

        private var color: Color {
            if isActive { return Theme.green }
            return isHovered ? Theme.text : Theme.inactiveTab
        }
    }
}
