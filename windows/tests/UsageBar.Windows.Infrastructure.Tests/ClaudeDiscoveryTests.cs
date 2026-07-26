using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Claude discovery. The candidate list follows the documented Windows install
/// locations; nothing is found through PATH, the working directory, or a shell.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeDiscoveryTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-claude-" + Guid.NewGuid().ToString("N"));

    public ClaudeDiscoveryTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }

    private string Write(string relativePath, string content = "stub")
    {
        var path = Path.Combine(_root, relativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content);
        return path;
    }

    private ClaudeExecutableLocator Locator(string? userProfile = null, string? localAppData = null, string? appData = null) =>
        new(
            folder => folder switch
            {
                Environment.SpecialFolder.UserProfile => userProfile ?? string.Empty,
                Environment.SpecialFolder.LocalApplicationData => localAppData ?? string.Empty,
                _ => string.Empty
            },
            name => name == "APPDATA" ? appData : null);

    /// <summary>
    /// The documented native installer location — what
    /// <c>irm https://claude.ai/install.ps1 | iex</c> produces, and the one the
    /// troubleshooting guide tells users to check first.
    /// </summary>
    [WindowsFact]
    public void TheNativeInstallerLayoutIsDiscovered()
    {
        var profile = Path.Combine(_root, "Profile");
        var executable = Write(Path.Combine("Profile", ".local", "bin", "claude.exe"));

        var lookup = Locator(userProfile: profile).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
        Assert.Equal(ProviderAdapterKind.NativeExecutable, lookup.AdapterKind);
        Assert.Empty(lookup.Executable!.LeadingArguments);
    }

    [WindowsFact]
    public void TheWinGetLayoutIsDiscovered()
    {
        var localAppData = Path.Combine(_root, "Local");
        var executable = Write(Path.Combine("Local", "Microsoft", "WinGet", "Links", "claude.exe"));

        var lookup = Locator(localAppData: localAppData).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
    }

    /// <summary>
    /// The npm global install links the same native binary into a per-platform
    /// package. The package root is documented; the file's exact position inside
    /// it is not, so it is searched for within that root rather than guessed.
    /// </summary>
    [WindowsFact]
    public void TheNpmPlatformPackageIsDiscovered()
    {
        var appData = Path.Combine(_root, "Roaming");
        var executable = Write(Path.Combine(
            "Roaming", "npm", "node_modules", "@anthropic-ai", "claude-code-win32-x64", "bin", "claude.exe"));

        var lookup = Locator(appData: appData).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
        Assert.Equal(ProviderAdapterKind.NativeExecutable, lookup.AdapterKind);
    }

    [WindowsFact]
    public void TheLegacyLocalInstallIsDiscoveredAndLabelled()
    {
        var profile = Path.Combine(_root, "Profile");
        Write(Path.Combine("Profile", ".claude", "local", "claude.exe"));

        var lookup = Locator(userProfile: profile).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(ProviderAdapterKind.NativeLocal, lookup.AdapterKind);
    }

    /// <summary>
    /// A shim only a shell could run is reported as unsupported. UsageBar never
    /// falls back to cmd.exe or PowerShell to make it work.
    /// </summary>
    [WindowsTheory]
    [InlineData("claude.cmd")]
    [InlineData("claude.bat")]
    [InlineData("claude.ps1")]
    public void AShellOnlyShimIsUnsupportedNotExecuted(string fileName)
    {
        var profile = Path.Combine(_root, "Profile");
        var shim = Write(Path.Combine("Profile", ".local", "bin", fileName));

        Assert.Equal(
            ExecutableLookupStatus.UnsupportedInstallation,
            ExecutableTrust.Validate(shim, Path.Combine(profile, ".local"))?.Status);
    }

    [WindowsFact]
    public void AnIdenticallyNamedExecutableOutsideTheTrustedRootIsRejected()
    {
        var profile = Path.Combine(_root, "Profile");
        var local = Path.Combine(profile, ".local");
        Directory.CreateDirectory(local);

        var impostor = Write(Path.Combine("Profile", "claude.exe"));

        Assert.Equal(ExecutableLookupStatus.Untrusted, ExecutableTrust.Validate(impostor, local)?.Status);
        Assert.Equal(ExecutableLookupStatus.Missing, Locator(userProfile: profile).Locate().Status);
    }

    [WindowsFact]
    public void AUserSelectedPathStillGoesThroughValidation()
    {
        var profile = Path.Combine(_root, "Profile");
        var selected = Write(Path.Combine("Elsewhere", "claude.exe"));
        var shim = Write(Path.Combine("Elsewhere", "claude.cmd"));

        // A valid selection is honored.
        Assert.Equal(
            ExecutableLookupStatus.Found,
            Locator(userProfile: profile).Locate(selected).Status);

        // A shell-only selection is refused rather than run through a shell.
        Assert.Equal(
            ExecutableLookupStatus.UnsupportedInstallation,
            Locator(userProfile: profile).Locate(shim).Status);

        // A selection that does not exist falls through to normal discovery.
        Assert.Equal(
            ExecutableLookupStatus.Missing,
            Locator(userProfile: profile).Locate(Path.Combine(_root, "absent", "claude.exe")).Status);
    }

    [WindowsFact]
    public void NothingIsDiscoveredFromThePathOrTheWorkingDirectory()
    {
        // No special folders and no APPDATA: there is nowhere documented to look.
        var locator = new ClaudeExecutableLocator(_ => string.Empty, _ => null);

        Assert.Empty(locator.NativeCandidates());
        Assert.Empty(locator.ProbeRoots());
        Assert.Equal(ExecutableLookupStatus.Missing, locator.Locate().Status);
    }

    [WindowsFact]
    public void CandidateLocationsAreAllRootedInDocumentedInstallDirectories()
    {
        var locator = Locator(
            userProfile: @"C:\Users\tester",
            localAppData: @"C:\Users\tester\AppData\Local",
            appData: @"C:\Users\tester\AppData\Roaming");

        var candidates = locator.NativeCandidates().ToList();
        Assert.NotEmpty(candidates);
        foreach (var candidate in candidates)
        {
            Assert.StartsWith(candidate.Root, candidate.Path, StringComparison.OrdinalIgnoreCase);
            Assert.EndsWith("claude.exe", candidate.Path, StringComparison.OrdinalIgnoreCase);
        }

        Assert.Contains(
            candidates,
            candidate => candidate.Path.EndsWith(@"\.local\bin\claude.exe", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(
            candidates,
            candidate => candidate.Path.Contains("WinGet", StringComparison.OrdinalIgnoreCase));

        var probes = locator.ProbeRoots().ToList();
        Assert.Contains(probes, probe => probe.Root.Contains("claude-code-win32-x64", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(probes, probe => probe.Root.EndsWith(@"\.claude\local", StringComparison.OrdinalIgnoreCase));
    }

    // MARK: - Git for Windows

    [WindowsFact]
    public void GitBashIsFoundInDocumentedRootsOnly()
    {
        var programFiles = Path.Combine(_root, "ProgramFiles");
        var bash = Write(Path.Combine("ProgramFiles", "Git", "bin", "bash.exe"));

        var locator = new GitBashLocator(
            folder => folder == Environment.SpecialFolder.ProgramFiles ? programFiles : string.Empty);

        Assert.Equal(bash, locator.Locate());
    }

    [WindowsFact]
    public void MissingGitBashIsNotAnError()
    {
        // Git for Windows is optional: the quota query disables tools, so its
        // absence must simply produce no environment variable.
        var locator = new GitBashLocator(_ => Path.Combine(_root, "nowhere"));

        Assert.Null(locator.Locate());
    }

    [WindowsFact]
    public void AnUntrustedBashIsNotUsed()
    {
        var programFiles = Path.Combine(_root, "ProgramFiles");
        // Right name, wrong place: outside the Git installation root.
        Write(Path.Combine("ProgramFiles", "bash.exe"));

        var locator = new GitBashLocator(
            folder => folder == Environment.SpecialFolder.ProgramFiles ? programFiles : string.Empty);

        Assert.Null(locator.Locate());
    }

    [Fact]
    public void TheGitBashVariableIsTheOneClaudeDocuments()
    {
        Assert.Equal("CLAUDE_CODE_GIT_BASH_PATH", GitBashLocator.EnvironmentVariableName);
    }
}
