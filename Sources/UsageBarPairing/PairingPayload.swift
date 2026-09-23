import Foundation

/// What a pairing QR carries, and the only thing it may carry.
///
/// Three fields, and none of them is a durable credential:
///
/// - `v` so a future format cannot be misread as this one
/// - `host` so the phone knows which tailnet machine to ask
/// - `pairingCode` a one-time value that buys exactly one credential issuance
///
/// There is deliberately **no** property for a long-lived bearer, a Tailscale
/// login, an email address, a `100.x` address, a tailnet identifier, a device
/// identifier or any usage. A QR is photographable by anyone who can see the
/// screen, so the rule is not "keep the payload small" but "put nothing in it
/// that is still worth having tomorrow".
///
/// One implementation, compiled into both the macOS host that writes the QR and
/// the iPhone app that reads it, so the two cannot disagree about the format.
public struct UsageBarPairingPayload: Equatable, Sendable {
    public static let currentVersion = 1

    /// A generous ceiling on the encoded form. A well-formed payload is around
    /// 120 bytes; anything approaching this is not one, and bounding before
    /// parsing is the cheapest way to not mishandle a hostile QR.
    public static let maximumEncodedBytes = 512

    /// Endpoints live on the tailnet and nowhere else.
    public static let requiredHostSuffix = ".ts.net"

    public enum PayloadError: Error, Equatable, CustomStringConvertible {
        case tooLarge
        case malformed
        case unsupportedVersion(found: Int)
        case unexpectedFields
        case hostNotTailnet
        case malformedCode

        /// One short sentence for every case. The scanner shows this to a
        /// person standing in front of a Mac; it must not teach a bystander
        /// which part of a forged QR nearly worked.
        public var description: String {
            switch self {
            case .unsupportedVersion:
                return "This pairing code is from a different version of UsageBar."
            default:
                return "That is not a UsageBar pairing code."
            }
        }
    }

    public let version: Int
    /// The `.ts.net` hostname, lowercased. Structurally checked here; the
    /// **client** is what validates it fully before building a URL from it —
    /// this type never constructs one.
    public let host: String
    public let pairingCode: UsageBarPairingCode

    public init(host: String, pairingCode: UsageBarPairingCode) throws {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try Self.requireTailnetHost(normalized)
        self.version = Self.currentVersion
        self.host = normalized
        self.pairingCode = pairingCode
    }

    private init(version: Int, host: String, pairingCode: UsageBarPairingCode) {
        self.version = version
        self.host = host
        self.pairingCode = pairingCode
    }

    /// Structural sanity, not the client's full validation.
    ///
    /// The phone runs the real endpoint validator on this string before it
    /// becomes a URL. What is enforced here is only what makes a QR a UsageBar
    /// QR at all: a plain tailnet hostname, never a URL, a port, a path, a
    /// credential or an address.
    static func requireTailnetHost(_ host: String) throws {
        guard !host.isEmpty, host.utf8.count <= 253 else { throw PayloadError.hostNotTailnet }
        guard host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw PayloadError.hostNotTailnet }
        // A scheme, a port, a path, a query or a credential would all mean the
        // QR is trying to say more than "which machine".
        for forbidden in ["://", "@", "?", "#", "/", ":"] {
            guard !host.contains(forbidden) else { throw PayloadError.hostNotTailnet }
        }
        guard host.hasSuffix(Self.requiredHostSuffix) else { throw PayloadError.hostNotTailnet }
        // At minimum <machine>.<tailnet>.ts.net — which also excludes a bare
        // dotted-quad, since an address cannot end in .ts.net.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 4 else { throw PayloadError.hostNotTailnet }
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63,
                  !label.hasPrefix("-"), !label.hasSuffix("-"),
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { throw PayloadError.hostNotTailnet }
        }
    }

    private enum Key: String, CaseIterable {
        case version = "v"
        case host
        case pairingCode
    }

    public func encoded() -> String {
        // Hand-built rather than `JSONEncoder`: the payload is three known
        // fields, and writing them explicitly means a property added to this
        // type later cannot silently start appearing in a QR.
        let object: [String: Any] = [
            Key.version.rawValue: version,
            Key.host.rawValue: host,
            Key.pairingCode.rawValue: pairingCode.encoded
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            preconditionFailure("a validated payload must always encode")
        }
        return text
    }

    /// Strict parse. A malformed QR is rejected, never repaired.
    ///
    /// Unknown keys are refused rather than ignored, which is the opposite of
    /// the usual forward-compatibility instinct and deliberate: the version
    /// field is how this format evolves, and silently tolerating an extra
    /// `accessKey` or `identity` would be exactly the smuggling channel the
    /// payload is shaped to exclude.
    public static func decode(_ text: String) throws -> UsageBarPairingPayload {
        guard text.utf8.count <= maximumEncodedBytes else { throw PayloadError.tooLarge }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { throw PayloadError.malformed }

        let known = Set(Key.allCases.map(\.rawValue))
        guard Set(dictionary.keys) == known else {
            // Missing a required key and carrying an unknown one are both
            // "this is not the format", and distinguishing them tells a forger
            // which half they got right.
            throw dictionary.keys.contains(where: { !known.contains($0) })
                ? PayloadError.unexpectedFields
                : PayloadError.malformed
        }

        guard let version = dictionary[Key.version.rawValue] as? Int else {
            throw PayloadError.malformed
        }
        guard version == currentVersion else {
            throw PayloadError.unsupportedVersion(found: version)
        }
        guard let host = dictionary[Key.host.rawValue] as? String,
              let code = dictionary[Key.pairingCode.rawValue] as? String
        else { throw PayloadError.malformed }

        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try requireTailnetHost(normalized)

        let pairingCode: UsageBarPairingCode
        do {
            pairingCode = try UsageBarPairingCode(decoding: code)
        } catch {
            throw PayloadError.malformedCode
        }

        return UsageBarPairingPayload(version: version, host: normalized, pairingCode: pairingCode)
    }
}
