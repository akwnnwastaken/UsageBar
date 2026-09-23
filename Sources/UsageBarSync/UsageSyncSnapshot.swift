import Foundation

/// Schema-v1 sanitized usage snapshot: the only shape that may cross the
/// UsageBar mobile sync boundary.
///
/// The contract lives in `shared/sync-schema/usage-snapshot.schema.json`; these
/// types mirror it field for field and deliberately have **no** storage for
/// anything the contract forbids. There is no property — and therefore no
/// serialization path — for a credential, a raw provider response, a provider
/// error, a command line, a filesystem path, a host or user name, an account
/// identifier, or any transport detail such as a URL, port, Tailscale address
/// or MagicDNS name. Prohibited data cannot be leaked by accident here because
/// there is nowhere to put it.
///
/// Nothing in this module talks to a network. The transport class selected by
/// the owner (a private Tailscale overlay) is recorded in
/// `docs/mobile-transport-decision.md`; none of it is implemented yet, and the
/// payload is deliberately independent of it.
public struct UsageSyncSnapshot: Codable, Equatable, Sendable {
    /// Wire contract version. Independent of the UsageBar product release
    /// version, which never appears in the payload.
    public let schemaVersion: Int

    /// When this *document* was built. Never a measurement time — see
    /// `UsageSyncMeasurement.measuredAt`.
    public let generatedAt: Date

    /// An empty array means no provider is connected. A non-empty array in
    /// which nothing is `collecting` means every connected provider is paused.
    public let providers: [UsageSyncProvider]

    public static let currentSchemaVersion = 1

    public init(
        schemaVersion: Int = UsageSyncSnapshot.currentSchemaVersion,
        generatedAt: Date,
        providers: [UsageSyncProvider]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.providers = providers
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case providers
    }
}

/// One provider's lifecycle state and, when the desktop holds one, its retained
/// measurement.
///
/// `connected` and `collecting` are two independent facts, exactly as
/// `ProviderCollectionPolicy` models them: pausing a provider leaves it
/// connected, which is the whole point of a pause, so a single flag could not
/// express both. A paused provider keeps its measurement.
public struct UsageSyncProvider: Codable, Equatable, Sendable {
    /// Stable lowercase slug — never a localized or display name.
    public let providerId: String

    /// Whether the provider's configuration is retained on the desktop.
    public let connected: Bool

    /// Whether the desktop may currently initiate readings for it.
    public let collecting: Bool

    /// The retained last successful reading, absent when there is none.
    public let measurement: UsageSyncMeasurement?

    public init(
        providerId: String,
        connected: Bool,
        collecting: Bool,
        measurement: UsageSyncMeasurement? = nil
    ) {
        self.providerId = providerId
        self.connected = connected
        self.collecting = collecting
        self.measurement = measurement
    }

    private enum CodingKeys: String, CodingKey {
        case providerId
        case connected
        case collecting
        case measurement
    }
}

/// A provider's retained accepted reading.
public struct UsageSyncMeasurement: Codable, Equatable, Sendable {
    /// When this reading was taken and accepted — the desktop's
    /// `lastSuccessfulAt`. It does not advance because a later refresh failed,
    /// because the provider was paused, or because a new snapshot was built.
    /// This is the only correct basis for freshness.
    public let measuredAt: Date

    /// The value UsageBar itself presents, already chosen by the product's
    /// provider-specific headline policy. Consumers must not recompute it.
    public let headlineRemainingPercent: Int

    /// Which entry of `windows` produced `headlineRemainingPercent`.
    public let headlineWindowId: String

    public let windows: [UsageSyncWindow]

    public init(
        measuredAt: Date,
        headlineRemainingPercent: Int,
        headlineWindowId: String,
        windows: [UsageSyncWindow]
    ) {
        self.measuredAt = measuredAt
        self.headlineRemainingPercent = headlineRemainingPercent
        self.headlineWindowId = headlineWindowId
        self.windows = windows
    }

    private enum CodingKeys: String, CodingKey {
        case measuredAt
        case headlineRemainingPercent
        case headlineWindowId
        case windows
    }
}

/// The structured category of a quota window.
///
/// `duration` and `unknown` are the forward-compatibility escape hatches: a
/// future provider window with a known length arrives as `duration`, and one
/// whose length the desktop cannot determine arrives as `unknown`. Neither
/// requires a schema version bump.
public enum UsageSyncWindowKind: String, Codable, Equatable, Sendable, CaseIterable {
    case fiveHour
    case weekly
    case weeklyScoped
    case duration
    case unknown
}

/// One quota window.
///
/// The qualifier fields are mutually exclusive by kind; `UsageSyncValidator`
/// enforces that. They are stored plainly rather than modelled as an enum with
/// associated values so that a *decoded* inconsistent payload can be
/// represented and then rejected, instead of failing to decode with an opaque
/// error that says nothing about which invariant broke.
public struct UsageSyncWindow: Codable, Equatable, Sendable {
    /// Canonical identity, matching the product's own `historyKey` spelling.
    public let windowId: String
    public let kind: UsageSyncWindowKind

    /// Model or model-family slug. Required for, and only for, `weeklyScoped`.
    public let scope: String?

    /// Window length in minutes. Required for `duration`; conventional for
    /// `fiveHour` (300) and `weekly` (10080); never present for `unknown`.
    public let durationMinutes: Int?

    /// Zero-based ordinal. Required for, and only for, `unknown`.
    public let position: Int?

    public let remainingPercent: Int
    public let resetsAt: Date?

    public init(
        windowId: String,
        kind: UsageSyncWindowKind,
        scope: String? = nil,
        durationMinutes: Int? = nil,
        position: Int? = nil,
        remainingPercent: Int,
        resetsAt: Date? = nil
    ) {
        self.windowId = windowId
        self.kind = kind
        self.scope = scope
        self.durationMinutes = durationMinutes
        self.position = position
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    private enum CodingKeys: String, CodingKey {
        case windowId
        case kind
        case scope
        case durationMinutes
        case position
        case remainingPercent
        case resetsAt
    }
}
