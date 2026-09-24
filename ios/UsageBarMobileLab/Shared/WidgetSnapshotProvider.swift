import Foundation
import WidgetKit
import UsageBarSync

struct UsageEntry: TimelineEntry, Equatable {
    let date: Date
    let state: UsageSurfaceState

    var snapshot: UsageSyncSnapshot? { state.snapshot }
    var isStale: Bool { state.isStale }
}

/// Builds widget timelines.
///
/// The extension fetches for itself rather than reading a container the app
/// wrote, because this architecture deliberately has no App Group. It shares
/// only credentials with the app, through the keychain.
struct UsageTimelineProvider: TimelineProvider {
    /// WidgetKit owns scheduling; this is a floor, not a promise. Asking for
    /// anything more frequent would be budget spent for nothing, since the
    /// system coalesces and defers refreshes anyway.
    static let refreshInterval: TimeInterval = 15 * 60

    /// How finely, and how far ahead, the one fetched reading is re-rendered.
    ///
    /// A widget's view is rendered when its timeline is *built*, not when it is
    /// looked at, so a timeline of one entry freezes its countdown at build
    /// time: forty minutes later the Lock Screen still claims the reading's
    /// window has as long left as it had then. The cure is more entries, not
    /// more fetches. Every entry below re-renders the *same* already-resolved
    /// state at a later instant, so the countdown falls and the age grows while
    /// the network, the keychain and the cache are never touched again.
    ///
    /// The horizon deliberately outruns `refreshInterval`: the system defers
    /// refreshes whenever it likes, and a timeline that ran out of entries
    /// would go back to displaying a frozen clock precisely when it had been
    /// deferred longest. Timing stays best-effort — this asks the system for
    /// nothing extra, it just gives the system more than one already-rendered
    /// answer to choose from.
    static let countdownStep: TimeInterval = 5 * 60
    static let countdownHorizon: TimeInterval = 60 * 60

    private let resolver: UsageSurfaceResolver

    init(
        store: ConnectionStore = KeychainConnectionStore(),
        cache: SnapshotCaching = FileSnapshotCache(fileName: UsageSurfaceResolver.extensionCacheFileName),
        client: SnapshotFetching = UsageSyncAPIClient()
    ) {
        self.resolver = UsageSurfaceResolver(store: store, cache: cache, client: client)
    }

    func placeholder(in context: Context) -> UsageEntry {
        // Synthetic, and never a real reading: the placeholder is rendered
        // before the widget is authorized to show anything, and it can appear
        // in system UI such as the widget gallery.
        UsageEntry(date: Date(), state: .loaded(WidgetPreviewData.snapshot))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let now = Date()
            // Exactly one resolve — therefore at most one fetch — per timeline.
            let state = await resolver.resolve()
            completion(Timeline(
                entries: Self.countdownEntries(for: state, startingAt: now),
                policy: .after(now.addingTimeInterval(Self.refreshInterval))
            ))
        }
    }

    /// One resolved state, rendered at a ladder of future instants.
    ///
    /// Every entry carries the *same* state — the same snapshot, the same
    /// `measuredAt`, the same percentages — and differs only in its `date`,
    /// which is the `now` the views format against. Nothing here can make a
    /// reading look newer than it is: a later entry renders a longer age, never
    /// a shorter one.
    static func countdownEntries(
        for state: UsageSurfaceState,
        startingAt start: Date
    ) -> [UsageEntry] {
        stride(from: 0, through: countdownHorizon, by: countdownStep).map { offset in
            UsageEntry(date: start.addingTimeInterval(offset), state: state)
        }
    }

    /// Delegates the credential-first revocation rule to `UsageSurfaceResolver`
    /// so widgets and Control Center controls cannot drift apart on it.
    func currentEntry(now: Date = Date()) async -> UsageEntry {
        UsageEntry(date: now, state: await resolver.resolve())
    }
}

/// Invented values for placeholders and previews. No real account data.
enum WidgetPreviewData {
    static let snapshot: UsageSyncSnapshot = {
        let generatedAt = Date()
        return UsageSyncSnapshot(
            generatedAt: generatedAt,
            providers: [
                UsageSyncProvider(
                    providerId: UsageProviderID.codex,
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: generatedAt,
                        headlineRemainingPercent: 64,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 64,
                                resetsAt: generatedAt.addingTimeInterval(4 * 3600)
                            )
                        ]
                    )
                ),
                UsageSyncProvider(
                    providerId: UsageProviderID.claude,
                    connected: true,
                    collecting: true,
                    measurement: UsageSyncMeasurement(
                        measuredAt: generatedAt,
                        headlineRemainingPercent: 52,
                        headlineWindowId: "five-hour",
                        windows: [
                            UsageSyncWindow(
                                windowId: "five-hour",
                                kind: .fiveHour,
                                durationMinutes: 300,
                                remainingPercent: 52,
                                resetsAt: generatedAt.addingTimeInterval(3 * 3600)
                            )
                        ]
                    )
                )
            ]
        )
    }()
}
