import SwiftUI
import WidgetKit
import UsageBarSync

/// Pulls the one provider a provider-specific widget cares about.
func provider(_ providerId: String, in entry: UsageEntry) -> UsageSyncProvider? {
    entry.snapshot?.providers.first { $0.providerId == providerId }
}

/// A headline percentage.
///
/// Marked `privacySensitive` because quota levels are personal account
/// information and a Lock Screen widget is visible without unlocking. iOS
/// redacts it according to the user's own setting; that decision is theirs,
/// not this app's.
struct HeadlineValue: View {
    let percent: Int?
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let percent {
                Text("\(percent)%")
                    .privacySensitive()
            } else {
                // Neutral, not an error: a provider with no measurement yet is
                // a normal state.
                Text("--")
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
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

/// A small dot beside data that came from cache after a failed fetch.
struct StaleIndicator: View {
    var body: some View {
        Image(systemName: "wifi.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 8) {
                header
                HStack(alignment: .top, spacing: 16) {
                    providerColumn(UsageProviderID.codex, detailed: true)
                    Divider()
                    providerColumn(UsageProviderID.claude, detailed: true)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                header
                providerRow(UsageProviderID.codex)
                providerRow(UsageProviderID.claude)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("UsageBar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if entry.isStale { StaleIndicator() }
            Spacer(minLength: 0)
        }
    }

    /// The headline countdown for one provider, already separated.
    ///
    /// Nil whenever the headline window has no future reset, so nothing here
    /// ever renders an expired or empty countdown.
    private func countdown(_ providerId: String) -> String? {
        SurfaceLinePresentation.countdownSuffix(in: provider(providerId, in: entry)?.measurement)
    }

    private func accessoryRow(_ providerId: String) -> some View {
        let value = provider(providerId, in: entry)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(ProviderPresentation.displayName(for: providerId))
                .font(.caption2)
            HeadlineValue(percent: value?.measurement?.headlineRemainingPercent, size: 14)
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

    private func providerRow(_ providerId: String) -> some View {
        let value = provider(providerId, in: entry)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ProviderPresentation.displayName(for: providerId))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 2)
            HeadlineValue(percent: value?.measurement?.headlineRemainingPercent, size: 24)
                .layoutPriority(1)
            if let remaining = countdown(providerId) {
                Text(remaining)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .privacySensitive()
            }
        }
    }

    private func providerColumn(_ providerId: String, detailed: Bool) -> some View {
        let value = provider(providerId, in: entry)
        return VStack(alignment: .leading, spacing: 3) {
            Text(ProviderPresentation.displayName(for: providerId))
                .font(.caption.weight(.medium))
            HeadlineValue(percent: value?.measurement?.headlineRemainingPercent, size: 30)
            if detailed, let measurement = value?.measurement {
                // The headline's own window and how long it has left. The
                // detail rows below keep their own percentages and are
                // deliberately left uncluttered — the requirement is that the
                // *headline's* reset is visible, not every window's.
                if let line = SurfaceLinePresentation.headlineWindowLine(in: measurement) {
                    Text(line)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                ForEach(measurement.windows.prefix(2), id: \.windowId) { window in
                    HStack(spacing: 4) {
                        Text(WindowPresentation.label(for: window))
                        Spacer(minLength: 2)
                        Text("\(window.remainingPercent)%").privacySensitive()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Text(FreshnessPresentation.age(of: measurement))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .privacySensitive()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    name: name, percent: percent, measurement: value?.measurement
                )).privacySensitive()
            } else {
                Text("\(name) --")
            }
        case .accessoryCircular:
            VStack(spacing: -2) {
                Text(String(name.prefix(1)))
                    .font(.caption2.weight(.bold))
                HeadlineValue(percent: percent, size: 15)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(name).font(.caption.weight(.semibold))
                    if entry.isStale { StaleIndicator() }
                }
                HeadlineValue(percent: percent, size: 20)
                if let measurement = value?.measurement {
                    // One cramped line for two facts, so both are shortened
                    // rather than one being dropped: "2h left · 3m ago". The
                    // age still comes from `measuredAt` and still has no stale
                    // threshold — it is just spelled in fewer characters.
                    Text(SurfaceLinePresentation.accessoryFooter(of: measurement))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .privacySensitive()
                }
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(name).font(.caption.weight(.semibold))
                    if entry.isStale { StaleIndicator() }
                    Spacer(minLength: 0)
                }
                HeadlineValue(percent: percent, size: 44)
                if let measurement = value?.measurement,
                   let line = SurfaceLinePresentation.headlineWindowLine(in: measurement) {
                    // The label beside the headline names the window the
                    // desktop actually chose. It used to read
                    // `measurement.windows.first`, which is a different window
                    // whenever Codex's most constrained limit is a multi-day
                    // one listed after the weekly — a confidently wrong label
                    // and, now, a countdown to the wrong reset.
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(FreshnessPresentation.age(of: measurement))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .privacySensitive()
                } else {
                    Text(value.map(ProviderPresentation.statusLabel) ?? "No data")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
