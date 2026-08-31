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

    /// <summary>
    /// One counter per provider, bumped whenever its connection or collection
    /// state changes. A read carries the value it launched with, so a result
    /// that outlives the state it was started under can be told apart from a
    /// current one — which current eligibility alone cannot do.
    /// </summary>
    private readonly Dictionary<string, int> _generations = new(StringComparer.Ordinal);

    private PendingCollectionRefresh _pendingRefreshAfterEnable;

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

    /// <summary>What the user manages; a paused provider stays in this list.</summary>
    public IReadOnlyList<string> ConnectedProviderNames => Settings.ConnectedProviderNames();

    /// <summary>What is actually being collected.</summary>
    public IReadOnlyList<string> EligibleProviderNames => Settings.EligibleProviderNames();

    /// <summary>Null when nothing is being collected, including when everything is paused.</summary>
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
        ConnectedProviderNames.Count > 0,
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

    /// <summary>
    /// Advances the auto-rotation. Does not query any provider. Rotation runs
    /// over the eligible providers, so pausing one of two leaves the preference
    /// intact and simply stops rotating until it resumes.
    /// </summary>
    public void RotateProvider()
    {
        var eligible = EligibleProviderNames;
        if (!Settings.RotationIsActive())
        {
            return;
        }

        _rotatingProviderIndex = ProviderRotation.NextIndex(
            _rotatingProviderIndex,
            eligible.Count);
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

        // Decided before any refreshing state is set: a cycle that reads nobody
        // must not look like a refresh at all — no spinner, no timestamp, no
        // completion. Retention still runs, so pausing everything does not stop
        // the 24-hour clock.
        if (!ProviderCollectionPolicy.CollectsUsage(new[] { ActionFor(ProviderNames.Codex), ActionFor(ProviderNames.ClaudeCode) }))
        {
            MaintainHistoryRetention(DateTimeOffset.Now);
            return;
        }

        IsRefreshing = true;
        RaiseChanged();

        // The measurements this cycle accepts. Every write happens inside a
        // posted action, and `_post` is a synchronous dispatcher invoke, so all
        // of them have run by the time the completion below is posted.
        var acceptedMeasurements = new Dictionary<string, ProviderUsage>(StringComparer.Ordinal);

        using var cancellation = new CancellationTokenSource();
        Interlocked.Exchange(ref _refresh, cancellation);

        try
        {
            var codexAction = ActionFor(ProviderNames.Codex);
            if (codexAction == ProviderCollectionAction.Collect)
            {
                var launchGeneration = GenerationOf(ProviderNames.Codex);
                var fetched = await _codexReader
                    .ReadAsync(Settings.CodexExecutablePath, cancellation.Token)
                    .ConfigureAwait(false);

                _post(() => Accept(ProviderNames.Codex, launchGeneration, fetched, acceptedMeasurements));
            }
            else if (codexAction == ProviderCollectionAction.DropCache)
            {
                _post(() => _usages.Remove(ProviderNames.Codex));
            }

            // Read from the state as it is now, not as it was at method entry:
            // the Codex read above may have taken long enough for the user to
            // pause or disconnect Claude in the meantime.
            var claudeAction = ActionFor(ProviderNames.ClaudeCode);
            if (claudeAction == ProviderCollectionAction.Collect)
            {
                var launchGeneration = GenerationOf(ProviderNames.ClaudeCode);
                var claude = await ClaudeReader()
                    .ReadAsync(cancellation.Token)
                    .ConfigureAwait(false);

                _post(() => Accept(ProviderNames.ClaudeCode, launchGeneration, claude, acceptedMeasurements));
            }
            else if (claudeAction == ProviderCollectionAction.DropCache)
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
            _post(() => CompleteRefresh(acceptedMeasurements));
        }
    }

    /// <summary>
    /// Applies a finished read — unless the provider moved on while it ran.
    ///
    /// A read that was launched, then had its provider paused, disconnected or
    /// reconnected, is discarded whole: no cached reading, no freshness change,
    /// no measurement for the display filter or the history.
    /// </summary>
    private void Accept(
        string providerName,
        int launchGeneration,
        ProviderUsage fetched,
        IDictionary<string, ProviderUsage> acceptedMeasurements)
    {
        // The launch decides whose state is checked. A result naming a
        // different provider is a broken contract, not something to validate
        // against whatever it claims to be.
        if (!string.Equals(fetched.Name, providerName, StringComparison.Ordinal))
        {
            return;
        }

        if (!ProviderCollectionPolicy.ShouldAccept(
                IsConnected(providerName),
                IsCollectionEnabled(providerName),
                launchGeneration,
                GenerationOf(providerName)))
        {
            return;
        }

        var now = DateTimeOffset.Now;
        _usages.TryGetValue(providerName, out var previous);
        var accepted = ProviderUsageTransition.Accept(previous, fetched, now);
        _usages[providerName] = accepted;

        if (accepted.Error is null && accepted.Windows.Count > 0)
        {
            acceptedMeasurements[providerName] = accepted;
        }
    }

    private void CompleteRefresh(IReadOnlyDictionary<string, ProviderUsage> acceptedMeasurements)
    {
        var now = DateTimeOffset.Now;
        IsRefreshing = false;

        // Consumed before the follow-up starts, so the follow-up cannot re-arm
        // itself and loop.
        var followUpRequested = _pendingRefreshAfterEnable.Consume();

        LastUpdated = now;

        // The filter advances once per completed refresh, from the measurements
        // that refresh accepted; the raw readings are what history records.
        _displayState.Advance(acceptedMeasurements);

        if (Settings.UsageHistoryEnabled ?? true)
        {
            _history = UsageHistoryRecorder.Record(_history, acceptedMeasurements, now);
            _storage.SaveHistory(_history, now);
        }

        RaiseChanged();

        if (followUpRequested)
        {
            _ = RefreshAsync();
        }
    }

    /// <summary>
    /// Retention for a tick that collected nothing: everything paused, or the
    /// history setting just switched back on. It prunes what has aged out and
    /// creates no sample, because nothing was measured.
    /// </summary>
    private void MaintainHistoryRetention(DateTimeOffset now)
    {
        if (!(Settings.UsageHistoryEnabled ?? true))
        {
            return;
        }

        var retained = UsageHistoryModel.Sanitized(_history, now);
        if (SameHistory(_history, retained))
        {
            return;
        }

        _history = retained;
        _storage.SaveHistory(_history, now);
        RaiseChanged();
    }

    private static bool SameHistory(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> left,
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> right) =>
        left.Count == right.Count &&
        left.All(entry =>
            right.TryGetValue(entry.Key, out var samples) &&
            entry.Value.SequenceEqual(samples));

    private bool IsConnected(string providerName) =>
        providerName == ProviderNames.Codex ? Settings.CodexConnected : Settings.ClaudeConnected;

    private bool IsCollectionEnabled(string providerName) =>
        (providerName == ProviderNames.Codex
            ? Settings.CodexCollectionEnabled
            : Settings.ClaudeCollectionEnabled) ?? true;

    private ProviderCollectionAction ActionFor(string providerName) =>
        ProviderCollectionPolicy.Action(IsConnected(providerName), IsCollectionEnabled(providerName));

    private int GenerationOf(string providerName) =>
        _generations.TryGetValue(providerName, out var generation) ? generation : 0;

    /// <summary>
    /// Invalidates every read of this provider that is already in flight.
    /// Always called as part of the same synchronous state change, so a read
    /// launched afterwards captures the new value and one launched before keeps
    /// the old.
    /// </summary>
    private void BumpGeneration(string providerName) =>
        _generations[providerName] = GenerationOf(providerName) + 1;

    /// <summary>
    /// The one runtime path that pauses or resumes collection for a provider.
    /// The connection, the cached readings, the displayed values and the
    /// recorded history all survive a pause; only the half-proven rise does not.
    ///
    /// No control calls this yet — wiring the settings surface is a later step.
    /// </summary>
    public void SetCollectionEnabled(string providerName, bool collectionEnabled)
    {
        if (IsCollectionEnabled(providerName) == collectionEnabled)
        {
            return;
        }

        UpdateSettings(settings =>
        {
            if (providerName == ProviderNames.Codex)
            {
                settings.CodexCollectionEnabled = collectionEnabled;
            }
            else
            {
                settings.ClaudeCollectionEnabled = collectionEnabled;
            }
        });
        BumpGeneration(providerName);

        if (!collectionEnabled)
        {
            _displayState.ClearPendingRise(providerName);
            return;
        }

        if (_pendingRefreshAfterEnable.RequestCollection(IsRefreshing))
        {
            _ = RefreshAsync();
        }
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
            // Connecting always resumes collection: a pause stored before the
            // provider was disconnected must never come back with it.
            settings.ClaudeCollectionEnabled = true;
            if (wasEmpty)
            {
                settings.SelectedProvider = ProviderNames.ClaudeCode;
            }
        });
        BumpGeneration(ProviderNames.ClaudeCode);

        _ = RefreshAsync();
    }

    public void ConnectCodex()
    {
        UpdateSettings(settings =>
        {
            var wasEmpty = settings.ConnectedProviderNames().Count == 0;
            settings.CodexConnected = true;
            // As for Claude: reconnecting resumes collection unconditionally.
            settings.CodexCollectionEnabled = true;
            if (wasEmpty)
            {
                settings.SelectedProvider = ProviderNames.Codex;
            }
        });
        BumpGeneration(ProviderNames.Codex);

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

        // Invalidates any read still in flight, so a result that arrives after
        // this point cannot bring the disconnected provider back.
        BumpGeneration(providerName);

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
    public string BuildDiagnostics()
    {
        // Every folder fact below comes from this one trace, captured during the
        // Codex lookup that produced the executable state being reported.
        // Resolving again here would describe the moment the summary was copied
        // rather than the moment discovery ran — and the whole open question is
        // whether those two moments resolve the same way.
        var trace = _codexReader.LastDiscoveryTrace;

        return DiagnosticsReportBuilder.Build(new DiagnosticsInput(
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
                ProviderDiagnosticsFor(ProviderNames.Codex),
                ProviderDiagnosticsFor(ProviderNames.ClaudeCode)
            },
            // Launch-context facts. Provider discovery was seen to depend on how
            // UsageBar was started, so a report says which context it came from
            // and how the folders discovery builds on resolved.
            trace.LocalAppDataState,
            trace.UserProfileState,
            trace.OfficialCodexCandidateState,
            ProcessParentInspector.Classify(),
            trace));
    }

    private ProviderDiagnostics ProviderDiagnosticsFor(string providerName)
    {
        var connected = IsConnected(providerName);
        // Derived from the collection policy, never from whether a reading
        // happens to be cached.
        var collecting = ProviderCollectionPolicy.IsEligible(
            connected,
            IsCollectionEnabled(providerName));

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
            collecting,
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
