import Foundation
import UsageBarSync

/// What a system surface — a widget timeline entry or a Control Center control
/// value — has to show at a point in time.
enum UsageSurfaceState: Equatable {
    /// Fresh data from this evaluation's own fetch.
    case loaded(UsageSyncSnapshot)
    /// The previous validated reading, after a fetch that did not succeed.
    case cached(UsageSyncSnapshot)
    /// Credentials exist but there is nothing to show yet.
    case unavailable
    /// No connection is configured — or it has been forgotten.
    case notConfigured

    var snapshot: UsageSyncSnapshot? {
        switch self {
        case .loaded(let value), .cached(let value): return value
        case .unavailable, .notConfigured: return nil
        }
    }

    var isStale: Bool {
        if case .cached = self { return true }
        return false
    }
}

/// The one place that decides what an extension surface may display.
///
/// Widgets and controls live in the same extension, share the same keychain
/// group, the same HTTPS client and the same private snapshot cache, and they
/// must obey the same revocation rule. Writing that rule twice — once for the
/// timeline provider and once for the control value provider — is precisely how
/// the two would eventually disagree, and the disagreement would be invisible
/// until a forgotten connection kept showing usage in Control Center. So both
/// call this.
struct UsageSurfaceResolver {
    /// The extension's own validated snapshot cache.
    ///
    /// Widgets and controls deliberately share it: they run in the same
    /// extension, therefore the same container, so a second file would be two
    /// copies of the same bytes with two chances to go stale. The *app's* cache
    /// stays separate — that separation is the App-Group-free architecture, and
    /// it is unaffected by this.
    static let extensionCacheFileName = "widget-snapshot-v1.json"

    let store: ConnectionStore
    let cache: SnapshotCaching
    let client: SnapshotFetching

    init(
        store: ConnectionStore = KeychainConnectionStore(),
        cache: SnapshotCaching = FileSnapshotCache(fileName: UsageSurfaceResolver.extensionCacheFileName),
        client: SnapshotFetching = UsageSyncAPIClient()
    ) {
        self.store = store
        self.cache = cache
        self.client = client
    }

    /// The credential check runs *first*, and it is what makes revocation work.
    ///
    /// Without an App Group the app cannot reach into this extension's sandbox
    /// to delete its cache, so "Forget Connection" cannot erase what a widget
    /// or a control already holds. Instead the extension refuses to *display*
    /// an authenticated snapshot whenever the shared credentials are gone.
    ///
    /// Three outcomes, not two, and the third is the subtle one:
    ///
    /// - **missing** — revocation. Forget the cache, show nothing.
    /// - **temporarilyUnavailable** — the device is locked and the keychain is
    ///   simply not readable right now. This is *not* revocation. Treating it
    ///   as one would delete a good cached snapshot every time the screen went
    ///   off, and the user would watch their widget empty itself overnight.
    /// - **available** — fetch, and fall back to the cache on failure.
    ///
    /// Do not reorder this. Fetching, or reading the cache, before the
    /// credential check would let a forgotten connection keep showing usage.
    func resolve() async -> UsageSurfaceState {
        switch store.availability() {
        case .missing:
            cache.clear()
            return .notConfigured

        case .temporarilyUnavailable:
            // No credential in hand means no request: an unauthenticated fetch
            // would be answered 401, which this surface would then — correctly,
            // and disastrously — treat as revocation.
            if let cached = cache.load() { return .cached(cached) }
            return .unavailable

        case .available(let connection):
            do {
                let fetched = try await client.fetchSnapshot(using: connection)
                try? cache.store(fetched)
                return .loaded(fetched)
            } catch let error as SnapshotFetchError where error.revokesStoredCredential {
                // The desktop refused this credential outright — revoked, or
                // superseded by a re-pairing. Forget it here too, so the phone
                // stops presenting usage it is no longer entitled to and the
                // user is offered setup rather than a silent failure.
                store.clear()
                cache.clear()
                return .notConfigured
            } catch {
                // A failed refresh must not blank a good reading: the Mac being
                // asleep is expected, not an error state worth erasing data for.
                if let cached = cache.load() {
                    return .cached(cached)
                }
                return .unavailable
            }
        }
    }
}
