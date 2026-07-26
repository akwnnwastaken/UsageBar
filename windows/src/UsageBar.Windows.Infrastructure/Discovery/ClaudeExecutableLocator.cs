using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// Finds a trusted native Windows Claude Code installation.
///
/// The candidate list follows the documented Windows install locations rather
/// than a PATH search:
/// <list type="bullet">
/// <item><c>%USERPROFILE%\.local\bin\claude.exe</c> — the native installer
/// (<c>irm https://claude.ai/install.ps1 | iex</c>), the recommended form.</item>
/// <item><c>%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe</c> — WinGet
/// (<c>winget install Anthropic.ClaudeCode</c>).</item>
/// <item>the npm global platform package, whose binary the documentation names
/// as an optional dependency such as <c>@anthropic-ai/claude-code-win32-x64</c>.</item>
/// <item><c>%USERPROFILE%\.claude\local</c> — the legacy local npm install
/// older Claude Code versions created.</item>
/// </list>
///
/// Claude Code on Windows ships a real native executable — the npm package
/// installs the same binary as the standalone installer and does not invoke
/// Node at runtime — so there is no Node launcher path here, unlike Codex.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ClaudeExecutableLocator
{
    /// <summary>
    /// Where the npm and legacy layouts are probed. Bounded on purpose: only
    /// inside a documented package root, only for a file named claude.exe, and
    /// only two directories deep.
    /// </summary>
    private const int MaximumProbeDepth = 2;

    private readonly Func<Environment.SpecialFolder, string> _specialFolder;
    private readonly Func<string, string?> _environmentVariable;

    public ClaudeExecutableLocator()
        : this(Environment.GetFolderPath, Environment.GetEnvironmentVariable)
    {
    }

    internal ClaudeExecutableLocator(
        Func<Environment.SpecialFolder, string> specialFolder,
        Func<string, string?> environmentVariable)
    {
        _specialFolder = specialFolder;
        _environmentVariable = environmentVariable;
    }

    public ExecutableLookup Locate(string? userSelectedPath = null)
    {
        var rejected = false;

        // An explicit user choice is honored first and validated identically:
        // choosing a path does not bypass any trust check.
        if (!string.IsNullOrWhiteSpace(userSelectedPath))
        {
            var directory = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(userSelectedPath));
            if (directory is not null)
            {
                var result = ExecutableTrust.Validate(userSelectedPath, directory);
                if (result is not null)
                {
                    return result;
                }
            }
        }

        foreach (var candidate in NativeCandidates())
        {
            var result = ExecutableTrust.Validate(candidate.Path, candidate.Root, candidate.AdapterKind);
            if (result is null)
            {
                continue;
            }

            if (result.Status == ExecutableLookupStatus.Found)
            {
                return result;
            }

            rejected = true;
        }

        foreach (var probe in ProbeRoots())
        {
            var result = ProbeForClaude(probe.Root, probe.AdapterKind);
            if (result is null)
            {
                continue;
            }

            if (result.Status == ExecutableLookupStatus.Found)
            {
                return result;
            }

            rejected = true;
        }

        return rejected ? ExecutableLookup.Untrusted : ExecutableLookup.Missing;
    }

    internal readonly record struct Candidate(string Path, string Root, ProviderAdapterKind AdapterKind);

    internal IEnumerable<Candidate> NativeCandidates()
    {
        var userProfile = _specialFolder(Environment.SpecialFolder.UserProfile);
        var localAppData = _specialFolder(Environment.SpecialFolder.LocalApplicationData);

        if (!string.IsNullOrEmpty(userProfile))
        {
            // The documented native installer location, and the one the
            // troubleshooting guide tells users to check first.
            var local = System.IO.Path.Combine(userProfile, ".local");
            yield return new Candidate(
                System.IO.Path.Combine(local, "bin", "claude.exe"),
                local,
                ProviderAdapterKind.NativeExecutable);
        }

        if (!string.IsNullOrEmpty(localAppData))
        {
            var winGet = System.IO.Path.Combine(localAppData, "Microsoft", "WinGet");
            yield return new Candidate(
                System.IO.Path.Combine(winGet, "Links", "claude.exe"),
                winGet,
                ProviderAdapterKind.NativeExecutable);
        }
    }

    internal readonly record struct ProbeRoot(string Root, ProviderAdapterKind AdapterKind);

    /// <summary>
    /// Package roots whose internal layout the documentation does not pin down.
    /// They are searched for a <c>claude.exe</c> rather than guessed at, but the
    /// search never leaves the documented root.
    /// </summary>
    internal IEnumerable<ProbeRoot> ProbeRoots()
    {
        var appData = _environmentVariable("APPDATA");
        if (!string.IsNullOrEmpty(appData))
        {
            var platformPackage = System.IO.Path.Combine(
                appData, "npm", "node_modules", "@anthropic-ai", "claude-code-win32-x64");
            yield return new ProbeRoot(platformPackage, ProviderAdapterKind.NativeExecutable);
        }

        var userProfile = _specialFolder(Environment.SpecialFolder.UserProfile);
        if (!string.IsNullOrEmpty(userProfile))
        {
            yield return new ProbeRoot(
                System.IO.Path.Combine(userProfile, ".claude", "local"),
                ProviderAdapterKind.NativeLocal);
        }
    }

    /// <summary>
    /// Looks for <c>claude.exe</c> inside one package root, at most
    /// <see cref="MaximumProbeDepth"/> directories down, and validates whatever
    /// it finds against that same root.
    /// </summary>
    private static ExecutableLookup? ProbeForClaude(string root, ProviderAdapterKind adapterKind)
    {
        if (!Directory.Exists(root))
        {
            return null;
        }

        foreach (var candidate in EnumerateCandidates(root, MaximumProbeDepth))
        {
            var result = ExecutableTrust.Validate(candidate, root, adapterKind);
            if (result is not null)
            {
                return result;
            }
        }

        return null;
    }

    private static IEnumerable<string> EnumerateCandidates(string directory, int depth)
    {
        string[] files;
        try
        {
            files = Directory.GetFiles(directory, "claude.exe", SearchOption.TopDirectoryOnly);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            yield break;
        }

        foreach (var file in files)
        {
            yield return file;
        }

        if (depth <= 0)
        {
            yield break;
        }

        string[] directories;
        try
        {
            directories = Directory.GetDirectories(directory);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            yield break;
        }

        foreach (var child in directories)
        {
            foreach (var file in EnumerateCandidates(child, depth - 1))
            {
                yield return file;
            }
        }
    }
}

/// <summary>
/// Finds Git for Windows' <c>bash.exe</c>.
///
/// Git for Windows is <b>optional</b> for UsageBar: the quota query runs with
/// tools disabled, so Claude never needs its Bash tool. When a trusted bash.exe
/// is present its path is passed through as <c>CLAUDE_CODE_GIT_BASH_PATH</c> —
/// the variable Claude Code documents for exactly this — so a Claude build that
/// probes for it at startup finds it instead of complaining. UsageBar never
/// launches bash.exe itself.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class GitBashLocator
{
    public const string EnvironmentVariableName = "CLAUDE_CODE_GIT_BASH_PATH";

    private readonly Func<Environment.SpecialFolder, string> _specialFolder;

    public GitBashLocator()
        : this(Environment.GetFolderPath)
    {
    }

    internal GitBashLocator(Func<Environment.SpecialFolder, string> specialFolder) =>
        _specialFolder = specialFolder;

    /// <summary>The trusted bash.exe path, or null when none is installed.</summary>
    public string? Locate()
    {
        foreach (var candidate in Candidates())
        {
            var result = ExecutableTrust.Validate(
                candidate.Path,
                candidate.Root,
                ProviderAdapterKind.GitForWindows);

            if (result is { Status: ExecutableLookupStatus.Found, Executable: not null })
            {
                return result.Executable.Path;
            }
        }

        return null;
    }

    internal IEnumerable<ClaudeExecutableLocator.Candidate> Candidates()
    {
        var programFiles = _specialFolder(Environment.SpecialFolder.ProgramFiles);
        var programFilesX86 = _specialFolder(Environment.SpecialFolder.ProgramFilesX86);
        var localAppData = _specialFolder(Environment.SpecialFolder.LocalApplicationData);

        foreach (var root in new[]
                 {
                     // Machine-wide installs, then the per-user install Git for
                     // Windows offers.
                     string.IsNullOrEmpty(programFiles) ? null : System.IO.Path.Combine(programFiles, "Git"),
                     string.IsNullOrEmpty(programFilesX86) ? null : System.IO.Path.Combine(programFilesX86, "Git"),
                     string.IsNullOrEmpty(localAppData) ? null : System.IO.Path.Combine(localAppData, "Programs", "Git")
                 })
        {
            if (root is null)
            {
                continue;
            }

            yield return new ClaudeExecutableLocator.Candidate(
                System.IO.Path.Combine(root, "bin", "bash.exe"),
                root,
                ProviderAdapterKind.GitForWindows);
        }
    }
}
