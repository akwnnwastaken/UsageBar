import Foundation

/// Which bundle is allowed to run Mobile Sync at all.
///
/// UsageBar links this module unconditionally, but containing the code is not
/// permission to run it. A test runner, a `swift run` build, or any bundle that
/// is not UsageBar itself must never open a listener, hold a mobile credential
/// or offer pairing merely because the executable was linked against this
/// module. The gate is the *bundle identity*, checked at runtime, because that
/// is the one thing a build cannot accidentally inherit.
public enum MobileSyncIdentity {
    /// UsageBar. The single identity permitted to run Mobile Sync.
    ///
    /// There is deliberately no second entry. The Mobile Lab host
    /// (`com.usagebar.mobilelab.host`) was a separate application with its own
    /// preference domain and its own Keychain access; it is not part of this
    /// product and must not be able to run this code. A dual allowlist would
    /// mean a lab build and a shipping build could serve the same phone from
    /// the same machine, which is precisely the confusion the identity gate
    /// exists to prevent.
    public static let productionBundleIdentifier = "local.codex.usagebar"

    /// The Keychain service namespace for the mobile auth record.
    ///
    /// Distinct from the iOS app's service, from anything a provider CLI uses,
    /// and from the Mobile Lab host's former service. Nothing migrates into it:
    /// a device paired with the standalone lab host is not paired with
    /// UsageBar, and must pair again.
    public static let keychainService = "local.codex.usagebar.mobile-sync"

    /// The fixed loopback port. A stable port keeps the externally configured
    /// Tailscale Serve mapping stable across restarts, which an ephemeral port
    /// could not.
    public static let loopbackPort: UInt16 = 18642

    /// Whether Mobile Sync may run in this process.
    public static func isEnabledForBundle(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == productionBundleIdentifier
    }

    /// The running process's answer. `Bundle.main.bundleIdentifier` is nil for
    /// a bare executable — a test runner, a `swift run` — and nil must mean
    /// "not UsageBar", so an unbundled build cannot start a listener either.
    public static var isEnabledForCurrentProcess: Bool {
        isEnabledForBundle(Bundle.main.bundleIdentifier)
    }
}
