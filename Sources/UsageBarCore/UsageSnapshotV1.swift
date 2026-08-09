import Foundation

/// Stable provider identifiers used by the public v1 telemetry contract.
public enum UsageProviderIDV1: String, Codable, CaseIterable, Sendable {
    case codex
    case claude
}

/// Provider collection state represented independently from UsageBar UI state.
public enum ProviderStateV1: String, Codable, Sendable {
    case disabled
    case unavailable
    case fresh
    case stale
}

/// Stable semantic kinds for normalized quota windows.
public enum UsageWindowKindV1: String, Codable, Sendable {
    case fiveHour
    case weekly
    case duration
    case unknown
}

/// Small, allowlisted public failure categories. Associated internal error text
/// is deliberately discarded before this boundary.
public enum ProviderErrorCodeV1: String, Codable, Sendable {
    case noData = "no_data"
    case notFound = "not_found"
    case untrustedExecutable = "untrusted_executable"
    case notAuthenticated = "not_authenticated"
    case timedOut = "timed_out"
    case unreadable
    case incompatible
    case commandFailed = "command_failed"
    case launchFailed = "launch_failed"
    case outputTooLarge = "output_too_large"
}

public struct ProviderErrorV1: Codable, Equatable, Sendable {
    public let code: ProviderErrorCodeV1

    public init(code: ProviderErrorCodeV1) {
        self.code = code
    }
}

public enum UsageSnapshotV1ValidationError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case invalidProviderCardinality(UsageProviderIDV1, count: Int)
    case invalidProviderState(UsageProviderIDV1, ProviderStateV1)
    case invalidUsedPercent(Int)
    case invalidDurationMinutes(Int)
}

public struct UsageWindowV1: Codable, Equatable, Sendable {
    public let kind: UsageWindowKindV1
    public let durationMinutes: Int?
    public let usedPercent: Int
    public let resetAt: Date?

    public init(
        kind: UsageWindowKindV1,
        durationMinutes: Int?,
        usedPercent: Int,
        resetAt: Date?
    ) throws {
        guard (0...100).contains(usedPercent) else {
            throw UsageSnapshotV1ValidationError.invalidUsedPercent(usedPercent)
        }
        if let durationMinutes, durationMinutes <= 0 {
            throw UsageSnapshotV1ValidationError.invalidDurationMinutes(durationMinutes)
        }
        if kind == .duration, durationMinutes == nil {
            throw UsageSnapshotV1ValidationError.invalidDurationMinutes(0)
        }

        self.kind = kind
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent
        self.resetAt = resetAt
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case durationMinutes
        case usedPercent
        case resetAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.durationMinutes) else {
            throw DecodingError.keyNotFound(
                CodingKeys.durationMinutes,
                .init(codingPath: container.codingPath, debugDescription: "Required nullable field is missing.")
            )
        }
        guard container.contains(.resetAt) else {
            throw DecodingError.keyNotFound(
                CodingKeys.resetAt,
                .init(codingPath: container.codingPath, debugDescription: "Required nullable field is missing.")
            )
        }
        try self.init(
            kind: container.decode(UsageWindowKindV1.self, forKey: .kind),
            durationMinutes: container.decodeIfPresent(Int.self, forKey: .durationMinutes),
            usedPercent: container.decode(Int.self, forKey: .usedPercent),
            resetAt: container.decodeIfPresent(Date.self, forKey: .resetAt)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(usedPercent, forKey: .usedPercent)
        try container.encode(resetAt, forKey: .resetAt)
    }
}

public struct ProviderSnapshotV1: Codable, Equatable, Sendable {
    public let id: UsageProviderIDV1
    public let state: ProviderStateV1
    public let lastSuccessfulAt: Date?
    public let error: ProviderErrorV1?
    public let windows: [UsageWindowV1]

    public init(
        id: UsageProviderIDV1,
        state: ProviderStateV1,
        lastSuccessfulAt: Date?,
        error: ProviderErrorV1?,
        windows: [UsageWindowV1]
    ) throws {
        let isValid: Bool
        switch state {
        case .disabled:
            isValid = lastSuccessfulAt == nil && error == nil && windows.isEmpty
        case .unavailable:
            isValid = lastSuccessfulAt == nil && error != nil && windows.isEmpty
        case .fresh:
            isValid = lastSuccessfulAt != nil && error == nil && !windows.isEmpty
        case .stale:
            isValid = lastSuccessfulAt != nil && error != nil && !windows.isEmpty
        }
        guard isValid else {
            throw UsageSnapshotV1ValidationError.invalidProviderState(id, state)
        }

        self.id = id
        self.state = state
        self.lastSuccessfulAt = lastSuccessfulAt
        self.error = error
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case state
        case lastSuccessfulAt
        case error
        case windows
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard container.contains(.lastSuccessfulAt) else {
            throw DecodingError.keyNotFound(
                CodingKeys.lastSuccessfulAt,
                .init(codingPath: container.codingPath, debugDescription: "Required nullable field is missing.")
            )
        }
        guard container.contains(.error) else {
            throw DecodingError.keyNotFound(
                CodingKeys.error,
                .init(codingPath: container.codingPath, debugDescription: "Required nullable field is missing.")
            )
        }
        try self.init(
            id: container.decode(UsageProviderIDV1.self, forKey: .id),
            state: container.decode(ProviderStateV1.self, forKey: .state),
            lastSuccessfulAt: container.decodeIfPresent(Date.self, forKey: .lastSuccessfulAt),
            error: container.decodeIfPresent(ProviderErrorV1.self, forKey: .error),
            windows: container.decode([UsageWindowV1].self, forKey: .windows)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(state, forKey: .state)
        try container.encode(lastSuccessfulAt, forKey: .lastSuccessfulAt)
        try container.encode(error, forKey: .error)
        try container.encode(windows, forKey: .windows)
    }
}

public struct UsageSnapshotV1: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let observedAt: Date
    public let providers: [ProviderSnapshotV1]

    public init(observedAt: Date, providers: [ProviderSnapshotV1]) throws {
        self.schemaVersion = Self.currentSchemaVersion
        self.observedAt = observedAt
        self.providers = try Self.validatedProviders(providers)
    }

    private init(schemaVersion: Int, observedAt: Date, providers: [ProviderSnapshotV1]) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw UsageSnapshotV1ValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        self.schemaVersion = schemaVersion
        self.observedAt = observedAt
        self.providers = try Self.validatedProviders(providers)
    }

    private static func validatedProviders(_ providers: [ProviderSnapshotV1]) throws -> [ProviderSnapshotV1] {
        for id in UsageProviderIDV1.allCases {
            let count = providers.filter { $0.id == id }.count
            guard count == 1 else {
                throw UsageSnapshotV1ValidationError.invalidProviderCardinality(id, count: count)
            }
        }
        return UsageProviderIDV1.allCases.compactMap { id in
            providers.first { $0.id == id }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case observedAt
        case providers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            observedAt: container.decode(Date.self, forKey: .observedAt),
            providers: container.decode([ProviderSnapshotV1].self, forKey: .providers)
        )
    }
}

/// Pure input boundary for projecting the current accepted UsageBar state.
/// Connection flags are separate because disabled providers are absent from the
/// existing in-memory provider dictionary.
public struct UsageSnapshotV1ProjectionInput {
    public let codexIsEnabled: Bool
    public let claudeIsEnabled: Bool
    public let usages: [String: ProviderUsage]

    public init(codexIsEnabled: Bool, claudeIsEnabled: Bool, usages: [String: ProviderUsage]) {
        self.codexIsEnabled = codexIsEnabled
        self.claudeIsEnabled = claudeIsEnabled
        self.usages = usages
    }
}

public enum UsageSnapshotV1Projection {
    public static func project(
        _ input: UsageSnapshotV1ProjectionInput,
        observedAt: Date
    ) throws -> UsageSnapshotV1 {
        let providers = try [
            provider(
                id: .codex,
                isEnabled: input.codexIsEnabled,
                usage: input.usages["Codex"]
            ),
            provider(
                id: .claude,
                isEnabled: input.claudeIsEnabled,
                usage: input.usages["Claude Code"]
            )
        ]
        return try UsageSnapshotV1(observedAt: observedAt, providers: providers)
    }

    private static func provider(
        id: UsageProviderIDV1,
        isEnabled: Bool,
        usage: ProviderUsage?
    ) throws -> ProviderSnapshotV1 {
        guard isEnabled else {
            return try ProviderSnapshotV1(
                id: id,
                state: .disabled,
                lastSuccessfulAt: nil,
                error: nil,
                windows: []
            )
        }

        guard let usage else {
            return try unavailable(id: id, issue: nil)
        }

        guard !usage.windows.isEmpty else {
            guard usage.lastSuccessfulAt == nil else {
                throw UsageSnapshotV1ValidationError.invalidProviderState(id, .unavailable)
            }
            return try unavailable(id: id, issue: usage.error)
        }

        guard let lastSuccessfulAt = usage.lastSuccessfulAt else {
            throw UsageSnapshotV1ValidationError.invalidProviderState(
                id,
                usage.error == nil ? .fresh : .stale
            )
        }

        let windows = try usage.windows.map { window in
            try UsageWindowV1(
                kind: kind(for: window.kind),
                durationMinutes: window.durationMinutes,
                usedPercent: window.usedPercent,
                resetAt: window.resetsAt
            )
        }
        let publicError = usage.error.map { ProviderErrorV1(code: errorCode(for: $0)) }
        return try ProviderSnapshotV1(
            id: id,
            state: publicError == nil ? .fresh : .stale,
            lastSuccessfulAt: lastSuccessfulAt,
            error: publicError,
            windows: windows
        )
    }

    private static func unavailable(
        id: UsageProviderIDV1,
        issue: ProviderIssue?
    ) throws -> ProviderSnapshotV1 {
        let code = issue.map(errorCode(for:)) ?? .noData
        return try ProviderSnapshotV1(
            id: id,
            state: .unavailable,
            lastSuccessfulAt: nil,
            error: ProviderErrorV1(code: code),
            windows: []
        )
    }

    private static func kind(for kind: UsageWindowKind) -> UsageWindowKindV1 {
        switch kind {
        case .fiveHour: return .fiveHour
        case .weekly: return .weekly
        case .duration: return .duration
        case .unknown: return .unknown
        }
    }

    private static func errorCode(for issue: ProviderIssue) -> ProviderErrorCodeV1 {
        switch issue {
        case .refreshing, .noData:
            return .noData
        case .codexNotFound, .claudeNotFound:
            return .notFound
        case .codexUntrustedExecutable, .claudeUntrustedExecutable:
            return .untrustedExecutable
        case .claudeNotLoggedIn:
            return .notAuthenticated
        case .codexTimedOut, .claudeUsageTimedOut:
            return .timedOut
        case .codexUsageUnavailable, .codexLimitMissing, .codexEmptyResponse, .claudeUsageUnreadable:
            return .unreadable
        case .codexIncompatible:
            return .incompatible
        case .codexCommandFailed:
            return .commandFailed
        case .codexLaunchFailed, .claudeLaunchFailed:
            return .launchFailed
        case .outputTooLarge:
            return .outputTooLarge
        }
    }
}

/// Canonical v1 JSON codec. The wire format uses sorted object keys and UTC
/// RFC 3339 timestamps with millisecond precision.
public enum UsageSnapshotV1JSON {
    public static func encode(_ snapshot: UsageSnapshotV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestampString(from: date))
        }
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) throws -> UsageSnapshotV1 {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard value.hasSuffix("Z"), let date = timestampDate(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an RFC 3339 UTC timestamp with millisecond precision."
                )
            }
            return date
        }
        return try decoder.decode(UsageSnapshotV1.self, from: data)
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func timestampDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
