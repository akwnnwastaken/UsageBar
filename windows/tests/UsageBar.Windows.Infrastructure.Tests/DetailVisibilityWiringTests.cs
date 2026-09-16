using System.Text.RegularExpressions;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Structural guards on the production detail-visibility wiring.
///
/// <b>These do not execute the controller or the views.</b> Both are internal
/// to the application project, which no test project references, so what the
/// rules themselves do is proven by the pure policy and the settings extensions
/// in <c>UsageBar.Windows.Core</c>. What is proven here is only that the
/// production surfaces still route through them: that the control forwards to
/// the one controller transition instead of writing the stored fields itself,
/// that the transition does not reach into the collection lifecycle, that the
/// panel's detailed body really is gated on the preference, and that nothing
/// deciding eligibility, tray status or rotation can see it.
///
/// Every assertion is scoped to a specific production file or member, so a
/// token appearing in a test, a comment or dead code cannot stand in for the
/// wiring.
/// </summary>
public sealed class DetailVisibilityWiringTests
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

    private static string Panel =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.App/Views/UsagePanelWindow.cs"));

    private static string CollectionPolicy =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.Core/Policies/ProviderCollectionPolicy.cs"));

    private static string SettingsModel =>
        File.ReadAllText(RepositoryFile("windows/src/UsageBar.Windows.Core/Settings/UsageBarSettings.cs"));

    /// <summary>
    /// One member's body. Some rules are about what a specific member must
    /// <b>not</b> touch, which a whole-file scan cannot express.
    /// </summary>
    private static string MemberBody(string source, string signature)
    {
        var start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Member not found: {signature}");

        var end = source.IndexOf("\n    public ", start + signature.Length, StringComparison.Ordinal);
        return end < 0 ? source[start..] : source[start..end];
    }

    /// <summary>
    /// One member's body, cut at the next member of <b>any</b> visibility or the
    /// next doc comment. <see cref="MemberBody"/> stops only at the next
    /// <c>public</c> member, which for a private helper would sweep in every
    /// private member after it; the runtime-decision rules below need each
    /// member on its own, so a token in a neighbour cannot mask or trip them.
    /// </summary>
    private static string RuntimeMemberBody(string source, string signature)
    {
        var start = source.IndexOf(signature, StringComparison.Ordinal);
        Assert.True(start >= 0, $"Member not found: {signature}");

        var from = start + signature.Length;
        var end = new[] { "\n    public ", "\n    private ", "\n    internal ", "\n    /// " }
            .Select(marker => source.IndexOf(marker, from, StringComparison.Ordinal))
            .Where(index => index >= 0)
            .DefaultIfEmpty(-1)
            .Min();
        return end < 0 ? source[start..] : source[start..end];
    }

    // MARK: - The control forwards to the one transition

    /// <summary>
    /// The settings control forwards intent to the controller. Writing the
    /// nullable field itself would put a second mutation path beside the
    /// canonical one.
    /// </summary>
    [Fact]
    public void SettingsTogglesDetailVisibilityThroughTheController()
    {
        Assert.Contains(
            "_controller.SetDetailsVisible(providerName, value)",
            SettingsWindow,
            StringComparison.Ordinal);
        Assert.DoesNotContain("CodexDetailsVisible", SettingsWindow, StringComparison.Ordinal);
        Assert.DoesNotContain("ClaudeDetailsVisible", SettingsWindow, StringComparison.Ordinal);
    }

    /// <summary>Each connected provider gets its own control, per provider name.</summary>
    [Fact]
    public void SettingsOffersTheControlForEveryConnectedProvider()
    {
        Assert.Contains("_controller.ConnectedProviderNames", SettingsWindow, StringComparison.Ordinal);
        Assert.Contains("text.ShowDetails", SettingsWindow, StringComparison.Ordinal);
        Assert.Contains(
            "_controller.AreDetailsVisible(providerName)",
            SettingsWindow,
            StringComparison.Ordinal);
    }

    /// <summary>
    /// The two controls are separate. "Show details" must never reach the
    /// collection transition, so the settings surface keeps exactly one call to
    /// each — the one belonging to its own control.
    /// </summary>
    [Fact]
    public void TheDetailControlNeverPausesCollection()
    {
        Assert.Single(Regex.Matches(SettingsWindow, @"SetCollectionEnabled\("));
        Assert.Single(Regex.Matches(SettingsWindow, @"SetDetailsVisible\("));
        Assert.Single(Regex.Matches(TrayMenu, @"SetCollectionEnabled\("));
        Assert.Single(Regex.Matches(TrayMenu, @"SetDetailsVisible\("));
    }

    /// <summary>
    /// The tray's quick toggle is the same transition, not a second path to the
    /// stored settings.
    /// </summary>
    [Fact]
    public void TheTrayQuickToggleUsesTheSameControllerTransition()
    {
        Assert.Contains(
            "_controller.SetDetailsVisible(providerName, !detailsVisible)",
            TrayMenu,
            StringComparison.Ordinal);
        Assert.Contains("text.ShowDetails", TrayMenu, StringComparison.Ordinal);
        Assert.DoesNotContain("CodexDetailsVisible", TrayMenu, StringComparison.Ordinal);
        Assert.DoesNotContain("ClaudeDetailsVisible", TrayMenu, StringComparison.Ordinal);
    }

    // MARK: - The transition stays a presentation change

    /// <summary>
    /// The canonical mutation stores the preference and nothing else. Every
    /// token below belongs to the collection lifecycle, the cache, the history
    /// or the user's selection — none of which a presentation choice may move.
    /// </summary>
    [Fact]
    public void ShowingOrHidingDetailsTouchesNothingButThePreference()
    {
        var body = MemberBody(Controller, "public void SetDetailsVisible(");

        Assert.DoesNotContain("SetCollectionEnabled", body, StringComparison.Ordinal);
        Assert.DoesNotContain("CollectionEnabled =", body, StringComparison.Ordinal);
        Assert.DoesNotContain("BumpGeneration", body, StringComparison.Ordinal);
        Assert.DoesNotContain("RefreshAsync", body, StringComparison.Ordinal);
        Assert.DoesNotContain("_pendingRefreshAfterEnable", body, StringComparison.Ordinal);
        Assert.DoesNotContain("_displayState", body, StringComparison.Ordinal);
        Assert.DoesNotContain("_usages", body, StringComparison.Ordinal);
        Assert.DoesNotContain("_history", body, StringComparison.Ordinal);
        Assert.DoesNotContain("SelectedProvider", body, StringComparison.Ordinal);
        Assert.DoesNotContain("AutoRotateProviders", body, StringComparison.Ordinal);
    }

    /// <summary>And the collection transition may not move the presentation.</summary>
    [Fact]
    public void PausingOrResumingLeavesDetailVisibilityAlone()
    {
        var body = MemberBody(Controller, "public void SetCollectionEnabled(");

        Assert.DoesNotContain("DetailsVisible", body, StringComparison.Ordinal);
    }

    /// <summary>
    /// Connecting re-enables collection deliberately. It must not do the same to
    /// the presentation choice: that is the user's, and it survives a
    /// disconnect and reconnect.
    /// </summary>
    [Fact]
    public void ConnectingAndDisconnectingPreserveDetailVisibility()
    {
        foreach (var member in new[]
                 {
                     "public void ConnectCodex(",
                     "public void ConnectClaude(",
                     "public void DisconnectProvider("
                 })
        {
            Assert.DoesNotContain("DetailsVisible", MemberBody(Controller, member), StringComparison.Ordinal);
        }
    }

    // MARK: - Eligibility, status and rotation cannot see it

    [Fact]
    public void TheCollectionPolicyHasNoNotionOfDetailVisibility()
    {
        Assert.DoesNotContain("Details", CollectionPolicy, StringComparison.Ordinal);
    }

    [Fact]
    public void EligibilityStatusAndRotationHaveNoNotionOfDetailVisibility()
    {
        foreach (var member in new[]
                 {
                     "public static IReadOnlyList<string> ConnectedProviderNames(",
                     "public static IReadOnlyList<string> EligibleProviderNames(",
                     "public static string? StatusProviderName(",
                     "public static bool RotationIsActive("
                 })
        {
            Assert.DoesNotContain("Details", MemberBody(SettingsModel, member), StringComparison.Ordinal);
        }
    }

    /// <summary>
    /// The tray presentation is built from the status provider and the cached
    /// readings. A provider whose card is collapsed is still both of those, so
    /// nothing about the tray may consult the preference.
    /// </summary>
    [Fact]
    public void TheTrayPresentationHasNoNotionOfDetailVisibility()
    {
        var body = MemberBody(Controller, "public TrayPresentation Presentation =>");

        Assert.DoesNotContain("Details", body, StringComparison.Ordinal);
    }

    // MARK: - The runtime decision sites cannot see it either

    /// <summary>
    /// The file-level rule above stops the policy from <i>having</i> a visibility
    /// parameter. This one stops the members that <i>call</i> the policy from
    /// folding the preference into an argument themselves — the shape
    /// <c>IsCollectionEnabled(p) &amp;&amp; AreDetailsVisible(p)</c> would pass
    /// every policy test and still stop a hidden provider from being read.
    /// Every member that decides what is launched, accepted, recorded, shown
    /// in the tray or rotated through is listed, each scanned on its own.
    /// </summary>
    [Theory]
    [InlineData("public async Task RefreshAsync(")]
    [InlineData("private void Accept(")]
    [InlineData("private ProviderCollectionAction ActionFor(")]
    [InlineData("private bool IsConnected(")]
    [InlineData("private bool IsCollectionEnabled(")]
    [InlineData("private void MaintainHistoryRetention(")]
    [InlineData("public void RotateProvider(")]
    [InlineData("public IReadOnlyList<string> ConnectedProviderNames =>")]
    [InlineData("public IReadOnlyList<string> EligibleProviderNames =>")]
    [InlineData("public string? StatusProviderName =>")]
    [InlineData("public IReadOnlyDictionary<string, ProviderUsage> DisplayUsages =>")]
    public void RuntimeDecisionMembersHaveNoNotionOfDetailVisibility(string signature)
    {
        var body = RuntimeMemberBody(Controller, signature);

        Assert.DoesNotContain("Details", body, StringComparison.Ordinal);
        Assert.DoesNotContain("ProviderCardPlan", body, StringComparison.Ordinal);
    }

    /// <summary>
    /// The three one-line decisions are pinned whole. A renamed preference
    /// would slip past a token scan; a changed expression cannot slip past
    /// this. The launch decision is the collection policy over live connected
    /// and collection state and nothing else; the status and eligible lists
    /// are the settings extensions' answers, unfiltered.
    /// </summary>
    [Fact]
    public void TheLaunchStatusAndEligibilityDecisionsAreExactlyThePolicyAnswers()
    {
        Assert.Contains(
            "private ProviderCollectionAction ActionFor(string providerName) =>\n"
            + "        ProviderCollectionPolicy.Action(IsConnected(providerName), IsCollectionEnabled(providerName));",
            Controller.Replace("\r\n", "\n", StringComparison.Ordinal),
            StringComparison.Ordinal);
        Assert.Contains(
            "public IReadOnlyList<string> EligibleProviderNames => Settings.EligibleProviderNames();",
            Controller,
            StringComparison.Ordinal);
        Assert.Contains(
            "public string? StatusProviderName => Settings.StatusProviderName(_rotatingProviderIndex);",
            Controller,
            StringComparison.Ordinal);
    }

    // MARK: - Each control and the setter reach their own provider

    /// <summary>
    /// The setter's Codex branch writes the Codex field and its Claude branch
    /// the Claude field. Both assignments being present is not enough — they
    /// could be swapped — so the branch structure is matched in order, and each
    /// field is written exactly once.
    /// </summary>
    [Fact]
    public void TheSetterWritesTheFieldOfTheProviderItWasGiven()
    {
        var body = RuntimeMemberBody(Controller, "public void SetDetailsVisible(");

        Assert.Matches(
            new Regex(
                @"if \(providerName == ProviderNames\.Codex\)\s*\{\s*"
                + @"settings\.CodexDetailsVisible = detailsVisible;\s*\}\s*"
                + @"else\s*\{\s*settings\.ClaudeDetailsVisible = detailsVisible;\s*\}"),
            body);
        Assert.Single(Regex.Matches(body, @"CodexDetailsVisible ="));
        Assert.Single(Regex.Matches(body, @"ClaudeDetailsVisible ="));
    }

    /// <summary>The collection setter is held to the same rule.</summary>
    [Fact]
    public void TheCollectionSetterWritesTheFieldOfTheProviderItWasGiven()
    {
        var body = RuntimeMemberBody(Controller, "public void SetCollectionEnabled(");

        Assert.Matches(
            new Regex(
                @"if \(providerName == ProviderNames\.Codex\)\s*\{\s*"
                + @"settings\.CodexCollectionEnabled = collectionEnabled;\s*\}\s*"
                + @"else\s*\{\s*settings\.ClaudeCollectionEnabled = collectionEnabled;\s*\}"),
            body);
    }

    /// <summary>
    /// The tray builds each provider's toggles inside that provider's own
    /// connected branch, and names the provider it is building for. Matched in
    /// order so the Codex branch cannot carry a Claude toggle or vice versa.
    /// </summary>
    [Fact]
    public void TheTrayTogglesNameTheProviderOfTheBranchTheyAreBuiltIn()
    {
        Assert.Matches(
            new Regex(
                @"if \(!_controller\.Settings\.CodexConnected\)[\s\S]*?"
                + @"CollectionToggle\(text, ProviderNames\.Codex\)[\s\S]*?"
                + @"DetailsToggle\(text, ProviderNames\.Codex\)[\s\S]*?"
                + @"if \(!_controller\.Settings\.ClaudeConnected\)[\s\S]*?"
                + @"CollectionToggle\(text, ProviderNames\.ClaudeCode\)[\s\S]*?"
                + @"DetailsToggle\(text, ProviderNames\.ClaudeCode\)"),
            TrayMenu);
        Assert.Single(Regex.Matches(TrayMenu, @"DetailsToggle\(text, ProviderNames\.Codex\)"));
        Assert.Single(Regex.Matches(TrayMenu, @"DetailsToggle\(text, ProviderNames\.ClaudeCode\)"));
    }

    // MARK: - The panel's body really is gated

    /// <summary>
    /// The card is built from the plan, and the plan is built from the stored
    /// preference the controller owns — the view never keeps its own copy.
    /// </summary>
    [Fact]
    public void ThePanelBuildsTheCardFromThePresentationPlan()
    {
        Assert.Contains("ProviderDetailPresentationPolicy.Card(", Panel, StringComparison.Ordinal);
        Assert.Contains("_controller.AreDetailsVisible(providerName)", Panel, StringComparison.Ordinal);
        Assert.DoesNotContain("CodexDetailsVisible", Panel, StringComparison.Ordinal);
        Assert.DoesNotContain("ClaudeDetailsVisible", Panel, StringComparison.Ordinal);
    }

    /// <summary>
    /// The frozen defect this guards against: hiding the chart while leaving the
    /// numeric rows. There is exactly one place usage windows are turned into
    /// rows, and its source list is the gated one, so no usage value, reset line,
    /// history summary or chart can survive a hidden body by another route.
    /// </summary>
    [Fact]
    public void EveryUsageRowComesFromTheGatedWindowList()
    {
        Assert.Contains(
            "var detailWindows = plan.ShowsDetailBody ? usage.Windows : Array.Empty<UsageWindow>();",
            Panel,
            StringComparison.Ordinal);
        Assert.Contains("detailWindows[position]", Panel, StringComparison.Ordinal);
        Assert.DoesNotContain("usage.Windows[", Panel, StringComparison.Ordinal);
        Assert.Single(Regex.Matches(Panel, @"WindowRow\(text,"));
    }

    /// <summary>
    /// A compact card is not a silent one: the paused marker and the active
    /// failure both come from the plan, which keeps them while the body is gone.
    /// </summary>
    [Fact]
    public void TheHeaderAndTheOperationalStateComeFromThePlanToo()
    {
        Assert.Contains("plan.ShowsPausedMarker", Panel, StringComparison.Ordinal);
        Assert.Contains("plan.ShowsOperationalIssue", Panel, StringComparison.Ordinal);
        Assert.Contains("text.Paused", Panel, StringComparison.Ordinal);
    }

    /// <summary>
    /// The panel consumes the state; it does not own it. Nothing here writes a
    /// setting, so closing and reopening the panel cannot change what is stored.
    /// </summary>
    [Fact]
    public void ThePanelNeverWritesThePreferenceItself()
    {
        Assert.DoesNotContain("SetDetailsVisible", Panel, StringComparison.Ordinal);
    }
}
