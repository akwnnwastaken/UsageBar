import SwiftUI
import UsageBarSync

struct ProviderCardView: View {
    let provider: UsageSyncProvider
    /// Overridable so tests and previews can pin the clock. In the app this is
    /// supplied by the `TimelineView` below.
    var now: Date = Date()

    var body: some View {
        // A minute schedule, purely so the countdown stays honest while the
        // dashboard is open.
        //
        // This is presentation only: it re-evaluates the view with a newer
        // `now` and does nothing else. No fetch, no cache write, no widget
        // reload, and `measuredAt` is untouched — the reading does not get
        // younger because the clock moved.
        TimelineView(.periodic(from: now, by: 60)) { context in
            card(now: max(now, context.date))
        }
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let measurement = provider.measurement {
                headline(measurement, now: now)
                Divider()
                ForEach(measurement.windows, id: \.windowId) { window in
                    WindowRow(window: window, now: now)
                }
            } else {
                Text(ProviderPresentation.statusLabel(for: provider))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(ProviderPresentation.displayName(for: provider.providerId))
                .font(.headline)
            Spacer()
            Text(ProviderPresentation.statusLabel(for: provider))
                .font(.caption.weight(.medium))
                .foregroundStyle(ProviderPresentation.isAttentionState(provider) ? .red : .secondary)
        }
    }

    private func headline(_ measurement: UsageSyncMeasurement, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(measurement.headlineRemainingPercent)")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Two facts on one line: how old the reading is, and how long the
            // headline's own window has left. Age is always from `measuredAt`
            // and always first, so a future reset can never make an old
            // measurement read as fresh.
            Text(FreshnessPresentation.headlineMetadata(of: measurement, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// A detailed window row.
///
/// It deliberately keeps the **absolute** reset time — "Resets 1:00 PM" — rather
/// than repeating the headline's countdown. The headline answers "should I slow
/// down?", these rows answer "when exactly?", and printing the same fact twice
/// in two formats would make the card longer without making it clearer.
private struct WindowRow: View {
    let window: UsageSyncWindow
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WindowPresentation.label(for: window))
                    .font(.subheadline)
                if let reset = FreshnessPresentation.resetLabel(for: window, now: now) {
                    Text(reset)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(window.remainingPercent)%")
                .font(.body.weight(.medium))
                .monospacedDigit()
        }
    }
}
