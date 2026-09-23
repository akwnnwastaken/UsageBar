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
            let entry = await currentEntry()
            let next = Date().addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
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
