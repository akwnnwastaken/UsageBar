import CoreGraphics
import Foundation

public enum AppLanguage: String {
    case turkish
    case english

    public static func preferred(from preferredLanguages: [String]) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("tr") == true ? .turkish : .english
    }
}

public enum UsageAlertLevel: Equatable {
    case normal
    case warning
    case critical
}

public enum UsageAlertPreset: String, CaseIterable {
    case late
    case balanced
    case early

    public var warningThreshold: Int {
        switch self {
        case .late: return 10
        case .balanced: return 20
        case .early: return 30
        }
    }

    public var criticalThreshold: Int {
        switch self {
        case .late: return 5
        case .balanced: return 10
        case .early: return 15
        }
    }
}

public struct UsageAlertPolicy {
    public let isEnabled: Bool
    public let preset: UsageAlertPreset

    public init(isEnabled: Bool, preset: UsageAlertPreset) {
        self.isEnabled = isEnabled
        self.preset = preset
    }

    public func level(for remainingPercent: Int) -> UsageAlertLevel {
        guard isEnabled else { return .normal }
        let clamped = min(100, max(0, remainingPercent))
        if clamped <= preset.criticalThreshold { return .critical }
        if clamped <= preset.warningThreshold { return .warning }
        return .normal
    }
}

/// Sağlayıcılar kalan yüzdeyi tam sayıya yuvarlayarak bildirir, bu yüzden gerçek
/// değer bir yuvarlama sınırındayken ardışık iki ölçüm 41 ↔ 42 gibi oynayabilir.
/// Ayrıca yeni spawn edilen bir okuyucu oturumu bazen server tarafında
/// cache'lenmiş, canlı değerin gerisinde kalan eski bir snapshot alabilir; bu da
/// 33 → 38 gibi birkaç puanlık sahte bir geri sıçrama olarak görünür.
/// Bir pencere içinde kalan yüzde gerçekte artamayacağı için, reset eşiğinin
/// altındaki (`riseHoldThreshold`) tüm yükselişler gösterimde bekletilir.
/// Sıçrama üst üste ölçümlerde de sürüyorsa kabul edilir; böylece gecikme birkaç
/// yenileme döngüsüyle sınırlı kalır ve gerçek bir artış kalıcı olarak gizlenmez.
/// Reset (~%100'e büyük sıçrama) eşiğin üstünde kaldığı için anında gösterilir.
/// Kayıtlı geçmiş her zaman ham kalır.
public enum UsageDisplayNoiseFilter {
    /// Bir yükselişin gerçek kabul edilmesi için gereken üst üste ölçüm sayısı.
    /// Gözlenen dalgalanmalar iki ölçüm sürebildiği için eşik üçtür; böylece
    /// gösterim en fazla üç yenileme geriden gelir ve kalıcı olarak yanlış kalmaz.
    public static let risePersistenceThreshold = 3

    /// Bu değerin altındaki yükselişler sahte (yuvarlama gürültüsü ya da eski
    /// snapshot geri sıçraması) kabul edilip bekletilir; bu değer ve üzeri
    /// yükselişler gerçek reset sayılıp anında geçirilir. Gözlenen geri
    /// sıçramalar birkaç puanlıktır (+4, +5); gerçek reset ise ~%100'e sıçradığı
    /// için 12'nin çok üstünde kalır.
    public static let riseHoldThreshold = 12

    public struct Decision: Equatable {
        public let displayed: Int
        public let pendingRise: Int?
        public let pendingCount: Int

        public init(displayed: Int, pendingRise: Int?, pendingCount: Int) {
            self.displayed = displayed
            self.pendingRise = pendingRise
            self.pendingCount = pendingCount
        }
    }

    public static func decide(
        raw: Int,
        previouslyDisplayed: Int?,
        pendingRise: Int?,
        pendingCount: Int
    ) -> Decision {
        let accepted = Decision(displayed: raw, pendingRise: nil, pendingCount: 0)
        guard let previouslyDisplayed else { return accepted }
        // Düşüşler gerçektir; reset eşiği ve üzeri sıçramalar (sıfırlama) da anında
        // gösterilir. Aradaki küçük yükselişler (yuvarlama / eski snapshot) bekletilir.
        let rise = raw - previouslyDisplayed
        guard rise >= 1, rise < riseHoldThreshold else { return accepted }
        let count = (pendingRise == raw ? pendingCount : 0) + 1
        guard count < risePersistenceThreshold else { return accepted }
        return Decision(displayed: previouslyDisplayed, pendingRise: raw, pendingCount: count)
    }
}

/// Outcome of a Codex quota fetch, decided from pure inputs so the ordering is
/// testable without spawning a process. The key rule: a fetch that ran out of
/// time is a **timeout**, even though UsageBar's own SIGTERM/SIGKILL leaves the
/// child with a non-zero termination status — that status must never be read as
/// a command failure. `terminationStatus` is therefore only consulted after the
/// timeout verdict, and only once the process has actually been reaped.
public enum CodexFetchOutcome: Equatable {
    case usage
    case outputTooLarge
    case incompatible
    case timedOut
    case commandFailed
    case emptyResponse

    public static func classify(
        hasUsage: Bool,
        outputExceeded: Bool,
        incompatible: Bool,
        didTimeout: Bool,
        terminationStatus: Int32
    ) -> CodexFetchOutcome {
        if outputExceeded { return .outputTooLarge }
        if hasUsage { return .usage }
        // Timeout wins over a non-zero exit: the non-zero status is a side
        // effect of the signal we sent to stop the timed-out process.
        if didTimeout { return .timedOut }
        if incompatible { return .incompatible }
        if terminationStatus != 0 { return .commandFailed }
        return .emptyResponse
    }
}

public enum UsageRefreshInterval: String, CaseIterable {
    case oneMinute
    case twoMinutes
    case fiveMinutes

    public static let fallback: UsageRefreshInterval = .fiveMinutes

    public var minutes: Int {
        switch self {
        case .oneMinute: return 1
        case .twoMinutes: return 2
        case .fiveMinutes: return 5
        }
    }

    public var seconds: TimeInterval { TimeInterval(minutes * 60) }

    public static func resolved(from rawValue: String?) -> UsageRefreshInterval {
        guard let rawValue, let interval = UsageRefreshInterval(rawValue: rawValue) else {
            return fallback
        }
        return interval
    }
}

public enum UsageRefreshPolicy {
    /// Menü açıldığında verinin bu süreden eskiyse yeniden okunması istenir.
    public static let menuOpenStalenessThreshold: TimeInterval = 30

    public static func shouldRefreshOnMenuOpen(lastUpdated: Date?, now: Date) -> Bool {
        guard let lastUpdated else { return false }
        return now.timeIntervalSince(lastUpdated) > menuOpenStalenessThreshold
    }
}

public enum ProviderRotation {
    public static let interval: TimeInterval = 30

    public static func nextIndex(after currentIndex: Int, providerCount: Int) -> Int {
        guard providerCount > 0 else { return 0 }
        return (max(0, currentIndex) + 1) % providerCount
    }
}

/// Pure state transition for disconnecting a provider, so the selection and
/// auto-rotate rules are testable without the AppKit menu.
public enum ProviderConnectionTransition {
    /// The provider that should be status-selected after `disconnected` is removed.
    /// Keeps the previous selection if it is still connected; otherwise falls back
    /// to whatever remains (nil if nothing does).
    public static func selection(
        afterDisconnecting disconnected: String,
        remaining: [String],
        previousSelection: String?
    ) -> String? {
        if let previousSelection,
           previousSelection != disconnected,
           remaining.contains(previousSelection) {
            return previousSelection
        }
        return remaining.first
    }

    /// Auto-rotate only makes sense with two or more connected providers.
    public static func autoRotateStaysEnabled(remainingCount: Int, wasEnabled: Bool) -> Bool {
        wasEnabled && remainingCount > 1
    }
}

// MARK: - Provider usage models

public enum UsageWindowKind: Equatable {
    case fiveHour
    case weekly
    case duration(minutes: Int)
    case unknown(position: Int)

    public static func classified(durationMinutes: Int?, position: Int) -> UsageWindowKind {
        guard let durationMinutes else { return .unknown(position: position) }
        if (4 * 60)...(6 * 60) ~= durationMinutes { return .fiveHour }
        if (6 * 24 * 60)...(8 * 24 * 60) ~= durationMinutes { return .weekly }
        return .duration(minutes: durationMinutes)
    }

    public var historyKey: String {
        switch self {
        case .fiveHour: return "five-hour"
        case .weekly: return "weekly"
        case .duration(let minutes): return "duration-\(minutes)"
        case .unknown(let position): return "unknown-\(position)"
        }
    }
}

public struct UsageWindow {
    public let kind: UsageWindowKind
    public let usedPercent: Int
    public let resetsAt: Date?
    public let durationMinutes: Int?

    public init(
        kind: UsageWindowKind? = nil,
        usedPercent: Int,
        resetsAt: Date?,
        durationMinutes: Int?,
        position: Int = 0
    ) {
        self.kind = kind ?? .classified(durationMinutes: durationMinutes, position: position)
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }
}

public enum ProviderIssue {
    case refreshing
    case noData
    case codexUsageUnavailable
    case codexLimitMissing
    case codexNotFound
    case codexUntrustedExecutable
    case codexTimedOut
    case codexEmptyResponse
    case codexIncompatible
    case codexCommandFailed
    case codexLaunchFailed(String)
    case claudeNotFound
    case claudeUntrustedExecutable
    case claudeNotLoggedIn
    case claudeUsageUnreadable
    case claudeUsageTimedOut
    case claudeLaunchFailed(String)
    case outputTooLarge(String)

    public var diagnosticCode: String {
        switch self {
        case .refreshing: return "refreshing"
        case .noData: return "no_data"
        case .codexUsageUnavailable: return "codex_usage_unavailable"
        case .codexLimitMissing: return "codex_limit_missing"
        case .codexNotFound: return "codex_not_found"
        case .codexUntrustedExecutable: return "codex_untrusted_executable"
        case .codexTimedOut: return "codex_timed_out"
        case .codexEmptyResponse: return "codex_empty_response"
        case .codexIncompatible: return "codex_incompatible"
        case .codexCommandFailed: return "codex_command_failed"
        case .codexLaunchFailed: return "codex_launch_failed"
        case .claudeNotFound: return "claude_not_found"
        case .claudeUntrustedExecutable: return "claude_untrusted_executable"
        case .claudeNotLoggedIn: return "claude_not_logged_in"
        case .claudeUsageUnreadable: return "claude_usage_unreadable"
        case .claudeUsageTimedOut: return "claude_usage_timed_out"
        case .claudeLaunchFailed: return "claude_launch_failed"
        case .outputTooLarge: return "output_too_large"
        }
    }
}

public struct ProviderUsage {
    public let name: String
    public let windows: [UsageWindow]
    public let error: ProviderIssue?
    public let lastSuccessfulAt: Date?

    public init(
        name: String,
        windows: [UsageWindow],
        error: ProviderIssue?,
        lastSuccessfulAt: Date? = nil
    ) {
        self.name = name
        self.windows = windows
        self.error = error
        self.lastSuccessfulAt = lastSuccessfulAt
    }

    public var session: UsageWindow? { windows.first { $0.kind == .fiveHour } }
    public var weekly: UsageWindow? { windows.first { $0.kind == .weekly } }
    public var isStale: Bool { error != nil && !windows.isEmpty && lastSuccessfulAt != nil }

    public static func unavailable(_ name: String, _ issue: ProviderIssue) -> ProviderUsage {
        ProviderUsage(name: name, windows: [], error: issue)
    }

    public func replacingWindows(_ replacements: [UsageWindow]) -> ProviderUsage {
        ProviderUsage(
            name: name,
            windows: replacements,
            error: error,
            lastSuccessfulAt: lastSuccessfulAt
        )
    }

    public func markedSuccessful(at date: Date) -> ProviderUsage {
        ProviderUsage(name: name, windows: windows, error: nil, lastSuccessfulAt: date)
    }

    public static func stale(from previous: ProviderUsage, issue: ProviderIssue) -> ProviderUsage {
        ProviderUsage(
            name: previous.name,
            windows: previous.windows,
            error: issue,
            lastSuccessfulAt: previous.lastSuccessfulAt
        )
    }
}

// MARK: - Usage history models

public struct UsageHistorySample: Codable, Equatable {
    public let recordedAt: Date
    public let remainingPercent: Int

    public init(recordedAt: Date, remainingPercent: Int) {
        self.recordedAt = recordedAt
        self.remainingPercent = remainingPercent
    }
}

public enum UsageHistoryModel {
    public static let retentionInterval: TimeInterval = 24 * 60 * 60
    public static let minimumSampleInterval: TimeInterval = 60
    public static let maximumSamplesPerSeries = 24 * 60 + 1
    public static let maximumSeries = 16
    public static let maximumEncodedBytes = 1 * 1_024 * 1_024

    public static func adding(
        remainingPercent: Int,
        at date: Date,
        to existing: [UsageHistorySample]
    ) -> [UsageHistorySample] {
        let cutoff = date.addingTimeInterval(-retentionInterval)
        var samples = existing.filter { $0.recordedAt >= cutoff && $0.recordedAt <= date }
        let sample = UsageHistorySample(
            recordedAt: date,
            remainingPercent: min(100, max(0, remainingPercent))
        )
        if let last = samples.last,
           date.timeIntervalSince(last.recordedAt) < minimumSampleInterval {
            samples[samples.count - 1] = sample
        } else {
            samples.append(sample)
        }
        return Array(samples.suffix(maximumSamplesPerSeries))
    }

    public static func encode(_ history: [String: [UsageHistorySample]]) -> Data? {
        try? JSONEncoder().encode(history)
    }

    public static func decode(_ data: Data?) -> [String: [UsageHistorySample]] {
        guard let data, data.count <= maximumEncodedBytes else { return [:] }
        return (try? JSONDecoder().decode([String: [UsageHistorySample]].self, from: data)) ?? [:]
    }

    public static func sanitized(
        _ history: [String: [UsageHistorySample]],
        now: Date
    ) -> [String: [UsageHistorySample]] {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        let latestAllowedDate = now.addingTimeInterval(minimumSampleInterval)
        var result: [String: [UsageHistorySample]] = [:]

        for key in history.keys.sorted().prefix(maximumSeries) where key.count <= 128 {
            let candidates = (history[key] ?? [])
                .filter { $0.recordedAt >= cutoff && $0.recordedAt <= latestAllowedDate }
                .sorted { $0.recordedAt < $1.recordedAt }
            var samples: [UsageHistorySample] = []
            for candidate in candidates {
                let normalized = UsageHistorySample(
                    recordedAt: candidate.recordedAt,
                    remainingPercent: min(100, max(0, candidate.remainingPercent))
                )
                if let last = samples.last,
                   normalized.recordedAt.timeIntervalSince(last.recordedAt) < minimumSampleInterval {
                    samples[samples.count - 1] = normalized
                } else {
                    samples.append(normalized)
                }
            }
            if !samples.isEmpty {
                result[key] = Array(samples.suffix(maximumSamplesPerSeries))
            }
        }
        return result
    }
}

public struct UsageHistoryChartModel {
    public static let resetJumpThreshold = 20
    public static let minimumVerticalSpan = 10.0

    public let samples: [UsageHistorySample]
    public let displaySamples: [UsageHistorySample]
    public let lowerBound: Double
    public let upperBound: Double

    public init(samples: [UsageHistorySample]) {
        let sortedSamples = samples.sorted { $0.recordedAt < $1.recordedAt }
        self.samples = sortedSamples

        // A window's remaining percentage only falls until the window resets (a
        // large upward jump back toward ~100%). To make each period a distinct,
        // readable arc, the chart begins at the most recent reset instead of
        // spanning the whole retained history — so once Claude's five-hour
        // window resets to ~100%, the chart starts over from that point.
        let resetStarts = sortedSamples.indices.dropFirst().filter { index in
            sortedSamples[index].remainingPercent - sortedSamples[index - 1].remainingPercent
                >= Self.resetJumpThreshold
        }
        let windowStart = resetStarts.last ?? 0
        let windowSamples = Array(sortedSamples[windowStart...])

        displaySamples = windowSamples.enumerated().map { index, sample in
            guard index > 0, index < windowSamples.count - 1 else { return sample }
            let previous = windowSamples[index - 1].remainingPercent
            let current = sample.remainingPercent
            let next = windowSamples[index + 1].remainingPercent
            guard previous == next, abs(current - previous) == 1 else { return sample }
            return UsageHistorySample(recordedAt: sample.recordedAt, remainingPercent: previous)
        }
        let values = displaySamples.map { Double(min(100, max(0, $0.remainingPercent))) }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 100
        let rawSpan = maximum - minimum
        let padding = max(2, rawSpan * 0.15)
        let desiredSpan = max(Self.minimumVerticalSpan, rawSpan + padding * 2)
        var lower = floor((minimum + maximum - desiredSpan) / 2)
        var upper = ceil((minimum + maximum + desiredSpan) / 2)

        if lower < 0 {
            upper = min(100, upper - lower)
            lower = 0
        }
        if upper > 100 {
            lower = max(0, lower - (upper - 100))
            upper = 100
        }
        if upper <= lower {
            lower = 0
            upper = 100
        }

        lowerBound = lower
        upperBound = upper
    }

    /// Duration of the shown window (since the last reset), not the full history.
    public var recordedDuration: TimeInterval {
        guard let first = displaySamples.first, let last = displaySamples.last else { return 0 }
        return max(0, last.recordedAt.timeIntervalSince(first.recordedAt))
    }

    /// Net change across the shown window (since the last reset).
    public var delta: Int? {
        guard let first = displaySamples.first, let last = displaySamples.last,
              displaySamples.count > 1 else { return nil }
        return last.remainingPercent - first.remainingPercent
    }

    public func normalizedY(for remainingPercent: Int) -> CGFloat {
        let clamped = Double(min(100, max(0, remainingPercent)))
        return CGFloat((clamped - lowerBound) / (upperBound - lowerBound))
    }
}

// MARK: - Usage summary

public struct UsageSummary {
    public let providerName: String
    public let remainingPercent: Int
    public let resetsAt: Date?
    public let windowKind: UsageWindowKind

    public init(providerName: String, remainingPercent: Int, resetsAt: Date?, windowKind: UsageWindowKind) {
        self.providerName = providerName
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.windowKind = windowKind
    }
}

public enum UsageSummaryCalculator {
    public static func summary(for providerName: String, in usages: [String: ProviderUsage]) -> UsageSummary? {
        guard let usage = usages[providerName] else { return nil }
        let selectedWindow: UsageWindow?
        if providerName == "Claude Code" {
            // Claude's menu-bar value represents the active five-hour window.
            // Fall back to weekly only when Claude does not return session data.
            selectedWindow = usage.session ?? usage.weekly
        } else {
            selectedWindow = usage.windows
                .max(by: { $0.usedPercent < $1.usedPercent })
        }
        guard let selectedWindow else { return nil }
        return UsageSummary(
            providerName: providerName,
            remainingPercent: min(100, max(0, 100 - selectedWindow.usedPercent)),
            resetsAt: selectedWindow.resetsAt,
            windowKind: selectedWindow.kind
        )
    }
}

// MARK: - Provider output parsing

public enum UsageParser {
    public static func codexResponse(from data: Data) -> ProviderUsage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? NSNumber,
            id.intValue == 2
        else { return nil }

        if let error = object["error"] as? [String: Any] {
            _ = error
            return .unavailable("Codex", .codexUsageUnavailable)
        }

        guard
            let result = object["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any]
        else {
            return .unavailable("Codex", .codexLimitMissing)
        }

        let windows = [limits["primary"], limits["secondary"]]
            .enumerated()
            .compactMap { rateWindow($0.element, position: $0.offset) }

        return ProviderUsage(name: "Codex", windows: windows, error: nil)
    }

    public static func claudeScreen(_ raw: String) -> ProviderUsage {
        let cleaned = stripTerminalCodes(raw)
        let session = percentage(afterAny: ["Current session", "Current Session"], in: cleaned)
        let sessionReset = resetDate(
            afterAny: ["Current session", "Current Session"],
            in: cleaned
        )
        let weekly = percentage(afterAny: [
            "Current week (all models)",
            "Current week",
            "Current Week"
        ], in: cleaned)
        let weeklyReset = resetDate(afterAny: [
            "Current week (all models)",
            "Current week",
            "Current Week"
        ], in: cleaned)

        if session == nil && weekly == nil {
            let issue: ProviderIssue
            if cleaned.localizedCaseInsensitiveContains("login") ||
                cleaned.localizedCaseInsensitiveContains("sign in") {
                issue = .claudeNotLoggedIn
            } else {
                issue = .claudeUsageUnreadable
            }
            return .unavailable("Claude Code", issue)
        }

        return ProviderUsage(
            name: "Claude Code",
            windows: [
                session.map {
                    UsageWindow(kind: .fiveHour, usedPercent: $0, resetsAt: sessionReset, durationMinutes: 300)
                },
                weekly.map {
                    UsageWindow(kind: .weekly, usedPercent: $0, resetsAt: weeklyReset, durationMinutes: 10_080)
                }
            ].compactMap { $0 },
            error: nil
        )
    }

    /// Parses the plain-text output of `claude -p "/usage"`. Print mode prints
    /// one line per window, e.g.
    ///   Current session: 100% used · resets Jul 23 at 10:20pm (Europe/Istanbul)
    ///   Current week (all models): 53% used · resets Jul 26 at 10pm (Europe/Istanbul)
    /// There are no terminal cursor moves, so there is none of the space-collapse
    /// or overlay-height fragility of the interactive `/usage` panel.
    public static func claudePrintUsage(_ raw: String, now: Date = Date()) -> ProviderUsage {
        let session = printWindow("Current session", in: raw, now: now)
        let weekly = printWindow("Current week[^:\\n]*", in: raw, now: now)

        if session == nil && weekly == nil {
            let lower = raw.lowercased()
            let notLoggedIn = lower.contains("log in")
                || lower.contains("login")
                || lower.contains("sign in")
                || lower.contains("not authenticated")
                || lower.contains("authenticate")
            return .unavailable(
                "Claude Code",
                notLoggedIn ? .claudeNotLoggedIn : .claudeUsageUnreadable
            )
        }

        return ProviderUsage(
            name: "Claude Code",
            windows: [
                session.map {
                    UsageWindow(kind: .fiveHour, usedPercent: $0.percent, resetsAt: $0.reset, durationMinutes: 300)
                },
                weekly.map {
                    UsageWindow(kind: .weekly, usedPercent: $0.percent, resetsAt: $0.reset, durationMinutes: 10_080)
                }
            ].compactMap { $0 },
            error: nil
        )
    }

    private static func printWindow(
        _ labelPattern: String,
        in text: String,
        now: Date
    ) -> (percent: Int, reset: Date?)? {
        let pattern = "(?is)\(labelPattern)\\s*:\\s*(\\d{1,3}(?:[.,]\\d+)?)\\s*%\\s*used(?:[^\\n]*?resets?\\s+([^\\n]+))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard
            let match = regex.firstMatch(in: text, range: range),
            let percentRange = Range(match.range(at: 1), in: text)
        else { return nil }
        let normalized = text[percentRange].replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized) else { return nil }
        let percent = min(100, max(0, Int(value.rounded())))
        var reset: Date?
        if match.numberOfRanges > 2, let resetRange = Range(match.range(at: 2), in: text) {
            let resetText = String(text[resetRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            reset = parseClaudeReset(resetText, now: now)
        }
        return (percent, reset)
    }

    private static func rateWindow(_ value: Any?, position: Int) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        guard let used = number(dictionary["usedPercent"]) else { return nil }
        let resetSeconds = number(dictionary["resetsAt"])
        let duration = number(dictionary["windowDurationMins"])
        return UsageWindow(
            usedPercent: min(100, max(0, Int(used.rounded()))),
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
            durationMinutes: duration.map { Int($0) },
            position: position
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func percentage(afterAny labels: [String], in text: String) -> Int? {
        var values: [Int] = []
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "(?is)\(escaped).{0,500}?(\\d{1,3}(?:[.,]\\d+)?)\\s*%"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard
                    match.numberOfRanges > 1,
                    let valueRange = Range(match.range(at: 1), in: text)
                else { continue }
                let normalized = text[valueRange].replacingOccurrences(of: ",", with: ".")
                if let value = Double(normalized) {
                    values.append(min(100, max(0, Int(value.rounded()))))
                }
            }
        }
        return values.last
    }

    private static func resetDate(afterAny labels: [String], in text: String) -> Date? {
        var dates: [Date] = []
        for label in labels {
            let escaped = NSRegularExpression.escapedPattern(for: label)
            let pattern = "(?is)\(escaped)(?:(?!Current\\s+(?:session|week)).){0,1200}?Resets?\\s+([^\\n]{1,120})"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard
                    match.numberOfRanges > 1,
                    let valueRange = Range(match.range(at: 1), in: text)
                else { continue }
                var value = String(text[valueRange])
                    .replacingOccurrences(of: "[│┃].*$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                if let date = parseClaudeReset(value) {
                    dates.append(date)
                }
            }
        }
        return dates.last
    }

    private static func parseClaudeReset(_ raw: String, now: Date = Date()) -> Date? {
        let value = raw
            .replacingOccurrences(of: "^(?:at|by)\\s+", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if value.range(of: "^in\\s+", options: [.regularExpression, .caseInsensitive]) != nil {
            let componentPatterns: [(String, TimeInterval)] = [
                ("(\\d+)\\s*(?:days?|d)\\b", 86_400),
                ("(\\d+)\\s*(?:hours?|hrs?|h)\\b", 3_600),
                ("(\\d+)\\s*(?:minutes?|mins?|m)\\b", 60)
            ]
            var interval: TimeInterval = 0
            for (pattern, multiplier) in componentPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                    continue
                }
                let range = NSRange(value.startIndex..<value.endIndex, in: value)
                if let match = regex.firstMatch(in: value, range: range),
                   let numberRange = Range(match.range(at: 1), in: value),
                   let number = Double(value[numberRange]) {
                    interval += number * multiplier
                }
            }
            if interval > 0 { return now.addingTimeInterval(interval) }
        }

        var dateText = value
        var timeZone = TimeZone.current
        if let zoneRegex = try? NSRegularExpression(pattern: "\\(([^()]+)\\)\\s*$"),
           let match = zoneRegex.firstMatch(
               in: dateText,
               range: NSRange(dateText.startIndex..<dateText.endIndex, in: dateText)
           ),
           let zoneRange = Range(match.range(at: 1), in: dateText) {
            if let parsedZone = TimeZone(identifier: String(dateText[zoneRange])) {
                timeZone = parsedZone
            }
            if let fullRange = Range(match.range(at: 0), in: dateText) {
                dateText.removeSubrange(fullRange)
                dateText = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Claude's /usage panel positions text with cursor moves rather than
        // literal spaces, so stripping terminal codes can concatenate the reset
        // date ("Jul 26 at 10pm" -> "Jul26at10pm"). Re-insert separators at
        // letter/digit boundaries and reattach the am/pm suffix so the formats
        // below can match. Short times like "5pm" are unaffected.
        dateText = dateText
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([0-9])([A-Za-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([0-9])\\s+([AaPp][Mm])\\b", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let formats = [
            "MMM d, yyyy, h:mma", "MMM d, yyyy, h:mm a",
            "MMM d, yyyy 'at' h:mma", "MMM d, yyyy 'at' h:mm a",
            "MMM d, h:mma", "MMM d, h:mm a",
            "MMM d 'at' h:mma", "MMM d 'at' h:mm a",
            "EEE, MMM d, h:mma", "EEE, MMM d, h:mm a",
            "EEE, MMM d 'at' h:mma", "EEE, MMM d 'at' h:mm a",
            "h:mma", "h:mm a",
            // Whole-hour times with no minutes, e.g. "Resets 5pm" or
            // "Resets Jul 26 at 10pm". Claude's /usage panel drops the minutes
            // on the hour, so these must be tried only after the h:mm formats
            // (otherwise "ha" would greedily parse the hour of a "4:59pm").
            "MMM d, yyyy, ha", "MMM d, yyyy 'at' ha",
            "MMM d, ha", "MMM d 'at' ha",
            "EEE, MMM d, ha", "EEE, MMM d 'at' ha",
            "ha", "h a",
            // Date-only, e.g. "Resets Aug 1".
            "MMM d, yyyy", "MMM d"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.defaultDate = now
            formatter.dateFormat = format
            guard var parsed = formatter.date(from: dateText) else { continue }

            // Minute-less formats ("5pm", "Jul 26 at 10pm") inherit the current
            // minute from defaultDate; pin them to the top of the hour so the
            // countdown is not offset by the current minute-of-hour.
            if !format.contains("mm") {
                var hourCalendar = Calendar(identifier: .gregorian)
                hourCalendar.timeZone = timeZone
                if let onHour = hourCalendar.date(
                    bySettingHour: hourCalendar.component(.hour, from: parsed),
                    minute: 0,
                    second: 0,
                    of: parsed
                ) {
                    parsed = onHour
                }
            }

            // Roll forward in the reset's own time zone, not the Mac's. Adding a
            // calendar day/year is DST-aware, so it must use a Gregorian calendar
            // pinned to `timeZone`; `Calendar.current` would offset the result by
            // the Mac↔reset zone gap and mishandle DST boundaries.
            var rollCalendar = Calendar(identifier: .gregorian)
            rollCalendar.timeZone = timeZone
            if !format.contains("MMM"), parsed <= now,
               let nextDay = rollCalendar.date(byAdding: .day, value: 1, to: parsed) {
                parsed = nextDay
            } else if format.contains("MMM"), !format.contains("yyyy"), parsed < now,
                      let nextYear = rollCalendar.date(byAdding: .year, value: 1, to: parsed) {
                parsed = nextYear
            }
            return parsed
        }
        return nil
    }

    private static func stripTerminalCodes(_ text: String) -> String {
        let ansi = "\u{001B}(?:\\[[0-?]*[ -/]*[@-~]|\\][^\u{0007}]*(?:\u{0007}|\u{001B}\\\\)|[()][0-2A-Z]|[@-_])"
        let withoutANSI = text.replacingOccurrences(
            of: ansi,
            with: "",
            options: .regularExpression
        )
        return withoutANSI
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0008}", with: "")
    }
}
