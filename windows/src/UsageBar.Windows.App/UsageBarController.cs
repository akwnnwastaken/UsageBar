using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using UsageBar.Windows.Infrastructure.Diagnostics;
using UsageBar.Windows.Infrastructure.Providers;
using UsageBar.Windows.Infrastructure.Startup;
using UsageBar.Windows.Infrastructure.Storage;

namespace UsageBar.Windows.App;

/// <summary>
/// The application's single source of truth: settings, provider readings,
/// history and the derived tray presentation. Every behavior rule comes from
/// UsageBar.Windows.Core; this type only sequences the work and raises a change
/// notification when the UI needs to redraw.
///
/// All mutation happens on the UI thread through the dispatcher supplied by the
/// caller, so the WPF and Windows Forms surfaces never see a torn state.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class UsageBarController : IDisposable
{
    private readonly UsageBarStorage _storage;
    private readonly CodexUsageReader _codexReader;
    private readonly IAutoStartService _autoStart;
    private readonly Action<Action> _post;

    private readonly Dictionary<string, ProviderUsage> _usages = new(StringComparer.Ordinal);
    private readonly UsageDisplayState _displayState = new();

    private IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> _history;
    private CancellationTokenSource? _refresh;
    private int _rotatingProviderIndex;
    private bool _disposed;

    public UsageBarController(
        UsageBarStorage storage,
        CodexUsageReader codexReader,
        IAutoStartService autoStart,
        Action<Action> post)
    {
        _storage = storage;
        _codexReader = codexReader;
        _autoStart = autoStart;
        _post = post;

        Settings = _storage.LoadSettings();
        _history = _storage.LoadHistory(DateTimeOffset.Now);
    }

    public event EventHandler? Changed;

    public UsageBarSettings Settings { get; private set; }

    public bool IsRefreshing { get; private set; }

    public DateTimeOffset? LastUpdated { get; private set; }

    public AppLanguage Language =>
        AppLanguages.Effective(Settings.Language, WindowsEnvironmentInfo.PreferredLanguages);

    public Localizer Text => new(Language);

    public UsageAlertPolicy AlertPolicy => new(
        Settings.UsageColorsEnabled ?? true,
        UsageBarSettingsSanitizer.ResolvePreset(Settings.UsageAlertPreset));

    public UsageRefreshInterval RefreshInterval => UsageRefreshIntervals.Resolved(Settings.RefreshInterval);

    public IReadOnlyList<string> ConnectedProviderNames => Settings.ConnectedProviderNames();

    public string? StatusProviderName => Settings.StatusProviderName(_rotatingProviderIndex);

    /// <summary>The smoothed readings shown in the tray and the panel.</summary>
    public IReadOnlyDictionary<string, ProviderUsage> DisplayUsages => _displayState.Apply(_usages);

    public IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> History => _history;

    public AutoStartState AutoStartState { get; private set; } = new(AutoStartStatus.Disabled);

    public TrayPresentation Presentation => TrayPresentationCalculator.Calculate(
        StatusProviderName,
        DisplayUsages,
        AlertPolicy,
        Text,
        IsRefreshing,
        Settings.ShowResetCountdown ?? false,
        DateTimeOffset.Now);

    public void Start()
    {
        AutoStartState = _autoStart.GetState();
        RaiseChanged();
        _ = RefreshAsync();
    }

    /// <summary>Advances the auto-rotation. Does not query any provider.</summary>
    public void RotateProvider()
    {
        if (!Settings.AutoRotateProviders || ConnectedProviderNames.Count <= 1)
        {
            return;
        }

        _rotatingProviderIndex = ProviderRotation.NextIndex(
            _rotatingProviderIndex,
            ConnectedProviderNames.Count);
        RaiseChanged();
    }

    /// <summary>Refreshes only when the shown data is older than 30 seconds.</summary>
    public void RefreshIfStale()
    {
        if (UsageRefreshPolicy.ShouldRefreshOnPanelOpen(LastUpdated, DateTimeOffset.Now))
        {
            _ = RefreshAsync();
        }
    }

    public async Task RefreshAsync()
    {
        if (IsRefreshing || _disposed)
        {
            return;
        }

        IsRefreshing = true;
        RaiseChanged();

        using var cancellation = new CancellationTokenSource();
        Interlocked.Exchange(ref _refresh, cancellation);

        try
        {
            if (Settings.CodexConnected)
            {
                var fetched = await _codexReader
                    .ReadAsync(Settings.CodexExecutablePath, cancellation.Token)
                    .ConfigureAwait(false);

                _post(() => Accept(fetched));
            }
            else
            {
                _post(() => _usages.Remove(ProviderNames.Codex));
            }

            // Claude is not implemented on Windows yet. Nothing is fabricated:
            // the provider simply never appears in the readings.
            _post(() => _usages.Remove(ProviderNames.ClaudeCode));
        }
        catch (OperationCanceledException)
        {
        }
        finally
        {
            // The refresh is no longer the current one; the using block owns it.
            Interlocked.CompareExchange(ref _refresh, null, cancellation);
            _post(CompleteRefresh);
        }
    }

    private void Accept(ProviderUsage fetched)
    {
        var now = DateTimeOffset.Now;
        _usages.TryGetValue(fetched.Name, out var previous);
        _usages[fetched.Name] = ProviderUsageTransition.Accept(previous, fetched, now);
    }

    private void CompleteRefresh()
    {
        var now = DateTimeOffset.Now;
        IsRefreshing = false;
        LastUpdated = now;

        // The filter advances once per completed refresh; the raw readings are
        // what history records.
        _displayState.Advance(_usages);

        if (Settings.UsageHistoryEnabled ?? true)
        {
            _history = UsageHistoryRecorder.Record(_history, _usages, ConnectedProviderNames, now);
            _storage.SaveHistory(_history, now);
        }

        RaiseChanged();
    }

    public void UpdateSettings(Action<UsageBarSettings> mutate)
    {
        ArgumentNullException.ThrowIfNull(mutate);

        var updated = Settings.Clone();
        mutate(updated);
        Settings = UsageBarSettingsSanitizer.Sanitize(updated);
        _storage.SaveSettings(Settings);
        RaiseChanged();
    }

    public void ConnectCodex()
    {
        UpdateSettings(settings =>
        {
            var wasEmpty = settings.ConnectedProviderNames().Count == 0;
            settings.CodexConnected = true;
            if (wasEmpty)
            {
                settings.SelectedProvider = ProviderNames.Codex;
            }
        });

        _ = RefreshAsync();
    }

    public void DisconnectProvider(string providerName)
    {
        var previousSelection = Settings.SelectedProvider;

        UpdateSettings(settings =>
        {
            if (providerName == ProviderNames.Codex)
            {
                settings.CodexConnected = false;
            }
            else
            {
                settings.ClaudeConnected = false;
            }

            var remaining = settings.ConnectedProviderNames();
            settings.SelectedProvider = ProviderConnectionTransition.Selection(
                providerName,
                remaining,
                previousSelection);

            if (!ProviderConnectionTransition.AutoRotateStaysEnabled(
                    remaining.Count,
                    settings.AutoRotateProviders))
            {
                settings.AutoRotateProviders = false;
            }
        });

        // Live readings and display state go; recorded history deliberately
        // stays until the user clears it explicitly.
        _usages.Remove(providerName);
        _displayState.Forget(providerName);
        RaiseChanged();
    }

    public void ClearHistory()
    {
        _history = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);
        _storage.ClearHistory();
        RaiseChanged();
    }

    public AutoStartState ToggleAutoStart()
    {
        AutoStartState = AutoStartState.IsOn ? _autoStart.Disable() : _autoStart.Enable();
        RaiseChanged();
        return AutoStartState;
    }

    /// <summary>
    /// The privacy-safe diagnostic summary. Everything it contains is a fixed
    /// code, a count or a version — never provider output, a path or a token.
    /// </summary>
    public string BuildDiagnostics() => DiagnosticsReportBuilder.Build(new DiagnosticsInput(
        WindowsEnvironmentInfo.ApplicationVersion,
        WindowsEnvironmentInfo.BuildId,
        WindowsEnvironmentInfo.Version,
        WindowsEnvironmentInfo.OsArchitecture,
        WindowsEnvironmentInfo.ProcessArchitecture,
        Language.StorageValue(),
        LastUpdated,
        Settings.UsageHistoryEnabled ?? true,
        _history.Count,
        _history.Values.Sum(samples => samples.Count),
        Settings.TrayGuidanceVersionShown,
        AutoStartState.IsOn,
        new[]
        {
            ProviderDiagnosticsFor(ProviderNames.Codex, Settings.CodexConnected),
            ProviderDiagnosticsFor(ProviderNames.ClaudeCode, Settings.ClaudeConnected)
        }));

    private ProviderDiagnostics ProviderDiagnosticsFor(string providerName, bool connected)
    {
        _usages.TryGetValue(providerName, out var usage);

        var dataState = usage switch
        {
            { IsStale: true } => ProviderDataState.Stale,
            { Error: not null } => ProviderDataState.Error,
            { Windows.Count: > 0 } => ProviderDataState.Fresh,
            _ => ProviderDataState.NoData
        };

        var executableState = providerName == ProviderNames.Codex
            ? _codexReader.LastExecutableState
            : ProviderExecutableState.Missing;
        var adapterKind = providerName == ProviderNames.Codex
            ? _codexReader.LastAdapterKind
            : ProviderAdapterKind.None;

        return new ProviderDiagnostics(
            providerName,
            connected,
            executableState,
            adapterKind,
            dataState,
            usage?.Windows.Select(window => window.Kind.HistoryKey).ToList() ?? new List<string>(),
            usage?.Error?.DiagnosticCode ?? DiagnosticsSanitizer.None);
    }

    private void RaiseChanged() => Changed?.Invoke(this, EventArgs.Empty);

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;

        // Cancel an in-flight refresh; the running task owns disposal of its
        // own token source.
        var refresh = Interlocked.Exchange(ref _refresh, null);
        try
        {
            refresh?.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // The refresh finished between the exchange and the cancel.
        }
    }
}
