import CommonCrypto
import CryptoKit
import Foundation

/// On-disk / on-clipboard layout, version 1.
///
///     offset  size  field
///     ------  ----  ---------------------------------------------
///          0     4  magic "FL26"
///          4     1  format version
///          5     1  KDF identifier
///          6     4  KDF iterations, big-endian UInt32
///         10    16  salt
///         26    12  AES-GCM nonce
///         38     n  ciphertext
///     38 + n    16  AES-GCM authentication tag
///
/// The whole thing is then base64-encoded.
///
/// The header is *self-describing*: the iteration count travels with the
/// message instead of living in a constant here. That is the point of the
/// design — a decryptor reads how the key was derived rather than assuming,
/// so raising the work factor later cannot strand previously encrypted
/// messages.
///
/// Bytes 0..<10 are passed to AES-GCM as additional authenticated data, so the
/// version and iteration count are covered by the authentication tag and
/// cannot be altered without detection. The salt needs no explicit binding: it
/// determines the key, so changing it fails authentication on its own.
enum CipherFormat {
    static let magic: [UInt8] = Array("FL26".utf8)
    static let version: UInt8 = 1

    static let headerLength = 10
    static let saltLength = 16
    static let nonceLength = 12
    static let tagLength = 16

    /// Minimum size of a well-formed payload: everything but the plaintext.
    static let minimumPayloadLength = headerLength + saltLength + nonceLength + tagLength

    /// OWASP's current floor for PBKDF2-HMAC-SHA256. Roughly 70ms on Apple
    /// silicon, which is imperceptible in an interactive tool.
    static let defaultIterations: UInt32 = 600_000

    /// Bounds enforced on a *parsed* iteration count. Key derivation happens
    /// before authentication can possibly succeed, so a hostile payload could
    /// otherwise ask the app to spin on four billion rounds. The tag check
    /// would eventually reject it, but only after the damage to responsiveness
    /// was done.
    static let minIterations: UInt32 = 10_000
    static let maxIterations: UInt32 = 10_000_000
}

/// Recorded in the header so a future build can add a memory-hard KDF without
/// breaking anything written today.
enum KDFIdentifier: UInt8 {
    case pbkdf2HMACSHA256 = 1
}

enum CipherError: LocalizedError, Equatable {
    case passwordRequired
    case passwordMismatch
    case inputRequired
    case malformedPayload
    case unsupportedVersion(UInt8)
    case unsupportedKDF(UInt8)
    case implausibleIterations(UInt32)
    case decryptionFailed
    case keyDerivationFailed(Int32)
    case randomGenerationFailed(Int32)
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .passwordRequired:
            "Password required."
        case .passwordMismatch:
            "Passwords do not match."
        case .inputRequired:
            "Input text required."
        case .malformedPayload:
            "This does not look like an FL2601 message."
        case .unsupportedVersion(let version):
            "Message uses format version \(version); this app supports version \(CipherFormat.version)."
        case .unsupportedKDF(let identifier):
            "Message uses an unknown key derivation function (id \(identifier))."
        case .implausibleIterations(let count):
            "Message declares \(count) iterations, outside the accepted range."
        case .decryptionFailed, .notUTF8:
            // A wrong password and a tampered message are indistinguishable
            // here by design: GCM authentication fails identically for both,
            // and guessing at which it was would only mislead.
            "Decryption failed. Check password and ciphertext."
        case .keyDerivationFailed(let status):
            "Key derivation failed (\(status))."
        case .randomGenerationFailed(let status):
            "Could not generate secure random bytes (\(status))."
        }
    }
}

/// PBKDF2-HMAC-SHA256 + AES-256-GCM.
///
/// An `actor` rather than a namespace: key derivation is hundreds of thousands
/// of HMAC rounds and must not run on the main thread.
actor CipherEngine {
    func encrypt(
        _ plaintext: String,
        password: String,
        iterations: UInt32 = CipherFormat.defaultIterations
    ) throws -> String {
        let salt = try Self.randomBytes(count: CipherFormat.saltLength)
        let header = Self.makeHeader(kdf: .pbkdf2HMACSHA256, iterations: iterations)
        let key = try Self.deriveKey(password: password, salt: salt, iterations: iterations)

        let sealed = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: key,
            authenticating: header
        )
        guard let combined = sealed.combined else {
            // Only nil for non-12-byte nonces; the default nonce is 12 bytes.
            throw CipherError.decryptionFailed
        }

        return (header + salt + combined).base64EncodedString()
    }

    func decrypt(_ ciphertext: String, password: String) throws -> String {
        // Browsers' atob() ignores ASCII whitespace, so base64 wrapped by an
        // email client still pastes cleanly. Match that leniency.
        let cleaned = ciphertext.filter { !$0.isWhitespace }

        guard let blob = Data(base64Encoded: cleaned),
              blob.count >= CipherFormat.minimumPayloadLength
        else {
            throw CipherError.malformedPayload
        }

        // Work in an array: slicing a Data preserves the parent's indices,
        // which makes offset arithmetic on slices quietly wrong.
        let bytes = [UInt8](blob)

        guard Array(bytes[0 ..< 4]) == CipherFormat.magic else {
            throw CipherError.malformedPayload
        }
        guard bytes[4] == CipherFormat.version else {
            throw CipherError.unsupportedVersion(bytes[4])
        }
        guard let kdf = KDFIdentifier(rawValue: bytes[5]) else {
            throw CipherError.unsupportedKDF(bytes[5])
        }

        let iterations = bytes[6 ... 9].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard (CipherFormat.minIterations ... CipherFormat.maxIterations).contains(iterations) else {
            throw CipherError.implausibleIterations(iterations)
        }

        let header = Data(bytes[0 ..< CipherFormat.headerLength])
        let salt = Data(bytes[CipherFormat.headerLength ..< (CipherFormat.headerLength + CipherFormat.saltLength)])
        let sealedBytes = Data(bytes[(CipherFormat.headerLength + CipherFormat.saltLength)...])

        let key: SymmetricKey
        switch kdf {
        case .pbkdf2HMACSHA256:
            key = try Self.deriveKey(password: password, salt: salt, iterations: iterations)
        }

        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: sealedBytes)
            plaintext = try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw CipherError.decryptionFailed
        }

        guard let text = String(data: plaintext, encoding: .utf8) else {
            throw CipherError.notUTF8
        }
        return text
    }

    // MARK: - Primitives

    private static func makeHeader(kdf: KDFIdentifier, iterations: UInt32) -> Data {
        var header = Data(CipherFormat.magic)
        header.append(CipherFormat.version)
        header.append(kdf.rawValue)
        header.append(UInt8((iterations >> 24) & 0xFF))
        header.append(UInt8((iterations >> 16) & 0xFF))
        header.append(UInt8((iterations >> 8) & 0xFF))
        header.append(UInt8(iterations & 0xFF))
        return header
    }

    /// CryptoKit exposes no PBKDF2, so this drops to CommonCrypto.
    private static func deriveKey(
        password: String,
        salt: Data,
        iterations: UInt32
    ) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        defer { derived.resetBytes() }

        let status = passwordBytes.withUnsafeBytes { passwordRaw in
            salt.withUnsafeBytes { saltRaw in
                derived.withUnsafeMutableBufferPointer { output in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordRaw.baseAddress?.assumingMemoryBound(to: CChar.self),
                        passwordBytes.count,
                        saltRaw.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        output.baseAddress,
                        output.count
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw CipherError.keyDerivationFailed(status)
        }
        // SymmetricKey copies the bytes, so zeroing `derived` on the way out is
        // safe. The password itself cannot be wiped — Swift's String gives no
        // way to reach its storage — so this is a partial measure, not a
        // guarantee.
        return SymmetricKey(data: Data(derived))
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, count, raw.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw CipherError.randomGenerationFailed(status)
        }
        return bytes
    }
}

private extension Array where Element == UInt8 {
    mutating func resetBytes() {
        withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            memset_s(base, buffer.count, 0, buffer.count)
        }
    }
}
