import Foundation
import SwiftUI
import UIKit
import WidgetKit
import UsageBarSync

/// The provider slugs this app knows by name.
///
/// They are the desktop's own stable identifiers, not display text, and they
/// are the join between a snapshot and the surface that shows it — a widget
/// kind, a control kind and a presentation lookup all key off the same string.
/// Spelling them once means a typo is a compile error rather than a widget that
/// silently renders nothing.
public enum UsageProviderID {
    public static let codex = "codex"
    public static let claude = "claude-code"
}

/// Turns schema facts into screen text.
///
/// Every label here is derived on the phone from structured fields. The desktop
/// sends identifiers and numbers, never localized strings: a display name
/// crossing the wire would be presentation leaking into a data contract, and it
/// would have to be versioned like data forever after.
public enum ProviderPresentation {
    /// Known providers get their product name; anything else gets a readable
    /// label derived from its slug, so a provider added on the desktop after
    /// this app shipped still renders sensibly instead of as a raw id.
    public static func displayName(for providerId: String) -> String {
        switch providerId {
        case UsageProviderID.codex:
            return "Codex"
        case UsageProviderID.claude:
            return "Claude"
        default:
            return providerId
                .split(separator: "-")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    /// A provider's lifecycle, as a value rather than as a string.
    ///
    /// The card needs to *style* these differently — a pill that is subtly
    /// active for one and attention-coloured for another — and matching on
    /// display text to decide a colour would break the moment the wording
    /// changed. These are the same four states the app has always reported; no
    /// new lifecycle state is invented here.
    public enum Status: Equatable, Sendable {
        case collecting
        case paused
        case waitingForData
        case disconnected
    }

    public static func status(for provider: UsageSyncProvider) -> Status {
        if !provider.connected { return .disconnected }
        if !provider.collecting { return .paused }
        if provider.measurement == nil { return .waitingForData }
        return .collecting
    }

    /// The lifecycle sentence for a provider card.
    public static func statusLabel(for provider: UsageSyncProvider) -> String {
        label(for: status(for: provider))
    }

    public static func label(for status: Status) -> String {
        switch status {
        case .collecting: return "Collecting"
        case .paused: return "Paused"
        case .waitingForData: return "Waiting for usage data"
        case .disconnected: return "Disconnected"
        }
    }

    /// A paused provider is a deliberate user choice, not a fault, so it must
    /// not be styled as an error. A disconnected one is genuinely absent.
    public static func isAttentionState(_ provider: UsageSyncProvider) -> Bool {
        status(for: provider) == .disconnected
    }
}

/// The restrained visual identity a provider card and its accents carry.
///
/// Centralised here rather than spelled out in the views, so the dashboard, a
/// progress bar and a status pill cannot end up with three different ideas of
/// what "Codex" looks like.
///
/// Deliberately generic: no provider logo, wordmark or trademark artwork is
/// bundled or imitated. A stock SF Symbol and a system colour is the whole
/// vocabulary. System colours are used in preference to literals because they
/// are the ones that already adapt to Light and Dark Mode and to the
/// accessibility contrast settings.
public enum ProviderVisual {
    public static func symbolName(for providerId: String) -> String {
        switch providerId {
        case UsageProviderID.codex:
            return "chevron.left.forwardslash.chevron.right"
        case UsageProviderID.claude:
            return "sparkle"
        default:
            return "gauge.with.dots.needle.bottom.50percent"
        }
    }

    public static func accent(for providerId: String) -> Color {
        switch providerId {
        case UsageProviderID.codex:
            return .teal
        case UsageProviderID.claude:
            return .orange
        default:
            return .accentColor
        }
    }
}

/// How much is left, as a colour.
///
/// Provider identity and usage level are two different things, and they are
/// deliberately carried by two different channels. The icon, the chip and the
/// status pill say *who* this is; a progress bar says *how much is left*. When
/// the bar carried provider identity instead — a cyan Codex bar, an orange
/// Claude bar — a nearly-empty weekly limit and a full one looked exactly
/// alike, which is the one thing a bar exists to distinguish.
///
/// This is presentation only. Nothing here classifies a reading as critical,
/// warning or healthy: no such threshold exists anywhere else in this product,
/// the desktop never stated one, and a colour that implied a policy the Mac
/// does not share would be the mobile surface inventing its own opinion. The
/// printed percentage stays authoritative, and colour is never the only way to
/// read the value — the number is always beside the bar, and the bar's own
/// length carries the same fact for anyone who cannot separate red from green.
public enum UsageLevelPresentation {
    /// A presentation-side clamp. The validated schema value is never
    /// modified; this only keeps a malformed percentage from producing a
    /// nonsense colour or a bar that draws outside its track.
    public static func displayPercent(_ percent: Int) -> Int {
        min(max(percent, 0), 100)
    }

    /// 0.0 when empty, 1.0 when full — the single scalar the colour derives
    /// from, exposed so the mapping can be tested as arithmetic rather than
    /// through rendered pixels.
    public static func level(for percent: Int) -> Double {
        Double(displayPercent(percent)) / 100
    }

    /// The hue the filled portion uses, in SwiftUI's 0...1 space.
    ///
    /// A straight ramp from red (0.0) to green (0.34) passes through orange
    /// and yellow on the way, which is exactly the progression asked for, and
    /// it stops at green rather than continuing into cyan and blue — so it
    /// never reads as a rainbow. The whole scale is monotonic: more remaining
    /// is always further along it, with no band where two different readings
    /// share a colour.
    public static func hue(for percent: Int) -> Double {
        level(for: percent) * 0.34
    }

    /// The colour for a filled bar at this remaining percentage.
    ///
    /// Resolved per trait collection rather than as a fixed value, because the
    /// midpoint of this scale is yellow: saturated yellow disappears against a
    /// white background and glares against a black one. Saturation is pulled
    /// back from full so the result reads as a product colour rather than as
    /// neon, and brightness moves in opposite directions for the two
    /// appearances so the same reading stays legible in both.
    public static func remainingColor(for percent: Int) -> Color {
        let hue = hue(for: percent)
        return Color(UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            return UIColor(
                hue: CGFloat(hue),
                saturation: isDark ? 0.70 : 0.90,
                brightness: isDark ? 0.95 : 0.80,
                alpha: 1
            )
        })
    }
}

/// The one remaining-percentage bar, shared by the dashboard and the widgets.
///
/// A second implementation in the widget extension is exactly how the two
/// surfaces would drift into disagreeing about what a colour or a length
/// means, so only the height differs between them — the dashboard can afford a
/// 6pt bar, a widget row cannot.
public struct UsageRemainingBar: View {
    public let remainingPercent: Int
    public var height: CGFloat

    public init(remainingPercent: Int, height: CGFloat = 6) {
        self.remainingPercent = remainingPercent
        self.height = height
    }

    private var fraction: Double {
        UsageLevelPresentation.level(for: remainingPercent)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(UsageLevelPresentation.remainingColor(for: remainingPercent))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: height)
        // The row that owns this bar speaks for it, so VoiceOver announces
        // "12 percent remaining" once rather than also describing a bare bar.
        .accessibilityHidden(true)
    }
}

// MARK: - Shared widget composition
//
// These views live here rather than inside the widget extension for the same
// reason the composed strings do: an app extension cannot be
// `@testable`-imported, so a layout written inline in `WidgetViews.swift` could
// never be asserted or rendered in a test. Keeping the composition here means
// the widgets' structure is under test, not just their wording — and the app
// and the extension share one visual vocabulary instead of two that drift.

/// A provider's identity in a widget: a generic glyph plus its name.
///
/// This is where provider identity lives, exactly as the chip and pill carry it
/// on the dashboard — never in a progress bar, whose colour has to mean "how
/// much is left". Marked accentable so that under the system's tinted rendering
/// mode the identity is what survives as the accented element.
public struct ProviderTag: View {
    public let providerId: String
    public var size: CGFloat

    public init(providerId: String, size: CGFloat = 10) {
        self.providerId = providerId
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ProviderVisual.symbolName(for: providerId))
                .font(.system(size: size - 1, weight: .bold))
                .foregroundStyle(ProviderVisual.accent(for: providerId))
                .widgetAccentable()
            Text(ProviderPresentation.displayName(for: providerId))
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// One window in a detailed provider widget, as a block: its name and
/// percentage, how long it has left, and a bar.
///
///     5 Hour                  93%
///     3h 10m left
///     [==========        ]
///
/// Each block carries its *own* countdown and its full name. The widget lists
/// the five-hour and the weekly side by side, and "3h 10m" against "6d 22h" is
/// what tells a person which of the two limits will stop them first.
///
/// Text styles rather than point literals, so the block follows Dynamic Type;
/// `ProviderWidgetSmallContent` falls back to the compact form when a larger
/// text size no longer fits. Contrast comes from the system's hierarchical
/// styles only — `.primary` for the name and the number, `.secondary` for the
/// countdown — so Light, Dark and tinted rendering all stay legible.
public struct WidgetWindowDetailRow: View {
    public let window: UsageSyncWindow
    public let now: Date
    public var compact: Bool

    public init(window: UsageSyncWindow, now: Date, compact: Bool = false) {
        self.window = window
        self.now = now
        self.compact = compact
    }

    private var remaining: String? {
        SurfaceLinePresentation.windowCountdown(for: window, now: now)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // The full name — "5 Hour", "Weekly" — which always fits; only a
            // long scoped name ("Weekly · Opus") on a narrow widget falls back
            // to its short form rather than being cut mid-word. The whole line
            // is what gets measured, so the percentage is never the part lost.
            ViewThatFits(in: .horizontal) {
                titleLine(WindowPresentation.label(for: window))
                titleLine(WindowPresentation.microLabel(for: window))
            }
            if let remaining {
                Text(remaining)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .privacySensitive()
            }
            UsageRemainingBar(remainingPercent: window.remainingPercent, height: compact ? 4 : 5)
                .padding(.top, compact ? 1 : 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func titleLine(_ name: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font((compact ? Font.caption : .footnote).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(window.remainingPercent)%")
                .font((compact ? Font.footnote : .subheadline).weight(.semibold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .privacySensitive()
        }
    }

    private var accessibilityLabel: String {
        var text = "\(WindowPresentation.label(for: window)), \(window.remainingPercent) percent remaining"
        if let resetsAt = window.resetsAt,
           let spoken = FreshnessPresentation.spokenTimeRemaining(until: resetsAt, from: now) {
            text += ", \(spoken) left"
        }
        return text
    }
}

/// The offline marker a widget shows when the last fetch failed and it is
/// rendering a cached snapshot.
public struct StaleIndicator: View {
    public init() {}

    public var body: some View {
        Image(systemName: "wifi.slash")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// The top line every Home Screen widget draws for one provider: the headline
/// percentage, dominant, on the left; the provider's identity and the
/// reading's short age stacked on the right.
///
///     93%            </> Codex
///                       2m ago
///
/// One implementation, shared by the single-provider widget and both overview
/// widgets, so the family cannot drift into three ideas of what a provider's
/// header looks like.
public struct WidgetProviderHeader: View {
    public let providerId: String
    public let provider: UsageSyncProvider?
    public let now: Date
    public var isStale: Bool
    public var headlineSize: CGFloat
    /// A short window name to set beside the number, when the caller does not
    /// name the headline window anywhere else.
    public var headlineWindowTag: String?
    /// False only where a caller has run out of height and freshness is the
    /// least important fact left on the line.
    public var showsAge: Bool
    /// False where the number may scale down a little rather than decide how
    /// wide the header wants to be.
    public var headlineSetsWidth: Bool

    public init(
        providerId: String,
        provider: UsageSyncProvider?,
        now: Date,
        isStale: Bool = false,
        headlineSize: CGFloat,
        headlineWindowTag: String? = nil,
        showsAge: Bool = true,
        headlineSetsWidth: Bool = true
    ) {
        self.providerId = providerId
        self.provider = provider
        self.now = now
        self.isStale = isStale
        self.headlineSize = headlineSize
        self.headlineWindowTag = headlineWindowTag
        self.showsAge = showsAge
        self.headlineSetsWidth = headlineSetsWidth
    }

    private var measurement: UsageSyncMeasurement? { provider?.measurement }

    public var body: some View {
        HStack(alignment: .top, spacing: 4) {
            // The headline gives way first (it scales down) so the provider's
            // name and the reading's age are never truncated beside it.
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                WidgetHeadlineValue(percent: measurement?.headlineRemainingPercent, size: headlineSize)
                if let headlineWindowTag {
                    Text(headlineWindowTag)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(
                minWidth: headlineSetsWidth ? nil : 0,
                idealWidth: headlineSetsWidth ? nil : 0,
                alignment: .leading
            )
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 1) {
                ProviderTag(providerId: providerId, size: 11)
                if showsAge, let measurement {
                    // Freshness stays its own fact, never replaced by a
                    // countdown; the stale marker belongs beside it.
                    HStack(spacing: 3) {
                        if isStale { StaleIndicator() }
                        Text(FreshnessPresentation.shortAge(of: measurement, now: now))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()
                    }
                } else if isStale {
                    StaleIndicator()
                }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// The single-provider Home Screen widget.
///
///     93%            </> Codex
///                       2m ago
///     5 Hour               93%
///     3h 10m left
///     [==========        ]
///     Weekly               99%
///     6d 22h 10m left
///     [================= ]
///
/// The headline percentage leads, dominant, with the provider's identity and
/// the reading's age stacked beside it; then the five-hour and weekly blocks
/// take the rest of the height. Identity and age share the headline's line
/// because two legible window blocks, a large headline and a separate footer
/// line measure ~160pt against the ~126pt a small widget has — something had
/// to move, and it is not the numbers.
///
/// The medium overview draws two of these side by side, so a provider reads
/// the same on either widget.
///
/// Lives here rather than in the extension so its composition, and whether it
/// fits a small widget, can be tested.
public struct ProviderWidgetSmallContent: View {
    public let providerId: String
    public let provider: UsageSyncProvider?
    public let now: Date
    public var isStale: Bool

    public init(providerId: String, provider: UsageSyncProvider?, now: Date, isStale: Bool = false) {
        self.providerId = providerId
        self.provider = provider
        self.now = now
        self.isStale = isStale
    }

    private var measurement: UsageSyncMeasurement? { provider?.measurement }

    public var body: some View {
        // The readable form whenever it fits — every current iPhone at the
        // default text size — and the compact one only where it genuinely
        // does not: the smallest iPhones, or a larger Dynamic Type size.
        ViewThatFits(in: .vertical) {
            layout(compact: false)
            layout(compact: true)
        }
    }

    /// Internal rather than private so a test can measure each form against
    /// real widget sizes.
    func layout(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetProviderHeader(
                providerId: providerId,
                provider: provider,
                now: now,
                isStale: isStale,
                headlineSize: compact ? 24 : 28,
                headlineWindowTag: headlineWindowTag
            )

            if let measurement {
                let windows = WindowPresentation.widgetDetailWindows(in: measurement)
                if windows.isEmpty {
                    // No window to itemise, so the headline keeps a bar of its
                    // own rather than the widget losing its progress entirely.
                    UsageRemainingBar(remainingPercent: measurement.headlineRemainingPercent, height: 5)
                        .padding(.top, 8)
                    Spacer(minLength: 0)
                } else if windows.count == 1 {
                    WidgetWindowDetailRow(window: windows[0], now: now, compact: compact)
                        .padding(.top, compact ? 4 : 8)
                    Spacer(minLength: 0)
                } else {
                    // Two blocks share whatever height is left, so a taller
                    // widget breathes instead of leaving a blank band.
                    Spacer(minLength: compact ? 3 : 4)
                    WidgetWindowDetailRow(window: windows[0], now: now, compact: compact)
                    Spacer(minLength: compact ? 4 : 6)
                    WidgetWindowDetailRow(window: windows[1], now: now, compact: compact)
                }
            } else {
                UsageRemainingBar(remainingPercent: 0, height: 5)
                    .opacity(0.35)
                    .padding(.top, 8)
                Text(provider.map(ProviderPresentation.statusLabel) ?? "No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// When the headline window — the desktop's chosen one, resolved through
    /// `headlineWindowId` — is not one of the blocks below, its short name sits
    /// beside the number, so the number is never unattributed.
    private var headlineWindowTag: String? {
        guard let measurement,
              let window = HeadlinePresentation.window(in: measurement),
              !WindowPresentation.widgetDetailWindows(in: measurement)
                .contains(where: { $0.windowId == window.windowId }) else {
            return nil
        }
        return WindowPresentation.microLabel(for: window)
    }
}

/// One provider in the small overview widget, where two providers share a
/// square and neither can afford a detail list.
///
///     93%            </> Codex
///                       1m ago
///     5 Hour · 1h 31m left
///     [==========        ]
///
/// The same header as the single-provider widget, then the headline window —
/// the desktop's chosen one, which is not always the five-hour — with its own
/// precise countdown, then its bar. There is deliberately no second window
/// here: two providers' worth of weekly rows would not fit without undoing the
/// readability of the rest.
///
/// How much of the window line is drawn is the caller's `tier`, so the
/// overview can give both providers the same one.
public struct OverviewProviderSummary: View {
    public let providerId: String
    public let provider: UsageSyncProvider?
    public let now: Date
    public var isStale: Bool
    public var compact: Bool
    public var tier: SurfaceLinePresentation.LineTier
    public var showsAge: Bool

    public init(
        providerId: String,
        provider: UsageSyncProvider?,
        now: Date,
        isStale: Bool = false,
        compact: Bool = false,
        tier: SurfaceLinePresentation.LineTier = .full,
        showsAge: Bool = true
    ) {
        self.providerId = providerId
        self.provider = provider
        self.now = now
        self.isStale = isStale
        self.compact = compact
        self.tier = tier
        self.showsAge = showsAge
    }

    private var measurement: UsageSyncMeasurement? { provider?.measurement }

    private var lineFont: Font { compact ? .caption2 : .caption }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            WidgetProviderHeader(
                providerId: providerId,
                provider: provider,
                now: now,
                isStale: isStale,
                headlineSize: compact ? 20 : 24,
                showsAge: showsAge,
                // The readable size is chosen only where its number fits
                // unscaled; the compact size may scale a little instead.
                headlineSetsWidth: !compact
            )

            if let measurement {
                if let parts = SurfaceLinePresentation.headlineWindowParts(in: measurement, now: now, tier: tier) {
                    windowLine(parts)
                        .accessibilityLabel(
                            SurfaceLinePresentation.spokenHeadlineWindowLine(in: measurement, now: now) ?? ""
                        )
                }
                // The bar tracks the headline percentage printed above it, so
                // the colour and the number always describe the same window.
                UsageRemainingBar(remainingPercent: measurement.headlineRemainingPercent, height: compact ? 4 : 5)
                    .padding(.top, 1)
            } else {
                Text(provider.map(ProviderPresentation.statusLabel) ?? "No data")
                    .font(lineFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // A status sentence has no countdown to protect; it scales
                    // a little rather than deciding the whole overview's tier.
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                UsageRemainingBar(remainingPercent: 0, height: compact ? 4 : 5)
                    .opacity(0.35)
                    .padding(.top, 1)
            }
        }
    }

    /// "5 Hour · 1h 31m left": the window's name in `.primary`, its own
    /// countdown — the shared precise spelling — in `.secondary`. Its ideal
    /// width is real, so the overview only picks a tier whose line fits whole.
    private func windowLine(_ parts: SurfaceLinePresentation.WindowLineParts) -> some View {
        var line = Text("")
        if let name = parts.name {
            line = Text(name).fontWeight(.semibold).foregroundStyle(.primary)
        }
        if let remaining = parts.countdown {
            let separator = parts.name == nil ? "" : " · "
            line = line + Text(separator + remaining).foregroundStyle(.secondary)
        }
        return line
            .font(lineFont)
            .lineLimit(1)
            .privacySensitive()
    }
}

/// One provider's place in an overview widget: which provider, and its entry
/// in the snapshot — nil when the snapshot does not carry it.
public struct WidgetProviderSlot: Identifiable {
    public let id: String
    public let provider: UsageSyncProvider?

    public init(id: String, provider: UsageSyncProvider?) {
        self.id = id
        self.provider = provider
    }
}

/// The small overview widget: two provider summaries stacked, with no global
/// title — each block already names its provider, and the height a "UsageBar"
/// heading would cost is better spent on the numbers.
public struct OverviewSmallContent: View {
    public let providers: [WidgetProviderSlot]
    public let now: Date
    public var isStale: Bool

    public init(providers: [WidgetProviderSlot], now: Date, isStale: Bool = false) {
        self.providers = providers
        self.now = now
        self.isStale = isStale
    }

    /// One presentation for the whole overview: a type size, a line tier, and
    /// whether the reading's age still has room.
    public struct Form: Hashable {
        public let compact: Bool
        public let tier: SurfaceLinePresentation.LineTier
        public let showsAge: Bool

        public init(compact: Bool, tier: SurfaceLinePresentation.LineTier, showsAge: Bool = true) {
            self.compact = compact
            self.tier = tier
            self.showsAge = showsAge
        }
    }

    /// Tried in order; the first that fits in both directions wins. Every
    /// block is drawn in the same form, and because a stack is as wide as its
    /// widest block, one provider's long line steps *both* down together.
    ///
    /// What gives way, in order: the readable type size, then spacing, then —
    /// only when height runs out — the reading's age, then the window name a
    /// piece at a time. The countdown's components never do. The last form,
    /// the countdown alone ("6d23h59m") without the age, is what keeps the
    /// smallest widget at the largest measured text size from ever ending a
    /// countdown in an ellipsis.
    public static let forms: [Form] = {
        var forms = [
            Form(compact: false, tier: .full),
            Form(compact: false, tier: .short)
        ]
        for tier in SurfaceLinePresentation.LineTier.allCases {
            forms.append(Form(compact: true, tier: tier))
            forms.append(Form(compact: true, tier: tier, showsAge: false))
        }
        return forms
    }()

    public var body: some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            ForEach(Self.forms, id: \.self) { form in
                layout(form)
            }
        }
    }

    /// Internal rather than private so a test can measure each form against
    /// real widget sizes.
    func layout(_ form: Form) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Spacer(minLength: form.compact ? (form.showsAge ? 6 : 4) : 8)
                }
                OverviewProviderSummary(
                    providerId: item.id,
                    provider: item.provider,
                    now: now,
                    isStale: isStale,
                    compact: form.compact,
                    tier: form.tier,
                    showsAge: form.showsAge
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The medium overview widget: the single-provider widget, twice, divided.
///
/// A medium widget is a small one's height and about twice its width, so each
/// column has at least the room the single-provider widget was measured and
/// approved in. Reusing that view whole — rather than a medium-only
/// variant — is what keeps a provider reading identically on both.
public struct OverviewMediumContent: View {
    public let providers: [WidgetProviderSlot]
    public let now: Date
    public var isStale: Bool

    public init(providers: [WidgetProviderSlot], now: Date, isStale: Bool = false) {
        self.providers = providers
        self.now = now
        self.isStale = isStale
    }

    /// The gap either side of the central divider.
    static let columnSpacing: CGFloat = 12

    public var body: some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            ForEach(Array(providers.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                }
                ProviderWidgetSmallContent(
                    providerId: item.id,
                    provider: item.provider,
                    now: now,
                    isStale: isStale
                )
            }
        }
    }
}

/// A headline percentage.
///
/// Marked `privacySensitive` because quota levels are personal account
/// information and a Lock Screen widget is visible without unlocking. iOS
/// redacts it according to the user's own setting; that decision is theirs,
/// not this app's.
public struct WidgetHeadlineValue: View {
    public let percent: Int?
    public var size: CGFloat

    public init(percent: Int?, size: CGFloat = 34) {
        self.percent = percent
        self.size = size
    }

    public var body: some View {
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

/// Window labels, built from `kind` plus its qualifier.
public enum WindowPresentation {
    public static func label(for window: UsageSyncWindow) -> String {
        switch window.kind {
        case .fiveHour:
            return "5 Hour"
        case .weekly:
            return "Weekly"
        case .weeklyScoped:
            // The scope is a model or model-family slug, e.g. "opus".
            guard let scope = window.scope, !scope.isEmpty else { return "Weekly" }
            return "Weekly · \(prettyScope(scope))"
        case .duration:
            guard let minutes = window.durationMinutes else { return "Limit" }
            return durationLabel(minutes: minutes)
        case .unknown:
            // The forward-compatibility case: the desktop saw a window it could
            // not classify. Say so neutrally rather than inventing a meaning,
            // and never fall back to showing the raw windowId.
            guard let position = window.position else { return "Additional Limit" }
            return "Additional Limit \(position + 1)"
        }
    }

    /// A short form for surfaces with one line of text and no room to spend.
    ///
    /// Control Center renders a control's label and nothing else — no status
    /// line — so the window a headline came from has to share that one line
    /// with the provider name and the percentage. "5H" is the cost of saying
    /// *which* limit the number refers to, which is the difference between a
    /// figure and a fact.
    ///
    /// The `weeklyScoped` scope is deliberately dropped here rather than
    /// abbreviated: "Weekly · Opus" has no honest short form, and the Home
    /// Screen widget already shows it in full.
    public static func compactLabel(for window: UsageSyncWindow) -> String {
        switch window.kind {
        case .fiveHour:
            return "5H"
        case .weekly, .weeklyScoped:
            return "Weekly"
        case .duration:
            guard let minutes = window.durationMinutes else { return "Limit" }
            return compactDurationLabel(minutes: minutes)
        case .unknown:
            return "Limit"
        }
    }

    /// The shortest label that still identifies a window, for a widget's
    /// detail rows.
    ///
    /// A medium widget column already names the headline window in full — "5
    /// Hour · 4h 6m left" — so repeating "5 Hour" in the rows beneath it spends
    /// a scarce line saying something the column has already said. "5H" and "W"
    /// are enough to tell two rows apart once the context is established above.
    ///
    /// A scoped weekly keeps its scope rather than collapsing to "W", because
    /// Claude can show a plain weekly and a scoped weekly together, and two
    /// rows both labelled "W" would be worse than no label at all.
    public static func microLabel(for window: UsageSyncWindow) -> String {
        switch window.kind {
        case .fiveHour:
            return "5H"
        case .weekly:
            return "W"
        case .weeklyScoped:
            guard let scope = window.scope, !scope.isEmpty else { return "W" }
            return prettyScope(scope)
        case .duration:
            guard let minutes = window.durationMinutes else { return "L" }
            return compactDurationLabel(minutes: minutes)
        case .unknown:
            return "L"
        }
    }

    /// The shortest honest name for a window: its kind alone. A scoped weekly
    /// becomes the plain weekly marker "W" — its scope is dropped, never
    /// replaced — so a line with no room left can still say which kind of
    /// limit a countdown belongs to.
    public static func markerLabel(for window: UsageSyncWindow) -> String {
        window.kind == .weeklyScoped ? "W" : microLabel(for: window)
    }

    /// The windows a compact widget lists beneath its headline, at most
    /// `limit` of them.
    ///
    /// Chosen by *kind*, never by array position: the five-hour window first,
    /// then the plain weekly, because those are the two limits a person
    /// actually paces against. The snapshot does not promise that
    /// `windows[0]` is the five-hour one — Codex lists a multi-day limit after
    /// the weekly, and some accounts have no five-hour window at all.
    ///
    /// Only windows that are in the snapshot are returned. A missing weekly is
    /// not replaced by an empty row, and nothing is invented to fill the space.
    /// The one addition is the headline window itself, when it is neither of
    /// the two and there is still room, so the big number above the rows is
    /// never the only place its window appears.
    public static func widgetDetailWindows(
        in measurement: UsageSyncMeasurement,
        limit: Int = 2
    ) -> [UsageSyncWindow] {
        var chosen: [UsageSyncWindow] = []
        for kind in [UsageSyncWindowKind.fiveHour, .weekly] {
            if let window = measurement.windows.first(where: { $0.kind == kind }) {
                chosen.append(window)
            }
        }
        if chosen.count < limit,
           let headline = HeadlinePresentation.window(in: measurement),
           !chosen.contains(where: { $0.windowId == headline.windowId }) {
            chosen.append(headline)
        }
        return Array(chosen.prefix(limit))
    }

    /// The largest unit that stays exact, so a three-day limit reads "3D".
    static func compactDurationLabel(minutes: Int) -> String {
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24))D" }
        if minutes % 60 == 0 { return "\(minutes / 60)H" }
        return "\(minutes)M"
    }

    private static func prettyScope(_ scope: String) -> String {
        scope
            .split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Renders a window length in the largest unit that stays exact, so a
    /// three-day limit reads as "3 Day" rather than "4320 Minute".
    static func durationLabel(minutes: Int) -> String {
        if minutes % (60 * 24) == 0 {
            let days = minutes / (60 * 24)
            return "\(days) Day"
        }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return "\(hours) Hour"
        }
        return "\(minutes) Minute"
    }
}

/// The one place any mobile surface resolves "which window is the headline".
///
/// The desktop has already chosen. `headlineRemainingPercent` is the number it
/// chose, and `headlineWindowId` names the window that produced it — so every
/// label and every countdown shown beside that percentage has to come from
/// *that* window.
///
/// `windows.first` is not it, and the difference is not theoretical: Codex's
/// headline is its most constrained window, which can legitimately be a
/// multi-day `duration` limit listed after the weekly one. A surface that read
/// the first window would then print a five-hour or weekly label beside a
/// three-day number, and a countdown to the wrong reset — confidently, and
/// wrongly, on a Lock Screen.
///
/// One resolver, used by the dashboard, the widgets and Control Center alike.
public enum HeadlinePresentation {
    /// The window `headlineWindowId` names, or nil when the snapshot does not
    /// contain it. Never a fallback guess: a missing headline window means the
    /// label and countdown are simply not shown, while the percentage — which
    /// is the desktop's own answer either way — still is.
    public static func window(in measurement: UsageSyncMeasurement) -> UsageSyncWindow? {
        measurement.windows.first { $0.windowId == measurement.headlineWindowId }
    }

    /// The headline window's full label, e.g. "5 Hour" or "Weekly · Opus".
    public static func label(in measurement: UsageSyncMeasurement) -> String? {
        window(in: measurement).map(WindowPresentation.label)
    }

    /// The headline window's short label, e.g. "5H", "Weekly", "3D".
    public static func compactLabel(in measurement: UsageSyncMeasurement) -> String? {
        window(in: measurement).map(WindowPresentation.compactLabel)
    }

    /// When the headline window resets, if it says.
    public static func resetsAt(in measurement: UsageSyncMeasurement) -> Date? {
        window(in: measurement)?.resetsAt
    }

    /// How long the headline window has left — "17m left", "2h 59m left",
    /// "1d 3h 14m left".
    ///
    /// Nil when the window carries no reset time, when the reset has already
    /// passed, or when the headline window is not in the snapshot. A countdown
    /// that has expired is not information.
    public static func compactReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.compactTimeRemaining(until: resetsAt, from: now)
    }

    /// The same interval with the spaces spent as digits — "2h59m" — for the
    /// Lock Screen and Control Center.
    public static func tightReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.tightTimeRemaining(until: resetsAt, from: now)
    }

    /// The interval spelled for VoiceOver — "2 hours 59 minutes".
    public static func spokenReset(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let resetsAt = resetsAt(in: measurement) else { return nil }
        return FreshnessPresentation.spokenTimeRemaining(until: resetsAt, from: now)
    }
}

/// The composed strings the widgets render.
///
/// They live here rather than inside the widget extension for one practical
/// reason: an app extension cannot be `@testable`-imported, so a line built
/// inline in `WidgetViews.swift` could never be asserted. Keeping the text here
/// means every surface's wording is under test, and the views stay layout only.
public enum SurfaceLinePresentation {
    /// The line under a provider widget's headline: which window the number
    /// belongs to, and how long that window has left.
    ///
    /// The Home Screen has room for the spaced form, so this is where the
    /// countdown reads at its most legible — "5 Hour · 2h 59m left". Nil when
    /// the headline window is not in the snapshot: a label is not invented,
    /// though the percentage is still shown above it.
    public static func headlineWindowLine(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let window = HeadlinePresentation.window(in: measurement) else { return nil }
        let label = WindowPresentation.label(for: window)
        guard let remaining = windowCountdown(for: window, now: now) else { return label }
        return "\(label) · \(remaining)"
    }

    /// The two halves of a headline window line, for a surface that styles
    /// them differently: the window's name, and that window's own countdown.
    /// `name` is nil only in the last-resort tier, where the countdown stands
    /// alone.
    public struct WindowLineParts: Equatable {
        public let name: String?
        public let countdown: String?
    }

    /// How much of a headline window line survives, from everything down to
    /// the countdown alone.
    ///
    /// The order is the order information is given up in: first the full
    /// window name, then the spaces in the countdown, then the name entirely.
    /// The countdown's *components* are never given up — every tier keeps
    /// every significant day, hour and minute — so a narrow line can lose
    /// words but never become an inexact time.
    public enum LineTier: CaseIterable, Sendable {
        /// "Weekly · Opus · 6d 23h 59m left"
        case full
        /// "Opus · 6d 23h 59m left"
        case short
        /// "Opus · 6d23h59m" — the Lock Screen's spelling
        case shortTight
        /// "W · 6d23h59m" — the scope dropped, the kind kept
        case markerTight
        /// "6d23h59m"
        case countdownOnly
    }

    /// The headline window — resolved through `headlineWindowId`, never by
    /// position — as a name and its countdown, spelled for `tier`. Nil when
    /// the snapshot does not carry the headline window: nothing is invented.
    ///
    /// The window names are only ever that window's own: its full label, its
    /// micro label, or — for a scoped weekly — the plain weekly marker. None
    /// of them can turn a weekly or a three-day limit into a "5 Hour".
    public static func headlineWindowParts(
        in measurement: UsageSyncMeasurement,
        now: Date = Date(),
        tier: LineTier = .full
    ) -> WindowLineParts? {
        guard let window = HeadlinePresentation.window(in: measurement) else { return nil }
        let spaced = windowCountdown(for: window, now: now)
        let tight = window.resetsAt.flatMap { FreshnessPresentation.tightTimeRemaining(until: $0, from: now) }
        switch tier {
        case .full:
            return WindowLineParts(name: WindowPresentation.label(for: window), countdown: spaced)
        case .short:
            return WindowLineParts(name: WindowPresentation.microLabel(for: window), countdown: spaced)
        case .shortTight:
            return WindowLineParts(name: WindowPresentation.microLabel(for: window), countdown: tight)
        case .markerTight:
            return WindowLineParts(name: WindowPresentation.markerLabel(for: window), countdown: tight)
        case .countdownOnly:
            // With no countdown to keep, the name is all there is to say.
            guard let tight else {
                return WindowLineParts(name: WindowPresentation.markerLabel(for: window), countdown: nil)
            }
            return WindowLineParts(name: nil, countdown: tight)
        }
    }

    /// What VoiceOver says for a headline window line, whatever tier is drawn:
    /// the full window name and the full countdown, in words — "Weekly · Opus,
    /// 6 days 23 hours 59 minutes left".
    public static func spokenHeadlineWindowLine(
        in measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String? {
        guard let window = HeadlinePresentation.window(in: measurement) else { return nil }
        let name = WindowPresentation.label(for: window)
        guard let resetsAt = window.resetsAt,
              let spoken = FreshnessPresentation.spokenTimeRemaining(until: resetsAt, from: now) else {
            return name
        }
        return "\(name), \(spoken) left"
    }

    /// The Lock Screen rectangular footer, where one cramped line has to carry
    /// both facts: "2h59m left · 3m ago".
    ///
    /// Both are shortened rather than one being dropped, and the countdown uses
    /// the tight spelling so that *both* of its components survive on a line
    /// this narrow — losing the minutes was the old behaviour this checkpoint
    /// exists to remove. "left" is kept because it is what distinguishes time
    /// remaining from the age sitting next to it. The age is still `measuredAt`
    /// and still carries no stale threshold.
    public static func accessoryFooter(
        of measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String {
        let age = FreshnessPresentation.shortAge(of: measurement, now: now)
        guard let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return age
        }
        return "\(remaining) left · \(age)"
    }

    /// The Lock Screen inline string. The percentage comes first so that the
    /// countdown is what a truncation costs, and the countdown is tight so that
    /// it keeps its minutes — "Codex 39% · 4h59m".
    public static func inline(
        name: String,
        percent: Int,
        measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String {
        guard let measurement,
              let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return "\(name) \(percent)%"
        }
        return "\(name) \(percent)% · \(remaining)"
    }

    /// Any one window's own countdown — "4h 52m left", "6d 13h 12m left" — for
    /// the provider widget's per-window rows.
    ///
    /// The same precise, floored decomposition every other surface uses, from
    /// that window's own `resetsAt`, not the headline's. Nil when the window
    /// has no reset or it has passed, and then no countdown is drawn at all.
    public static func windowCountdown(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        return FreshnessPresentation.compactTimeRemaining(until: resetsAt, from: now)
    }

    /// The already-separated countdown an overview row appends after a
    /// percentage, or nil when there is nothing to count down to.
    ///
    /// Tight, because the overview carries two providers on one line and the
    /// alternative to spending the space is dropping the minutes.
    public static func countdownSuffix(
        in measurement: UsageSyncMeasurement?,
        now: Date = Date()
    ) -> String? {
        guard let measurement,
              let remaining = HeadlinePresentation.tightReset(in: measurement, now: now) else {
            return nil
        }
        return "· \(remaining)"
    }
}

/// The floored day/hour/minute remainder of a live countdown.
///
/// One decomposition, shared by the dashboard, the Home Screen widgets, the
/// Lock Screen accessories and Control Center, so no surface can arrive at its
/// own arithmetic. Each surface chooses only how to *spell* the result.
///
/// It replaces an earlier policy that rendered the largest whole unit alone, so
/// that "2h 59m" read as "2h left" and "1d 3h 14m" as "1d left". Flooring to a
/// single unit is safe in the sense that it never overstates the time left, but
/// it discards up to an hour — or up to a day — of real interval, and a person
/// deciding whether to keep working needs the remainder, not its leading digit.
///
/// Seconds are still floored away, because every surface promises minute
/// resolution and a countdown that renders seconds would have to tick to stay
/// true. What is no longer discarded is the part of the interval that matters.
struct ResetRemainder: Equatable {
    let days: Int
    let hours: Int
    let minutes: Int

    /// Nil when the reset is already past: a negative countdown is not
    /// information, and the snapshot it came from is by then stale anyway.
    init?(until resetsAt: Date, from now: Date) {
        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else { return nil }
        // A window with forty seconds left is still open, and "0m left" would
        // say it had closed. Under a minute is reported as the minute it is
        // still inside.
        let totalMinutes = max(seconds / 60, 1)
        days = totalMinutes / (60 * 24)
        hours = (totalMinutes % (60 * 24)) / 60
        minutes = totalMinutes % 60
    }

    /// The significant components, largest first, with zeroes dropped.
    ///
    /// This is the whole policy: `2h 59m` keeps its minutes and `1d 3h 14m`
    /// keeps all three parts, while `1d 0h 0m` collapses to a bare "1d",
    /// because a zero component is noise rather than precision. `1d 0h 14m`
    /// therefore reads "1d 14m" — the hours are genuinely zero, so printing
    /// them would say nothing.
    private var units: [(value: Int, short: String, spoken: String)] {
        [
            (days, "d", "day"),
            (hours, "h", "hour"),
            (minutes, "m", "minute")
        ].filter { $0.value > 0 }
    }

    /// "1d 3h 14m" — for surfaces with room to breathe.
    var spaced: String {
        units.map { "\($0.value)\($0.short)" }.joined(separator: " ")
    }

    /// "1d3h14m" — for Control Center and the Lock Screen, where a space is a
    /// character that could have been a digit. Every component survives; only
    /// the whitespace is spent.
    var tight: String {
        units.map { "\($0.value)\($0.short)" }.joined()
    }

    /// "1 day 3 hours 14 minutes" — what VoiceOver should say, since "1d3h14m"
    /// is not a sentence.
    var spoken: String {
        units
            .map { "\($0.value) \($0.spoken)\($0.value == 1 ? "" : "s")" }
            .joined(separator: " ")
    }
}

/// Freshness.
public enum FreshnessPresentation {
    /// Age comes from the provider's own `measuredAt` and never from the
    /// snapshot's `generatedAt`.
    ///
    /// `generatedAt` is when the *document* was built, which advances every
    /// time the desktop serializes — including when a provider's reading is
    /// retained, stale or paused. Using it would make a week-old measurement
    /// look seconds fresh, which is precisely the failure the contract was
    /// shaped to prevent.
    public static func age(of measurement: UsageSyncMeasurement, now: Date = Date()) -> String {
        relativeAge(from: measurement.measuredAt, to: now)
    }

    /// How long a window has left, at minute resolution — "17m left",
    /// "1h 7m left", "2h 59m left", "1d 3h 14m left".
    ///
    /// Returns `nil` when the window has no reset time, or when that time has
    /// already passed.
    public static func compactTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now).map { "\($0.spaced) left" }
    }

    /// The same interval with its spaces spent — "2h59m" — for the one-line
    /// surfaces. No "left" suffix: the caller adds one where the line has room
    /// and the word earns its place.
    public static func tightTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now)?.tight
    }

    /// The interval as VoiceOver should read it — "2 hours 59 minutes".
    public static func spokenTimeRemaining(until resetsAt: Date, from now: Date = Date()) -> String? {
        ResetRemainder(until: resetsAt, from: now)?.spoken
    }

    /// Phase 5 states the age as a fact and draws no conclusion from it. No
    /// "stale" threshold is invented here: what counts as too old is a client
    /// policy question that has not been decided, and a wrong threshold is
    /// worse than none.
    static func relativeAge(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 0 { return "Updated just now" }
        if seconds < 60 { return "Updated just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "Updated 1 day ago" : "Updated \(days) days ago"
    }

    /// The headline's two facts in one sentence: how old the reading is, and
    /// how long its window has left.
    ///
    /// The card renders them on separate lines so that neither can be mistaken
    /// for the other, and uses this composed form as the accessibility label —
    /// VoiceOver reads one sentence where the eye reads two rows. A future
    /// reset must never make an old measurement look fresh — a desktop asleep
    /// for two days can still hold a reading whose five-hour window resets in
    /// an hour — so the age is always present and always first.
    public static func headlineMetadata(
        of measurement: UsageSyncMeasurement,
        now: Date = Date()
    ) -> String {
        let age = self.age(of: measurement, now: now)
        guard let remaining = HeadlinePresentation.compactReset(in: measurement, now: now) else {
            return age
        }
        return "\(age) · \(remaining)"
    }

    /// The shortest honest age, for surfaces with one cramped line.
    ///
    /// Same source as every other freshness string — `measuredAt`, never
    /// `generatedAt` — and deliberately no stale threshold: what counts as too
    /// old is a client policy question that has not been decided, and a wrong
    /// threshold is worse than none.
    public static func shortAge(of measurement: UsageSyncMeasurement, now: Date = Date()) -> String {
        shortAge(from: measurement.measuredAt, to: now)
    }

    static func shortAge(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date).rounded())
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    /// Reset times are absolute instants; show them in the phone's locale.
    public static func resetLabel(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        return "Resets \(absoluteReset(resetsAt, now: now))"
    }

    /// A detail row's reset fact, in full: how long is left, and when exactly —
    /// "Resets in 4h 59m · 4:59 PM".
    ///
    /// The two are not redundant. The countdown answers "how much longer may I
    /// keep going?", which is the question a quota provokes; the clock time
    /// answers "when exactly?", which is what someone plans an afternoon
    /// around. A multi-day window needs the date as well, so the absolute part
    /// widens to "Sep 27, 9:59 PM" once the reset is not today.
    ///
    /// Once the reset has passed there is no interval left to state, so the row
    /// falls back to the absolute instant alone rather than printing a zero or
    /// a negative countdown.
    public static func resetSummary(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let clock = absoluteReset(resetsAt, now: now)
        guard let remainder = ResetRemainder(until: resetsAt, from: now) else {
            return "Resets \(clock)"
        }
        return "Resets in \(remainder.spaced) · \(clock)"
    }

    /// What VoiceOver should say for a detail row's reset.
    public static func spokenResetSummary(for window: UsageSyncWindow, now: Date = Date()) -> String? {
        guard let resetsAt = window.resetsAt else { return nil }
        let clock = absoluteReset(resetsAt, now: now)
        guard let remainder = ResetRemainder(until: resetsAt, from: now) else {
            return "Resets at \(clock)"
        }
        return "Resets in \(remainder.spoken), at \(clock)"
    }

    /// The locale's own rendering of an instant. `Locale.autoupdatingCurrent`
    /// decides 12- or 24-hour; this code never assumes one.
    private static func absoluteReset(_ resetsAt: Date, now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        if Calendar.current.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateStyle = .none
            formatter.timeStyle = .short
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
        }
        return formatter.string(from: resetsAt)
    }
}
