import Foundation

/// A labelled envelope around the base64 payload.
///
///     -----BEGIN FL2601 MESSAGE-----
///     Comment: Encrypted with FL2601 Cipher Tool
///     Comment: https://github.com/sevmorris/FL2601
///
///     RkwyNgEBAAlfkOZ2Iq3rW1sT...
///     -----END FL2601 MESSAGE-----
///
/// This is a **display convention, not part of the cryptographic format**. The
/// bytes between the markers are exactly what `CipherEngine` produces, and
/// deleting the envelope by hand leaves a payload any build can read. Its only
/// job is to tell a recipient who has never heard of this tool what they are
/// looking at, and where to get something that opens it.
///
/// Keeping it out of the format matters: the header inside the payload is
/// covered by the GCM tag, but these lines are not authenticated and must never
/// be trusted. Nothing here is read back during decryption except as a hint
/// about where the base64 starts and ends.
enum MessageArmor {
    static let beginMarker = "-----BEGIN FL2601 MESSAGE-----"
    static let endMarker = "-----END FL2601 MESSAGE-----"

    private static let comments = [
        "Comment: Encrypted with FL2601 Cipher Tool",
        "Comment: https://github.com/sevmorris/FL2601",
    ]

    /// Base64 line width. Matches the PGP convention and keeps the block intact
    /// through mail clients that reflow long lines.
    private static let lineWidth = 64

    static func wrap(_ base64: String) -> String {
        var lines = [beginMarker]
        lines.append(contentsOf: comments)
        lines.append("")
        lines.append(contentsOf: wrapped(base64))
        lines.append(endMarker)
        return lines.joined(separator: "\n")
    }

    /// Extracts the payload from an armored block.
    ///
    /// Input carrying no armor is returned unchanged, so bare base64 — including
    /// anything produced before this envelope existed — still decrypts.
    static func unwrap(_ text: String) -> String {
        guard let begin = text.range(of: beginMarker) else { return text }

        let afterBegin = text[begin.upperBound...]
        let body = afterBegin.range(of: endMarker)
            .map { afterBegin[..<$0.lowerBound] } ?? afterBegin

        return body
            .split(whereSeparator: \.isNewline)
            // Armor headers take the form "Name: value". Base64 has no colon,
            // so this discards them without touching the payload.
            .filter { !$0.contains(":") }
            .joined()
    }

    private static func wrapped(_ s: String) -> [String] {
        guard !s.isEmpty else { return [""] }
        return stride(from: 0, to: s.count, by: lineWidth).map { offset in
            let start = s.index(s.startIndex, offsetBy: offset)
            let end = s.index(start, offsetBy: min(lineWidth, s.count - offset))
            return String(s[start ..< end])
        }
    }
}
