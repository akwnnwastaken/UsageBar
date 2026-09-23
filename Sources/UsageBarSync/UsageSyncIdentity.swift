import Foundation
import UsageBarCore

/// How product identities become wire identities.
///
/// Both mappings reuse spellings the product already computes — window ids are
/// `UsageWindowKind.historyKey` verbatim — so the snapshot never invents a
/// second naming system that could drift from the desktop's own.
public enum UsageSyncIdentity {
    /// The wire id for a product provider name: lowercased, runs of
    /// non-alphanumerics collapsed to a single `-`.
    ///
    /// `"Codex"` becomes `"codex"` and `"Claude Code"` becomes `"claude-code"`,
    /// the two ids schema v1 documents. A name that normalizes to nothing
    /// yields `nil` rather than an unusable id, so the builder fails loudly
    /// instead of emitting a malformed snapshot.
    public static func providerId(forProductName name: String) -> String? {
        var slug = ""
        var pendingSeparator = false
        for character in name.lowercased().unicodeScalars {
            let isSafe = ("a"..."z").contains(character) || ("0"..."9").contains(character)
            if isSafe {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.unicodeScalars.append(character)
            } else {
                pendingSeparator = true
            }
        }
        return slug.isEmpty ? nil : slug
    }

    public static func isValidProviderId(_ id: String) -> Bool {
        !id.isEmpty && providerId(forProductName: id) == id
    }

    /// The wire window identity for a product window kind. This is exactly
    /// `UsageWindowKind.historyKey`, deliberately not a parallel spelling.
    public static func windowId(for kind: UsageWindowKind) -> String {
        kind.historyKey
    }

    /// The wire kind for a product window kind.
    public static func windowKind(for kind: UsageWindowKind) -> UsageSyncWindowKind {
        switch kind {
        case .fiveHour: return .fiveHour
        case .weekly: return .weekly
        case .weeklyScoped: return .weeklyScoped
        case .duration: return .duration
        case .unknown: return .unknown
        }
    }

    /// The identity a decoded window ought to carry, given its kind and
    /// qualifier, or `nil` when the qualifier needed to derive one is missing —
    /// in which case the qualifier check has already reported the real problem.
    public static func expectedWindowId(for window: UsageSyncWindow) -> String? {
        switch window.kind {
        case .fiveHour: return "five-hour"
        case .weekly: return "weekly"
        case .weeklyScoped: return window.scope.map { "weekly-\($0)" }
        case .duration: return window.durationMinutes.map { "duration-\($0)" }
        case .unknown: return window.position.map { "unknown-\($0)" }
        }
    }
}
