import Foundation

/// Deterministic local JSON encoding and decoding for schema-v1 snapshots.
///
/// "Local" is literal: this type turns a snapshot into `Data` and back. It does
/// not write to `UserDefaults`, does not persist anywhere, and does not send
/// anything. No transport exists yet.
///
/// Timestamps use one canonical representation — RFC 3339 in UTC, e.g.
/// `2026-01-15T14:05:00Z`. Decoding additionally accepts fractional seconds and
/// non-UTC offsets, because the contract permits them and a sender other than
/// this builder may legitimately produce them; encoding always normalizes to
/// UTC so output is stable.
public enum UsageSyncSerialization {
    /// Thrown when a timestamp is not a representation the contract allows.
    public struct MalformedTimestamp: Error, CustomStringConvertible {
        public let description = "timestamp is not a valid RFC 3339 instant"
    }

    private static let utcFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    public static func string(from date: Date) -> String {
        utcFormatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        utcFormatter.date(from: string) ?? fractionalFormatter.date(from: string)
    }

    /// Keys are sorted so a snapshot encodes byte-identically every time, which
    /// keeps tests and diffs readable. Consumers must not depend on key order:
    /// JSON objects are unordered and a later encoder change must stay free to
    /// reorder them.
    public static func encoder(sortedKeys: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        var formatting: JSONEncoder.OutputFormatting = [.withoutEscapingSlashes]
        if sortedKeys { formatting.insert(.sortedKeys) }
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let value = date(from: raw) else { throw MalformedTimestamp() }
            return value
        }
        return decoder
    }

    /// Encodes a snapshot, validating it first. An invalid snapshot is never
    /// serialized, so nothing malformed can be handed to a future transport.
    public static func encode(_ snapshot: UsageSyncSnapshot) throws -> Data {
        try UsageSyncValidator.validate(snapshot)
        return try encoder().encode(snapshot)
    }

    /// Decodes a snapshot and validates it. Everything arriving from outside is
    /// untrusted structured input: it is validated before it can be used, and a
    /// failure rejects the whole document rather than repairing it.
    public static func decode(_ data: Data) throws -> UsageSyncSnapshot {
        let snapshot = try decoder().decode(UsageSyncSnapshot.self, from: data)
        try UsageSyncValidator.validate(snapshot)
        return snapshot
    }

    /// Decodes without validating, for tests that need to observe a malformed
    /// payload being rejected by the validator rather than by the decoder.
    public static func decodeWithoutValidation(_ data: Data) throws -> UsageSyncSnapshot {
        try decoder().decode(UsageSyncSnapshot.self, from: data)
    }
}
