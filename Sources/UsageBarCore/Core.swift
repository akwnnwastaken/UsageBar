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
/// Bir pencere içinde kalan yüzde gerçekte artamayacağı için tek ölçümlük +1
/// sıçramaları gösterimde bekletilir. Sıçrama ikinci ölçümde de sürüyorsa kabul
/// edilir; böylece gecikme tek bir yenileme döngüsüyle sınırlı kalır ve gerçek
/// bir artış kalıcı olarak gizlenmez. Kayıtlı geçmiş her zaman ham kalır.
public enum UsageDisplayNoiseFilter {
    /// +1'lik bir yükselişin gerçek kabul edilmesi için gereken üst üste ölçüm
    /// sayısı. Gözlenen yuvarlama dalgalanmaları iki ölçüm sürebildiği için eşik
    /// üçtür; böylece gösterim en fazla üç yenileme geriden gelir ve kalıcı
    /// olarak yanlış kalmaz.
    public static let risePersistenceThreshold = 3

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
        // Düşüşler ve +2 ve üzeri sıçramalar (sıfırlama, limit değişimi) gerçektir.
        guard raw == previouslyDisplayed + 1 else { return accepted }
        let count = (pendingRise == raw ? pendingCount : 0) + 1
        guard count < risePersistenceThreshold else { return accepted }
        return Decision(displayed: previouslyDisplayed, pendingRise: raw, pendingCount: count)
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
