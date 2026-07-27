using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Core.History;
using UsageBar.Windows.Core.Localization;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using UsageBar.Windows.Infrastructure.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using UsageBar.Windows.Infrastructure.Providers;
using UsageBar.Windows.Infrastructure.Startup;
using UsageBar.Windows.Infrastructure.Storage;
using UsageBar.Windows.Infrastructure.Wsl;

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
    private readonly Func<UsageBarSettings, IClaudeUsageReader> _claudeReaderFactory;

    /// <summary>
    /// Rebuilt whenever the Claude installation settings change, so an adapter
    /// never keeps a cached resolution from a mode the user has since left.
    /// </summary>
    private IClaudeUsageReader? _claudeReader;
    private string? _claudeReaderKey;

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
        Action<Action> post,
        Func<UsageBarSettings, IClaudeUsageReader>? claudeReaderFactory = null)
    {
        _storage = storage;
        _codexReader = codexReader;
        _autoStart = autoStart;
        _post = post;
        _claudeReaderFactory = claudeReaderFactory ?? DefaultClaudeReader;

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

    /// <summary>
    /// WSL distribution names offered in settings. Enumerated once, lazily, so
    /// opening settings does not start every distribution on every visit. Only
    /// names — never a path inside a distribution.
    /// </summary>
    public IReadOnlyList<string> WslDistributions { get; private set; } = Array.Empty<string>();

    private bool _wslDistributionsLoaded;

    /// <summary>Enumerates WSL distributions once, on demand.</summary>
    public async Task LoadWslDistributionsAsync()
    {
        if (_wslDistributionsLoaded || _disposed)
        {
            return;
        }

        _wslDistributionsLoaded = true;

        try
        {
            var runner = new WslCommandRunner();
            if (!runner.IsInstalled)
            {
                return;
            }

            var distributions = await runner
                .ListDistributionsAsync(CancellationToken.None)
                .ConfigureAwait(false);

            _post(() =>
            {
                WslDistributions = distributions;
                RaiseChanged();
            });
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException)
        {
            // WSL being unusable is a normal state, not an error to surface.
        }
    }

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

            if (Settings.ClaudeConnected)
            {
                var claude = await ClaudeReader()
                    .ReadAsync(cancellation.Token)
                    .ConfigureAwait(false);

                _post(() => Accept(claude));
            }
            else
            {
                _post(() => _usages.Remove(ProviderNames.ClaudeCode));
            }
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

    /// <summary>
    /// The reader for the current Claude settings, rebuilt only when those
    /// settings change so adapter caches survive an ordinary refresh.
    /// </summary>
    private IClaudeUsageReader ClaudeReader()
    {
        var key = string.Join(
            '|',
            Settings.ClaudeAdapterMode ?? string.Empty,
            Settings.ClaudeWslDistribution ?? string.Empty,
            Settings.ClaudeExecutablePath ?? string.Empty);

        if (_claudeReader is null || _claudeReaderKey != key)
        {
            _claudeReader = _claudeReaderFactory(Settings);
            _claudeReaderKey = key;
        }

        return _claudeReader;
    }

    private static IClaudeUsageReader DefaultClaudeReader(UsageBarSettings settings) =>
        new ClaudeUsageReader(
            ClaudeAdapterModes.Resolved(settings.ClaudeAdapterMode),
            settings.ClaudeExecutablePath,
            settings.ClaudeWslDistribution);

    public void ConnectClaude()
    {
        UpdateSettings(settings =>
        {
            var wasEmpty = settings.ConnectedProviderNames().Count == 0;
            settings.ClaudeConnected = true;
            if (wasEmpty)
            {
                settings.SelectedProvider = ProviderNames.ClaudeCode;
            }
        });

        _ = RefreshAsync();
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
        },
        // Launch-context facts. Provider discovery was seen to depend on how
        // UsageBar was started, so a report says which context it came from and
        // whether the folders discovery builds on resolved at all.
        FolderState(WindowsKnownFolder.LocalApplicationData),
        FolderState(WindowsKnownFolder.UserProfile),
        _codexReader.OfficialCandidateState(),
        ProcessParentInspector.Classify()));

    private static FolderResolutionState FolderState(WindowsKnownFolder folder) =>
        new WindowsKnownFolderResolver().Resolve(folder).Count > 0
            ? FolderResolutionState.Available
            : FolderResolutionState.Empty;

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
            : _claudeReader?.LastExecutableState ?? ProviderExecutableState.Missing;
        var adapterKind = providerName == ProviderNames.Codex
            ? _codexReader.LastAdapterKind
            : _claudeReader?.LastAdapterKind ?? ProviderAdapterKind.None;

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
