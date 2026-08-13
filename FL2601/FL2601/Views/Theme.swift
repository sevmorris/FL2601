import SwiftUI

/// The app's palette. Deliberately dark-only — the phosphor-terminal look is
/// the design, not a color scheme, so there is no light variant.
enum Theme {
    static let green = Color(hex: 0x33FF33)
    static let greenHi = Color(hex: 0x99FF99)
    static let greenLo = Color(hex: 0x1A6B1A)
    static let background = Color(hex: 0x0A0A0A)
    static let panel = Color(hex: 0x111111)
    static let inputBackground = Color.black
    static let resultBackground = Color(hex: 0x050505)
    static let error = Color(hex: 0xFF4444)

    /// Amber for the middle band of the strength meter. Red and green alone
    /// would force every passphrase into pass or fail, and most sit between.
    static let caution = Color(hex: 0xE0A02A)

    /// Fill for the payload map's segments, lifted off the panel enough to read
    /// as a distinct surface.
    static let panelRaised = Color(hex: 0x1A1F18)

    // Greys lifted from the original stylesheet's values. Against the #111
    // panel the inactive tab was at 2.5:1 and the footnote at 3.3:1, both under
    // the 4.5:1 needed for body text; they now sit at 5.5:1 and 4.7:1. Field
    // outlines went from 1.2:1 to 1.6:1 — still quiet, but actually visible.
    static let border = Color(hex: 0x383838)
    static let text = Color(hex: 0xD6D6D6)
    static let inactiveTab = Color(hex: 0x8A8A8A)
    static let footnote = Color(hex: 0x7E7E7E)

    /// 1rem in the stylesheet == 16pt here.
    enum Size {
        static let title: CGFloat = 19   // 1.2rem
        static let body: CGFloat = 16    // 1rem
        static let label: CGFloat = 13   // 0.8rem
        static let result: CGFloat = 14  // 0.9rem
        static let micro: CGFloat = 11   // 0.7rem
    }

    /// The stylesheet asks for 'Courier New', which ships with macOS. Falling
    /// back to the system monospace keeps this safe if it is ever missing.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "Courier New", size: size) != nil {
            return .custom("Courier New", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
