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
    private readonly Func<Environment.SpecialFolder, string> _specialFolder;
    private readonly Func<string, string?> _environmentVariable;

    public CodexExecutableLocator()
        : this(Environment.GetFolderPath, Environment.GetEnvironmentVariable)
    {
    }

    internal CodexExecutableLocator(
        Func<Environment.SpecialFolder, string> specialFolder,
        Func<string, string?> environmentVariable)
    {
        _specialFolder = specialFolder;
        _environmentVariable = environmentVariable;
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
        var localAppData = _specialFolder(Environment.SpecialFolder.LocalApplicationData);
        var programFiles = _specialFolder(Environment.SpecialFolder.ProgramFiles);
        var userProfile = _specialFolder(Environment.SpecialFolder.UserProfile);

        if (!string.IsNullOrEmpty(localAppData))
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

        if (!string.IsNullOrEmpty(programFiles))
        {
            yield return new Candidate(
                System.IO.Path.Combine(programFiles, "codex", "codex.exe"),
                System.IO.Path.Combine(programFiles, "codex"));
        }

        if (!string.IsNullOrEmpty(userProfile))
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
        var appData = _environmentVariable("APPDATA");
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
        var programFiles = _specialFolder(Environment.SpecialFolder.ProgramFiles);
        var localAppData = _specialFolder(Environment.SpecialFolder.LocalApplicationData);

        var candidates = new List<Candidate>();
        if (!string.IsNullOrEmpty(programFiles))
        {
            candidates.Add(new Candidate(
                System.IO.Path.Combine(programFiles, "nodejs", "node.exe"),
                System.IO.Path.Combine(programFiles, "nodejs")));
        }

        if (!string.IsNullOrEmpty(localAppData))
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
