using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// Finds a trusted Codex installation.
///
/// Only documented candidate locations are searched, each pinned to the
/// installation root it must live under. The user's PATH is never used to pick a
/// winner and the current working directory is never consulted, so a project
/// that ships its own <c>codex.exe</c> cannot hijack a quota check.
///
/// Supported installation formats:
/// <list type="bullet">
/// <item>native per-user install (<c>%LOCALAPPDATA%\Programs\codex</c>)</item>
/// <item>native machine install (<c>%ProgramFiles%\codex</c>)</item>
/// <item>ChatGPT desktop's bundled Codex</item>
/// <item>WinGet link, Scoop shim and Cargo bin, when they are real executables</item>
/// <item>npm global install, started through a validated <c>node.exe</c></item>
/// <item>an explicit user-selected executable</item>
/// </list>
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class CodexExecutableLocator
{
    private readonly IKnownFolderResolver _folders;

    public CodexExecutableLocator()
        : this(new WindowsKnownFolderResolver())
    {
    }

    /// <summary>
    /// Candidate roots come from the resolver, which asks the shell before the
    /// framework. A context where one of those sources returns nothing no longer
    /// silently removes the official Codex candidate.
    /// </summary>
    public CodexExecutableLocator(IKnownFolderResolver folders) => _folders = folders;

    internal CodexExecutableLocator(
        Func<Environment.SpecialFolder, string> specialFolder,
        Func<string, string?> environmentVariable)
        : this(LegacyResolver.From(specialFolder, environmentVariable))
    {
    }

    /// <summary>
    /// The documented native Codex path, and whether it could even be built.
    /// Reported in diagnostics so a machine where Local AppData does not resolve
    /// is distinguishable from one where Codex is genuinely not installed.
    /// </summary>
    public CandidateState OfficialCandidateState()
    {
        var roots = _folders.Resolve(WindowsKnownFolder.LocalApplicationData);
        if (roots.Count == 0)
        {
            return CandidateState.NotConstructed;
        }

        foreach (var root in roots)
        {
            var candidate = System.IO.Path.Combine(
                root, "Programs", "OpenAI", "Codex", "bin", "codex.exe");
            if (File.Exists(candidate))
            {
                return CandidateState.Exists;
            }
        }

        return CandidateState.Missing;
    }

    public ExecutableLookup Locate(string? userSelectedPath = null)
    {
        var rejected = false;

        // An explicit user choice is honored first, but validated identically.
        if (!string.IsNullOrWhiteSpace(userSelectedPath))
        {
            var directory = System.IO.Path.GetDirectoryName(System.IO.Path.GetFullPath(userSelectedPath));
            if (directory is not null)
            {
                var result = ExecutableTrust.Validate(userSelectedPath, directory);
                if (result is { Status: ExecutableLookupStatus.Found })
                {
                    return result;
                }

                if (result is not null)
                {
                    return result;
                }
            }
        }

        foreach (var candidate in NativeCandidates())
        {
            var result = ExecutableTrust.Validate(candidate.Path, candidate.Root);
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

        var nodeLauncher = LocateNodeLauncher();
        if (nodeLauncher is not null)
        {
            if (nodeLauncher.Status == ExecutableLookupStatus.Found)
            {
                return nodeLauncher;
            }

            rejected = true;
        }

        return rejected ? ExecutableLookup.Untrusted : ExecutableLookup.Missing;
    }

    internal readonly record struct Candidate(string Path, string Root);

    internal IEnumerable<Candidate> NativeCandidates()
    {
        // Every resolved root is tried, so one source returning nothing cannot
        // remove a candidate the other source can still build.
        foreach (var localAppData in _folders.Resolve(WindowsKnownFolder.LocalApplicationData))
        {
            var programs = System.IO.Path.Combine(localAppData, "Programs");

            // The official native Windows installer, found during physical
            // testing against codex-cli 0.145.0. It nests the executable under
            // a vendor folder and a `bin` directory, so neither the path nor
            // the trusted root matches the flatter layouts below.
            yield return new Candidate(
                System.IO.Path.Combine(programs, "OpenAI", "Codex", "bin", "codex.exe"),
                System.IO.Path.Combine(programs, "OpenAI", "Codex"));

            yield return new Candidate(
                System.IO.Path.Combine(programs, "codex", "codex.exe"),
                System.IO.Path.Combine(programs, "codex"));

            // The Windows equivalent of the macOS ChatGPT.app bundled Codex.
            yield return new Candidate(
                System.IO.Path.Combine(programs, "ChatGPT", "resources", "codex.exe"),
                System.IO.Path.Combine(programs, "ChatGPT"));

            var winGetLinks = System.IO.Path.Combine(localAppData, "Microsoft", "WinGet", "Links");
            yield return new Candidate(
                System.IO.Path.Combine(winGetLinks, "codex.exe"),
                System.IO.Path.Combine(localAppData, "Microsoft", "WinGet"));
        }

        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        if (!string.IsNullOrEmpty(programFiles))
        {
            yield return new Candidate(
                System.IO.Path.Combine(programFiles, "codex", "codex.exe"),
                System.IO.Path.Combine(programFiles, "codex"));
        }

        foreach (var userProfile in _folders.Resolve(WindowsKnownFolder.UserProfile))
        {
            yield return new Candidate(
                System.IO.Path.Combine(userProfile, ".cargo", "bin", "codex.exe"),
                System.IO.Path.Combine(userProfile, ".cargo"));
            yield return new Candidate(
                System.IO.Path.Combine(userProfile, "scoop", "shims", "codex.exe"),
                System.IO.Path.Combine(userProfile, "scoop"));
        }
    }

    /// <summary>
    /// npm installs Codex as a JavaScript entry point plus a <c>.cmd</c> shim.
    /// The shim is never run — that would mean invoking cmd.exe. Instead the
    /// script and a real <c>node.exe</c> are validated separately and Node is
    /// started directly with the script as its first argument.
    /// </summary>
    internal ExecutableLookup? LocateNodeLauncher()
    {
        var appData = _folders.Resolve(WindowsKnownFolder.RoamingApplicationData).FirstOrDefault();
        if (string.IsNullOrEmpty(appData))
        {
            return null;
        }

        var npmRoot = System.IO.Path.Combine(appData, "npm");
        var script = System.IO.Path.Combine(
            npmRoot, "node_modules", "@openai", "codex", "bin", "codex.js");

        if (!File.Exists(script))
        {
            return null;
        }

        if (!ExecutableTrust.IsTrustedScript(script, npmRoot))
        {
            return ExecutableLookup.Untrusted;
        }

        var node = LocateNode();
        if (node is null)
        {
            // The installation exists but cannot be started without a shell.
            return ExecutableLookup.UnsupportedInstallation;
        }

        if (node.Status != ExecutableLookupStatus.Found || node.Executable is null)
        {
            return node;
        }

        return ExecutableLookup.Found(new ResolvedExecutable(
            node.Executable.Path,
            new[] { System.IO.Path.GetFullPath(script) },
            ProviderAdapterKind.NodeLauncher));
    }

    internal ExecutableLookup? LocateNode()
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);

        var candidates = new List<Candidate>();
        if (!string.IsNullOrEmpty(programFiles))
        {
            candidates.Add(new Candidate(
                System.IO.Path.Combine(programFiles, "nodejs", "node.exe"),
                System.IO.Path.Combine(programFiles, "nodejs")));
        }

        foreach (var localAppData in _folders.Resolve(WindowsKnownFolder.LocalApplicationData))
        {
            candidates.Add(new Candidate(
                System.IO.Path.Combine(localAppData, "Programs", "nodejs", "node.exe"),
                System.IO.Path.Combine(localAppData, "Programs", "nodejs")));
        }

        ExecutableLookup? rejected = null;
        foreach (var candidate in candidates)
        {
            var result = ExecutableTrust.Validate(
                candidate.Path,
                candidate.Root,
                ProviderAdapterKind.NodeLauncher);
            if (result is null)
            {
                continue;
            }

            if (result.Status == ExecutableLookupStatus.Found)
            {
                return result;
            }

            rejected = result;
        }

        return rejected;
    }
}
