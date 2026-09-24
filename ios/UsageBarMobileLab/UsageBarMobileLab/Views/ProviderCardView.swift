import SwiftUI
import UsageBarSync

/// One provider's card.
///
/// Four layers, in decreasing order of how quickly they answer "should I slow
/// down?": who this is and whether it is running, the headline percentage, the
/// headline's own window and reset, and then the per-window detail.
struct ProviderCardView: View {
    let provider: UsageSyncProvider
    /// Overridable so tests and previews can pin the clock. In the app this is
    /// supplied by the `TimelineView` below.
    var now: Date = Date()

    private var accent: Color { ProviderVisual.accent(for: provider.providerId) }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The glyph chip grows with the name beside it instead of staying a fixed
    /// 24pt box that the symbol overflows at accessibility sizes.
    @ScaledMetric(relativeTo: .headline) private var chipSize: CGFloat = 24

    var body: some View {
        // A minute schedule, purely so the countdown stays honest while the
        // dashboard is open.
        //
        // This is presentation only: it re-evaluates the view with a newer
        // `now` and does nothing else. No fetch, no cache write, no widget
        // reload, and `measuredAt` is untouched — the reading does not get
        // younger because the clock moved. The age line ages *with* the tick,
        // which is the point: both facts move forward, and neither pretends to
        // be the other.
        TimelineView(.periodic(from: now, by: 60)) { context in
            card(now: max(now, context.date))
        }
    }

    private func card(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let measurement = provider.measurement {
                headline(measurement, now: now)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(measurement.windows, id: \.windowId) { window in
                        WindowRow(window: window, tint: accent, now: now)
                    }
                }
            } else {
                emptyState
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Header

    /// Name and status side by side at normal sizes; stacked once Dynamic Type
    /// reaches an accessibility size, where a pill squeezed into the leftover
    /// width would break its own word across two lines.
    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                identity
                StatusPill(status: ProviderPresentation.status(for: provider), accent: accent)
            }
        } else {
            HStack(spacing: 10) {
                identity
                Spacer(minLength: 8)
                StatusPill(status: ProviderPresentation.status(for: provider), accent: accent)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            // A generic SF Symbol in a tinted chip. No provider logo, wordmark
            // or trademark artwork is bundled or imitated.
            Image(systemName: ProviderVisual.symbolName(for: provider.providerId))
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: chipSize, height: chipSize)
                .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)

            Text(ProviderPresentation.displayName(for: provider.providerId))
                .font(.headline)
        }
    }

    // MARK: - Headline

    private func headline(_ measurement: UsageSyncMeasurement, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

            // Which window this number belongs to, and how long that window has
            // left — resolved through `headlineWindowId`, never array order.
            if let line = SurfaceLinePresentation.headlineWindowLine(in: measurement, now: now) {
                Text(line)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }

            // Deliberately its own row, below the countdown rather than beside
            // it. They are different facts, and a countdown that ticks while
            // the app is open must never read as evidence that the measurement
            // was refreshed. A desktop asleep for two days can still hold a
            // reading whose window resets in an hour.
            Text(FreshnessPresentation.age(of: measurement, now: now))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headlineAccessibilityLabel(measurement, now: now))
    }

    private func headlineAccessibilityLabel(
        _ measurement: UsageSyncMeasurement,
        now: Date
    ) -> String {
        var text = "\(measurement.headlineRemainingPercent) percent remaining"
        if let label = HeadlinePresentation.label(in: measurement) {
            text += ". \(label) window"
            if let spoken = HeadlinePresentation.spokenReset(in: measurement, now: now) {
                text += ", \(spoken) left"
            }
        }
        return text + ". \(FreshnessPresentation.age(of: measurement, now: now))"
    }

    // MARK: - No measurement

    /// No reading means no percentage, no progress bar and no countdown. The
    /// pill already names the state; this line says what it means, without
    /// inventing a number to fill the space.
    private var emptyState: some View {
        Text(emptyStateDetail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyStateDetail: String {
        switch ProviderPresentation.status(for: provider) {
        case .disconnected:
            return "Not connected. Connect this provider in UsageBar on your Mac."
        case .paused:
            return "Collection is paused on the Mac, so there is no reading to show."
        case .waitingForData, .collecting:
            return "No reading yet. The Mac will send one once it has measured this provider."
        }
    }
}

// MARK: - Status pill

/// The provider's lifecycle as a compact capsule.
///
/// The dot is decoration and the word is the state: colour is never the only
/// thing carrying the meaning, on screen or to VoiceOver. A paused provider is
/// a deliberate choice rather than a fault, so it is styled neutrally; only a
/// genuinely disconnected one gets attention colour.
private struct StatusPill: View {
    let status: ProviderPresentation.Status
    let accent: Color

    private var tint: Color {
        switch status {
        case .collecting: return accent
        case .paused, .waitingForData: return Color.secondary
        case .disconnected: return Color.red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(ProviderPresentation.label(for: status))
                .font(.caption2.weight(.semibold))
                // Wrap at spaces rather than being squeezed into a mid-word
                // break, and never truncate the state to fit.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(ProviderPresentation.label(for: status))")
    }
}

// MARK: - Remaining bar

/// A thin bar showing **remaining** percentage, matching the number beside it
/// and the menu bar on the Mac: full is untouched quota, empty is spent.
///
/// It classifies nothing. There is no "warning" or "critical" band here,
/// because no such threshold exists anywhere else in this product and a bar
/// that invented one would be asserting a policy the desktop never stated.
private struct RemainingBar: View {
    let remainingPercent: Int
    let tint: Color

    /// A display-side clamp only: the validated schema value is never
    /// modified, and the number printed beside the bar still says exactly what
    /// the snapshot said. This keeps a malformed percentage from drawing
    /// outside its own track.
    private var fraction: Double {
        Double(min(max(remainingPercent, 0), 100)) / 100
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
        // The row speaks for it, so VoiceOver does not announce a bare bar.
        .accessibilityHidden(true)
    }
}

// MARK: - Window row

/// A detailed window row: the limit, what is left of it, and when it turns over.
///
/// It keeps the **absolute** reset time alongside the countdown. The two answer
/// different questions — "how much longer may I keep going?" and "when
/// exactly?" — and the second is what someone plans an afternoon around.
private struct WindowRow: View {
    let window: UsageSyncWindow
    let tint: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(WindowPresentation.label(for: window))
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text("\(window.remainingPercent)%")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            RemainingBar(remainingPercent: window.remainingPercent, tint: tint)

            // Nothing is rendered when the window carries no reset time, and no
            // countdown is rendered once that time has passed.
            if let summary = FreshnessPresentation.resetSummary(for: window, now: now) {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var text = "\(WindowPresentation.label(for: window)), "
        text += "\(window.remainingPercent) percent remaining"
        if let spoken = FreshnessPresentation.spokenResetSummary(for: window, now: now) {
            text += ". \(spoken)"
        }
        return text
    }
}

// MARK: - Previews

/// Invented sample values only — never a real account's quota.
private enum CardPreviewData {
    static let now = Date(timeIntervalSince1970: 1_772_000_000)

    static func window(
        _ id: String,
        _ kind: UsageSyncWindowKind,
        percent: Int,
        minutes: Int? = nil,
        scope: String? = nil,
        resetsIn: TimeInterval?
    ) -> UsageSyncWindow {
        UsageSyncWindow(
            windowId: id, kind: kind, scope: scope, durationMinutes: minutes,
            remainingPercent: percent,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) }
        )
    }

    static func provider(
        _ id: String,
        connected: Bool = true,
        collecting: Bool = true,
        percent: Int? = nil,
        headline: String = "five-hour",
        measuredMinutesAgo: Double = 2,
        windows: [UsageSyncWindow] = []
    ) -> UsageSyncProvider {
        UsageSyncProvider(
            providerId: id,
            connected: connected,
            collecting: collecting,
            measurement: percent.map { value in
                UsageSyncMeasurement(
                    measuredAt: now.addingTimeInterval(-measuredMinutesAgo * 60),
                    headlineRemainingPercent: value,
                    headlineWindowId: headline,
                    windows: windows
                )
            }
        )
    }

    /// Full quota, a short window.
    static var codexFull: UsageSyncProvider {
        provider(UsageProviderID.codex, percent: 100, windows: [
            window("five-hour", .fiveHour, percent: 100, minutes: 300, resetsIn: 4 * 3600 + 59 * 60),
            window("weekly", .weekly, percent: 96, minutes: 10_080, resetsIn: 5 * 86_400)
        ])
    }

    /// The shape from the owner's brief: a mid headline and a tighter weekly.
    static var claudeMixed: UsageSyncProvider {
        provider(UsageProviderID.claude, percent: 39, windows: [
            window("five-hour", .fiveHour, percent: 39, minutes: 300, resetsIn: 4 * 3600 + 59 * 60),
            window("weekly", .weekly, percent: 16, minutes: 10_080,
                   resetsIn: 3 * 86_400 + 21 * 3600 + 14 * 60)
        ])
    }

    /// A multi-day headline that is *not* the first window, and a low number.
    static var codexDurationHeadline: UsageSyncProvider {
        provider(UsageProviderID.codex, percent: 4, headline: "duration-4320",
                 measuredMinutesAgo: 620, windows: [
            window("weekly", .weekly, percent: 87, minutes: 10_080, resetsIn: 5 * 86_400),
            window("duration-4320", .duration, percent: 4, minutes: 4_320,
                   resetsIn: 2 * 86_400 + 3 * 3600 + 14 * 60)
        ])
    }

    static var paused: UsageSyncProvider {
        provider(UsageProviderID.claude, collecting: false, percent: 52, windows: [
            window("five-hour", .fiveHour, percent: 52, minutes: 300, resetsIn: 71 * 60)
        ])
    }

    static var disconnected: UsageSyncProvider {
        provider(UsageProviderID.codex, connected: false)
    }

    static var noMeasurement: UsageSyncProvider {
        provider(UsageProviderID.claude)
    }

    /// No reset instant at all, and a scoped weekly whose label runs long.
    static var scopedNoReset: UsageSyncProvider {
        provider(UsageProviderID.claude, percent: 91, headline: "weekly-opus", windows: [
            window("weekly-opus", .weeklyScoped, percent: 91, minutes: 10_080,
                   scope: "opus", resetsIn: nil)
        ])
    }
}

private struct CardPreviewList: View {
    var body: some View {
        List {
            ForEach(Array(providers.enumerated()), id: \.offset) { _, provider in
                Section { ProviderCardView(provider: provider, now: CardPreviewData.now) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var providers: [UsageSyncProvider] {
        [
            CardPreviewData.codexFull,
            CardPreviewData.claudeMixed,
            CardPreviewData.codexDurationHeadline,
            CardPreviewData.paused,
            CardPreviewData.disconnected,
            CardPreviewData.noMeasurement,
            CardPreviewData.scopedNoReset
        ]
    }
}

#Preview("Cards — Light") {
    CardPreviewList().preferredColorScheme(.light)
}

#Preview("Cards — Dark") {
    CardPreviewList().preferredColorScheme(.dark)
}

#Preview("Cards — Accessibility XXL") {
    CardPreviewList().environment(\.dynamicTypeSize, .accessibility3)
}
