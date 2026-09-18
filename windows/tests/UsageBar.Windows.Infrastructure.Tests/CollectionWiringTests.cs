using System.Text.RegularExpressions;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Structural guards on the production controller.
///
/// <b>These do not execute <c>UsageBarController</c>.</b> It is internal to the
/// application project, which no test project references, so what the rules
/// themselves do is proven by the pure policies in
/// <c>UsageBar.Windows.Core</c>. What is proven here is only that the
/// controller still routes through those policies, and that the two whole-cache
/// shapes the display filter and the history recorder used to be fed from are
/// gone. They assert the shape of the wiring, never its layout.
/// </summary>
public sealed class CollectionWiringTests
{
    private static string RepositoryFile(string relativePath)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, relativePath.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Repository file not found: {relativePath}");
    }

    private static string Controller =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/UsageBarController.cs"));

    private static string SettingsWindow =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/Views/SettingsWindow.cs"));

    private static string TrayMenu =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/Tray/TrayIconController.cs"));

    private static string TrayApplication =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/TrayApplication.cs"));

    private static string Panel =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/Views/UsagePanelWindow.cs"));

    private static string DetailPresentationPolicy =>
        File.ReadAllText(RepositoryFile(
            "windows/src/UsageBar.Windows.Core/Policies/ProviderDetailPresentationPolicy.cs"));

    [Fact]
    public void EveryProviderLaunchDecisionGoesThroughTheCollectionPolicy()
    {
        Assert.Contains("ProviderCollectionPolicy.Action(", Controller, StringComparison.Ordinal);
        Assert.Contains("ProviderCollectionPolicy.CollectsUsage(", Controller, StringComparison.Ordinal);
    }

    [Fact]
    public void AcceptanceGoesThroughTheGenerationGate()
    {
        Assert.Contains("ProviderCollectionPolicy.ShouldAccept(", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// One reader call per provider. A third would be a path that never
    /// consulted the gate above.
    /// </summary>
    [Fact]
    public void ThereIsExactlyOneReadSitePerProvider()
    {
        Assert.Equal(2, Regex.Matches(Controller, @"\.ReadAsync\(").Count);
    }

    /// <summary>
    /// The frozen defect: advancing the display filter from the whole usage
    /// cache lets one provider's refresh confirm a rise nobody measured again.
    /// </summary>
    [Fact]
    public void TheDisplayFilterIsNoLongerAdvancedFromTheWholeCache()
    {
        Assert.DoesNotContain("_displayState.Advance(_usages)", Controller, StringComparison.Ordinal);
        Assert.Contains("_displayState.Advance(acceptedMeasurements)", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// The same defect for history: samples may only come from measurements the
    /// cycle accepted, never from whatever sits in the cache for the connected
    /// providers.
    /// </summary>
    [Fact]
    public void HistoryIsNoLongerRecordedFromTheWholeCache()
    {
        Assert.DoesNotContain("Record(_history, _usages", Controller, StringComparison.Ordinal);
        Assert.DoesNotContain("ConnectedProviderNames, now", Controller, StringComparison.Ordinal);
        Assert.Contains("Record(_history, acceptedMeasurements, now)", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// Pausing clears the half-proven rise; forgetting the displayed value as
    /// well is disconnect's job and must stay that way. Both calls exist
    /// legitimately somewhere in the controller, so a whole-file scan cannot
    /// tell a pause that also forgets from one that does not: each call is
    /// pinned to the member it belongs to.
    /// </summary>
    [Fact]
    public void PausingClearsThePendingRiseWithoutForgettingTheProvider()
    {
        var pauseBody = ControllerMember("public void SetCollectionEnabled(");
        var disconnectBody = ControllerMember("public void DisconnectProvider(");

        Assert.Contains("_displayState.ClearPendingRise(providerName)", pauseBody, StringComparison.Ordinal);
        Assert.DoesNotContain("_displayState.Forget(providerName)", pauseBody, StringComparison.Ordinal);
        Assert.Contains("_displayState.Forget(providerName)", disconnectBody, StringComparison.Ordinal);
    }

    /// <summary>
    /// Connecting writes collection state explicitly, so a pause stored before
    /// a disconnect cannot come back with the provider.
    /// </summary>
    [Fact]
    public void ConnectingReEnablesCollectionForBothProviders()
    {
        Assert.Contains("settings.CodexCollectionEnabled = true;", Controller, StringComparison.Ordinal);
        Assert.Contains("settings.ClaudeCollectionEnabled = true;", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// The body of one controller member. Some rules are about what a specific
    /// transition must <b>not</b> touch, which a whole-file scan cannot express.
    /// </summary>
    private static string ControllerMember(string signature)
    {
        var source = Controller;
        var start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Controller member not found: {signature}");

        var end = source.IndexOf("\n    public ", start + signature.Length, StringComparison.Ordinal);
        return end < 0 ? source[start..] : source[start..end];
    }

    /// <summary>
    /// Pausing is not a selection change and not a rotation change: both
    /// preferences must survive it untouched, so resuming restores what the
    /// user chose. Disconnect keeps its own separate repair rules.
    /// </summary>
    [Fact]
    public void PausingLeavesTheStoredSelectionAndRotationPreferenceAlone()
    {
        var body = ControllerMember("public void SetCollectionEnabled(");

        Assert.DoesNotContain("SelectedProvider", body, StringComparison.Ordinal);
        Assert.DoesNotContain("AutoRotateProviders", body, StringComparison.Ordinal);
    }

    /// <summary>
    /// The settings control forwards intent to the controller. Writing the
    /// nullable field itself would skip the generation bump, the pending-rise
    /// clearing and the coalesced refresh that make a pause safe.
    /// </summary>
    [Fact]
    public void SettingsTogglesCollectionThroughTheController()
    {
        Assert.Contains(
            "_controller.SetCollectionEnabled(providerName, value)",
            SettingsWindow,
            StringComparison.Ordinal);
        Assert.DoesNotContain("CodexCollectionEnabled", SettingsWindow, StringComparison.Ordinal);
        Assert.DoesNotContain("ClaudeCollectionEnabled", SettingsWindow, StringComparison.Ordinal);
    }

    /// <summary>Each connected provider gets its own control, per provider name.</summary>
    [Fact]
    public void SettingsOffersTheControlForEveryConnectedProvider()
    {
        Assert.Contains("_controller.ConnectedProviderNames", SettingsWindow, StringComparison.Ordinal);
        Assert.Contains("text.CollectUsage", SettingsWindow, StringComparison.Ordinal);
    }

    /// <summary>
    /// The tray's quick toggle is the same transition, not a second path to the
    /// stored settings.
    /// </summary>
    [Fact]
    public void TheTrayQuickToggleUsesTheSameControllerTransition()
    {
        Assert.Contains(
            "_controller.SetCollectionEnabled(providerName, !isCollecting)",
            TrayMenu,
            StringComparison.Ordinal);
        Assert.DoesNotContain("CodexCollectionEnabled", TrayMenu, StringComparison.Ordinal);
        Assert.DoesNotContain("ClaudeCollectionEnabled", TrayMenu, StringComparison.Ordinal);
    }

    /// <summary>
    /// Rotation follows the providers actually being collected. Counting
    /// connected ones would keep rotating to a provider with no live value.
    /// </summary>
    [Fact]
    public void TheRotationTimerFollowsEligibleProviders()
    {
        Assert.Contains("Settings.RotationIsActive()", TrayApplication, StringComparison.Ordinal);
        Assert.DoesNotContain(
            "ConnectedProviderNames.Count > 1",
            TrayApplication,
            StringComparison.Ordinal);
    }

    /// <summary>
    /// The tray presentation is told whether anything is connected, so a null
    /// status provider can mean "everything paused" instead of "connect one".
    /// </summary>
    [Fact]
    public void TrayPresentationCanTellPausedApartFromNothingConnected()
    {
        Assert.Contains("ConnectedProviderNames.Count > 0", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// Collection state is reported from the policy, never inferred from
    /// whether a reading happens to be cached.
    /// </summary>
    [Fact]
    public void DiagnosticsReportCollectionStateSeparately()
    {
        Assert.Contains("ProviderCollectionPolicy.IsEligible(", Controller, StringComparison.Ordinal);
        Assert.Contains("collecting,", Controller, StringComparison.Ordinal);
    }

    /// <summary>
    /// The body of one controller member, cut at the next member of <b>any</b>
    /// visibility. <see cref="ControllerMember"/> stops only at the next
    /// <c>public</c> member, which for a private helper would sweep in every
    /// private neighbour after it.
    /// </summary>
    private static string ControllerPrivateMember(string signature)
    {
        var source = Controller;
        var start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Controller member not found: {signature}");

        var from = start + signature.Length;
        var end = new[] { "\n    public ", "\n    private ", "\n    internal ", "\n    /// " }
            .Select(marker => source.IndexOf(marker, from, StringComparison.Ordinal))
            .Where(index => index >= 0)
            .DefaultIfEmpty(-1)
            .Min();
        return end < 0 ? source[start..] : source[start..end];
    }

    /// <summary>
    /// <c>ProviderDiagnostics</c> is a positional record whose <c>Connected</c>
    /// and <c>Collecting</c> are adjacent <c>bool</c>s, so swapping the two
    /// arguments compiles and only shows for a paused provider — connected but
    /// not collecting — which would then read as disconnected yet collecting.
    /// This pins the order at the one production construction. It is
    /// whitespace-tolerant but not order-tolerant.
    /// </summary>
    [Fact]
    public void DiagnosticsPassConnectedBeforeCollecting()
    {
        var body = ControllerPrivateMember("private ProviderDiagnostics ProviderDiagnosticsFor(");

        Assert.Single(Regex.Matches(body, @"new ProviderDiagnostics\("));
        Assert.Matches(
            new Regex(@"new ProviderDiagnostics\(\s*providerName,\s*connected,\s*collecting,"),
            body);
    }

    /// <summary>
    /// A finished read is applied to the provider it was launched for, never to
    /// the provider its result claims to be. The identity check must be the
    /// first thing <c>Accept</c> does: matched as one ordered pattern so that
    /// deleting the mismatch rejection, or moving it below the policy gate and
    /// the cache writes that follow it, fails here even though
    /// <c>fetched.Name</c> and <c>ShouldAccept</c> both still appear somewhere.
    /// </summary>
    [Fact]
    public void AcceptanceRejectsAResultNamingAnotherProvider()
    {
        var body = ControllerPrivateMember("private void Accept(");

        Assert.Matches(
            new Regex(
                @"if \(!string\.Equals\(\s*fetched\.Name,\s*providerName,\s*StringComparison\.Ordinal\)\)"
                + @"\s*\{\s*return;\s*\}"
                + @"[\s\S]*?ProviderCollectionPolicy\.ShouldAccept\("),
            body);
    }

    /// <summary>
    /// The panel keeps a paused provider visible and does not blame it for an
    /// error UsageBar is no longer trying to produce.
    ///
    /// The panel now asks <c>ProviderDetailPresentationPolicy</c> for the whole
    /// card, and that policy is where <c>RendersActiveError</c> is applied — so
    /// the rule is still the collection policy's, reached one step further out.
    /// The second assertion below pins that step, so the decision cannot quietly
    /// become the panel's own again.
    /// </summary>
    [Fact]
    public void ThePanelMarksAPausedProviderInsteadOfShowingItsRetainedError()
    {
        Assert.Contains("text.Paused", Panel, StringComparison.Ordinal);
        Assert.Contains("ProviderDetailPresentationPolicy.Card(", Panel, StringComparison.Ordinal);
        Assert.Contains("plan.ShowsOperationalIssue", Panel, StringComparison.Ordinal);
        Assert.Contains(
            "ProviderCollectionPolicy.RendersActiveError(",
            DetailPresentationPolicy,
            StringComparison.Ordinal);
        Assert.Contains("EligibleProviderNames.Count > 0", Panel, StringComparison.Ordinal);
    }
}
