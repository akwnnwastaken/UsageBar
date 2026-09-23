import Foundation

/// A validated Tailscale MagicDNS hostname.
///
/// The app accepts a *host*, never a URL. That distinction is the point: if the
/// user could type a URL, they could type a scheme, a port, a path or
/// credentials, and the bearer token would follow wherever that pointed. By
/// accepting only a hostname and building the URL ourselves, the only thing a
/// user can influence is *which tailnet machine* is asked — never how.
///
/// This type cannot hold an invalid host: the only way to make one is through
/// `init(validating:)`, which rejects everything below.
public struct UsageSyncHost: Equatable, Hashable, Sendable {
    /// Endpoints live on the tailnet and nowhere else.
    public static let requiredSuffix = ".ts.net"

    /// The routes the desktop service exposes.
    public static let snapshotPath = "/v1/snapshot"
    public static let pairingPath = "/v1/pair"

    public enum ValidationError: Error, Equatable, CustomStringConvertible {
        case empty
        case containsWhitespaceOrControlCharacters
        case containsScheme
        case containsCredentials
        case containsPort
        case containsPath
        case containsQueryOrFragment
        case isIPAddress
        case notTailnetHost
        case malformedLabel

        /// User-facing copy. Deliberately says what is wrong with the *input*
        /// and never echoes the input back into a log or a screen.
        public var description: String {
            switch self {
            case .empty:
                return "Enter your Tailscale hostname."
            case .containsWhitespaceOrControlCharacters:
                return "The hostname cannot contain spaces."
            case .containsScheme:
                return "Enter the hostname only, without https://."
            case .containsCredentials:
                return "The hostname cannot contain a username or password."
            case .containsPort:
                return "The hostname cannot contain a port."
            case .containsPath:
                return "Enter the hostname only, without a path."
            case .containsQueryOrFragment:
                return "The hostname cannot contain ? or #."
            case .isIPAddress:
                return "Enter the MagicDNS name, not an IP address."
            case .notTailnetHost:
                return "The hostname must end in .ts.net."
            case .malformedLabel:
                return "That is not a valid hostname."
            }
        }
    }

    /// Lowercased, fully validated.
    public let value: String

    public init(validating raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError.empty }

        // Reject before lowercasing so a control character cannot be smuggled
        // through a case fold.
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            throw ValidationError.containsWhitespaceOrControlCharacters
        }

        let host = trimmed.lowercased()

        guard !host.contains("://"), !host.hasPrefix("http") || !host.contains(":") else {
            throw ValidationError.containsScheme
        }
        guard !host.contains("@") else { throw ValidationError.containsCredentials }
        guard !host.contains("?"), !host.contains("#") else {
            throw ValidationError.containsQueryOrFragment
        }
        guard !host.contains("/") else { throw ValidationError.containsPath }
        guard !host.contains(":") else { throw ValidationError.containsPort }

        // A dotted-quad is a routable address, not a MagicDNS name. Rejecting
        // it keeps the raw 100.x tailnet address out of the app entirely.
        guard !Self.looksLikeIPAddress(host) else { throw ValidationError.isIPAddress }

        guard host.hasSuffix(Self.requiredSuffix) else { throw ValidationError.notTailnetHost }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        // At minimum: <machine>.<tailnet>.ts.net
        guard labels.count >= 4 else { throw ValidationError.malformedLabel }
        for label in labels {
            guard Self.isValidLabel(String(label)) else { throw ValidationError.malformedLabel }
        }
        guard host.utf8.count <= 253 else { throw ValidationError.malformedLabel }

        self.value = host
    }

    /// The one URL the app ever requests. Built here, never supplied by a user
    /// or by the desktop, so no response can redirect the app's idea of its own
    /// endpoint.
    public var snapshotURL: URL { url(path: Self.snapshotPath) }

    /// The pairing route, built the same way and from the same validated host.
    public var pairingURL: URL { url(path: Self.pairingPath) }

    private func url(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = value
        components.path = path
        guard let url = components.url else {
            preconditionFailure("a validated host must always produce a URL")
        }
        return url
    }

    private static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.utf8.count <= 63 else { return false }
        guard !label.hasPrefix("-"), !label.hasSuffix("-") else { return false }
        return label.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }

    private static func looksLikeIPAddress(_ host: String) -> Bool {
        var address = in_addr()
        if inet_pton(AF_INET, host, &address) == 1 { return true }
        var address6 = in6_addr()
        if inet_pton(AF_INET6, host, &address6) == 1 { return true }
        // A trailing all-numeric label cannot be a real TLD, so treat a
        // dotted-numeric string as an address even when it is malformed.
        let labels = host.split(separator: ".")
        if let last = labels.last, last.allSatisfy(\.isNumber) { return true }
        return false
    }
}
