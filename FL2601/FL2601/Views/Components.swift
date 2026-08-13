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
            // Flexible on purpose: this is the one element that absorbs slack,
            // so the panel keeps a constant height whether or not the
            // confirmation field is showing.
            .frame(minHeight: 200, maxHeight: .infinity)
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

// MARK: - Passphrase strength

struct StrengthMeter: View {
    let estimate: PassphraseStrength.Estimate?

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    // No track until there is something to measure, otherwise an
                    // empty meter reads as a stray rule under the field.
                    Rectangle().fill(estimate == nil ? Color.clear : Theme.border)
                    Rectangle()
                        .fill(color)
                        .frame(width: proxy.size.width * (estimate?.fraction ?? 0))
                }
            }
            .frame(height: 2)

            Text(readout)
                .font(Theme.mono(Theme.Size.micro))
                .foregroundStyle(estimate == nil ? Theme.inactiveTab : color)
                .fixedSize()
        }
        // Reserve the row unconditionally so typing never nudges the layout.
        .frame(height: 14)
        .animation(.easeOut(duration: 0.2), value: estimate?.bits ?? 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(estimate.map { "Passphrase strength \($0.band.label), about \($0.bits) bits" }
            ?? "Passphrase strength not yet estimated")
    }

    private var readout: String {
        guard let estimate else { return "" }
        return "~\(estimate.bits) bits · \(estimate.band.label)"
    }

    private var color: Color {
        switch estimate?.band {
        case .weak: Theme.error
        case .fair: Theme.caution
        case .strong, .veryStrong: Theme.green
        case nil: Theme.border
        }
    }
}

// MARK: - Payload map

/// Shows what the payload in hand is actually made of.
///
/// Drawn to true scale wherever both segments clear a minimum readable width,
/// which covers everything from a one-line note to a few kilobytes. Only at the
/// extremes — a very large message, where the framing's real share rounds to a
/// hairline — does a floor take over. The exact byte counts sit underneath
/// either way, so the figures never depend on the drawing.
///
/// Two segments rather than five. Splitting out header, salt, nonce and tag
/// would be unreadable the moment a message exceeds a few hundred bytes — the
/// ciphertext takes over 90% of the width and the rest become slivers. Grouping
/// them also states something truer than the five-way split does: everything
/// except the ciphertext is public by design. The salt, the nonce, the version,
/// the iteration count and the tag are all readable by anyone holding the
/// block. Only your message is not.
struct PayloadMap: View {
    let info: PayloadInfo

    private var overheadBytes: Int { info.totalBytes - info.ciphertextBytes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let total = max(info.totalBytes, 1)
                let minSegment: CGFloat = 76
                let rawPublic = proxy.size.width * Double(overheadBytes) / Double(total)
                // Clamp against a floor on each side rather than a fixed
                // ceiling. A short message really is mostly framing, and a cap
                // would hide that; this stays exact until a segment would
                // become too narrow to read.
                let publicWidth = min(
                    max(rawPublic, minSegment),
                    max(minSegment, proxy.size.width - minSegment)
                )

                HStack(spacing: 0) {
                    segment("PUBLIC", detail: "\(overheadBytes) B", hatched: true)
                        .frame(width: publicWidth)
                    segment("CIPHERTEXT", detail: "\(info.ciphertextBytes.formatted()) B", hatched: false)
                }
            }
            .frame(height: 28)

            Text(summary)
                .font(Theme.mono(Theme.Size.micro))
                .foregroundStyle(Theme.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        "\(info.totalBytes.formatted()) bytes · v\(info.version) · "
            + "\(info.iterations.formatted()) rounds · "
            + "\(overheadBytes) bytes public framing · "
            + "\(info.plaintextBytes.formatted()) bytes encrypted"
    }

    private func segment(_ name: String, detail: String, hatched: Bool) -> some View {
        ZStack {
            Rectangle().fill(Theme.panelRaised)
            if hatched { HatchPattern() }
            Text("\(name) \(detail)")
                .font(Theme.mono(9))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().strokeBorder(Theme.greenLo, lineWidth: 1))
    }
}

/// Diagonal hatching, marking the one part of the payload that is readable by
/// anyone: the header travels in the clear, though the tag still covers it.
private struct HatchPattern: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let step: CGFloat = 7
                let extent = proxy.size.width + proxy.size.height
                var x: CGFloat = -proxy.size.height
                while x < extent {
                    path.move(to: CGPoint(x: x, y: proxy.size.height))
                    path.addLine(to: CGPoint(x: x + proxy.size.height, y: 0))
                    x += step
                }
            }
            .stroke(Theme.greenLo, lineWidth: 1)
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

// MARK: - Idle cursor

/// Fills the output area before there is anything to show, so the empty space
/// reads as a waiting terminal rather than an unfinished screen.
struct IdlePrompt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true

    var body: some View {
        HStack(spacing: 0) {
            Text("awaiting input")
                .font(Theme.mono(Theme.Size.result))
                .foregroundStyle(Theme.inactiveTab)
            Rectangle()
                .fill(Theme.greenLo)
                .frame(width: 9, height: 16)
                .opacity(on ? 1 : 0)
                .padding(.leading, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(560))
                on.toggle()
            }
        }
        .accessibilityHidden(true)
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
