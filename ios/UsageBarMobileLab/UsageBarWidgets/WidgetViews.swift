import SwiftUI
import WidgetKit
import UsageBarSync

/// Pulls the one provider a provider-specific widget cares about.
func provider(_ providerId: String, in entry: UsageEntry) -> UsageSyncProvider? {
    entry.snapshot?.providers.first { $0.providerId == providerId }
}

/// Shown whenever credentials are absent — including right after Forget
/// Connection, even if this extension still holds a cached snapshot.
struct NotConfiguredView: View {
    var compact = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.secondary)
            Text("Open UsageBar")
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Overview

struct OverviewWidgetView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch entry.state {
        case .notConfigured:
            NotConfiguredView(compact: family == .accessoryRectangular)
        case .unavailable:
            unavailable
        case .loaded, .cached:
            content
        }
    }

    private var unavailable: some View {
        VStack(spacing: 2) {
            Text("UsageBar").font(.caption).foregroundStyle(.secondary)
            Text("--").font(.title2.weight(.semibold))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            // One line per provider rather than two side-by-side columns: the
            // family is two lines tall, and a row can carry a countdown where a
            // column could only have grown a third line it has no room for.
            VStack(alignment: .leading, spacing: 0) {
                accessoryRow(UsageProviderID.codex)
                accessoryRow(UsageProviderID.claude)
            }
        case .systemMedium:
            // Each column is the single-provider widget itself, so a provider
            // reads the same here as on its own widget.
            OverviewMediumContent(providers: slots, now: entry.date, isStale: entry.isStale)
        default:
            // Two compact provider summaries; each names its own provider, so
            // no global title spends the height the numbers need.
            OverviewSmallContent(providers: slots, now: entry.date, isStale: entry.isStale)
        }
    }

    private var slots: [WidgetProviderSlot] {
        [UsageProviderID.codex, UsageProviderID.claude].map {
            WidgetProviderSlot(id: $0, provider: provider($0, in: entry))
        }
    }

    /// The headline countdown for one provider, already separated.
    ///
    /// Nil whenever the headline window has no future reset, so nothing here
    /// ever renders an expired or empty countdown.
    private func countdown(_ providerId: String) -> String? {
        SurfaceLinePresentation.countdownSuffix(
            in: provider(providerId, in: entry)?.measurement, now: entry.date
        )
    }

    private func accessoryRow(_ providerId: String) -> some View {
        let value = provider(providerId, in: entry)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(ProviderPresentation.displayName(for: providerId))
                .font(.caption2)
            WidgetHeadlineValue(percent: value?.measurement?.headlineRemainingPercent, size: 14)
                // The percentage outranks the countdown: if the line has to
                // give something up, it gives up the countdown.
                .layoutPriority(1)
            if let remaining = countdown(providerId) {
                Text(remaining)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Single provider

struct ProviderWidgetView: View {
    var entry: UsageEntry
    var providerId: String
    @Environment(\.widgetFamily) private var family

    private var value: UsageSyncProvider? { provider(providerId, in: entry) }
    private var percent: Int? { value?.measurement?.headlineRemainingPercent }
    private var name: String { ProviderPresentation.displayName(for: providerId) }


    var body: some View {
        switch entry.state {
        case .notConfigured:
            notConfigured
        default:
            content
        }
    }

    @ViewBuilder
    private var notConfigured: some View {
        switch family {
        case .accessoryInline:
            Text("UsageBar --")
        case .accessoryCircular:
            Text("--").font(.headline)
        default:
            NotConfiguredView(compact: family != .systemSmall)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            // Inline gets one short string and no decoration. The percentage
            // comes first so that if the system truncates, the countdown is
            // what is lost.
            if let percent {
                Text(SurfaceLinePresentation.inline(
                    name: name, percent: percent, measurement: value?.measurement, now: entry.date
                )).privacySensitive()
            } else {
                Text("\(name) --")
            }
        case .accessoryCircular:
            VStack(spacing: -2) {
                Text(String(name.prefix(1)))
                    .font(.caption2.weight(.bold))
                WidgetHeadlineValue(percent: percent, size: 15)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(name).font(.caption.weight(.semibold))
                    if entry.isStale { StaleIndicator() }
                }
                WidgetHeadlineValue(percent: percent, size: 20)
                if let measurement = value?.measurement {
                    // One cramped line for two facts, so both are shortened
                    // rather than one being dropped: "2h left · 3m ago". The
                    // age still comes from `measuredAt` and still has no stale
                    // threshold — it is just spelled in fewer characters.
                    Text(SurfaceLinePresentation.accessoryFooter(of: measurement, now: entry.date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .privacySensitive()
                }
            }
        default:
            // The headline, then the five-hour and weekly windows each with its
            // own bar and countdown — whichever of the two the snapshot really
            // has. Every countdown renders against `entry.date`.
            ProviderWidgetSmallContent(
                providerId: providerId,
                provider: value,
                now: entry.date,
                isStale: entry.isStale
            )
        }
    }
}
