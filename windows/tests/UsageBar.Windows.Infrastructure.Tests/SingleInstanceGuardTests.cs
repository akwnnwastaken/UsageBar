using System.Runtime.Versioning;
using UsageBar.Windows.Infrastructure.Startup;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// One UsageBar per signed-in user. A second launch — including the one an
/// installer performs right after an upgrade — must stand down rather than add a
/// duplicate tray icon.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class SingleInstanceGuardTests
{
    private static string UniqueName() =>
        @"Local\UsageBarTest." + Guid.NewGuid().ToString("N");

    [WindowsFact]
    public void TheFirstAcquisitionWins()
    {
        var name = UniqueName();

        using var first = SingleInstanceGuard.Acquire(name);

        Assert.True(first.IsOnlyInstance);
    }

    [WindowsFact]
    public void ASecondAcquisitionStandsDown()
    {
        var name = UniqueName();

        using var first = SingleInstanceGuard.Acquire(name);
        using var second = SingleInstanceGuard.Acquire(name);

        Assert.True(first.IsOnlyInstance);
        Assert.False(second.IsOnlyInstance);
    }

    /// <summary>
    /// After the running instance exits — which is what happens when an upgrade
    /// closes it — the next launch must be able to take over.
    /// </summary>
    [WindowsFact]
    public void ReleasingAllowsTheNextInstanceToTakeOver()
    {
        var name = UniqueName();

        var first = SingleInstanceGuard.Acquire(name);
        Assert.True(first.IsOnlyInstance);
        first.Dispose();

        using var next = SingleInstanceGuard.Acquire(name);
        Assert.True(next.IsOnlyInstance);
    }

    [WindowsFact]
    public void DisposingAGuardThatStoodDownIsHarmless()
    {
        var name = UniqueName();

        using var first = SingleInstanceGuard.Acquire(name);
        var second = SingleInstanceGuard.Acquire(name);

        Assert.False(second.IsOnlyInstance);
        second.Dispose();
        // Disposing twice must not throw either.
        second.Dispose();

        // The original still holds it.
        using var third = SingleInstanceGuard.Acquire(name);
        Assert.False(third.IsOnlyInstance);
    }

    /// <summary>
    /// The name is a contract with the installer: Inno Setup waits on this exact
    /// mutex to know whether UsageBar is running, instead of matching a process
    /// name that could belong to something else.
    /// </summary>
    [Fact]
    public void TheMutexNameIsPerSessionAndStable()
    {
        Assert.Equal(@"Local\UsageBar.Windows.SingleInstance", SingleInstanceGuard.DefaultName);
        Assert.StartsWith(@"Local\", SingleInstanceGuard.DefaultName, StringComparison.Ordinal);
        // Global\ would make one user's UsageBar block another's.
        Assert.DoesNotContain(@"Global\", SingleInstanceGuard.DefaultName, StringComparison.Ordinal);
    }

    [WindowsFact]
    public void TheApplicationUsesTheGuardRatherThanItsOwnMutex()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        string? program = null;
        while (directory is not null && program is null)
        {
            var candidate = Path.Combine(
                directory.FullName, "windows", "src", "UsageBar.Windows.App", "Program.cs");
            if (File.Exists(candidate))
            {
                program = File.ReadAllText(candidate);
            }

            directory = directory.Parent;
        }

        Assert.NotNull(program);
        Assert.Contains("SingleInstanceGuard.Acquire()", program!, StringComparison.Ordinal);
        Assert.Contains("IsOnlyInstance", program!, StringComparison.Ordinal);
        // No hand-rolled second mechanism.
        Assert.DoesNotContain("new Mutex(", program!, StringComparison.Ordinal);
    }
}
