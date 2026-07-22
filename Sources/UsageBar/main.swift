import AppKit
import Darwin
import Foundation
import ServiceManagement

struct UsageWindow {
    let usedPercent: Int
    let resetsAt: Date?
    let durationMinutes: Int?
}

enum ProviderIssue {
    case custom(String)
    case refreshing
    case noData
    case codexUsageUnavailable
    case codexLimitMissing
    case codexNotFound
    case codexTimedOut
    case codexEmptyResponse
    case codexLaunchFailed(String)
    case claudeNotFound
    case claudeNotLoggedIn
    case claudeUsageUnreadable
    case claudeLaunchFailed(String)
    case processTimedOut(String)
    case outputTooLarge(String)
}

struct ProviderUsage {
    let name: String
    let session: UsageWindow?
    let weekly: UsageWindow?
    let error: ProviderIssue?

    static func unavailable(_ name: String, _ issue: ProviderIssue) -> ProviderUsage {
        ProviderUsage(name: name, session: nil, weekly: nil, error: issue)
    }
}

enum AppLanguage: String {
    case turkish
    case english

    static func preferred(from preferredLanguages: [String]) -> AppLanguage {
        preferredLanguages.first?.lowercased().hasPrefix("tr") == true ? .turkish : .english
    }
}

enum AppMetadata {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }
}

enum UsageAlertLevel: Equatable {
    case normal
    case warning
    case critical
}

enum UsageAlertPreset: String, CaseIterable {
    case late
    case balanced
    case early

    var warningThreshold: Int {
        switch self {
        case .late: return 10
        case .balanced: return 20
        case .early: return 30
        }
    }

    var criticalThreshold: Int {
        switch self {
        case .late: return 5
        case .balanced: return 10
        case .early: return 15
        }
    }
}

struct UsageAlertPolicy {
    let isEnabled: Bool
    let preset: UsageAlertPreset

    func level(for remainingPercent: Int) -> UsageAlertLevel {
        guard isEnabled else { return .normal }
        let clamped = min(100, max(0, remainingPercent))
        if clamped <= preset.criticalThreshold { return .critical }
        if clamped <= preset.warningThreshold { return .warning }
        return .normal
    }
}

enum ProviderRotation {
    static let interval: TimeInterval = 30

    static func nextIndex(after currentIndex: Int, providerCount: Int) -> Int {
        guard providerCount > 0 else { return 0 }
        return (max(0, currentIndex) + 1) % providerCount
    }
}

struct UsageHistorySample: Codable, Equatable {
    let recordedAt: Date
    let remainingPercent: Int
}

enum UsageHistoryModel {
    static let retentionInterval: TimeInterval = 24 * 60 * 60
    static let minimumSampleInterval: TimeInterval = 60

    static func adding(
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
        return samples
    }

    static func encode(_ history: [String: [UsageHistorySample]]) -> Data? {
        try? JSONEncoder().encode(history)
    }

    static func decode(_ data: Data?) -> [String: [UsageHistorySample]] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([String: [UsageHistorySample]].self, from: data)) ?? [:]
    }
}

struct UsageHistoryChartModel {
    static let resetJumpThreshold = 20
    static let minimumVerticalSpan = 10.0

    let samples: [UsageHistorySample]
    let displaySamples: [UsageHistorySample]
    let lowerBound: Double
    let upperBound: Double
    let resetIndices: [Int]

    init(samples: [UsageHistorySample]) {
        let sortedSamples = samples.sorted { $0.recordedAt < $1.recordedAt }
        self.samples = sortedSamples
        displaySamples = sortedSamples.enumerated().map { index, sample in
            guard index > 0, index < sortedSamples.count - 1 else { return sample }
            let previous = sortedSamples[index - 1].remainingPercent
            let current = sample.remainingPercent
            let next = sortedSamples[index + 1].remainingPercent
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
        resetIndices = sortedSamples.indices.dropFirst().filter { index in
            sortedSamples[index].remainingPercent - sortedSamples[index - 1].remainingPercent
                >= Self.resetJumpThreshold
        }
    }

    var recordedDuration: TimeInterval {
        guard let first = samples.first, let last = samples.last else { return 0 }
        return max(0, last.recordedAt.timeIntervalSince(first.recordedAt))
    }

    var delta: Int? {
        guard let first = samples.first, let last = samples.last, samples.count > 1 else { return nil }
        return last.remainingPercent - first.remainingPercent
    }

    func normalizedY(for remainingPercent: Int) -> CGFloat {
        let clamped = Double(min(100, max(0, remainingPercent)))
        return CGFloat((clamped - lowerBound) / (upperBound - lowerBound))
    }
}

struct Localizer {
    let language: AppLanguage

    private func pick(_ turkish: String, _ english: String) -> String {
        language == .turkish ? turkish : english
    }

    var usageTooltip: String { pick("Codex ve Claude Code kullanımı", "Codex and Claude Code usage") }
    var connectFirst: String { pick("Önce bir sağlayıcı bağlayın", "Connect a provider first") }
    var refreshing: String { pick("Yenileniyor…", "Refreshing…") }
    var noData: String { pick("Henüz veri yok", "No data yet") }
    var connectCodex: String { pick("Codex'e bağlan", "Connect Codex") }
    var connectClaude: String { pick("Claude Code'a bağlan", "Connect Claude Code") }
    var refreshNow: String { pick("Şimdi yenile", "Refresh now") }
    var quit: String { pick("UsageBar'dan çık", "Quit UsageBar") }
    var showInMenuBar: String { pick("Üst çubukta göster", "Show in menu bar") }
    var languageTitle: String { pick("Dil", "Language") }
    var usageColorsTitle: String { pick("Kullanım renkleri", "Usage colors") }
    var usageColorsEnabled: String { pick("Renkleri kullan", "Use colors") }
    var menuBarAppearance: String { pick("Üst çubuk görünümü", "Menu bar appearance") }
    var showResetInMenuBar: String { pick("Sıfırlanma süresini göster", "Show reset countdown") }
    var automatic: String { pick("Otomatik", "Auto") }
    var usageHistoryTitle: String { pick("Kullanım geçmişi", "Usage history") }
    var showUsageHistory: String { pick("24 saatlik mini grafiği göster", "Show 24-hour mini chart") }
    var clearUsageHistory: String { pick("Geçmişi temizle", "Clear history") }
    var launchAtLogin: String { pick("Mac açılışında başlat", "Launch at login") }
    var loginItemFailed: String { pick("Başlangıç ayarı değiştirilemedi", "Could not change login item") }
    var loginItemNeedsApproval: String { pick("onay gerekli", "approval required") }
    var fiveHours: String { pick("5 saat", "5 hours") }
    var weekly: String { pick("Haftalık", "Weekly") }

    func usageHistoryRange(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return pick("İlk kayıt", "First sample")
        }

        let totalMinutes = Int(duration) / 60
        if totalMinutes < 60 {
            return pick("Son \(totalMinutes) dk", "Last \(totalMinutes)m")
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            let suffix = minutes > 0 ? pick(" \(minutes) dk", " \(minutes)m") : ""
            return pick("Son \(totalHours) sa", "Last \(totalHours)h") + suffix
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        let suffix = hours > 0 ? pick(" \(hours) sa", " \(hours)h") : ""
        return pick("Son \(days) gün", "Last \(days)d") + suffix
    }

    func usageHistorySummary(_ model: UsageHistoryChartModel) -> String {
        guard let first = model.samples.first, let last = model.samples.last else { return noData }
        let firstPercent = language == .turkish
            ? "%\(first.remainingPercent)"
            : "\(first.remainingPercent)%"
        guard let delta = model.delta else {
            return pick("Başlangıç: \(firstPercent)", "Start: \(firstPercent)")
        }

        let lastPercent = language == .turkish
            ? "%\(last.remainingPercent)"
            : "\(last.remainingPercent)%"
        let signedDelta = delta > 0 ? "+\(delta)" : "\(delta)"
        var result = pick(
            "\(firstPercent) → \(lastPercent) · değişim \(signedDelta)",
            "\(firstPercent) → \(lastPercent) · change \(signedDelta)"
        )
        if !model.resetIndices.isEmpty {
            result += pick(
                " · \(model.resetIndices.count) sıfırlama",
                " · \(model.resetIndices.count) reset"
            )
        }
        return result
    }
    var codexNotFoundTitle: String { pick("Codex bulunamadı", "Codex not found") }
    var codexNotFoundMessage: String {
        pick(
            "Önce ChatGPT veya Codex komut satırı uygulamasını kurup hesabınıza giriş yapın.",
            "Install ChatGPT or the Codex CLI and sign in first."
        )
    }
    var claudeNotFoundTitle: String { pick("Claude Code bulunamadı", "Claude Code not found") }
    var claudeNotFoundMessage: String {
        pick("Önce Claude Code'u kurup hesabınıza giriş yapın.", "Install Claude Code and sign in first.")
    }
    var connectClaudeTitle: String { pick("Claude Code'a bağlanılsın mı?", "Connect Claude Code?") }
    var connectClaudeMessage: String {
        pick(
            "UsageBar yalnızca Claude Code'un mevcut giriş durumunu ve yapılandırılmış kullanım sınırlarını izole bir oturumda okuyacak. macOS, Claude Code kimliği için Anahtar Zinciri izni sorabilir. Bu pencerede bir kez 'Her Zaman İzin Ver' seçilebilir. Disk, ağ diski, ekran, erişilebilirlik veya otomasyon izni gerekmez.",
            "UsageBar will read only Claude Code's current sign-in status and structured usage limits in an isolated session. macOS may request Keychain access for the Claude Code credential; you can choose 'Always Allow' once. Disk, network volume, screen recording, accessibility, and automation access are not required."
        )
    }
    var connect: String { pick("Bağlan", "Connect") }
    var cancel: String { pick("Vazgeç", "Cancel") }
    var ok: String { pick("Tamam", "OK") }
    var now: String { pick("şimdi", "now") }

    func remaining(_ percent: Int) -> String {
        pick("%\(percent) kaldı", "\(percent)% remaining")
    }

    func remainingTooltip(provider: String, percent: Int) -> String {
        pick("\(provider): %\(percent) kaldı", "\(provider): \(percent)% remaining")
    }

    func waitingForUsage(provider: String) -> String {
        pick("\(provider) kullanım bilgisi bekleniyor", "Waiting for \(provider) usage")
    }

    func alertPresetTitle(_ preset: UsageAlertPreset) -> String {
        let name: String
        switch preset {
        case .late: name = pick("Geç", "Late")
        case .balanced: name = pick("Dengeli", "Balanced")
        case .early: name = pick("Erken", "Early")
        }
        return pick(
            "\(name) — turuncu %\(preset.warningThreshold), kırmızı %\(preset.criticalThreshold)",
            "\(name) — orange \(preset.warningThreshold)%, red \(preset.criticalThreshold)%"
        )
    }

    func resetIn(_ duration: String) -> String {
        pick("Sıfırlama: \(duration)", "Resets in \(duration)")
    }

    func lastUpdated(_ time: String) -> String {
        pick("Son güncelleme: \(time)", "Last updated: \(time)")
    }

    func relativeReset(_ date: Date, now: Date = Date()) -> String {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        let minutes = (interval % 3_600) / 60
        if language == .turkish {
            if days > 0 { return "\(days)g \(hours)sa" }
            if hours > 0 { return "\(hours)sa \(minutes)dk" }
            if minutes > 0 { return "\(minutes)dk" }
            return self.now
        }

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return self.now
    }

    func issue(_ issue: ProviderIssue) -> String {
        switch issue {
        case .custom(let message): return message
        case .refreshing: return refreshing
        case .noData: return noData
        case .codexUsageUnavailable:
            return pick("Codex kullanım bilgisi alınamadı", "Could not retrieve Codex usage")
        case .codexLimitMissing:
            return pick("Codex kullanım sınırı bulunamadı", "Codex usage limit not found")
        case .codexNotFound:
            return codexNotFoundTitle
        case .codexTimedOut:
            return pick("Codex yanıtı zaman aşımına uğradı", "Codex response timed out")
        case .codexEmptyResponse:
            return pick("Codex kullanım yanıtı boş", "Codex returned an empty usage response")
        case .codexLaunchFailed(let reason):
            return pick("Codex başlatılamadı: \(reason)", "Could not start Codex: \(reason)")
        case .claudeNotFound:
            return claudeNotFoundTitle
        case .claudeNotLoggedIn:
            return pick("Claude Code'a giriş yapılmamış", "Claude Code is not signed in")
        case .claudeUsageUnreadable:
            return pick("Claude kullanım yüzdesi okunamadı", "Could not read Claude usage")
        case .claudeLaunchFailed(let reason):
            return pick("Claude Code başlatılamadı: \(reason)", "Could not start Claude Code: \(reason)")
        case .processTimedOut(let provider):
            return pick("\(provider) işlemi zaman aşımına uğradı", "\(provider) process timed out")
        case .outputTooLarge(let provider):
            return pick("\(provider) çok fazla çıktı üretti", "\(provider) produced too much output")
        }
    }
}

struct UsageSummary {
    let providerName: String
    let remainingPercent: Int
    let resetsAt: Date?
}

enum UsageSummaryCalculator {
    static func summary(for providerName: String, in usages: [String: ProviderUsage]) -> UsageSummary? {
        guard let usage = usages[providerName] else { return nil }
        let selectedWindow: UsageWindow?
        if providerName == "Claude Code" {
            // Claude's menu-bar value represents the active five-hour window.
            // Fall back to weekly only when Claude does not return session data.
            selectedWindow = usage.session ?? usage.weekly
        } else {
            selectedWindow = [usage.session, usage.weekly]
                .compactMap { $0 }
                .max(by: { $0.usedPercent < $1.usedPercent })
        }
        guard let selectedWindow else { return nil }
        return UsageSummary(
            providerName: providerName,
            remainingPercent: min(100, max(0, 100 - selectedWindow.usedPercent)),
            resetsAt: selectedWindow.resetsAt
        )
    }
}

enum UsageParser {
    static func codexResponse(from data: Data) -> ProviderUsage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = object["id"] as? NSNumber,
            id.intValue == 2
        else { return nil }

        if let error = object["error"] as? [String: Any] {
            if let message = error["message"] as? String {
                return .unavailable("Codex", .custom(message))
            }
            return .unavailable("Codex", .codexUsageUnavailable)
        }

        guard
            let result = object["result"] as? [String: Any],
            let limits = result["rateLimits"] as? [String: Any]
        else {
            return .unavailable("Codex", .codexLimitMissing)
        }

        let primary = rateWindow(limits["primary"])
        let secondary = rateWindow(limits["secondary"])
        let windows = [primary, secondary].compactMap { $0 }

        // `primary` and `secondary` describe ordering, not duration. Some
        // accounts expose a five-hour primary window, while others expose only
        // a weekly primary window. Classify using the duration returned by the
        // API instead of assigning fixed labels by position.
        var session = windows.first(where: { window in
            guard let minutes = window.durationMinutes else { return false }
            return minutes <= 24 * 60
        })
        var weekly = windows.first(where: { window in
            guard let minutes = window.durationMinutes else { return false }
            return minutes >= 6 * 24 * 60 && minutes <= 8 * 24 * 60
        })

        // Older Codex versions may omit windowDurationMins. Preserve their
        // positional behavior only when no duration can be classified.
        if session == nil && weekly == nil {
            session = primary
            weekly = secondary
        }

        return ProviderUsage(name: "Codex", session: session, weekly: weekly, error: nil)
    }

    static func claudeScreen(_ raw: String) -> ProviderUsage {
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
            session: session.map {
                UsageWindow(usedPercent: $0, resetsAt: sessionReset, durationMinutes: 300)
            },
            weekly: weekly.map {
                UsageWindow(usedPercent: $0, resetsAt: weeklyReset, durationMinutes: 10_080)
            },
            error: nil
        )
    }

    static func claudeStatusLine(_ raw: String) -> ProviderUsage? {
        let cleaned = stripTerminalCodes(raw)
        guard let markerRange = cleaned.range(of: "USAGEBAR_LIMITS:") else { return nil }
        let statusOutput = String(cleaned[markerRange.lowerBound...])
        // Claude redraws its status line incrementally. The initial frame can
        // contain `USAGEBAR_LIMITS:|||`, followed later by only the changed
        // numeric suffix at another cursor position. Parse the first complete
        // numeric tuple after our unique marker rather than requiring one
        // contiguous rendered line.
        let pattern = "([0-9]{1,4}(?:\\.[0-9]+)?)\\|([0-9]{9,}(?:\\.[0-9]+)?)\\|([0-9]{1,4}(?:\\.[0-9]+)?)\\|([0-9]{9,}(?:\\.[0-9]+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(statusOutput.startIndex..<statusOutput.endIndex, in: statusOutput)
        var result: ProviderUsage?

        for match in regex.matches(in: statusOutput, range: range) {
            guard match.numberOfRanges == 5 else { continue }
            let values: [String] = (1...4).compactMap { index in
                guard let valueRange = Range(match.range(at: index), in: statusOutput) else { return nil }
                return String(statusOutput[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard values.count == 4 else { continue }

            let fiveHourUsed = Double(values[0])
            let fiveHourReset = Double(values[1])
            let sevenDayUsed = Double(values[2])
            let sevenDayReset = Double(values[3])
            guard fiveHourUsed != nil || sevenDayUsed != nil else { continue }

            result = ProviderUsage(
                name: "Claude Code",
                session: fiveHourUsed.map {
                    UsageWindow(
                        usedPercent: min(100, max(0, Int($0.rounded()))),
                        resetsAt: fiveHourReset.map { Date(timeIntervalSince1970: $0) },
                        durationMinutes: 300
                    )
                },
                weekly: sevenDayUsed.map {
                    UsageWindow(
                        usedPercent: min(100, max(0, Int($0.rounded()))),
                        resetsAt: sevenDayReset.map { Date(timeIntervalSince1970: $0) },
                        durationMinutes: 10_080
                    )
                },
                error: nil
            )
        }
        return result
    }

    private static func rateWindow(_ value: Any?) -> UsageWindow? {
        guard let dictionary = value as? [String: Any] else { return nil }
        guard let used = number(dictionary["usedPercent"]) else { return nil }
        let resetSeconds = number(dictionary["resetsAt"])
        let duration = number(dictionary["windowDurationMins"])
        return UsageWindow(
            usedPercent: min(100, max(0, Int(used.rounded()))),
            resetsAt: resetSeconds.map { Date(timeIntervalSince1970: $0) },
            durationMinutes: duration.map { Int($0) }
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

        let formats = [
            "MMM d, yyyy, h:mma", "MMM d, yyyy, h:mm a",
            "MMM d, yyyy 'at' h:mma", "MMM d, yyyy 'at' h:mm a",
            "MMM d, h:mma", "MMM d, h:mm a",
            "MMM d 'at' h:mma", "MMM d 'at' h:mm a",
            "EEE, MMM d, h:mma", "EEE, MMM d, h:mm a",
            "EEE, MMM d 'at' h:mma", "EEE, MMM d 'at' h:mm a",
            "h:mma", "h:mm a"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.defaultDate = now
            formatter.dateFormat = format
            guard var parsed = formatter.date(from: dateText) else { continue }

            if !format.contains("MMM"), parsed <= now,
               let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: parsed) {
                parsed = nextDay
            } else if format.contains("MMM"), !format.contains("yyyy"), parsed < now,
                      let nextYear = Calendar.current.date(byAdding: .year, value: 1, to: parsed) {
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

enum ExecutableLocator {
    static func codex() -> String? {
        firstExecutable([
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath
        ])
    }

    static func claude() -> String? {
        firstExecutable([
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSString(string: "~/.claude/bin/claude").expandingTildeInPath,
            NSString(string: "~/.claude/local/claude").expandingTildeInPath,
            NSString(string: "~/.local/bin/claude").expandingTildeInPath
        ])
    }

    private static func firstExecutable(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

/// Keeps provider CLIs away from the folder that UsageBar was launched from.
/// In particular, Claude Code normally discovers project files, hooks, MCP
/// servers and integrations from its current directory. That discovery can
/// make macOS attribute unrelated Desktop/Documents/network-volume access to
/// UsageBar. Quota checks only need the user's local login, so they run from a
/// private temporary directory with a deliberately small environment.
private enum ProviderProcessContext {
    static let workingDirectory: URL = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("local.codex.usagebar", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return FileManager.default.temporaryDirectory
        }
    }()

    static let environment: [String: String] = {
        let inherited = ProcessInfo.processInfo.environment
        var value: [String: String] = [
            "HOME": NSHomeDirectory(),
            "PATH": [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                "/usr/sbin", "/sbin"
            ].joined(separator: ":"),
            "TERM": "xterm-256color",
            "TMPDIR": FileManager.default.temporaryDirectory.path
        ]
        for key in ["USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let inheritedValue = inherited[key] {
                value[key] = inheritedValue
            }
        }
        return value
    }()

    static func apply(to process: Process) {
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
    }
}

private enum ProviderProcessLimits {
    static let maxOutputBytes = 2 * 1_024 * 1_024
    static let authTimeout: DispatchTimeInterval = .seconds(5)
    private static let terminationGrace: TimeInterval = 1

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(terminationGrace)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }
}

private final class BoundedDataCapture {
    private let limit: Int
    private let lock = NSLock()
    private var data = Data()
    private var exceeded = false

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    @discardableResult
    func append(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !chunk.isEmpty else { return !exceeded }

        let remaining = max(0, limit - data.count)
        if chunk.count > remaining {
            data.append(chunk.prefix(remaining))
            exceeded = true
        } else {
            data.append(chunk)
        }
        return !exceeded
    }

    func snapshot() -> (data: Data, exceeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, exceeded)
    }
}

final class CodexUsageFetcher {
    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable = ExecutableLocator.codex() else {
                completion(.unavailable("Codex", .codexNotFound))
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            // UsageBar only needs the account quota RPC. Disabling unrelated
            // app/plugin features avoids background catalog scans and their
            // associated file/network access.
            process.arguments = [
                "app-server", "--stdio",
                "--disable", "apps",
                "--disable", "plugins",
                "--disable", "remote_plugin",
                "--disable", "plugin_sharing"
            ]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errors
            ProviderProcessContext.apply(to: process)

            let semaphore = DispatchSemaphore(value: 0)
            let lock = NSLock()
            var pending = Data()
            var result: ProviderUsage?
            var totalOutputBytes = 0
            var outputExceeded = false
            var didSignal = false

            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock()
                defer { lock.unlock() }

                guard !outputExceeded else { return }
                let remaining = ProviderProcessLimits.maxOutputBytes - totalOutputBytes
                guard chunk.count <= remaining else {
                    outputExceeded = true
                    pending.removeAll(keepingCapacity: false)
                    if !didSignal {
                        didSignal = true
                        semaphore.signal()
                    }
                    return
                }
                totalOutputBytes += chunk.count
                pending.append(chunk)
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = pending.prefix(upTo: newline)
                    pending.removeSubrange(...newline)
                    if let parsed = UsageParser.codexResponse(from: Data(line)) {
                        result = parsed
                        if !didSignal {
                            didSignal = true
                            semaphore.signal()
                        }
                        break
                    }
                }
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            do {
                try process.run()
                let messages = [
                    "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"usage_bar\",\"title\":\"UsageBar\",\"version\":\"\(AppMetadata.version)\"}}}",
                    "{\"method\":\"initialized\"}",
                    "{\"method\":\"account/rateLimits/read\",\"id\":2}"
                ].joined(separator: "\n") + "\n"
                input.fileHandleForWriting.write(Data(messages.utf8))

                let waitResult = semaphore.wait(timeout: .now() + 15)
                input.fileHandleForWriting.closeFile()
                ProviderProcessLimits.stop(process)
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil

                lock.lock()
                let final = result
                let exceeded = outputExceeded
                lock.unlock()

                if exceeded {
                    completion(.unavailable("Codex", .outputTooLarge("Codex")))
                } else if let final {
                    completion(final)
                } else if waitResult == .timedOut {
                    completion(.unavailable("Codex", .codexTimedOut))
                } else {
                    completion(.unavailable("Codex", .codexEmptyResponse))
                }
            } catch {
                ProviderProcessLimits.stop(process)
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                completion(.unavailable("Codex", .codexLaunchFailed(error.localizedDescription)))
            }
        }
    }

}

final class ClaudeUsageFetcher {
    private static let statusLineSettings: String = {
        guard let executablePath = Bundle.main.executableURL?.path else { return "{}" }
        let quotedExecutable = "'" + executablePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(quotedExecutable) --claude-status-filter"
        let settings: [String: Any] = [
            "statusLine": [
                "type": "command",
                "command": command,
                "padding": 0
            ]
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: settings),
            let json = String(data: data, encoding: .utf8)
        else { return "{}" }
        return json
    }()

    func fetch(completion: @escaping (ProviderUsage) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            guard let executable = ExecutableLocator.claude() else {
                completion(.unavailable("Claude Code", .claudeNotFound))
                return
            }

            switch Self.loginStatus(executable) {
            case .loggedIn:
                break
            case .loggedOut:
                completion(.unavailable("Claude Code", .claudeNotLoggedIn))
                return
            case .timedOut:
                completion(.unavailable("Claude Code", .processTimedOut("Claude Code")))
                return
            case .outputTooLarge:
                completion(.unavailable("Claude Code", .outputTooLarge("Claude Code")))
                return
            }

            let process = Process()
            let input = Pipe()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            // Ignore user/project/local settings and inject only a tiny status
            // line that exposes Claude's official structured quota fields.
            // This avoids project files, hooks, plugins, MCP and Chrome while
            // keeping normal local authentication available.
            process.arguments = [
                "-q", "/dev/null", executable,
                "--setting-sources", "",
                "--settings", Self.statusLineSettings,
                "--no-chrome",
                "--strict-mcp-config",
                "--tools", ""
            ]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = output
            ProviderProcessContext.apply(to: process)

            let captured = BoundedDataCapture(limit: ProviderProcessLimits.maxOutputBytes)
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                captured.append(chunk)
            }

            do {
                try process.run()
                Thread.sleep(forTimeInterval: 1.5)
                input.fileHandleForWriting.write(Data("/usage\r".utf8))
                Thread.sleep(forTimeInterval: 5.0)
                input.fileHandleForWriting.write(Data([0x1B]))
                Thread.sleep(forTimeInterval: 0.5)
                input.fileHandleForWriting.write(Data("/exit\r".utf8))
                Thread.sleep(forTimeInterval: 1.0)
                input.fileHandleForWriting.closeFile()
                ProviderProcessLimits.stop(process)
                output.fileHandleForReading.readabilityHandler = nil

                let snapshot = captured.snapshot()
                guard !snapshot.exceeded else {
                    completion(.unavailable("Claude Code", .outputTooLarge("Claude Code")))
                    return
                }
                let screen = String(decoding: snapshot.data, as: UTF8.self)
                completion(
                    UsageParser.claudeStatusLine(screen)
                        ?? UsageParser.claudeScreen(screen)
                )
            } catch {
                ProviderProcessLimits.stop(process)
                output.fileHandleForReading.readabilityHandler = nil
                completion(.unavailable("Claude Code", .claudeLaunchFailed(error.localizedDescription)))
            }
        }
    }

    private enum LoginStatus {
        case loggedIn
        case loggedOut
        case timedOut
        case outputTooLarge
    }

    private static func loginStatus(_ executable: String) -> LoginStatus {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        let captured = BoundedDataCapture(limit: ProviderProcessLimits.maxOutputBytes)
        let terminated = DispatchSemaphore(value: 0)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "status"]
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { _ in terminated.signal() }
        ProviderProcessContext.apply(to: process)

        output.fileHandleForReading.readabilityHandler = { handle in
            captured.append(handle.availableData)
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
            let waitResult = terminated.wait(timeout: .now() + ProviderProcessLimits.authTimeout)
            if waitResult == .timedOut {
                ProviderProcessLimits.stop(process)
            }
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            captured.append(output.fileHandleForReading.readDataToEndOfFile())

            if waitResult == .timedOut { return .timedOut }
            let snapshot = captured.snapshot()
            if snapshot.exceeded { return .outputTooLarge }
            guard
                let object = try JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any],
                let loggedIn = object["loggedIn"] as? Bool
            else { return .loggedOut }
            return loggedIn ? .loggedIn : .loggedOut
        } catch {
            ProviderProcessLimits.stop(process)
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            return .loggedOut
        }
    }

}

final class UsageSparklineView: NSView {
    private let model: UsageHistoryChartModel
    private let lineColor: NSColor

    init(frame frameRect: NSRect, samples: [UsageHistorySample], lineColor: NSColor) {
        model = UsageHistoryChartModel(samples: samples)
        self.lineColor = lineColor
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let chartRect = bounds.insetBy(dx: 1, dy: 2)
        NSColor.secondaryLabelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: chartRect, xRadius: 4, yRadius: 4).fill()
        guard let first = model.displaySamples.first, let last = model.displaySamples.last else { return }

        let duration = max(1, last.recordedAt.timeIntervalSince(first.recordedAt))
        let point: (Int, UsageHistorySample) -> NSPoint = { index, sample in
            let elapsed = sample.recordedAt.timeIntervalSince(first.recordedAt)
            let x = self.model.displaySamples.count == 1
                ? chartRect.midX
                : chartRect.minX + CGFloat(elapsed / duration) * chartRect.width
            let y = chartRect.minY + self.model.normalizedY(for: sample.remainingPercent) * chartRect.height
            return NSPoint(x: x, y: y)
        }

        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setStroke()
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: chartRect.minX, y: chartRect.midY))
        guide.line(to: NSPoint(x: chartRect.maxX, y: chartRect.midY))
        guide.lineWidth = 0.5
        guide.stroke()

        for index in model.resetIndices {
            let resetPoint = point(index, model.samples[index])
            let marker = NSBezierPath()
            marker.move(to: NSPoint(x: resetPoint.x, y: chartRect.minY))
            marker.line(to: NSPoint(x: resetPoint.x, y: chartRect.maxY))
            lineColor.withAlphaComponent(0.35).setStroke()
            marker.lineWidth = 1
            marker.stroke()
            lineColor.setStroke()
            let ring = NSRect(x: resetPoint.x - 2.5, y: resetPoint.y - 2.5, width: 5, height: 5)
            NSBezierPath(ovalIn: ring).stroke()
        }

        let path = NSBezierPath()
        for (index, sample) in model.displaySamples.enumerated() {
            let samplePoint = point(index, sample)
            if index == 0 { path.move(to: samplePoint) } else { path.line(to: samplePoint) }
        }
        lineColor.setStroke()
        path.lineWidth = 1.75
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        let latestPoint = point(model.displaySamples.count - 1, last)
        let dotRect = NSRect(x: latestPoint.x - 2, y: latestPoint.y - 2, width: 4, height: 4)
        lineColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PreferenceKey {
        static let codexConnected = "provider.codex.connected"
        static let claudeConnected = "provider.claude.connected"
        static let selectedProvider = "status.selected.provider"
        static let language = "app.language"
        static let usageColorsEnabled = "status.usage.colors.enabled"
        static let usageAlertPreset = "status.usage.alert.preset"
        static let showResetInMenuBar = "status.reset.countdown.visible"
        static let autoRotateProviders = "status.providers.auto.rotate"
        static let usageHistoryEnabled = "usage.history.enabled"
        static let usageHistoryData = "usage.history.samples.v1"
        static let legacyCodexEnabled = "provider.codex.enabled"
        static let legacyClaudeEnabled = "provider.claude.enabled"
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu: NSMenu = {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }()
    private let codexFetcher = CodexUsageFetcher()
    private let claudeFetcher = ClaudeUsageFetcher()
    private var usages: [String: ProviderUsage] = [:]
    private var lastUpdated: Date?
    private var isRefreshing = false
    private var refreshTimer: Timer?
    private var statusPresentationTimer: Timer?
    private var rotatingProviderIndex = 0
    private var usageHistory: [String: [UsageHistorySample]] = [:]

    private var language: AppLanguage {
        get {
            guard let raw = UserDefaults.standard.string(forKey: PreferenceKey.language) else {
                return AppLanguage.preferred(from: Locale.preferredLanguages)
            }
            return AppLanguage(rawValue: raw)
                ?? AppLanguage.preferred(from: Locale.preferredLanguages)
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.language) }
    }

    private var text: Localizer { Localizer(language: language) }

    private var usageColorsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.usageColorsEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: PreferenceKey.usageColorsEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.usageColorsEnabled) }
    }

    private var usageAlertPreset: UsageAlertPreset {
        get {
            guard let raw = UserDefaults.standard.string(forKey: PreferenceKey.usageAlertPreset) else {
                return .balanced
            }
            return UsageAlertPreset(rawValue: raw) ?? .balanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: PreferenceKey.usageAlertPreset) }
    }

    private var usageAlertPolicy: UsageAlertPolicy {
        UsageAlertPolicy(isEnabled: usageColorsEnabled, preset: usageAlertPreset)
    }

    private var showResetInMenuBar: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.showResetInMenuBar) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.showResetInMenuBar) }
    }

    private var autoRotateProviders: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.autoRotateProviders) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.autoRotateProviders) }
    }

    private var usageHistoryEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: PreferenceKey.usageHistoryEnabled) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: PreferenceKey.usageHistoryEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.usageHistoryEnabled) }
    }

    private var codexConnected: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.codexConnected) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.codexConnected) }
    }

    private var claudeConnected: Bool {
        get { UserDefaults.standard.bool(forKey: PreferenceKey.claudeConnected) }
        set { UserDefaults.standard.set(newValue, forKey: PreferenceKey.claudeConnected) }
    }

    private var connectedProviderNames: [String] {
        var names: [String] = []
        if codexConnected { names.append("Codex") }
        if claudeConnected { names.append("Claude Code") }
        return names
    }

    private var selectedProviderName: String? {
        get {
            let saved = UserDefaults.standard.string(forKey: PreferenceKey.selectedProvider)
            if let saved, connectedProviderNames.contains(saved) { return saved }
            return connectedProviderNames.first
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: PreferenceKey.selectedProvider)
            } else {
                UserDefaults.standard.removeObject(forKey: PreferenceKey.selectedProvider)
            }
        }
    }

    private var statusProviderName: String? {
        let providers = connectedProviderNames
        guard !providers.isEmpty else { return nil }
        if autoRotateProviders && providers.count > 1 {
            return providers[rotatingProviderIndex % providers.count]
        }
        return selectedProviderName
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPreferences()
        usageHistory = UsageHistoryModel.decode(
            UserDefaults.standard.data(forKey: PreferenceKey.usageHistoryData)
        )
        NSApp.setActivationPolicy(.accessory)
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.title = "%—"
        statusItem.button?.toolTip = text.usageTooltip
        rebuildMenu()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        configureStatusPresentationTimer()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) > 60 {
            refresh()
        }
    }

    @objc private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        rebuildMenu()

        let group = DispatchGroup()
        if codexConnected {
            group.enter()
            codexFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.usages[usage.name] = usage
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Codex")
        }

        if claudeConnected {
            group.enter()
            claudeFetcher.fetch { [weak self] usage in
                DispatchQueue.main.async {
                    self?.usages[usage.name] = usage
                    group.leave()
                }
            }
        } else {
            usages.removeValue(forKey: "Claude Code")
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.isRefreshing = false
            let updateDate = Date()
            self.lastUpdated = updateDate
            self.recordUsageHistory(at: updateDate)
            self.updateStatusTitle()
            self.rebuildMenu()
        }
    }

    private func updateStatusTitle() {
        if let statusProviderName,
           let summary = UsageSummaryCalculator.summary(for: statusProviderName, in: usages) {
            var title = "%\(summary.remainingPercent)"
            if showResetInMenuBar, let resetsAt = summary.resetsAt {
                title += " · \(text.relativeReset(resetsAt))"
            }
            let level = usageAlertPolicy.level(for: summary.remainingPercent)
            statusItem.button?.title = ""
            statusItem.button?.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                    .foregroundColor: statusColor(for: level)
                ]
            )
            statusItem.button?.image = providerIcon(for: summary.providerName, size: 16)
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.imageScaling = .scaleProportionallyDown
            statusItem.button?.toolTip = text.remainingTooltip(
                provider: summary.providerName,
                percent: summary.remainingPercent
            )
        } else {
            statusItem.button?.attributedTitle = NSAttributedString(string: "")
            statusItem.button?.title = "%—"
            statusItem.button?.image = statusProviderName.flatMap { providerIcon(for: $0, size: 16) }
            statusItem.button?.toolTip = statusProviderName.map { text.waitingForUsage(provider: $0) }
                ?? text.connectFirst
        }
    }

    private func configureStatusPresentationTimer() {
        statusPresentationTimer?.invalidate()
        statusPresentationTimer = nil

        let shouldRotate = autoRotateProviders && connectedProviderNames.count > 1
        guard shouldRotate || showResetInMenuBar else { return }
        let interval: TimeInterval = shouldRotate ? ProviderRotation.interval : 60
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.autoRotateProviders && self.connectedProviderNames.count > 1 {
                self.rotatingProviderIndex = ProviderRotation.nextIndex(
                    after: self.rotatingProviderIndex,
                    providerCount: self.connectedProviderNames.count
                )
            }
            self.updateStatusTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        statusPresentationTimer = timer
    }

    private func recordUsageHistory(at date: Date) {
        guard usageHistoryEnabled else { return }
        for providerName in connectedProviderNames {
            guard let summary = UsageSummaryCalculator.summary(for: providerName, in: usages) else {
                continue
            }
            usageHistory[providerName] = UsageHistoryModel.adding(
                remainingPercent: summary.remainingPercent,
                at: date,
                to: usageHistory[providerName] ?? []
            )
        }
        persistUsageHistory()
    }

    private func persistUsageHistory() {
        guard let data = UsageHistoryModel.encode(usageHistory) else { return }
        UserDefaults.standard.set(data, forKey: PreferenceKey.usageHistoryData)
    }

    private func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PreferenceKey.codexConnected) == nil {
            let legacy = defaults.object(forKey: PreferenceKey.legacyCodexEnabled) != nil
                && defaults.bool(forKey: PreferenceKey.legacyCodexEnabled)
            defaults.set(legacy, forKey: PreferenceKey.codexConnected)
        }
        if defaults.object(forKey: PreferenceKey.claudeConnected) == nil {
            let legacy = defaults.object(forKey: PreferenceKey.legacyClaudeEnabled) != nil
                && defaults.bool(forKey: PreferenceKey.legacyClaudeEnabled)
            defaults.set(legacy, forKey: PreferenceKey.claudeConnected)
        }
        if defaults.string(forKey: PreferenceKey.selectedProvider) == nil {
            selectedProviderName = connectedProviderNames.first
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let connectedNames = connectedProviderNames
        for (index, providerName) in connectedNames.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let fallback: ProviderIssue = isRefreshing ? .refreshing : .noData
            addProvider(usages[providerName] ?? .unavailable(providerName, fallback))
        }

        if !connectedNames.isEmpty {
            menu.addItem(.separator())
            addProviderSelector()
            addMenuBarAppearanceSettings()
            addUsageColorSettings()
            addUsageHistorySettings()
        }

        if !codexConnected || !claudeConnected {
            if !menu.items.isEmpty { menu.addItem(.separator()) }
            if !codexConnected {
                addConnectionItem(
                    title: text.connectCodex,
                    providerName: "Codex",
                    action: #selector(connectCodex)
                )
            }
            if !claudeConnected {
                addConnectionItem(
                    title: text.connectClaude,
                    providerName: "Claude Code",
                    action: #selector(connectClaude)
                )
            }
        }

        menu.addItem(.separator())
        addLanguageSelector()
        addLaunchAtLoginItem()
        menu.addItem(.separator())

        if let lastUpdated {
            let item = NSMenuItem(
                title: text.lastUpdated(formattedTime(lastUpdated)),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }

        let refreshItem = NSMenuItem(
            title: isRefreshing ? text.refreshing : text.refreshNow,
            action: #selector(refresh),
            keyEquivalent: ""
        )
        refreshItem.target = self
        refreshItem.isEnabled = !isRefreshing && !connectedNames.isEmpty
        menu.addItem(refreshItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: text.quit, action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func addProviderSelector() {
        let providerNames = connectedProviderNames
        let supportsAutomatic = providerNames.count > 1
        let providerLabels = providerNames.map { $0 == "Claude Code" ? "Claude" : $0 }
        let labels = supportsAutomatic ? [text.automatic] + providerLabels : providerLabels
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 276, height: 58))

        let label = NSTextField(labelWithString: text.showInMenuBar)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 37, width: 252, height: 16)
        container.addSubview(label)

        let selector = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectStatusProvider(_:))
        )
        selector.segmentStyle = .rounded
        selector.frame = NSRect(x: 12, y: 7, width: 252, height: 28)
        if supportsAutomatic && autoRotateProviders {
            selector.selectedSegment = 0
        } else {
            let providerIndex = providerNames.firstIndex(of: selectedProviderName ?? "") ?? 0
            selector.selectedSegment = providerIndex + (supportsAutomatic ? 1 : 0)
        }
        container.addSubview(selector)

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func addMenuBarAppearanceSettings() {
        let rootItem = NSMenuItem(title: text.menuBarAppearance, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()
        let resetItem = NSMenuItem(
            title: text.showResetInMenuBar,
            action: #selector(toggleResetInMenuBar),
            keyEquivalent: ""
        )
        resetItem.target = self
        resetItem.state = showResetInMenuBar ? .on : .off
        submenu.addItem(resetItem)
        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func addLanguageSelector() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 276, height: 58))

        let label = NSTextField(labelWithString: text.languageTitle)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 12, y: 37, width: 252, height: 16)
        container.addSubview(label)

        let selector = NSSegmentedControl(
            labels: ["Türkçe", "English"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(selectLanguage(_:))
        )
        selector.segmentStyle = .rounded
        selector.frame = NSRect(x: 12, y: 7, width: 252, height: 28)
        selector.selectedSegment = language == .turkish ? 0 : 1
        container.addSubview(selector)

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func addUsageColorSettings() {
        let rootItem = NSMenuItem(title: text.usageColorsTitle, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()

        let enabledItem = NSMenuItem(
            title: text.usageColorsEnabled,
            action: #selector(toggleUsageColors),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = usageColorsEnabled ? .on : .off
        submenu.addItem(enabledItem)
        submenu.addItem(.separator())

        for preset in UsageAlertPreset.allCases {
            let item = NSMenuItem(
                title: text.alertPresetTitle(preset),
                action: #selector(selectUsageAlertPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = usageAlertPreset == preset ? .on : .off
            item.isEnabled = usageColorsEnabled
            submenu.addItem(item)
        }

        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func addUsageHistorySettings() {
        let rootItem = NSMenuItem(title: text.usageHistoryTitle, action: nil, keyEquivalent: "")
        let submenu = manuallyEnabledMenu()

        let enabledItem = NSMenuItem(
            title: text.showUsageHistory,
            action: #selector(toggleUsageHistory),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = usageHistoryEnabled ? .on : .off
        submenu.addItem(enabledItem)

        let clearItem = NSMenuItem(
            title: text.clearUsageHistory,
            action: #selector(clearUsageHistory),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.isEnabled = usageHistory.values.contains { !$0.isEmpty }
        submenu.addItem(clearItem)

        rootItem.submenu = submenu
        menu.addItem(rootItem)
    }

    private func manuallyEnabledMenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        return submenu
    }

    private func addLaunchAtLoginItem() {
        let status = SMAppService.mainApp.status
        let suffix = status == .requiresApproval ? " (\(text.loginItemNeedsApproval))" : ""
        let item = NSMenuItem(
            title: text.launchAtLogin + suffix,
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        item.target = self
        item.state = status == .enabled ? .on : (status == .requiresApproval ? .mixed : .off)
        menu.addItem(item)
    }

    private func addConnectionItem(title: String, providerName: String, action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = providerIcon(for: providerName, size: 16)
        menu.addItem(item)
    }

    private func addProvider(_ usage: ProviderUsage) {
        var rows: [NSAttributedString] = []
        if let session = usage.session {
            rows.append(windowTitle(text.fiveHours, session))
        }
        if let weekly = usage.weekly {
            rows.append(windowTitle(text.weekly, weekly))
        }
        if let error = usage.error {
            rows.append(errorTitle(error))
        }

        let historySamples = usageHistoryEnabled ? (usageHistory[usage.name] ?? []) : []
        let historyHeight: CGFloat = historySamples.isEmpty ? 0 : 58

        let width: CGFloat = 276
        let rowHeights = rows.map { attributedTitle in
            attributedTitle.string.contains("\n") ? CGFloat(40) : CGFloat(25)
        }
        let height = 46 + rowHeights.reduce(0, +) + historyHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        if let icon = providerIcon(for: usage.name, size: 18) {
            let imageView = NSImageView(frame: NSRect(x: 12, y: height - 31, width: 18, height: 18))
            imageView.image = icon
            imageView.imageScaling = .scaleProportionallyDown
            container.addSubview(imageView)
        }

        let title = NSTextField(labelWithString: usage.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: 38, y: height - 34, width: width - 50, height: 23)
        container.addSubview(title)

        var rowTop = height - 42
        for (attributedTitle, rowHeight) in zip(rows, rowHeights) {
            rowTop -= rowHeight
            let row = NSTextField(labelWithAttributedString: attributedTitle)
            row.maximumNumberOfLines = 2
            row.lineBreakMode = .byWordWrapping
            row.frame = NSRect(
                x: 14,
                y: rowTop,
                width: width - 28,
                height: rowHeight
            )
            container.addSubview(row)
        }

        if let latestSample = historySamples.last {
            let historyModel = UsageHistoryChartModel(samples: historySamples)
            let historyRange = text.usageHistoryRange(historyModel.recordedDuration)
            let historySummary = text.usageHistorySummary(historyModel)
            let historyLabel = NSTextField(labelWithString: historyRange)
            historyLabel.font = .systemFont(ofSize: 10, weight: .medium)
            historyLabel.textColor = .secondaryLabelColor
            historyLabel.frame = NSRect(x: 14, y: 43, width: width - 28, height: 13)
            container.addSubview(historyLabel)

            let summaryLabel = NSTextField(labelWithString: historySummary)
            summaryLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
            summaryLabel.textColor = .secondaryLabelColor
            summaryLabel.lineBreakMode = .byTruncatingTail
            summaryLabel.frame = NSRect(x: 14, y: 30, width: width - 28, height: 12)
            container.addSubview(summaryLabel)

            let graph = UsageSparklineView(
                frame: NSRect(x: 14, y: 6, width: width - 28, height: 22),
                samples: historySamples,
                lineColor: remainingColor(latestSample.remainingPercent)
            )
            graph.setAccessibilityLabel(historyRange)
            graph.setAccessibilityValue(historySummary)
            container.addSubview(graph)
        }

        let item = NSMenuItem()
        item.view = container
        menu.addItem(item)
    }

    private func windowTitle(_ label: String, _ window: UsageWindow) -> NSAttributedString {
        let remainingPercent = min(100, max(0, 100 - window.usedPercent))
        let prefix = "\(label): "
        let remaining = text.remaining(remainingPercent)
        var displayText = prefix + remaining
        if let resetsAt = window.resetsAt {
            displayText += "\n\(text.resetIn(text.relativeReset(resetsAt)))"
        }
        let attributed = NSMutableAttributedString(
            string: displayText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: remainingColor(remainingPercent)
            ],
            range: NSRange(location: prefix.utf16.count, length: remaining.utf16.count)
        )
        if let lineBreak = displayText.firstIndex(of: "\n") {
            let resetStart = displayText.index(after: lineBreak)
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor
                ],
                range: NSRange(resetStart..<displayText.endIndex, in: displayText)
            )
        }
        return attributed
    }

    private func errorTitle(_ issue: ProviderIssue) -> NSAttributedString {
        let informational: Bool
        switch issue {
        case .refreshing, .noData: informational = true
        default: informational = false
        }
        return NSAttributedString(
            string: text.issue(issue),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: informational ? NSColor.secondaryLabelColor : NSColor.systemRed
            ]
        )
    }

    private func remainingColor(_ percent: Int) -> NSColor {
        guard usageColorsEnabled else { return .labelColor }
        switch usageAlertPolicy.level(for: percent) {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal: return .systemGreen
        }
    }

    private func statusColor(for level: UsageAlertLevel) -> NSColor {
        switch level {
        case .critical: return .systemRed
        case .warning: return .systemOrange
        case .normal: return .labelColor
        }
    }

    private func providerIcon(for providerName: String, size: CGFloat) -> NSImage? {
        let appPaths: [String]
        let fallbackSymbol: String
        switch providerName {
        case "Codex":
            appPaths = ["/Applications/Codex.app", "/Applications/ChatGPT.app"]
            fallbackSymbol = "ellipsis.curlybraces"
        case "Claude Code":
            appPaths = ["/Applications/Claude.app"]
            fallbackSymbol = "sparkles"
        default:
            appPaths = []
            fallbackSymbol = "gauge.with.dots.needle.33percent"
        }

        if let appPath = appPaths.first(where: { FileManager.default.fileExists(atPath: $0) }),
           let icon = NSWorkspace.shared.icon(forFile: appPath).copy() as? NSImage {
            icon.size = NSSize(width: size, height: size)
            return icon
        }

        let symbol = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: providerName)
        symbol?.size = NSSize(width: size, height: size)
        symbol?.isTemplate = true
        return symbol
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func connectCodex() {
        guard ExecutableLocator.codex() != nil else {
            showConnectionError(
                title: text.codexNotFoundTitle,
                message: text.codexNotFoundMessage
            )
            return
        }
        let wasEmpty = connectedProviderNames.isEmpty
        codexConnected = true
        if wasEmpty { selectedProviderName = "Codex" }
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
        refresh()
    }

    @objc private func connectClaude() {
        guard ExecutableLocator.claude() != nil else {
            showConnectionError(
                title: text.claudeNotFoundTitle,
                message: text.claudeNotFoundMessage
            )
            return
        }

        let alert = NSAlert()
        alert.messageText = text.connectClaudeTitle
        alert.informativeText = text.connectClaudeMessage
        alert.alertStyle = .informational
        alert.addButton(withTitle: text.connect)
        alert.addButton(withTitle: text.cancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let wasEmpty = connectedProviderNames.isEmpty
        claudeConnected = true
        if wasEmpty { selectedProviderName = "Claude Code" }
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
        refresh()
    }

    @objc private func selectStatusProvider(_ sender: NSSegmentedControl) {
        let providerNames = connectedProviderNames
        let supportsAutomatic = providerNames.count > 1
        if supportsAutomatic && sender.selectedSegment == 0 {
            autoRotateProviders = true
            rotatingProviderIndex = providerNames.firstIndex(of: selectedProviderName ?? "") ?? 0
        } else {
            let providerIndex = sender.selectedSegment - (supportsAutomatic ? 1 : 0)
            guard providerNames.indices.contains(providerIndex) else { return }
            autoRotateProviders = false
            rotatingProviderIndex = providerIndex
            selectedProviderName = providerNames[providerIndex]
        }
        configureStatusPresentationTimer()
        updateStatusTitle()
    }

    @objc private func toggleResetInMenuBar() {
        showResetInMenuBar.toggle()
        configureStatusPresentationTimer()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func toggleUsageColors() {
        usageColorsEnabled.toggle()
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func selectUsageAlertPreset(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let preset = UsageAlertPreset(rawValue: raw)
        else { return }
        usageAlertPreset = preset
        updateStatusTitle()
        rebuildMenu()
    }

    @objc private func toggleUsageHistory() {
        usageHistoryEnabled.toggle()
        if usageHistoryEnabled { recordUsageHistory(at: Date()) }
        rebuildMenu()
    }

    @objc private func clearUsageHistory() {
        usageHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: PreferenceKey.usageHistoryData)
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            rebuildMenu()
        } catch {
            showConnectionError(
                title: text.loginItemFailed,
                message: error.localizedDescription
            )
        }
    }

    @objc private func selectLanguage(_ sender: NSSegmentedControl) {
        let selectedLanguage: AppLanguage = sender.selectedSegment == 1 ? .english : .turkish
        guard selectedLanguage != language else { return }
        language = selectedLanguage
        updateStatusTitle()
        menu.cancelTracking()
        rebuildMenu()
    }

    private func showConnectionError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: text.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .turkish ? "tr_TR" : "en_US")
        formatter.dateFormat = language == .turkish ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}

private func runSelfTest() -> Int32 {
    let turkish = Localizer(language: .turkish)
    let english = Localizer(language: .english)
    let durationOrigin = Date(timeIntervalSince1970: 1_000_000)
    guard
        turkish.remaining(59) == "%59 kaldı",
        english.remaining(59) == "59% remaining",
        english.remainingTooltip(provider: "Codex", percent: 59) == "Codex: 59% remaining",
        AppLanguage.preferred(from: ["tr-TR", "en-US"]) == .turkish,
        AppLanguage.preferred(from: ["en-US", "tr-TR"]) == .english,
        AppLanguage.preferred(from: []) == .english,
        turkish.issue(.claudeNotLoggedIn) == "Claude Code'a giriş yapılmamış",
        english.issue(.claudeNotLoggedIn) == "Claude Code is not signed in",
        english.relativeReset(
            durationOrigin.addingTimeInterval(3_600 + 15 * 60),
            now: durationOrigin
        ) == "1h 15m",
        english.relativeReset(
            durationOrigin.addingTimeInterval(6 * 86_400 + 21 * 3_600),
            now: durationOrigin
        ) == "6d 21h"
    else {
        fputs("Dil testi başarısız\n", stderr)
        return 1
    }

    let balancedAlerts = UsageAlertPolicy(isEnabled: true, preset: .balanced)
    let disabledAlerts = UsageAlertPolicy(isEnabled: false, preset: .early)
    guard
        balancedAlerts.level(for: 21) == .normal,
        balancedAlerts.level(for: 20) == .warning,
        balancedAlerts.level(for: 11) == .warning,
        balancedAlerts.level(for: 10) == .critical,
        balancedAlerts.level(for: -1) == .critical,
        disabledAlerts.level(for: 0) == .normal
    else {
        fputs("Kullanım renk eşiği testi başarısız\n", stderr)
        return 1
    }

    let historyOrigin = Date(timeIntervalSince1970: 2_000_000)
    let historyWithExpiredSample = [
        UsageHistorySample(
            recordedAt: historyOrigin.addingTimeInterval(-UsageHistoryModel.retentionInterval - 1),
            remainingPercent: 95
        ),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(-120), remainingPercent: 80)
    ]
    let prunedHistory = UsageHistoryModel.adding(
        remainingPercent: 70,
        at: historyOrigin,
        to: historyWithExpiredSample
    )
    let replacedHistory = UsageHistoryModel.adding(
        remainingPercent: 65,
        at: historyOrigin.addingTimeInterval(30),
        to: prunedHistory
    )
    let encodedHistory = UsageHistoryModel.encode(["Codex": replacedHistory])
    let decodedHistory = UsageHistoryModel.decode(encodedHistory)
    let flatChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 33)
    ])
    let changingChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 33),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(35 * 60), remainingPercent: 31)
    ])
    let resetChart = UsageHistoryChartModel(samples: [
        UsageHistorySample(recordedAt: historyOrigin, remainingPercent: 20),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(60), remainingPercent: 19),
        UsageHistorySample(recordedAt: historyOrigin.addingTimeInterval(120), remainingPercent: 90)
    ])
    let noisyChart = UsageHistoryChartModel(samples: [33, 34, 33, 32, 31].enumerated().map {
        UsageHistorySample(
            recordedAt: historyOrigin.addingTimeInterval(Double($0.offset * 60)),
            remainingPercent: $0.element
        )
    })
    guard
        prunedHistory.count == 2,
        replacedHistory.count == 2,
        replacedHistory.last?.remainingPercent == 65,
        decodedHistory["Codex"] == replacedHistory,
        flatChart.lowerBound == 28,
        flatChart.upperBound == 38,
        changingChart.delta == -2,
        resetChart.resetIndices == [2],
        noisyChart.samples.map(\.remainingPercent) == [33, 34, 33, 32, 31],
        noisyChart.displaySamples.map(\.remainingPercent) == [33, 33, 33, 32, 31],
        turkish.usageHistoryRange(changingChart.recordedDuration) == "Son 35 dk",
        english.usageHistoryRange(changingChart.recordedDuration) == "Last 35m",
        english.usageHistorySummary(changingChart) == "33% → 31% · change -2"
    else {
        fputs("Yerel kullanım geçmişi testi başarısız\n", stderr)
        return 1
    }

    let codex = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":35,"windowDurationMins":300,"resetsAt":1784740000},"secondary":{"usedPercent":12.4,"windowDurationMins":10080,"resetsAt":1785000000}}}}
    """
    guard
        let parsedCodex = UsageParser.codexResponse(from: Data(codex.utf8)),
        parsedCodex.session?.usedPercent == 35,
        parsedCodex.weekly?.usedPercent == 12
    else {
        fputs("Codex parser testi başarısız\n", stderr)
        return 1
    }

    let claude = """
    Current session     41% used
    Resets in 2 hours 15 minutes
    Current week (all models)     18% used
    Resets Jul 29, 11:59pm (Europe/Istanbul)
    """
    let parsedClaude = UsageParser.claudeScreen(claude)
    guard
        parsedClaude.session?.usedPercent == 41,
        parsedClaude.weekly?.usedPercent == 18,
        parsedClaude.session?.resetsAt != nil,
        parsedClaude.weekly?.resetsAt != nil
    else {
        fputs("Claude parser testi başarısız\n", stderr)
        return 1
    }

    let structuredClaude = UsageParser.claudeStatusLine("""
    \u{001B}[2CUSAGEBAR_LIMITS:|||\r
    \u{001B}[18C101|1784740200|25|1785092400\r
    """)
    guard
        structuredClaude?.session?.usedPercent == 100,
        structuredClaude?.weekly?.usedPercent == 25,
        structuredClaude?.session?.resetsAt?.timeIntervalSince1970 == 1_784_740_200,
        structuredClaude?.weekly?.resetsAt?.timeIntervalSince1970 == 1_785_092_400
    else {
        fputs("Claude yapılandırılmış limit testi başarısız\n", stderr)
        return 1
    }

    let summary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Codex": parsedCodex,
        "Claude Code": parsedClaude
    ])
    guard summary?.providerName == "Claude Code", summary?.remainingPercent == 59 else {
        fputs("Kalan kullanım özeti testi başarısız\n", stderr)
        return 1
    }

    let claudeSessionFirst = ProviderUsage(
        name: "Claude Code",
        session: UsageWindow(
            usedPercent: 20,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000),
            durationMinutes: 300
        ),
        weekly: UsageWindow(usedPercent: 95, resetsAt: nil, durationMinutes: 10_080),
        error: nil
    )
    let sessionFirstSummary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Claude Code": claudeSessionFirst
    ])
    guard
        sessionFirstSummary?.remainingPercent == 80,
        sessionFirstSummary?.resetsAt?.timeIntervalSince1970 == 1_800_000_000
    else {
        fputs("Claude 5 saatlik pencere önceliği testi başarısız\n", stderr)
        return 1
    }

    guard
        ProviderRotation.nextIndex(after: 0, providerCount: 2) == 1,
        ProviderRotation.nextIndex(after: 1, providerCount: 2) == 0,
        ProviderRotation.nextIndex(after: 8, providerCount: 0) == 0,
        ProviderRotation.interval == 30
    else {
        fputs("Sağlayıcı dönüşüm testi başarısız\n", stderr)
        return 1
    }

    let claudeWeeklyFallback = ProviderUsage(
        name: "Claude Code",
        session: nil,
        weekly: UsageWindow(usedPercent: 26, resetsAt: nil, durationMinutes: 10_080),
        error: nil
    )
    let weeklyFallbackSummary = UsageSummaryCalculator.summary(for: "Claude Code", in: [
        "Claude Code": claudeWeeklyFallback
    ])
    guard weeklyFallbackSummary?.remainingPercent == 74 else {
        fputs("Claude haftalık yedek pencere testi başarısız\n", stderr)
        return 1
    }

    let weeklyOnlyCodex = """
    {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":13,"windowDurationMins":10080,"resetsAt":1785340800},"secondary":null}}}
    """
    guard
        let parsedWeeklyOnly = UsageParser.codexResponse(from: Data(weeklyOnlyCodex.utf8)),
        parsedWeeklyOnly.session == nil,
        parsedWeeklyOnly.weekly?.usedPercent == 13
    else {
        fputs("Codex haftalık-only parser testi başarısız\n", stderr)
        return 1
    }

    let boundedCapture = BoundedDataCapture(limit: 4)
    guard
        boundedCapture.append(Data([1, 2, 3])),
        !boundedCapture.append(Data([4, 5])),
        boundedCapture.snapshot().data == Data([1, 2, 3, 4]),
        boundedCapture.snapshot().exceeded
    else {
        fputs("Çıktı sınırı testi başarısız\n", stderr)
        return 1
    }

    print("UsageBar öz testi başarılı")
    return 0
}

private func runClaudeStatusFilter() -> Int32 {
    let maximumInputBytes = 64 * 1_024
    var input = Data()

    while true {
        let chunk = FileHandle.standardInput.readData(ofLength: 4 * 1_024)
        if chunk.isEmpty { break }
        guard input.count + chunk.count <= maximumInputBytes else { return 1 }
        input.append(chunk)
    }

    guard
        let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
        let limits = object["rate_limits"] as? [String: Any]
    else { return 1 }

    func field(_ window: String, _ key: String) -> String {
        guard
            let values = limits[window] as? [String: Any],
            let value = values[key]
        else { return "" }
        if let number = value as? NSNumber { return number.stringValue }
        if let string = value as? String, Double(string) != nil { return string }
        return ""
    }

    let fields = [
        field("five_hour", "used_percentage"),
        field("five_hour", "resets_at"),
        field("seven_day", "used_percentage"),
        field("seven_day", "resets_at")
    ]
    print("USAGEBAR_LIMITS:" + fields.joined(separator: "|"))
    return 0
}

if CommandLine.arguments.contains("--self-test") {
    exit(runSelfTest())
}

if CommandLine.arguments.contains("--claude-status-filter") {
    exit(runClaudeStatusFilter())
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
