import Foundation

/// The one-time secret a pairing QR carries.
///
/// It is **not** the long-lived bearer. It authorizes exactly one exchange, in
/// which the desktop issues a separate long-lived credential. Keeping them
/// distinct is what makes a photographed QR survivable: the code in the picture
/// expires in minutes, is single-use, and by the time anyone could act on it
/// the session that honoured it is gone.
public struct UsageBarPairingCode: Sendable, Equatable {
    /// 256 bits. A pairing window is short and attempt-limited, so this is far
    /// more than the situation requires — which is the right side to err on for
    /// a value that is briefly visible on a screen.
    public static let byteCount = 32

    public enum DecodingError: Error, Equatable, CustomStringConvertible {
        case malformedEncoding
        case wrongLength(found: Int, expected: Int)

        public var description: String {
            // Deliberately vague: this text can reach a screen, and a parser
            // that explains precisely how a secret was malformed is an oracle.
            "The pairing code is not valid."
        }
    }

    private let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Fresh from the system CSPRNG.
    public static func generate() -> UsageBarPairingCode {
        var buffer = [UInt8](repeating: 0, count: byteCount)
        for index in buffer.indices {
            buffer[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return UsageBarPairingCode(bytes: buffer)
    }

    /// Parses the base64url form carried by a QR payload.
    ///
    /// base64url without padding: a QR encodes more characters per module in
    /// alphanumeric mode, and `+`, `/` and `=` are exactly the characters that
    /// would force a denser, harder-to-scan symbol.
    public init(decoding text: String) throws {
        guard text.count <= 128,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else {
            throw DecodingError.malformedEncoding
        }
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError.malformedEncoding
        }
        guard data.count == Self.byteCount else {
            throw DecodingError.wrongLength(found: data.count, expected: Self.byteCount)
        }
        self.bytes = Array(data)
    }

    public var encoded: String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public var bitCount: Int { bytes.count * 8 }

    /// Compares in time independent of where the values first differ.
    ///
    /// A short-circuiting comparison on a secret leaks the matching prefix
    /// length through timing. The attempt ceiling makes that hard to exploit
    /// here, but defences that depend on another defence holding are how this
    /// goes wrong.
    public func matches(_ other: UsageBarPairingCode) -> Bool {
        UsageBarConstantTime.equal(bytes, other.bytes)
    }

    /// Equality is the constant-time comparison, so no call site can
    /// accidentally reintroduce a short-circuiting one through `==`.
    public static func == (lhs: UsageBarPairingCode, rhs: UsageBarPairingCode) -> Bool {
        lhs.matches(rhs)
    }
}

/// Fixed-time byte comparison, shared by every secret comparison in the lab.
public enum UsageBarConstantTime {
    /// Runs over the full span of `expected` regardless of where — or whether —
    /// the inputs diverge. Unequal lengths are folded into the same accumulator
    /// rather than returned early.
    public static func equal(_ expected: [UInt8], _ candidate: [UInt8]) -> Bool {
        guard !expected.isEmpty else { return false }
        var difference: UInt8 = candidate.count == expected.count ? 0 : 1
        for index in expected.indices {
            let actual = index < candidate.count ? candidate[index] : 0
            difference |= expected[index] ^ actual
        }
        return difference == 0
    }
}
