import Foundation

/// A deliberately simple estimate of how much entropy a passphrase carries.
///
/// **What this measures.** The size of the character pool in use, multiplied by
/// an effective length that discounts repetition. Nothing more.
///
/// **What it does not measure.** Predictability. `Password123!` scores well here
/// and would fall to a dictionary attack in seconds; a long lowercase phrase of
/// common words scores well and is not much better. A real estimator needs a
/// word list and pattern matching — zxcvbn is the reference — and vendoring one
/// is more dependency than this app is willing to carry.
///
/// So the readout is framed as an upper bound on typed entropy, not a promise.
/// It is here because the app's own threat model names passphrase entropy as
/// the weak link, and saying nothing at all was worse than saying this with a
/// caveat attached.
enum PassphraseStrength {

    enum Band {
        case weak
        case fair
        case strong
        case veryStrong

        /// Thresholds chosen against this app's actual work factor. A serious
        /// GPU rig manages on the order of a million PBKDF2-SHA256 guesses per
        /// second at 600,000 iterations, so roughly 45 bits buys about a year.
        var label: String {
            switch self {
            case .weak: "weak"
            case .fair: "fair"
            case .strong: "strong"
            case .veryStrong: "very strong"
            }
        }
    }

    struct Estimate: Equatable {
        let bits: Int
        let band: Band
        /// 0...1, for a meter. Saturates at 96 bits.
        var fraction: Double { min(1, Double(bits) / 96) }
    }

    static func estimate(_ passphrase: String) -> Estimate? {
        guard !passphrase.isEmpty else { return nil }

        let bits = Int(entropyBits(passphrase).rounded())
        let band: Band
        switch bits {
        case ..<40: band = .weak
        case 40 ..< 60: band = .fair
        case 60 ..< 80: band = .strong
        default: band = .veryStrong
        }
        return Estimate(bits: bits, band: band)
    }

    // MARK: - Internals

    static func entropyBits(_ passphrase: String) -> Double {
        guard !passphrase.isEmpty else { return 0 }

        let scalars = Array(passphrase.unicodeScalars)
        var pool = 0
        var sawLower = false, sawUpper = false, sawDigit = false
        var sawSymbol = false, sawNonASCII = false

        for s in scalars {
            switch s {
            case "a" ... "z": sawLower = true
            case "A" ... "Z": sawUpper = true
            case "0" ... "9": sawDigit = true
            default: s.isASCII ? (sawSymbol = true) : (sawNonASCII = true)
            }
        }
        if sawLower { pool += 26 }
        if sawUpper { pool += 26 }
        if sawDigit { pool += 10 }
        if sawSymbol { pool += 33 }        // printable ASCII punctuation
        if sawNonASCII { pool += 100 }     // rough, and deliberately conservative
        guard pool > 1 else { return 0 }

        // Repetition earns less than novelty. Characters beyond the first
        // occurrence of each count half.
        let unique = Set(scalars).count
        let repeated = scalars.count - unique
        let effectiveLength = Double(unique) + Double(repeated) * 0.5

        return effectiveLength * log2(Double(pool))
    }
}
