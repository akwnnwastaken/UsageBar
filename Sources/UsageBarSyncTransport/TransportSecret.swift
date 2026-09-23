import Foundation

/// The prototype's second authentication factor: an ephemeral bearer secret.
///
/// Tailscale already answers *which tailnet user* is calling, and Serve proves
/// it by injecting an identity header. That is a strong network boundary, but
/// the threat model (T18) records why it is not treated as sufficient on its
/// own: whoever controls the Tailscale account can place a new node inside the
/// overlay, and if reachability alone were authorization that node would read
/// snapshots freely. So reachability and possession are required together.
///
/// The secret is ephemeral by construction. It is generated per run, never
/// written to the repository, never logged, and never placed in a snapshot.
public struct UsageSyncTransportSecret: Sendable {
    /// Minimum accepted entropy. 256 bits is far beyond what a private-overlay
    /// endpoint needs, and costs nothing.
    public static let minimumByteCount = 32

    private let bytes: [UInt8]

    public enum LoadFailure: Error, Equatable, CustomStringConvertible {
        case unreadable
        case tooShort(found: Int, minimum: Int)
        case insecurePermissions(found: UInt16)

        public var description: String {
            switch self {
            case .unreadable:
                return "secret file could not be read"
            case .tooShort(let found, let minimum):
                return "secret is \(found) bytes; minimum is \(minimum)"
            case .insecurePermissions(let found):
                return "secret file mode is \(String(found, radix: 8)); required 600"
            }
        }
    }

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Generates a fresh secret from the system CSPRNG.
    public static func generate(byteCount: Int = minimumByteCount) -> UsageSyncTransportSecret {
        // `SystemRandomNumberGenerator` is the platform CSPRNG (arc4random on
        // Darwin), which is what a credential requires.
        var buffer = [UInt8](repeating: 0, count: max(byteCount, minimumByteCount))
        for index in buffer.indices {
            buffer[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return UsageSyncTransportSecret(bytes: buffer)
    }

    /// Builds a secret from an already-known string, for tests and for the
    /// probe reading its scratch file.
    public static func fromString(_ value: String) throws -> UsageSyncTransportSecret {
        let bytes = Array(value.utf8)
        guard bytes.count >= minimumByteCount else {
            throw LoadFailure.tooShort(found: bytes.count, minimum: minimumByteCount)
        }
        return UsageSyncTransportSecret(bytes: bytes)
    }

    /// Reads a secret from a file that must be owner-read/write only.
    ///
    /// The permission check is part of the contract, not a nicety: a
    /// world-readable secret on a shared machine defeats the entire second
    /// factor, and failing closed here is cheaper than discovering it later.
    public static func load(contentsOfFile path: String) throws -> UsageSyncTransportSecret {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: path),
              let posix = attributes[.posixPermissions] as? NSNumber else {
            throw LoadFailure.unreadable
        }
        let mode = posix.uint16Value & 0o777
        guard mode == 0o600 else {
            throw LoadFailure.insecurePermissions(found: mode)
        }
        guard let data = manager.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            throw LoadFailure.unreadable
        }
        return try fromString(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Renders the secret for the one legitimate consumer: a client that must
    /// present it. Never called on a response path.
    public func presentedValue() -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// Hex form, used when generating a scratch file.
    public static func generateHexString(byteCount: Int = minimumByteCount) -> String {
        let secret = generate(byteCount: byteCount)
        return secret.bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares a candidate in time independent of *where* it first differs.
    ///
    /// A short-circuiting `==` on a credential leaks the matching prefix length
    /// through timing, which is enough to recover a secret byte by byte given
    /// enough attempts. Length is compared first and separately — that much is
    /// unavoidable and harmless — and the byte loop then always runs to
    /// completion over a fixed span.
    public func matches(_ candidate: String) -> Bool {
        guard !bytes.isEmpty else { return false }
        let candidateBytes = Array(candidate.utf8)
        var difference: UInt8 = candidateBytes.count == bytes.count ? 0 : 1
        for index in 0..<bytes.count {
            let expected = bytes[index]
            let actual = index < candidateBytes.count ? candidateBytes[index] : 0
            difference |= expected ^ actual
        }
        return difference == 0
    }

    public var byteCount: Int { bytes.count }
}
