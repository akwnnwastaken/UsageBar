using System.Globalization;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Localization;

/// <summary>
/// Every user-facing string in Turkish and English. The macOS strings are
/// carried over verbatim where the concept exists on both platforms; the
/// Windows-only strings (tray guidance, context menu, startup) follow the same
/// tone and are provided in both languages.
/// </summary>
public sealed class Localizer
{
    public Localizer(AppLanguage language) => Language = language;

    public AppLanguage Language { get; }

    private bool IsTurkish => Language == AppLanguage.Turkish;

    private string Pick(string turkish, string english) => IsTurkish ? turkish : english;

    private CultureInfo Culture => CultureInfo.GetCultureInfo(IsTurkish ? "tr-TR" : "en-US");

    // MARK: - General

    public string AppName => "UsageBar";
    public string UsageTooltip => Pick("Codex ve Claude Code kullanımı", "Codex and Claude Code usage");
    public string ConnectFirst => Pick("Önce bir sağlayıcı bağlayın", "Connect a provider first");
    public string Refreshing => Pick("Yenileniyor…", "Refreshing…");
    public string NoData => Pick("Henüz veri yok", "No data yet");
    public string Now => Pick("şimdi", "now");
    public string Ok => Pick("Tamam", "OK");
    public string Cancel => Pick("Vazgeç", "Cancel");
    public string Connect => Pick("Bağlan", "Connect");

    // MARK: - Tray context menu

    public string RefreshNow => Pick("Şimdi yenile", "Refresh now");
    public string ShowUsageBar => Pick("UsageBar'ı göster", "Show UsageBar");
    public string LaunchAtStartup => Pick("Windows açılışında başlat", "Launch at startup");
    public string Settings => Pick("Ayarlar", "Settings");
    public string ExitUsageBar => Pick("UsageBar'dan çık", "Exit UsageBar");

    // MARK: - Panel

    public string ShowInTray => Pick("Tepside göster", "Show in tray");
    public string Automatic => Pick("Otomatik", "Auto");
    public string ConnectCodex => Pick("Codex'e bağlan", "Connect Codex");
    public string ConnectClaude => Pick("Claude Code'a bağlan", "Connect Claude Code");
    public string DisconnectCodex => Pick("Codex bağlantısını kaldır", "Disconnect Codex");
    public string DisconnectClaude => Pick("Claude Code bağlantısını kaldır", "Disconnect Claude Code");
    public string LanguageTitle => Pick("Dil", "Language");
    public string UsageColorsTitle => Pick("Kullanım renkleri", "Usage colors");
    public string UsageColorsEnabled => Pick("Renkleri kullan", "Use colors");
    public string TrayAppearance => Pick("Tepsi görünümü", "Tray appearance");
    public string ShowResetCountdown => Pick("Sıfırlanma süresini ipucunda göster", "Show reset countdown in the tooltip");
    public string UsageHistoryTitle => Pick("Kullanım geçmişi", "Usage history");
    public string ShowUsageHistory => Pick("24 saatlik mini grafiği göster", "Show 24-hour mini chart");
    public string ClearUsageHistory => Pick("Geçmişi temizle", "Clear history");
    public string CopyDiagnostics => Pick("Tanılama özetini kopyala", "Copy diagnostics");
    public string DiagnosticsCopied => Pick("Tanılama özeti panoya kopyalandı", "Diagnostics copied to the clipboard");
    public string RefreshIntervalTitle => Pick("Yenileme aralığı", "Refresh interval");
    public string ThresholdProfileTitle => Pick("Uyarı profili", "Threshold profile");
    public string FiveHours => Pick("5 saat", "5 hours");
    public string Weekly => Pick("Haftalık", "Weekly");
    public string Connected => Pick("Bağlı", "Connected");
    public string NotConnected => Pick("Bağlı değil", "Not connected");
    public string Close => Pick("Kapat", "Close");
    public string HistoryDisabled => Pick("Geçmiş kapalı", "History is off");

    /// <summary>
    /// Shown instead of a Claude connect action while the Windows Claude
    /// adapters do not exist yet. UsageBar never fabricates provider data, so
    /// the option is disabled and labeled rather than shown as working.
    /// </summary>
    public string ClaudeNotSupportedYet => Pick(
        "Claude Code — Windows'ta henüz desteklenmiyor",
        "Claude Code — not supported on Windows yet");

    public string ClaudeNotSupportedYetDetail => Pick(
        "Claude Code okuyucusu Windows sürümüne henüz eklenmedi. Bu sürümde yalnızca Codex kullanılabilir.",
        "The Claude Code reader has not been added to the Windows build yet. This build supports Codex only.");

    // MARK: - Tray visibility guidance

    public string TrayGuidanceTitle => Pick("UsageBar'ı görünür tutun", "Keep UsageBar visible");

    /// <summary>
    /// Physical testing showed Windows does not necessarily place a moved icon
    /// beside the clock — it landed next to the `^` button, which is normal
    /// Windows ordering. The wording therefore asks for the visible tray area
    /// rather than promising an exact position the application cannot control.
    /// </summary>
    public string TrayGuidanceBody => Pick(
        "UsageBar simgesi ^ menüsünde gizliyse simgeyi görev çubuğundaki görünür sistem tepsisi alanına taşıyın.",
        "If UsageBar is hidden under ^, move its icon to the visible system tray area on the taskbar.");

    /// <summary>The fuller explanation shown in settings, next to the manual action.</summary>
    public string TrayGuidanceDetail => Pick(
        "Windows, UsageBar simgesini ilk açılışta ^ menüsünde gizleyebilir. Simgeyi ^ menüsünden görev çubuğundaki görünür sistem tepsisi alanına taşıyabilirsiniz. Windows simgeyi saatin hemen yanına yerleştirmeyebilir; görünür alanda bulunması yeterlidir.",
        "Windows may initially hide UsageBar under the ^ menu. You can move the icon from the overflow menu to the visible system tray area. Windows may not place it immediately next to the clock; being visible in the tray area is sufficient.");

    /// <summary>Fallback route for Windows builds where dragging is unavailable.</summary>
    public string TrayGuidanceSettingsPath => Pick(
        "Windows Ayarlar > Kişiselleştirme > Görev Çubuğu > Diğer sistem tepsisi simgeleri",
        "Windows Settings > Personalization > Taskbar > Other system tray icons");

    public string ShowTrayGuidanceAgain => Pick(
        "Sistem tepsisi yönlendirmesini yeniden göster",
        "Show system tray guidance again");

    // MARK: - Startup

    public string LaunchAtStartupFailed => Pick(
        "Başlangıç ayarı değiştirilemedi",
        "Could not change the startup setting");

    public string LaunchAtStartupBlockedByPolicy => Pick(
        "Başlangıç ayarı sistem ilkesi tarafından engellendi",
        "The startup setting is blocked by system policy");

    public string LaunchAtStartupStalePath => Pick(
        "Başlangıç kaydı başka bir konumu gösteriyor",
        "The startup entry points at a different location");

    // MARK: - Provider connection errors

    public string CodexNotFoundTitle => Pick("Codex bulunamadı", "Codex not found");

    public string CodexNotFoundMessage => Pick(
        "Önce ChatGPT veya Codex komut satırı uygulamasını kurup hesabınıza giriş yapın.",
        "Install ChatGPT or the Codex CLI and sign in first.");

    public string CodexUntrustedTitle => Pick("Codex güvenli değil", "Codex is not trusted");

    public string CodexUntrustedMessage => Pick(
        "Codex çalıştırılabilir dosyasının konumu veya türü güvenli bulunmadı. Codex'i resmi kaynaktan yeniden kurun.",
        "The Codex executable has an unsafe location or file type. Reinstall Codex from an official source.");

    public string ClaudeNotFoundTitle => Pick("Claude Code bulunamadı", "Claude Code not found");

    public string ClaudeNotFoundMessage => Pick(
        "Önce Claude Code'u kurup hesabınıza giriş yapın.",
        "Install Claude Code and sign in first.");

    public string ClaudeUntrustedTitle => Pick("Claude Code güvenli değil", "Claude Code is not trusted");

    public string ClaudeUntrustedMessage => Pick(
        "Claude Code çalıştırılabilir dosyasının konumu veya türü güvenli bulunmadı. Claude Code'u resmi kaynaktan yeniden kurun.",
        "The Claude Code executable has an unsafe location or file type. Reinstall Claude Code from an official source.");

    public string UnsupportedInstallationTitle => Pick(
        "Desteklenmeyen kurulum biçimi",
        "Unsupported installation format");

    public string UnsupportedInstallationMessage => Pick(
        "Bu kurulum yalnızca bir kabuk üzerinden çalıştırılabiliyor. UsageBar sağlayıcıları kabuk üzerinden başlatmaz. Desteklenen kurulum biçimleri için docs/windows-port.md dosyasına bakın.",
        "This installation can only be started through a shell. UsageBar never launches providers through a shell. See docs/windows-port.md for the supported installation formats.");

    public string ConnectClaudeTitle => Pick("Claude Code'a bağlanılsın mı?", "Connect Claude Code?");

    public string ConnectClaudeMessage => Pick(
        "UsageBar yalnızca Claude Code'un mevcut giriş durumunu ve kullanım sınırlarını izole bir oturumda okuyacak. Parola, API anahtarı veya oturum belirteci saklanmaz; tarayıcı kullanılmaz.",
        "UsageBar will read only Claude Code's current sign-in status and usage limits in an isolated session. No password, API key or session token is stored, and no browser is used.");

    // MARK: - Formatted values

    public string Remaining(int percent) =>
        Pick($"%{percent} kaldı", $"{percent}% remaining");

    public string RemainingTooltip(string provider, int percent) =>
        Pick($"{provider}: %{percent} kaldı", $"{provider}: {percent}% remaining");

    public string StaleTooltip(string provider, int percent) =>
        Pick($"{provider}: %{percent} kaldı (eski veri)", $"{provider}: {percent}% remaining (stale)");

    public string WaitingForUsage(string provider) =>
        Pick($"{provider} kullanım bilgisi bekleniyor", $"Waiting for {provider} usage");

    public string ResetIn(string duration) =>
        Pick($"Sıfırlama: {duration}", $"Resets in {duration}");

    public string WindowResetsIn(string windowLabel, string duration) =>
        Pick($"{windowLabel} penceresi {duration} içinde sıfırlanır", $"{windowLabel} window resets in {duration}");

    public string LastUpdated(string time) =>
        Pick($"Son güncelleme: {time}", $"Last updated: {time}");

    public string AppVersion(string version) =>
        Pick($"Sürüm {version}", $"Version {version}");

    public string StaleData(string lastSuccessfulTime, ProviderIssue issue) =>
        Pick(
            $"Son iyi veri: {lastSuccessfulTime}\n{Issue(issue)}",
            $"Last good data: {lastSuccessfulTime}\n{Issue(issue)}");

    public string FormattedTime(DateTimeOffset value) =>
        value.ToLocalTime().ToString(IsTurkish ? "HH:mm" : "h:mm tt", Culture);

    public string AlertPresetTitle(UsageAlertPreset preset)
    {
        var name = preset switch
        {
            UsageAlertPreset.Late => Pick("Geç", "Late"),
            UsageAlertPreset.Early => Pick("Erken", "Early"),
            _ => Pick("Dengeli", "Balanced")
        };

        return Pick(
            $"{name} — turuncu %{preset.WarningThreshold()}, kırmızı %{preset.CriticalThreshold()}",
            $"{name} — orange {preset.WarningThreshold()}%, red {preset.CriticalThreshold()}%");
    }

    public string RefreshIntervalOption(UsageRefreshInterval interval)
    {
        var minutes = interval.Minutes();
        return Pick(
            $"{minutes} dakika",
            minutes == 1 ? "1 minute" : $"{minutes} minutes");
    }

    public string UsageWindowLabel(UsageWindow window, int position)
    {
        ArgumentNullException.ThrowIfNull(window);

        switch (window.Kind.CategoryKind)
        {
            case UsageWindowKind.Category.FiveHour:
                return FiveHours;
            case UsageWindowKind.Category.Weekly:
                return Weekly;
            case UsageWindowKind.Category.Duration:
            {
                var minutes = window.Kind.Value;
                var days = minutes / (24 * 60);
                var hours = minutes % (24 * 60) / 60;
                var remainingMinutes = minutes % 60;
                var parts = new List<string>(3);
                if (days > 0)
                {
                    parts.Add(Pick($"{days} gün", $"{days} days"));
                }

                if (hours > 0)
                {
                    parts.Add(Pick($"{hours} saat", $"{hours} hours"));
                }

                if (remainingMinutes > 0)
                {
                    parts.Add(Pick($"{remainingMinutes} dk", $"{remainingMinutes} min"));
                }

                return parts.Count == 0
                    ? Pick("Kullanım penceresi", "Usage window")
                    : string.Join(" ", parts);
            }

            default:
                return Pick($"Kullanım penceresi {position + 1}", $"Usage window {position + 1}");
        }
    }

    /// <summary>Compact countdown, e.g. <c>6d 21h</c> / <c>6g 21sa</c>.</summary>
    public string RelativeReset(DateTimeOffset date, DateTimeOffset now)
    {
        var interval = date - now;
        var totalSeconds = (long)Math.Max(0, interval.TotalSeconds);
        var days = totalSeconds / 86_400;
        var hours = totalSeconds % 86_400 / 3_600;
        var minutes = totalSeconds % 3_600 / 60;

        if (IsTurkish)
        {
            if (days > 0)
            {
                return $"{days}g {hours}sa";
            }

            if (hours > 0)
            {
                return $"{hours}sa {minutes}dk";
            }

            return minutes > 0 ? $"{minutes}dk" : Now;
        }

        if (days > 0)
        {
            return $"{days}d {hours}h";
        }

        if (hours > 0)
        {
            return $"{hours}h {minutes}m";
        }

        return minutes > 0 ? $"{minutes}m" : Now;
    }

    public string UsageHistoryRange(TimeSpan duration)
    {
        if (duration.TotalSeconds < 60)
        {
            return Pick("İlk kayıt", "First sample");
        }

        var totalMinutes = (int)duration.TotalMinutes;
        if (totalMinutes < 60)
        {
            return Pick($"Son {totalMinutes} dk", $"Last {totalMinutes}m");
        }

        var totalHours = totalMinutes / 60;
        var minutes = totalMinutes % 60;
        if (totalHours < 24)
        {
            var suffix = minutes > 0 ? Pick($" {minutes} dk", $" {minutes}m") : string.Empty;
            return Pick($"Son {totalHours} sa", $"Last {totalHours}h") + suffix;
        }

        var days = totalHours / 24;
        var hours = totalHours % 24;
        var hourSuffix = hours > 0 ? Pick($" {hours} sa", $" {hours}h") : string.Empty;
        return Pick($"Son {days} gün", $"Last {days}d") + hourSuffix;
    }

    public string UsageHistorySummary(UsageHistoryChartModel model)
    {
        ArgumentNullException.ThrowIfNull(model);

        if (model.DisplaySamples.Count == 0)
        {
            return NoData;
        }

        var first = model.DisplaySamples[0];
        var last = model.DisplaySamples[^1];
        var firstPercent = IsTurkish ? $"%{first.RemainingPercent}" : $"{first.RemainingPercent}%";
        if (model.Delta is not int delta)
        {
            return Pick($"Başlangıç: {firstPercent}", $"Start: {firstPercent}");
        }

        var lastPercent = IsTurkish ? $"%{last.RemainingPercent}" : $"{last.RemainingPercent}%";
        var signedDelta = delta > 0 ? $"+{delta}" : delta.ToString(CultureInfo.InvariantCulture);
        return Pick(
            $"{firstPercent} → {lastPercent} · değişim {signedDelta}",
            $"{firstPercent} → {lastPercent} · change {signedDelta}");
    }

    public string Issue(ProviderIssue issue)
    {
        ArgumentNullException.ThrowIfNull(issue);

        return issue.Code switch
        {
            ProviderIssueCode.Refreshing => Refreshing,
            ProviderIssueCode.NoData => NoData,
            ProviderIssueCode.CodexUsageUnavailable =>
                Pick("Codex kullanım bilgisi alınamadı", "Could not retrieve Codex usage"),
            ProviderIssueCode.CodexLimitMissing =>
                Pick("Codex kullanım sınırı bulunamadı", "Codex usage limit not found"),
            ProviderIssueCode.CodexNotFound => CodexNotFoundTitle,
            ProviderIssueCode.CodexUntrustedExecutable => CodexUntrustedTitle,
            ProviderIssueCode.CodexUnsupportedInstallation => UnsupportedInstallationTitle,
            ProviderIssueCode.CodexTimedOut =>
                Pick("Codex yanıtı zaman aşımına uğradı", "Codex response timed out"),
            ProviderIssueCode.CodexEmptyResponse =>
                Pick("Codex kullanım yanıtı boş", "Codex returned an empty usage response"),
            ProviderIssueCode.CodexIncompatible =>
                Pick(
                    "Codex sürümü güvenli kullanım sorgusuyla uyumlu değil",
                    "This Codex version is incompatible with the safe usage query"),
            ProviderIssueCode.CodexCommandFailed =>
                Pick("Codex kullanım komutu başarısız oldu", "The Codex usage command failed"),
            ProviderIssueCode.CodexLaunchFailed =>
                Pick($"Codex başlatılamadı: {issue.Detail}", $"Could not start Codex: {issue.Detail}"),
            ProviderIssueCode.ClaudeNotFound => ClaudeNotFoundTitle,
            ProviderIssueCode.ClaudeUntrustedExecutable => ClaudeUntrustedTitle,
            ProviderIssueCode.ClaudeUnsupportedInstallation => UnsupportedInstallationTitle,
            ProviderIssueCode.ClaudeNotLoggedIn =>
                Pick("Claude Code'a giriş yapılmamış", "Claude Code is not signed in"),
            ProviderIssueCode.ClaudeUsageUnreadable =>
                Pick("Claude kullanım yüzdesi okunamadı", "Could not read Claude usage"),
            ProviderIssueCode.ClaudeUsageTimedOut =>
                Pick("Claude kullanım sorgusu zaman aşımına uğradı", "Claude usage query timed out"),
            ProviderIssueCode.ClaudeLaunchFailed =>
                Pick($"Claude Code başlatılamadı: {issue.Detail}", $"Could not start Claude Code: {issue.Detail}"),
            ProviderIssueCode.OutputTooLarge =>
                Pick($"{issue.Detail} çok fazla çıktı üretti", $"{issue.Detail} produced too much output"),
            _ => NoData
        };
    }
}
