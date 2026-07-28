using System.Text.RegularExpressions;
using UsageBar.Windows.Infrastructure.Diagnostics;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// A test that only means something once a build revision has been supplied.
///
/// Windows CI exports <c>USAGEBAR_SOURCE_REVISION</c> before building, so there
/// the assemblies under test really were stamped and the assertion runs. On a
/// developer machine the variable is absent and the test reports as skipped —
/// never as passed.
/// </summary>
public sealed class SourceRevisionFactAttribute : FactAttribute
{
    public SourceRevisionFactAttribute()
    {
        if (string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("USAGEBAR_SOURCE_REVISION")))
        {
            Skip = "Requires USAGEBAR_SOURCE_REVISION: the build revision is supplied by Windows CI.";
        }
    }
}

/// <summary>
/// How a Windows build learns which commit it came from.
///
/// GitHub checks out <c>refs/pull/N/merge</c> for a pull request — a synthetic
/// merge commit that exists only for that run. Reading the revision from
/// <c>git rev-parse HEAD</c> there stamps artifacts with a SHA nobody can look
/// up, which is how UsageBar 2.0.0 shipped as <c>2.0.0+14bea7e</c> even though
/// its tree matched the approved source commit.
///
/// The pipeline is PowerShell and YAML, so these assertions are made against
/// those files directly, the same way <see cref="InstallerDefinitionTests"/>
/// asserts the installer's policy against its definition. They fail if the
/// revision ever goes back to being derived from the checkout, if validation is
/// dropped, or if one of the artifact paths stops being told which revision to
/// expect.
/// </summary>
public sealed class SourceRevisionPipelineTests
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

    private static string Workflow => File.ReadAllText(RepositoryFile(".github/workflows/windows-ci.yml"));

    private static string Resolver => File.ReadAllText(RepositoryFile("windows/scripts/source-revision.ps1"));

    private static string PackageScript => File.ReadAllText(RepositoryFile("windows/scripts/package.ps1"));

    private static string VerifyPackageScript => File.ReadAllText(RepositoryFile("windows/scripts/verify-package.ps1"));

    private static string VerifyInstallerScript => File.ReadAllText(RepositoryFile("windows/scripts/verify-installer.ps1"));

    // MARK: - Which commit the workflow chooses

    /// <summary>
    /// The correction itself: a pull-request run must identify the head commit,
    /// and every other run the commit that triggered it.
    /// </summary>
    [Fact]
    public void ThePullRequestRevisionIsTheHeadCommitNotTheMergeRef()
    {
        Assert.Contains("github.event.pull_request.head.sha", Workflow, StringComparison.Ordinal);
        Assert.Contains("github.sha", Workflow, StringComparison.Ordinal);
        Assert.Matches(@"EVENT_NAME\s*-eq\s*'pull_request'", Workflow);

        // The checkout's own HEAD may be printed for contrast, but it must never
        // become the revision the artifacts are stamped with.
        Assert.DoesNotMatch(@"USAGEBAR_SOURCE_REVISION=\$\(git rev-parse", Workflow);
        Assert.DoesNotMatch(@"-SourceRevision\s+\$\(git rev-parse", Workflow);
    }

    /// <summary>
    /// The revision is workflow input until it has been checked, so it is
    /// validated before it reaches a build, and rejected rather than patched up.
    /// </summary>
    [Fact]
    public void TheWorkflowValidatesAFullCommitSha()
    {
        Assert.Contains("^[0-9a-fA-F]{40}$", Workflow, StringComparison.Ordinal);
        Assert.Contains("::error::", Workflow, StringComparison.Ordinal);
        Assert.Matches(@"(?s)-notmatch\s*'\^\[0-9a-fA-F\]\{40\}\$'.*?exit 1", Workflow);
    }

    /// <summary>
    /// One resolved revision, passed to everything that can produce or inspect a
    /// binary. A step left out would silently reintroduce the drift this change
    /// exists to remove.
    /// </summary>
    [Fact]
    public void TheResolvedRevisionReachesEveryArtifactPath()
    {
        Assert.Contains("USAGEBAR_SOURCE_REVISION=$revision", Workflow, StringComparison.Ordinal);
        Assert.Contains("USAGEBAR_BUILD_ID=$buildId", Workflow, StringComparison.Ordinal);

        // The solution build the tests run against.
        Assert.Contains("-p:SourceRevisionId=$env:USAGEBAR_BUILD_ID", Workflow, StringComparison.Ordinal);

        // Portable packaging and both verification gates.
        Assert.Contains("./scripts/package.ps1 -SkipTests -SourceRevision $env:USAGEBAR_SOURCE_REVISION", Workflow, StringComparison.Ordinal);
        Assert.Contains("./scripts/verify-package.ps1 -ExpectedSourceRevision $env:USAGEBAR_SOURCE_REVISION", Workflow, StringComparison.Ordinal);
        Assert.Contains("./scripts/verify-installer.ps1 -ExpectedSourceRevision $env:USAGEBAR_SOURCE_REVISION", Workflow, StringComparison.Ordinal);

        // And the rules themselves are exercised in the run.
        Assert.Contains("./scripts/test-source-revision.ps1", Workflow, StringComparison.Ordinal);
    }

    /// <summary>
    /// The event payload is read through environment variables, never
    /// interpolated into the script body, and the trigger and permissions stay
    /// as they were.
    /// </summary>
    [Fact]
    public void TheWorkflowKeepsItsMinimalTriggerAndPermissions()
    {
        Assert.Matches(@"(?m)^permissions:\s*$", Workflow);
        Assert.Matches(@"(?m)^\s{2}contents:\s*read\s*$", Workflow);
        Assert.DoesNotContain("pull_request_target", Workflow, StringComparison.Ordinal);
        Assert.DoesNotContain("actions/github-script", Workflow, StringComparison.Ordinal);

        // The payload values arrive as env, so nothing in them is evaluated.
        Assert.Matches(@"PULL_REQUEST_HEAD_SHA:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\}\}", Workflow);
        Assert.Contains("$env:PULL_REQUEST_HEAD_SHA", Workflow, StringComparison.Ordinal);

        // Every action reference stays pinned to a commit SHA.
        foreach (Match use in Regex.Matches(Workflow, @"uses:\s*(\S+)"))
        {
            Assert.Matches(@"@[0-9a-f]{40}$", use.Groups[1].Value);
        }
    }

    // MARK: - What the scripts do with it

    /// <summary>
    /// Packaging takes the revision as an input and no longer derives it from
    /// the checkout, which is what produced the merge-ref build id.
    /// </summary>
    [Fact]
    public void PackagingTakesTheRevisionAsAnInput()
    {
        Assert.Contains("[string] $SourceRevision", PackageScript, StringComparison.Ordinal);
        Assert.Contains("Resolve-UsageBarSourceRevision", PackageScript, StringComparison.Ordinal);
        Assert.Contains("-p:SourceRevisionId=$buildId", PackageScript, StringComparison.Ordinal);

        // The old behaviour: the short revision read straight from HEAD.
        Assert.DoesNotContain("rev-parse --short=7 HEAD", PackageScript, StringComparison.Ordinal);

        // Nothing may fall back to a version number or a placeholder.
        Assert.DoesNotMatch(@"SourceRevisionId=(unknown|''|""""|\$version)", PackageScript);
    }

    /// <summary>
    /// The fallback exists for local builds only, and an unresolvable revision
    /// stops the build instead of producing an unstamped artifact.
    /// </summary>
    [Fact]
    public void TheResolverFallsBackToTheCheckoutAndOtherwiseFails()
    {
        Assert.Contains("rev-parse HEAD", Resolver, StringComparison.Ordinal);
        Assert.Contains("^[0-9a-fA-F]{40}$", Resolver, StringComparison.Ordinal);
        Assert.Contains("throw", Resolver, StringComparison.Ordinal);

        // No silent substitute for a revision that cannot be resolved.
        Assert.DoesNotMatch(@"return\s+'unknown'", Resolver);
        Assert.DoesNotMatch(@"return\s+''\s*$", Resolver);
    }

    /// <summary>
    /// Both gates compare what the artifact carries against the revision they
    /// were told to expect, so a package stamped with the wrong commit fails
    /// verification rather than shipping.
    /// </summary>
    [Fact]
    public void BothVerificationGatesCheckTheEmbeddedRevision()
    {
        foreach (var gate in new[] { VerifyPackageScript, VerifyInstallerScript })
        {
            Assert.Contains("[string] $ExpectedSourceRevision", gate, StringComparison.Ordinal);
            Assert.Contains("Get-UsageBarEmbeddedBuildId", gate, StringComparison.Ordinal);
            Assert.Contains("Get-UsageBarBuildId", gate, StringComparison.Ordinal);
            Assert.Contains("-eq $expectedBuildId", gate, StringComparison.Ordinal);
        }
    }

    // MARK: - What the built assembly reports

    /// <summary>
    /// The end of the chain: the assembly this test runs against reports the
    /// seven-character prefix of the revision the workflow resolved. Everything
    /// above is plumbing; this is the value a physical tester reads back.
    /// </summary>
    [SourceRevisionFact]
    public void TheBuildIdIsThePrefixOfTheSuppliedSourceRevision()
    {
        var revision = Environment.GetEnvironmentVariable("USAGEBAR_SOURCE_REVISION")!.Trim();

        Assert.Matches("^[0-9a-fA-F]{40}$", revision);
        Assert.Equal(revision.ToLowerInvariant()[..7], WindowsEnvironmentInfo.BuildId);
        Assert.NotEqual("unknown", WindowsEnvironmentInfo.BuildId);
    }
}
