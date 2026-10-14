import Foundation

/// The one-time copy of preferences from UsageBar's former bundle identifier.
///
/// UsageBar 2.3.4 and earlier ran as `local.codex.usagebar`, so every
/// preference — provider connections, settings and the usage history — lives
/// in that defaults domain. The app now runs as `com.akwnnwastaken.usagebar`,
/// whose domain starts empty. Without this copy an upgrade would silently
/// disconnect both providers and drop the recorded history.
///
/// The copy is deliberately bounded:
/// - it runs only inside the shipped bundle, so a test runner or an unbundled
///   `swift run` build never reads another domain;
/// - before it has run, the legacy value wins over one already in the current
///   domain: only a pre-release build of the identifier change can have
///   written there, for example the "not connected" fallback a first launch
///   records, and the upgrade must restore the user's real choices. Keys only
///   the current domain has are kept;
/// - once it has run it never touches the current domain again;
/// - it runs once, recorded by `completedKey`, even when there is nothing to
///   copy;
/// - it leaves the legacy domain untouched, so an older build still finds its
///   own preferences.
///
/// The domain holds only non-secret preferences and the timestamp/percentage
/// history; credentials are never stored in `UserDefaults`.
public enum LegacyBundlePreferenceMigration {
    public static let legacyDomain = "local.codex.usagebar"
    public static let currentBundleIdentifier = "com.akwnnwastaken.usagebar"
    public static let completedKey = "migration.legacy-bundle-identifier.completed"

    /// Copies every legacy value into `defaults` and returns how many were
    /// copied.
    ///
    /// `currentDomain` and `legacyDomain` are the persistent domains as stored,
    /// passed in rather than read here so the policy can be exercised against a
    /// throwaway suite. The completion marker is read from the persistent
    /// domain, not `defaults.object(forKey:)`, so a global or registered
    /// default can never stand in for a copy that did not happen.
    @discardableResult
    public static func run(
        defaults: UserDefaults,
        currentDomain: [String: Any],
        legacyDomain: [String: Any]?,
        bundleIdentifier: String?
    ) -> Int {
        guard bundleIdentifier == currentBundleIdentifier,
              currentDomain[completedKey] == nil
        else { return 0 }

        var copied = 0
        for (key, value) in legacyDomain ?? [:]
        where key != completedKey {
            defaults.set(value, forKey: key)
            copied += 1
        }
        defaults.set(true, forKey: completedKey)
        return copied
    }
}
