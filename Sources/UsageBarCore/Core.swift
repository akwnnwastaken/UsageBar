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
