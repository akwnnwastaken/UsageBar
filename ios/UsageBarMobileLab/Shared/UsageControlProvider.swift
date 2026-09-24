import Foundation
import WidgetKit
import UsageBarSync

/// Kind strings are stable identity: iOS keys a *placed* control by them, so
/// renaming one silently removes controls people have already added to their
/// Control Center. They are pinned by tests for that reason.
enum ControlKindID {
    static let overview = "UsageBarControlOverview"
    static let codex = "UsageBarControlCodex"
    static let claude = "UsageBarControlClaude"
}

/// SF Symbols for the controls.
///
/// Deliberately generic: Phase 7 bundles no provider trademark or artwork. They
/// are chosen to stay meaningful at the smallest Control Center size, where iOS
/// may render the glyph and nothing else — which is also why the three differ
/// from each other rather than sharing one gauge.
enum ControlSymbol {
    static let overview = "gauge.with.dots.needle.bottom.50percent"
    static let codex = "chart.bar.fill"
    static let claude = "chart.pie.fill"
}

/// One provider's headline, reduced to what a control may display.
///
/// `remainingPercent` is `headlineRemainingPercent` straight from the snapshot,
/// never recomputed from `windows`: the desktop has already applied its
/// provider-specific headline policy, and a second opinion on the phone is how
/// Control Center would come to disagree with the Mac beside it.
struct UsageControlHeadline: Equatable, Sendable {
    let providerId: String
    /// Absent when the provider is connected but holds no measurement yet.
    let remainingPercent: Int?
    /// The provider's own reading time. Freshness comes from here and never
    /// from the snapshot's `generatedAt`, which advances whenever the desktop
    /// serializes — including for a retained or paused reading.
    let measuredAt: Date?
    /// Short label for the window `headlineWindowId` names — "5H", "Weekly",
    /// "3D". Absent when there is no measurement, or when the snapshot names a
    /// headline window that is not in its own `windows` array.
    let windowLabel: String?
    /// When that same window resets. Absent when the window carries no reset
    /// time, which schema v1 permits.
    let resetsAt: Date?
}

/// Everything a UsageBar control is allowed to know.
///
/// The system stores and re-reads control values, so this type is the second
/// privacy boundary after the schema itself. There is no property for a host,
/// a bearer, a MagicDNS name, a Tailscale identity, an HTTP status or an error
/// string — as with `UsageSyncSnapshot`, prohibited data cannot leak here by
/// accident because there is nowhere to put it.
///
/// It is deliberately not `Codable`: a control value is derived on demand from
/// the extension's already-validated snapshot cache, and giving it a
/// serialization path would invite a third cache holding a *presentation* of
/// usage that no validator checks.
struct UsageControlValue: Equatable, Sendable {
    /// Why the headlines are what they are. Never a network or auth detail.
    enum Availability: Equatable, Sendable {
        /// No connection configured, or it has been forgotten.
        case notConfigured
        /// Configured, but nothing validated has ever been seen.
        case unavailable
        /// This evaluation fetched and validated a snapshot.
        case live
        /// The fetch did not succeed; this is the last validated reading.
        case cached
    }

    let availability: Availability
    let headlines: [UsageControlHeadline]

    static let notConfigured = UsageControlValue(availability: .notConfigured, headlines: [])
    static let unavailable = UsageControlValue(availability: .unavailable, headlines: [])

    func headline(for providerId: String) -> UsageControlHeadline? {
        headlines.first { $0.providerId == providerId }
    }

    /// The most conservative reading time in the snapshot.
    ///
    /// A control shows one status line for possibly two providers, so it must
    /// report the *oldest* measurement rather than the newest: saying "updated
    /// just now" because one of two providers is fresh would be the same lie
    /// `generatedAt` would tell.
    var oldestMeasuredAt: Date? {
        headlines.compactMap(\.measuredAt).min()
    }

    /// Projects a resolved surface state onto the control's display model.
    init(state: UsageSurfaceState) {
        switch state {
        case .notConfigured:
            self = .notConfigured
        case .unavailable:
            self = .unavailable
        case .loaded(let snapshot):
            self.init(availability: .live, snapshot: snapshot)
        case .cached(let snapshot):
            self.init(availability: .cached, snapshot: snapshot)
        }
    }

    init(availability: Availability, headlines: [UsageControlHeadline]) {
        self.availability = availability
        self.headlines = headlines
    }

    private init(availability: Availability, snapshot: UsageSyncSnapshot) {
        // Field by field, exactly like the snapshot builder on the desktop.
        // Never map a whole model across a boundary that has a smaller
        // vocabulary than the model does.
        self.availability = availability
        self.headlines = snapshot.providers.map { provider in
            UsageControlHeadline(
                providerId: provider.providerId,
                remainingPercent: provider.measurement?.headlineRemainingPercent,
                measuredAt: provider.measurement?.measuredAt,
                // One shared resolver, used by the dashboard and the widgets
                // too, so no surface can drift into assuming `windows.first`.
                windowLabel: provider.measurement.flatMap(HeadlinePresentation.compactLabel),
                resetsAt: provider.measurement.flatMap(HeadlinePresentation.resetsAt)
            )
        }
    }
}

/// The text a Control Center control asks the system to show.
///
/// Physical iPhone testing decided the shape of this. Control Center renders a
/// control's **label and nothing else**: at 1x1 not even that, only the glyph,
/// and at 1x2 and 2x2 a single line of text under the glyph. The
/// `controlWidgetStatus` line — Apple's documented secondary slot, still set by
/// the controls — was never drawn at any size tested on iOS 27.
///
/// So the title carries everything that has to be readable, and nothing is
/// designed on the assumption that a second line will rescue it. The status
/// text remains for the placements and versions that do render it, and is
/// never the only home for anything important.
enum ControlPresentation {
    /// Neutral stand-in for a provider that is configured but has no reading.
    static let missingValue = "—%"

    /// A provider control's one line: name, the window the headline came from,
    /// the headline itself, and how long that window has left —
    /// "Codex 5H 64% · 2h left".
    ///
    /// The window label is there because a bare "64%" is a figure without a
    /// fact. Codex's headline can be its five-hour limit on one reading and a
    /// multi-day limit on another, and a number whose window is unstated
    /// invites exactly the wrong conclusion about how much room is left.
    ///
    /// The countdown is what makes the percentage actionable: 21% with three
    /// days to run and 21% with twenty minutes to run are different situations.
    /// It is the owner's chosen use of the one remaining slot on the line, in
    /// place of the reading's age. The tradeoff is explicit — a control alone
    /// no longer shows that a reading is old, which on a direct overlay it can
    /// be whenever the desktop is asleep — so age stays on the app dashboard
    /// and the widgets, which have the room for both.
    static func providerTitle(
        for value: UsageControlValue,
        providerId: String,
        now: Date = Date()
    ) -> String {
        let name = ProviderPresentation.displayName(for: providerId)
        switch value.availability {
        case .notConfigured:
            // No quota, not even a placeholder percentage: the control must not
            // suggest it is holding a number it is merely refusing to show.
            // Since the status line is not drawn, the instruction goes here.
            return "Open UsageBar"
        case .unavailable:
            return "\(name) \(missingValue)"
        case .live, .cached:
            guard let headline = value.headline(for: providerId),
                  let percent = headline.remainingPercent else {
                return "\(name) \(missingValue)"
            }
            // Ordered most to least important, because a narrow control
            // truncates from the right: the number survives, then the window it
            // belongs to, and the age is the first thing to go.
            var parts = [name]
            if let window = headline.windowLabel { parts.append(window) }
            parts.append("\(percent)%")
            var title = parts.joined(separator: " ")
            // Tight, and without a "left" suffix: Control Center truncates from
            // the right and every character spent on whitespace or on the word
            // is a character the minutes might have needed. The old policy
            // bought that room by dropping the minutes entirely — "4h left" for
            // four hours fifty-nine — which is the inaccuracy this replaces.
            if let resetsAt = headline.resetsAt,
               let remaining = FreshnessPresentation.tightTimeRemaining(until: resetsAt, from: now) {
                title += " · " + remaining
            }
            return title
        }
    }

    /// The overview control's one line: both headlines — "Codex 64% · Claude 52%".
    ///
    /// Window labels are deliberately omitted here. Two providers already fill
    /// the line, and a string that truncates has told the user less than a
    /// shorter one that fits. The provider-specific controls are where the
    /// window belongs.
    static func overviewTitle(for value: UsageControlValue) -> String {
        switch value.availability {
        case .notConfigured:
            return "Open UsageBar"
        case .unavailable:
            return "UsageBar \(missingValue)"
        case .live, .cached:
            let parts = value.headlines.map { headline -> String in
                let name = ProviderPresentation.displayName(for: headline.providerId)
                guard let percent = headline.remainingPercent else {
                    return "\(name) \(missingValue)"
                }
                return "\(name) \(percent)%"
            }
            return parts.isEmpty ? "UsageBar \(missingValue)" : parts.joined(separator: " · ")
        }
    }

    /// The secondary status line, where a placement renders one.
    ///
    /// Control Center on iOS 27 does not, which is why nothing depends on it.
    /// It carries lifecycle and freshness only. A refusal, a redirect, a 500, a
    /// hostname or an auth outcome would all be details about the transport,
    /// and a control is the last place any of them belong.
    static func status(for value: UsageControlValue, now: Date = Date()) -> String {
        switch value.availability {
        case .notConfigured:
            return "Open app to connect"
        case .unavailable:
            return "No usage data yet"
        case .cached:
            return "Cached"
        case .live:
            guard let measuredAt = value.oldestMeasuredAt else { return "No usage data yet" }
            return FreshnessPresentation.relativeAge(from: measuredAt, to: now)
        }
    }
}

/// Supplies Control Center with the current value for a UsageBar control.
///
/// It creates no network client, no keychain accessor and no cache of its own.
/// The whole point is that it runs the *same* `UsageSurfaceResolver` the widget
/// timelines run, in the same extension, so a control cannot end up with either
/// a second transport policy or a second answer to "may this be displayed?".
struct UsageControlValueProvider: ControlValueProvider {
    private let resolver: UsageSurfaceResolver

    init(
        store: ConnectionStore = KeychainConnectionStore(),
        cache: SnapshotCaching = FileSnapshotCache(fileName: UsageSurfaceResolver.extensionCacheFileName),
        client: SnapshotFetching = UsageSyncAPIClient()
    ) {
        self.resolver = UsageSurfaceResolver(store: store, cache: cache, client: client)
    }

    /// Shown in the controls gallery, before the control is authorized to show
    /// anything. Entirely invented: it reads no keychain, no cache and no
    /// network, and its numbers are not anybody's usage.
    var previewValue: UsageControlValue {
        UsageControlValue(availability: .live, headlines: [
            UsageControlHeadline(
                providerId: UsageProviderID.codex,
                remainingPercent: 64,
                measuredAt: nil,
                windowLabel: "5H",
                resetsAt: nil
            ),
            UsageControlHeadline(
                providerId: UsageProviderID.claude,
                remainingPercent: 52,
                measuredAt: nil,
                windowLabel: "5H",
                resetsAt: nil
            )
        ])
    }

    /// The system decides when to ask. There is no timer, no `BackgroundTasks`
    /// work and no push handler behind this — a control is evaluated when
    /// Control Center wants a value, and the request is bounded by the shared
    /// client's own timeout and 64 KiB ceiling.
    func currentValue() async throws -> UsageControlValue {
        UsageControlValue(state: await resolver.resolve())
    }
}
