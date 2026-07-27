using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Known-folder resolution, and the provider discovery built on top of it.
///
/// Physical testing showed Codex being found when UsageBar was launched from the
/// Start Menu and not found when Setup launched it, on identical files. The
/// official Codex candidate is built from Local AppData, so a context where that
/// folder resolves to nothing explains it exactly: the candidate is never
/// constructed and the provider looks absent. These tests pin the behaviour that
/// removes the dependency on any single source.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class KnownFolderResolutionTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-folders-" + Guid.NewGuid().ToString("N"));

    public KnownFolderResolutionTests() => Directory.CreateDirectory(_root);

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

    private string MakeDirectory(params string[] segments)
    {
        var path = Path.Combine(_root, Path.Combine(segments));
        Directory.CreateDirectory(path);
        return path;
    }

    private string MakeExecutable(params string[] segments)
    {
        var path = Path.Combine(_root, Path.Combine(segments));
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "stub");
        return path;
    }

    private static WindowsKnownFolderResolver Resolver(string? shell, string? framework) =>
        new(_ => shell, _ => framework);

    private static IKnownFolderResolver Roots(
        string? localAppData = null,
        string? userProfile = null,
        string? roaming = null)
    {
        var map = new Dictionary<WindowsKnownFolder, IReadOnlyList<string>>();
        if (localAppData is not null) { map[WindowsKnownFolder.LocalApplicationData] = new[] { localAppData }; }
        if (userProfile is not null) { map[WindowsKnownFolder.UserProfile] = new[] { userProfile }; }
        if (roaming is not null) { map[WindowsKnownFolder.RoamingApplicationData] = new[] { roaming }; }
        return KnownFolderResolvers.FromRoots(map);
    }

    // MARK: - The resolver

    /// <summary>
    /// The hypothesis, made concrete: <c>Environment.GetFolderPath</c> returns
    /// nothing, the shell answers, and Codex is still found.
    /// </summary>
    [WindowsFact]
    public void CodexIsFoundWhenOnlyTheShellResolvesLocalAppData()
    {
        var localAppData = MakeDirectory("Local");
        var executable = MakeExecutable("Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe");

        var resolver = Resolver(shell: localAppData, framework: string.Empty);
        Assert.Equal(new[] { localAppData }, resolver.Resolve(WindowsKnownFolder.LocalApplicationData));

        var lookup = new CodexExecutableLocator(resolver).Locate();
        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
    }

    /// <summary>The reverse: the shell fails and the framework carries it.</summary>
    [WindowsFact]
    public void CodexIsFoundWhenOnlyTheFrameworkResolvesLocalAppData()
    {
        var localAppData = MakeDirectory("Local");
        MakeExecutable("Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe");

        var lookup = new CodexExecutableLocator(Resolver(shell: null, framework: localAppData)).Locate();

        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
    }

    /// <summary>
    /// One source pointing somewhere wrong must not shadow the source that is
    /// right: both roots are tried, and the trusted candidate wins.
    /// </summary>
    [WindowsFact]
    public void AWrongSourceDoesNotHideTheValidOne()
    {
        var wrong = MakeDirectory("Wrong");
        var right = MakeDirectory("Right");
        var executable = MakeExecutable("Right", "Programs", "OpenAI", "Codex", "bin", "codex.exe");

        var resolver = Resolver(shell: wrong, framework: right);
        Assert.Equal(new[] { wrong, right }, resolver.Resolve(WindowsKnownFolder.LocalApplicationData));

        var lookup = new CodexExecutableLocator(resolver).Locate();
        Assert.Equal(ExecutableLookupStatus.Found, lookup.Status);
        Assert.Equal(executable, lookup.Executable?.Path);
    }

    /// <summary>
    /// Two sources naming the same folder produce one root, so a candidate is
    /// validated once however many sources agree on it.
    /// </summary>
    [WindowsFact]
    public void IdenticalSourcesAreDeduplicated()
    {
        var localAppData = MakeDirectory("Local");

        var resolver = Resolver(
            shell: localAppData.ToUpperInvariant() + Path.DirectorySeparatorChar,
            framework: localAppData);

        Assert.Single(resolver.Resolve(WindowsKnownFolder.LocalApplicationData));
    }

    [WindowsFact]
    public void ASourceThatPointsNowhereIsDiscarded()
    {
        var real = MakeDirectory("Local");

        // A folder that does not exist is not a root...
        Assert.Equal(
            new[] { real },
            Resolver(shell: Path.Combine(_root, "does-not-exist"), framework: real)
                .Resolve(WindowsKnownFolder.LocalApplicationData));

        // ...and neither is a blank or unusable answer.
        Assert.Empty(Resolver(shell: "   ", framework: "\0invalid")
            .Resolve(WindowsKnownFolder.LocalApplicationData));
    }

    [WindowsFact]
    public void AllSourcesUnavailableYieldsMissingRatherThanAWrongAnswer()
    {
        var resolver = Resolver(shell: null, framework: string.Empty);

        Assert.Empty(resolver.Resolve(WindowsKnownFolder.LocalApplicationData));
        Assert.Equal(ExecutableLookupStatus.Missing, new CodexExecutableLocator(resolver).Locate().Status);
        Assert.Equal(CandidateState.NotConstructed, new CodexExecutableLocator(resolver).OfficialCandidateState());
    }

    /// <summary>
    /// Nothing is remembered, so a folder that resolved to nothing once is asked
    /// about again rather than being treated as permanently absent.
    /// </summary>
    [WindowsFact]
    public void AFailedResolutionIsNotCached()
    {
        var localAppData = MakeDirectory("Local");
        string? current = null;

        var resolver = new WindowsKnownFolderResolver(_ => current, _ => null);
        Assert.Empty(resolver.Resolve(WindowsKnownFolder.LocalApplicationData));

        current = localAppData;
        Assert.Equal(new[] { localAppData }, resolver.Resolve(WindowsKnownFolder.LocalApplicationData));
    }

    // MARK: - Candidate state

    [WindowsFact]
    public void TheOfficialCandidateStateDistinguishesAllThreeCases()
    {
        var localAppData = MakeDirectory("Local");

        // No root at all: the candidate cannot even be built.
        Assert.Equal(
            CandidateState.NotConstructed,
            new CodexExecutableLocator(Roots()).OfficialCandidateState());

        // A root, but no Codex under it.
        Assert.Equal(
            CandidateState.Missing,
            new CodexExecutableLocator(Roots(localAppData: localAppData)).OfficialCandidateState());

        MakeExecutable("Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe");
        Assert.Equal(
            CandidateState.Exists,
            new CodexExecutableLocator(Roots(localAppData: localAppData)).OfficialCandidateState());
    }

    // MARK: - Trust is unchanged

    /// <summary>
    /// Resolving more roots must not loosen anything: an executable outside the
    /// installation root it belongs to is still refused, and never located.
    /// </summary>
    [WindowsFact]
    public void AnUntrustedExecutableIsStillRejected()
    {
        var localAppData = MakeDirectory("Local");
        var impostor = MakeExecutable("Local", "Programs", "OpenAI", "codex.exe");

        Assert.Equal(
            ExecutableLookupStatus.Untrusted,
            ExecutableTrust.Validate(impostor, Path.Combine(localAppData, "Programs", "OpenAI", "Codex"))?.Status);

        Assert.Equal(
            ExecutableLookupStatus.Missing,
            new CodexExecutableLocator(Roots(localAppData: localAppData)).Locate().Status);
    }

    [WindowsTheory]
    [InlineData("codex.cmd")]
    [InlineData("codex.bat")]
    public void AShellOnlyShimIsStillUnsupported(string fileName)
    {
        var localAppData = MakeDirectory("Local");
        var shim = MakeExecutable("Local", "Programs", "OpenAI", "Codex", "bin", fileName);

        Assert.Equal(
            ExecutableLookupStatus.UnsupportedInstallation,
            ExecutableTrust.Validate(shim, Path.Combine(localAppData, "Programs", "OpenAI", "Codex"))?.Status);
    }

    // MARK: - Providers stay independent

    /// <summary>
    /// Claude reaches its installation through the user profile, so it keeps
    /// working even when Local AppData resolves to nothing — which is exactly
    /// what was observed physically, and why Claude worked while Codex did not.
    /// </summary>
    [WindowsFact]
    public void ClaudeAndCodexResolveIndependently()
    {
        var userProfile = MakeDirectory("Profile");
        var claude = MakeExecutable("Profile", ".local", "bin", "claude.exe");

        // No Local AppData at all.
        var profileOnly = Roots(userProfile: userProfile);

        var claudeLookup = new ClaudeExecutableLocator(profileOnly).Locate();
        Assert.Equal(ExecutableLookupStatus.Found, claudeLookup.Status);
        Assert.Equal(claude, claudeLookup.Executable?.Path);

        // Codex is genuinely absent here, and says so without affecting Claude.
        Assert.Equal(ExecutableLookupStatus.Missing, new CodexExecutableLocator(profileOnly).Locate().Status);

        // With Local AppData back, Codex resolves without disturbing Claude.
        var localAppData = MakeDirectory("Local");
        MakeExecutable("Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe");
        var both = Roots(localAppData: localAppData, userProfile: userProfile);

        Assert.Equal(ExecutableLookupStatus.Found, new CodexExecutableLocator(both).Locate().Status);
        Assert.Equal(ExecutableLookupStatus.Found, new ClaudeExecutableLocator(both).Locate().Status);
    }

    /// <summary>
    /// The installer-launch context, reproduced: the framework call returns
    /// nothing for every folder, the shell still answers, and both providers
    /// resolve. Depending on a single source, this configuration found neither.
    /// </summary>
    [WindowsFact]
    public void TheInstallerLaunchContextStillFindsBothProviders()
    {
        var profile = MakeDirectory("Profile");
        var localAppData = MakeDirectory("Profile", "AppData", "Local");
        MakeExecutable("Profile", ".local", "bin", "claude.exe");
        MakeExecutable("Profile", "AppData", "Local", "Programs", "OpenAI", "Codex", "bin", "codex.exe");

        var resolver = new WindowsKnownFolderResolver(
            folder => folder == WindowsKnownFolder.UserProfile ? profile : localAppData,
            _ => string.Empty);

        Assert.Equal(ExecutableLookupStatus.Found, new CodexExecutableLocator(resolver).Locate().Status);
        Assert.Equal(ExecutableLookupStatus.Found, new ClaudeExecutableLocator(resolver).Locate().Status);
        Assert.Equal(CandidateState.Exists, new CodexExecutableLocator(resolver).OfficialCandidateState());
    }

    // MARK: - The environment is not a source of trust

    /// <summary>
    /// <c>LOCALAPPDATA</c> is inherited, so a parent process could point
    /// discovery anywhere. It must never become a root.
    /// </summary>
    [WindowsFact]
    public void TheInheritedEnvironmentVariableIsNeverASource()
    {
        var planted = MakeDirectory("Planted");
        MakeExecutable("Planted", "Programs", "OpenAI", "Codex", "bin", "codex.exe");

        var original = Environment.GetEnvironmentVariable("LOCALAPPDATA");
        Environment.SetEnvironmentVariable("LOCALAPPDATA", planted);
        try
        {
            // Neither source offers anything, so the planted value must not be
            // picked up from the environment behind their backs.
            var resolver = new WindowsKnownFolderResolver(_ => null, _ => null);

            Assert.Empty(resolver.Resolve(WindowsKnownFolder.LocalApplicationData));
            Assert.Equal(ExecutableLookupStatus.Missing, new CodexExecutableLocator(resolver).Locate().Status);
        }
        finally
        {
            Environment.SetEnvironmentVariable("LOCALAPPDATA", original);
        }
    }

    // MARK: - Parent process

    [WindowsFact]
    public void TheParentProcessKindIsClassifiedWithoutExposingIt()
    {
        var kind = ProcessParentInspector.Classify();

        Assert.Contains(kind, Enum.GetValues<ProcessParentKind>());

        // Whatever it is, it is a bare classification with nothing identifying.
        var reported = kind.ToString();
        Assert.DoesNotContain(".exe", reported, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\\", reported, StringComparison.Ordinal);
        Assert.DoesNotContain(Environment.UserName, reported, StringComparison.OrdinalIgnoreCase);
    }
}
