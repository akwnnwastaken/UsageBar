import Foundation

/// Why a snapshot is not valid.
///
/// Every case carries only structural identifiers the contract already
/// transmits — provider ids, window ids, kinds, counts. No case carries raw
/// provider text, a provider error, a credential or any transport detail, so a
/// validation failure can be logged in full without leaking anything the
/// snapshot itself was designed to exclude.
public enum UsageSyncValidationError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(found: Int, expected: Int)
    case duplicateProviderId(String)
    case duplicateWindowId(providerId: String, windowId: String)
    case headlineWindowNotFound(providerId: String, headlineWindowId: String)
    case headlineDisagreesWithWindow(providerId: String, windowId: String)
    case disconnectedProviderHasMeasurement(providerId: String)
    case disconnectedProviderIsCollecting(providerId: String)
    case percentageOutOfRange(providerId: String, windowId: String?, value: Int)
    case measuredAfterGenerated(providerId: String)
    case missingQualifier(providerId: String, windowId: String, kind: UsageSyncWindowKind, qualifier: String)
    case unexpectedQualifier(providerId: String, windowId: String, kind: UsageSyncWindowKind, qualifier: String)
    case windowIdDisagreesWithKind(providerId: String, windowId: String, expected: String)
    case emptyWindows(providerId: String)
    case malformedProviderId(String)

    public var description: String {
        switch self {
        case .unsupportedSchemaVersion(let found, let expected):
            return "unsupported schemaVersion \(found), expected \(expected)"
        case .duplicateProviderId(let id):
            return "duplicate providerId '\(id)'"
        case .duplicateWindowId(let providerId, let windowId):
            return "duplicate windowId '\(windowId)' in provider '\(providerId)'"
        case .headlineWindowNotFound(let providerId, let windowId):
            return "headlineWindowId '\(windowId)' does not resolve in provider '\(providerId)'"
        case .headlineDisagreesWithWindow(let providerId, let windowId):
            return "headlineRemainingPercent disagrees with window '\(windowId)' in provider '\(providerId)'"
        case .disconnectedProviderHasMeasurement(let providerId):
            return "disconnected provider '\(providerId)' carries a measurement"
        case .disconnectedProviderIsCollecting(let providerId):
            return "disconnected provider '\(providerId)' is marked collecting"
        case .percentageOutOfRange(let providerId, let windowId, let value):
            let whereAt = windowId.map { "window '\($0)'" } ?? "headline"
            return "percentage \(value) out of range 0...100 at \(whereAt) in provider '\(providerId)'"
        case .measuredAfterGenerated(let providerId):
            return "measuredAt is later than generatedAt in provider '\(providerId)'"
        case .missingQualifier(let providerId, let windowId, let kind, let qualifier):
            return "window '\(windowId)' of kind '\(kind.rawValue)' in provider '\(providerId)' is missing required '\(qualifier)'"
        case .unexpectedQualifier(let providerId, let windowId, let kind, let qualifier):
            return "window '\(windowId)' of kind '\(kind.rawValue)' in provider '\(providerId)' must not carry '\(qualifier)'"
        case .windowIdDisagreesWithKind(let providerId, let windowId, let expected):
            return "windowId '\(windowId)' in provider '\(providerId)' disagrees with its kind, expected '\(expected)'"
        case .emptyWindows(let providerId):
            return "provider '\(providerId)' has a measurement with no windows"
        case .malformedProviderId(let id):
            return "malformed providerId '\(id)'"
        }
    }
}

/// Pure validation of the invariants JSON Schema cannot express, plus the
/// range and state rules that matter enough to check twice.
///
/// Nothing here repairs a snapshot. An invalid snapshot produces a
/// deterministic error and is rejected whole, because silently fixing a payload
/// that crossed a trust boundary would hide exactly the corruption the check
/// exists to catch.
public enum UsageSyncValidator {
    public static func validate(_ snapshot: UsageSyncSnapshot) throws {
        guard snapshot.schemaVersion == UsageSyncSnapshot.currentSchemaVersion else {
            throw UsageSyncValidationError.unsupportedSchemaVersion(
                found: snapshot.schemaVersion,
                expected: UsageSyncSnapshot.currentSchemaVersion
            )
        }

        var seenProviderIds = Set<String>()
        for provider in snapshot.providers {
            guard UsageSyncIdentity.isValidProviderId(provider.providerId) else {
                throw UsageSyncValidationError.malformedProviderId(provider.providerId)
            }
            guard seenProviderIds.insert(provider.providerId).inserted else {
                throw UsageSyncValidationError.duplicateProviderId(provider.providerId)
            }
            try validate(provider, generatedAt: snapshot.generatedAt)
        }
    }

    private static func validate(_ provider: UsageSyncProvider, generatedAt: Date) throws {
        let id = provider.providerId

        if !provider.connected {
            guard !provider.collecting else {
                throw UsageSyncValidationError.disconnectedProviderIsCollecting(providerId: id)
            }
            guard provider.measurement == nil else {
                throw UsageSyncValidationError.disconnectedProviderHasMeasurement(providerId: id)
            }
        }

        guard let measurement = provider.measurement else { return }

        guard !measurement.windows.isEmpty else {
            throw UsageSyncValidationError.emptyWindows(providerId: id)
        }
        guard (0...100).contains(measurement.headlineRemainingPercent) else {
            throw UsageSyncValidationError.percentageOutOfRange(
                providerId: id, windowId: nil, value: measurement.headlineRemainingPercent
            )
        }
        guard measurement.measuredAt <= generatedAt else {
            throw UsageSyncValidationError.measuredAfterGenerated(providerId: id)
        }

        var seenWindowIds = Set<String>()
        for window in measurement.windows {
            guard seenWindowIds.insert(window.windowId).inserted else {
                throw UsageSyncValidationError.duplicateWindowId(providerId: id, windowId: window.windowId)
            }
            try validate(window, providerId: id)
        }

        let matches = measurement.windows.filter { $0.windowId == measurement.headlineWindowId }
        guard matches.count == 1, let headlineWindow = matches.first else {
            throw UsageSyncValidationError.headlineWindowNotFound(
                providerId: id, headlineWindowId: measurement.headlineWindowId
            )
        }
        guard headlineWindow.remainingPercent == measurement.headlineRemainingPercent else {
            throw UsageSyncValidationError.headlineDisagreesWithWindow(
                providerId: id, windowId: headlineWindow.windowId
            )
        }
    }

    private static func validate(_ window: UsageSyncWindow, providerId: String) throws {
        guard (0...100).contains(window.remainingPercent) else {
            throw UsageSyncValidationError.percentageOutOfRange(
                providerId: providerId, windowId: window.windowId, value: window.remainingPercent
            )
        }

        func require(_ value: Any?, _ name: String) throws {
            guard value != nil else {
                throw UsageSyncValidationError.missingQualifier(
                    providerId: providerId, windowId: window.windowId, kind: window.kind, qualifier: name
                )
            }
        }
        func forbid(_ value: Any?, _ name: String) throws {
            guard value == nil else {
                throw UsageSyncValidationError.unexpectedQualifier(
                    providerId: providerId, windowId: window.windowId, kind: window.kind, qualifier: name
                )
            }
        }

        switch window.kind {
        case .fiveHour, .weekly:
            try forbid(window.scope, "scope")
            try forbid(window.position, "position")
        case .weeklyScoped:
            try require(window.scope, "scope")
            try forbid(window.position, "position")
        case .duration:
            try require(window.durationMinutes, "durationMinutes")
            try forbid(window.scope, "scope")
            try forbid(window.position, "position")
        case .unknown:
            try require(window.position, "position")
            try forbid(window.scope, "scope")
            try forbid(window.durationMinutes, "durationMinutes")
        }

        if let expected = UsageSyncIdentity.expectedWindowId(for: window) {
            guard window.windowId == expected else {
                throw UsageSyncValidationError.windowIdDisagreesWithKind(
                    providerId: providerId, windowId: window.windowId, expected: expected
                )
            }
        }
    }
}
