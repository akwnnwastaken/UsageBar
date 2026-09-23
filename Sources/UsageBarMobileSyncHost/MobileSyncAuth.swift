import Foundation
import CryptoKit
import UsageBarPairing

/// A SHA-256 digest, kept as bytes so every comparison is explicit.
public struct MobileSyncDigest: Equatable, Sendable {
    public static let byteCount = 32

    public let bytes: [UInt8]

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    public static func of(_ value: String) -> MobileSyncDigest {
        MobileSyncDigest(bytes: Array(SHA256.hash(data: Data(value.utf8))))
    }

    public init?(hexEncoded text: String) {
        guard text.count == Self.byteCount * 2 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.byteCount)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.bytes = bytes
    }

    public var hexEncoded: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Constant-time, like every other secret comparison in the lab. A digest
    /// is not itself a secret, but the answer to "does this digest match"
    /// gates a credential, and a timing side channel on that answer would let
    /// a caller search for a matching bearer far faster than brute force.
    public func matches(_ other: MobileSyncDigest) -> Bool {
        UsageBarConstantTime.equal(bytes, other.bytes)
    }

    public static func == (lhs: MobileSyncDigest, rhs: MobileSyncDigest) -> Bool {
        lhs.matches(rhs)
    }
}

/// How a Tailscale identity becomes something safe to persist.
///
/// A Serve-injected `Tailscale-User-Login` is an email address: personal data,
/// and exactly the kind of thing that should not sit in a Keychain item, a log
/// or a crash report for the lifetime of a pairing. The Mac keeps only its
/// digest, which answers the one question it needs to answer — "is this the
/// same caller that paired?" — and nothing else.
public enum MobileSyncTailscaleIdentity {
    /// Normalization must be identical at pairing time and at every later
    /// request, or the binding would fail whenever Serve changed the casing of
    /// a header. Trim, lowercase, and nothing more clever than that.
    public static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.utf8.count <= 320 else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { return nil }
        return trimmed
    }

    public static func digest(of raw: String) -> MobileSyncDigest? {
        normalized(raw).map(MobileSyncDigest.of)
    }
}

/// The long-lived mobile credential, as the Mac remembers it.
///
/// The raw bearer is **not** here, and there is no property that could hold it.
/// The Mac issues one during pairing, returns it to the phone over the
/// already-authenticated HTTPS response, and keeps only its digest — so a Mac
/// Keychain dump, a backup or a stolen laptop yields nothing that can be
/// replayed against the endpoint.
public struct MobileSyncAuthRecord: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let bearerDigest: MobileSyncDigest
    /// The tailnet identity that performed the pairing. A bearer alone is not
    /// enough: it must be presented by the same identity Serve proved at
    /// pairing time, so a leaked token used from another tailnet node fails.
    public let identityDigest: MobileSyncDigest
    public let createdAt: Date

    public init(
        schemaVersion: Int = MobileSyncAuthRecord.currentSchemaVersion,
        bearerDigest: MobileSyncDigest,
        identityDigest: MobileSyncDigest,
        createdAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.bearerDigest = bearerDigest
        self.identityDigest = identityDigest
        self.createdAt = createdAt
    }

    /// Both factors, both constant-time, and both required.
    public func authorizes(bearer: String, identity: String) -> Bool {
        guard let identityDigest = MobileSyncTailscaleIdentity.digest(of: identity) else {
            return false
        }
        let bearerMatches = self.bearerDigest.matches(MobileSyncDigest.of(bearer))
        let identityMatches = self.identityDigest.matches(identityDigest)
        // Both computed before the `&&`, so the work done does not depend on
        // which factor failed.
        return bearerMatches && identityMatches
    }

    // MARK: - Persistence form

    private enum Key: String, CaseIterable {
        case schemaVersion
        case bearerDigest
        case identityDigest
        case createdAt
    }

    /// Encoded explicitly, field by field. A property added to this type later
    /// cannot start being written to the Keychain without this method changing.
    public func encoded() -> Data {
        let object: [String: Any] = [
            Key.schemaVersion.rawValue: schemaVersion,
            Key.bearerDigest.rawValue: bearerDigest.hexEncoded,
            Key.identityDigest.rawValue: identityDigest.hexEncoded,
            Key.createdAt.rawValue: createdAt.timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            preconditionFailure("auth record must always encode")
        }
        return data
    }

    public static func decode(_ data: Data) -> MobileSyncAuthRecord? {
        guard data.count <= 4_096,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let schemaVersion = dictionary[Key.schemaVersion.rawValue] as? Int,
              schemaVersion == currentSchemaVersion,
              let bearerHex = dictionary[Key.bearerDigest.rawValue] as? String,
              let identityHex = dictionary[Key.identityDigest.rawValue] as? String,
              let createdAt = dictionary[Key.createdAt.rawValue] as? TimeInterval,
              let bearerDigest = MobileSyncDigest(hexEncoded: bearerHex),
              let identityDigest = MobileSyncDigest(hexEncoded: identityHex)
        else { return nil }
        return MobileSyncAuthRecord(
            schemaVersion: schemaVersion,
            bearerDigest: bearerDigest,
            identityDigest: identityDigest,
            createdAt: Date(timeIntervalSince1970: createdAt)
        )
    }
}

/// The long-lived bearer, at the one moment it exists in the clear.
public enum MobileSyncBearer {
    /// 256 bits, base64url. It is generated, returned to the phone once, and
    /// then exists only as a digest on this machine.
    public static let byteCount = 32

    public static func generate() -> String {
        var buffer = [UInt8](repeating: 0, count: byteCount)
        for index in buffer.indices {
            buffer[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
