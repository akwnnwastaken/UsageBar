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
    /// well is disconnect's job and must stay that way.
    /// </summary>
    [Fact]
    public void PausingClearsThePendingRiseWithoutForgettingTheProvider()
    {
        Assert.Contains("_displayState.ClearPendingRise(providerName)", Controller, StringComparison.Ordinal);
        Assert.Contains("_displayState.Forget(providerName)", Controller, StringComparison.Ordinal);
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
}
