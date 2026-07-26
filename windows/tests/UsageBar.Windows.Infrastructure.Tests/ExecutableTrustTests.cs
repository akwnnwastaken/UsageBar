using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;
using UsageBar.Windows.Infrastructure.Discovery;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Executable validation. Every candidate must be a real file, inside the
/// installation root it is expected in, and of a type Windows can start without
/// a shell.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ExecutableTrustTests : IDisposable
{
    private readonly string _root = Path.Combine(
        Path.GetTempPath(),
        "usagebar-trust-" + Guid.NewGuid().ToString("N"));

    public ExecutableTrustTests() => Directory.CreateDirectory(_root);

    public void Dispose()
    {
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
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

    [Fact]
    public void AMissingFileIsReportedAsNotFound()
    {
        Assert.Null(ExecutableTrust.Validate(Path.Combine(_root, "absent.exe"), _root));
    }

    [Fact]
    public void EmptyOrWhitespacePathsAreNotFound()
    {
        Assert.Null(ExecutableTrust.Validate(string.Empty, _root));
        Assert.Null(ExecutableTrust.Validate("   ", _root));
    }

    [WindowsFact]
    public void ANativeExecutableInsideTheRootIsTrusted()
    {
        var path = Write("codex.exe");

        var lookup = ExecutableTrust.Validate(path, _root);

        Assert.Equal(ExecutableLookupStatus.Found, lookup?.Status);
        Assert.Equal(path, lookup?.Executable?.Path);
        Assert.Equal(ProviderAdapterKind.NativeExecutable, lookup?.Executable?.AdapterKind);
    }

    [WindowsFact]
    public void ADirectoryIsRejected()
    {
        var directory = Path.Combine(_root, "codex.exe");
        Directory.CreateDirectory(directory);

        Assert.Equal(ExecutableLookupStatus.Untrusted, ExecutableTrust.Validate(directory, _root)?.Status);
    }

    [WindowsFact]
    public void AFileOutsideTheAllowedRootIsRejected()
    {
        var path = Write("codex.exe");
        var otherRoot = Path.Combine(_root, "elsewhere");
        Directory.CreateDirectory(otherRoot);

        Assert.Equal(ExecutableLookupStatus.Untrusted, ExecutableTrust.Validate(path, otherRoot)?.Status);
    }

    [WindowsFact]
    public void PathTraversalCannotEscapeTheRoot()
    {
        var inner = Path.Combine(_root, "inner");
        Directory.CreateDirectory(inner);
        var outside = Write("outside.exe");
        var traversal = Path.Combine(inner, "..", "outside.exe");

        Assert.Equal(ExecutableLookupStatus.Untrusted, ExecutableTrust.Validate(traversal, inner)?.Status);
        Assert.Equal(ExecutableLookupStatus.Found, ExecutableTrust.Validate(outside, _root)?.Status);
    }

    /// <summary>
    /// A shim that only a shell can run is reported as an unsupported
    /// installation. UsageBar never silently falls back to cmd.exe or
    /// PowerShell to make it work.
    /// </summary>
    [WindowsTheory]
    [InlineData("codex.cmd")]
    [InlineData("codex.bat")]
    [InlineData("codex.ps1")]
    [InlineData("codex.vbs")]
    public void ShellOnlyShimsAreUnsupportedNotExecuted(string fileName)
    {
        var path = Write(fileName);

        Assert.Equal(
            ExecutableLookupStatus.UnsupportedInstallation,
            ExecutableTrust.Validate(path, _root)?.Status);
    }

    [WindowsTheory]
    [InlineData("codex.txt")]
    [InlineData("codex.dll")]
    [InlineData("codex")]
    public void UnsupportedFileTypesAreRejected(string fileName)
    {
        var path = Write(fileName);

        Assert.Equal(ExecutableLookupStatus.Untrusted, ExecutableTrust.Validate(path, _root)?.Status);
    }

    [WindowsFact]
    public void ATrustedScriptMustLiveInsideItsRoot()
    {
        var script = Write(Path.Combine("node_modules", "codex.js"));

        Assert.True(ExecutableTrust.IsTrustedScript(script, _root));
        Assert.False(ExecutableTrust.IsTrustedScript(script, Path.Combine(_root, "node_modules", "other")));
        Assert.False(ExecutableTrust.IsTrustedScript(Path.Combine(_root, "absent.js"), _root));
    }

    /// <summary>
    /// Discovery never consults the current directory: a provider-named
    /// executable sitting in the working directory must not be picked up.
    /// </summary>
    [WindowsFact]
    public void TheCurrentDirectoryIsNeverAnImplicitCandidate()
    {
        var locator = new CodexExecutableLocator(
            _ => string.Empty,
            _ => null);

        Assert.Empty(locator.NativeCandidates());
        Assert.Equal(ExecutableLookupStatus.Missing, locator.Locate().Status);
    }

    /// <summary>Windows-only: the candidate list is built from Windows paths.</summary>
    [WindowsFact]
    public void CandidateLocationsAreAllRootedInDocumentedInstallDirectories()
    {
        var locator = new CodexExecutableLocator(
            folder => folder switch
            {
                Environment.SpecialFolder.LocalApplicationData => @"C:\Users\tester\AppData\Local",
                Environment.SpecialFolder.ProgramFiles => @"C:\Program Files",
                Environment.SpecialFolder.UserProfile => @"C:\Users\tester",
                _ => string.Empty
            },
            name => name == "APPDATA" ? @"C:\Users\tester\AppData\Roaming" : null);

        var candidates = locator.NativeCandidates().ToList();

        Assert.NotEmpty(candidates);
        foreach (var candidate in candidates)
        {
            Assert.StartsWith(candidate.Root, candidate.Path, StringComparison.OrdinalIgnoreCase);
            Assert.EndsWith(".exe", candidate.Path, StringComparison.OrdinalIgnoreCase);
        }

        // The documented formats are all represented.
        Assert.Contains(candidates, candidate => candidate.Path.Contains(@"Programs\codex", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(candidates, candidate => candidate.Path.Contains("ChatGPT", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(candidates, candidate => candidate.Path.Contains("WinGet", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(candidates, candidate => candidate.Path.Contains(".cargo", StringComparison.OrdinalIgnoreCase));
        Assert.Contains(candidates, candidate => candidate.Path.Contains("scoop", StringComparison.OrdinalIgnoreCase));
    }

    [WindowsFact]
    public void AnNpmInstallWithoutNodeIsReportedAsUnsupportedRatherThanRunThroughAShell()
    {
        var appData = Path.Combine(_root, "Roaming");
        var npmRoot = Path.Combine(appData, "npm");
        Directory.CreateDirectory(Path.Combine(npmRoot, "node_modules", "@openai", "codex", "bin"));
        File.WriteAllText(
            Path.Combine(npmRoot, "node_modules", "@openai", "codex", "bin", "codex.js"),
            "// stub");
        // The shim a shell would use exists, and is deliberately ignored.
        File.WriteAllText(Path.Combine(npmRoot, "codex.cmd"), "@echo off");

        var locator = new CodexExecutableLocator(
            _ => Path.Combine(_root, "no-such-folder"),
            name => name == "APPDATA" ? appData : null);

        Assert.Equal(ExecutableLookupStatus.UnsupportedInstallation, locator.LocateNodeLauncher()?.Status);
    }

    [WindowsFact]
    public void AnNpmInstallWithNodeResolvesToNodePlusTheScript()
    {
        var appData = Path.Combine(_root, "Roaming");
        var scriptDirectory = Path.Combine(appData, "npm", "node_modules", "@openai", "codex", "bin");
        Directory.CreateDirectory(scriptDirectory);
        var script = Path.Combine(scriptDirectory, "codex.js");
        File.WriteAllText(script, "// stub");

        var programFiles = Path.Combine(_root, "ProgramFiles");
        Directory.CreateDirectory(Path.Combine(programFiles, "nodejs"));
        var node = Path.Combine(programFiles, "nodejs", "node.exe");
        File.WriteAllText(node, "stub");

        var locator = new CodexExecutableLocator(
            folder => folder == Environment.SpecialFolder.ProgramFiles ? programFiles : string.Empty,
            name => name == "APPDATA" ? appData : null);

        var lookup = locator.LocateNodeLauncher();

        Assert.Equal(ExecutableLookupStatus.Found, lookup?.Status);
        Assert.Equal(node, lookup?.Executable?.Path);
        Assert.Equal(ProviderAdapterKind.NodeLauncher, lookup?.Executable?.AdapterKind);
        Assert.Equal(new[] { script }, lookup?.Executable?.LeadingArguments);

        // The provider arguments follow the script, in order.
        Assert.Equal(
            new[] { script, "app-server", "--stdio" },
            lookup?.Executable?.BuildArguments(new[] { "app-server", "--stdio" }));
    }
}
