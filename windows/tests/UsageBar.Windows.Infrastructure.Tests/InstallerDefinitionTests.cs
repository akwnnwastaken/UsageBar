using System.Text.RegularExpressions;
using UsageBar.Windows.Infrastructure.Startup;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The installer's policy, asserted against its own definition.
///
/// These are the promises a physical tester cannot easily check by eye: that the
/// install stays inside the user profile, that the identity never moves, that
/// the version has exactly one source, and that the installer does not take over
/// anything the application already owns.
/// </summary>
public sealed class InstallerDefinitionTests
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

    private static string InstallerScript => File.ReadAllText(RepositoryFile("windows/installer/UsageBar.iss"));

    private static string PackageScript => File.ReadAllText(RepositoryFile("windows/scripts/package-installer.ps1"));

    private static string BuildProps => File.ReadAllText(RepositoryFile("windows/Directory.Build.props"));

    // MARK: - Identity

    /// <summary>
    /// The AppId is what makes an upgrade an upgrade. If it were regenerated per
    /// build, every installer would add its own entry to Installed Apps.
    /// </summary>
    [Fact]
    public void TheAppIdIsALiteralStableGuid()
    {
        var match = Regex.Match(InstallerScript, @"(?m)^AppId=\{\{([0-9A-Fa-f]{8}-(?:[0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12})\}");

        Assert.True(match.Success, "AppId must be a literal GUID.");
        Assert.True(Guid.TryParse(match.Groups[1].Value, out _));

        // Nothing may compute it at build time.
        Assert.DoesNotContain("AppId={#", InstallerScript, StringComparison.Ordinal);
        Assert.DoesNotContain("CreateGuid", InstallerScript, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The smoke test asserts registry state under the AppId, so the two must
    /// agree or the upgrade check would silently pass against nothing.
    /// </summary>
    [Fact]
    public void TheSmokeTestChecksTheSameAppId()
    {
        var declared = Regex.Match(InstallerScript, @"(?m)^AppId=\{\{([0-9A-Fa-f-]{36})\}").Groups[1].Value;
        var smokeTest = File.ReadAllText(RepositoryFile("windows/scripts/smoke-test-installer.ps1"));

        Assert.Contains(declared, smokeTest, StringComparison.OrdinalIgnoreCase);
    }

    // MARK: - Version

    /// <summary>
    /// One authoritative version source. The installer takes it from the same
    /// MSBuild property that stamps the assemblies, so a release cannot ship an
    /// installer and a binary that disagree.
    /// </summary>
    [Fact]
    public void TheVersionComesFromDirectoryBuildProps()
    {
        Assert.Matches(@"<Version>\s*\d+\.\d+\.\d+\s*</Version>", BuildProps);

        // The packaging script reads it from there...
        Assert.Contains("Directory.Build.props", PackageScript, StringComparison.Ordinal);
        Assert.Contains("<Version>", PackageScript, StringComparison.Ordinal);

        // ...and hands it to the installer, which requires it rather than
        // carrying a copy.
        Assert.Contains("/DAppVersion=$version", PackageScript, StringComparison.Ordinal);
        Assert.Contains("#ifndef AppVersion", InstallerScript, StringComparison.Ordinal);
        Assert.DoesNotMatch(@"(?m)^AppVersion=\d", InstallerScript);
    }

    [Fact]
    public void TheVersionFlowsIntoWindowsFileMetadata()
    {
        foreach (var directive in new[]
                 {
                     "VersionInfoVersion={#AppVersion}",
                     "VersionInfoProductVersion={#AppVersion}",
                     "VersionInfoProductName=",
                     "VersionInfoCompany=",
                     "VersionInfoDescription="
                 })
        {
            Assert.Contains(directive, InstallerScript, StringComparison.Ordinal);
        }
    }

    // MARK: - Scope

    [Fact]
    public void TheInstallIsCurrentUserOnly()
    {
        Assert.Matches(@"(?m)^PrivilegesRequired=lowest\s*$", InstallerScript);
        Assert.Matches(@"(?m)^DefaultDirName=\{localappdata\}\\Programs\\", InstallerScript);

        // Without this directive an elevated or all-users install cannot be
        // selected, by the wizard or from the command line.
        Assert.DoesNotMatch(@"(?m)^PrivilegesRequiredOverridesAllowed=", InstallerScript);
    }

    [Theory]
    [InlineData("HKLM")]
    [InlineData("[Registry]")]
    [InlineData("{pf}")]
    [InlineData("{commonpf")]
    [InlineData("{sys}")]
    [InlineData("ChangesEnvironment")]
    [InlineData("schtasks")]
    [InlineData("{userstartup}")]
    [InlineData("{commonstartup}")]
    public void TheInstallerTouchesNothingOutsideItsOwnFiles(string forbidden)
    {
        Assert.DoesNotContain(forbidden, InstallerScript, StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// The application owns its HKCU Run preference. A second mechanism in the
    /// installer would fight it, and would survive an uninstall.
    /// </summary>
    [Fact]
    public void TheInstallerCreatesNoAutostartOfItsOwn()
    {
        Assert.DoesNotContain(@"CurrentVersion\Run", InstallerScript, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("runonce", InstallerScript, StringComparison.OrdinalIgnoreCase);
    }

    // MARK: - Data preservation

    /// <summary>
    /// Settings and history live beside the install directory, not inside it, so
    /// removing program files cannot remove them. The installer must also delete
    /// nothing of its own accord.
    /// </summary>
    [Fact]
    public void UserDataIsOutsideAnythingTheUninstallerRemoves()
    {
        var storage = File.ReadAllText(
            RepositoryFile("windows/src/UsageBar.Windows.Infrastructure/Storage/UsageBarStorage.cs"));

        // The application stores under %LOCALAPPDATA%\UsageBar...
        Assert.Contains("LocalApplicationData", storage, StringComparison.Ordinal);
        Assert.Contains("\"UsageBar\"", storage, StringComparison.Ordinal);

        // ...and the installer installs to %LOCALAPPDATA%\Programs\UsageBar,
        // a different directory, and deletes nothing recursively.
        Assert.Contains(@"DefaultDirName={localappdata}\Programs\", InstallerScript, StringComparison.Ordinal);
        Assert.DoesNotMatch(@"(?m)^Type:\s*filesandordirs", InstallerScript);
        Assert.DoesNotContain("{localappdata}\\UsageBar\"", InstallerScript, StringComparison.Ordinal);
    }

    // MARK: - Experience

    [Fact]
    public void BothLanguagesAreOffered()
    {
        Assert.Contains("Name: \"en\"; MessagesFile: \"compiler:Default.isl\"", InstallerScript, StringComparison.Ordinal);
        Assert.Contains("Name: \"tr\"; MessagesFile: \"compiler:Languages\\Turkish.isl\"", InstallerScript, StringComparison.Ordinal);

        // And the custom strings exist in both.
        Assert.Contains("en.LaunchAfterInstall=", InstallerScript, StringComparison.Ordinal);
        Assert.Contains("tr.LaunchAfterInstall=", InstallerScript, StringComparison.Ordinal);
        Assert.Contains("tr.CreateDesktopIcon=", InstallerScript, StringComparison.Ordinal);
    }

    [Fact]
    public void ShortcutsFollowTheAgreedDefaults()
    {
        // Start Menu always; desktop optional and off by default.
        Assert.Contains("{autoprograms}\\", InstallerScript, StringComparison.Ordinal);
        Assert.Matches(@"Name:\s*""desktopicon"".*Flags:\s*unchecked", InstallerScript);
        Assert.Matches(@"\{autodesktop\}.*Tasks:\s*desktopicon", InstallerScript);
    }

    /// <summary>
    /// UsageBar has no main window, so the post-install launch must not wait for
    /// one — that would look like a hung installer.
    /// </summary>
    [Fact]
    public void TheLaunchOptionSuitsATrayApplication()
    {
        Assert.Matches(@"\[Run\][\s\S]*Flags:\s*nowait postinstall skipifsilent", InstallerScript);
        Assert.DoesNotContain("runascurrentuser", InstallerScript, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("waituntilterminated", InstallerScript, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void NoLicensePageIsManufactured()
    {
        Assert.Matches(@"(?m)^LicenseFile=\s*$", InstallerScript);
    }

    [Fact]
    public void NoRebootIsEverRequested()
    {
        Assert.Matches(@"(?m)^AlwaysRestart=no\s*$", InstallerScript);
        Assert.Matches(@"(?m)^RestartIfNeededByRun=no\s*$", InstallerScript);
    }

    // MARK: - Running application

    /// <summary>
    /// A running instance is found through the mutex the application creates, not
    /// by process name — a name match could hit something unrelated.
    /// </summary>
    [Fact]
    public void TheRunningApplicationIsDetectedByTheApplicationsOwnMutex()
    {
        Assert.Contains($"AppMutex={SingleInstanceGuard.DefaultName}", InstallerScript, StringComparison.Ordinal);
        Assert.Matches(@"(?m)^CloseApplications=yes\s*$", InstallerScript);

        // Nothing force-kills.
        Assert.DoesNotContain("CloseApplications=force", InstallerScript, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("taskkill", InstallerScript, StringComparison.OrdinalIgnoreCase);
    }

    // MARK: - Artifact

    [Fact]
    public void TheArtifactNameIsDeterministic()
    {
        Assert.Matches(@"(?m)^OutputBaseFilename=UsageBar-Setup-x64\s*$", InstallerScript);
        Assert.Contains("UsageBar-Setup-x64", PackageScript, StringComparison.Ordinal);
    }

    [Fact]
    public void AChecksumIsWrittenBesideTheInstaller()
    {
        Assert.Contains("Get-FileHash", PackageScript, StringComparison.Ordinal);
        Assert.Contains("SHA256", PackageScript, StringComparison.Ordinal);
        Assert.Contains(".sha256", PackageScript, StringComparison.Ordinal);
    }

    /// <summary>
    /// The toolchain is pinned and verified before it runs, rather than pulled
    /// from an unpinned third-party action.
    /// </summary>
    [Fact]
    public void TheInnoSetupToolchainIsPinnedAndChecksummed()
    {
        Assert.Matches(@"\$innoVersion\s*=\s*'6\.\d+\.\d+'", PackageScript);
        Assert.Contains("github.com/jrsoftware/issrc/releases/download/", PackageScript, StringComparison.Ordinal);
        Assert.Matches(@"\$innoSha256\s*=\s*'[0-9a-f]{64}'", PackageScript);

        // The checksum is compared before the downloaded file is executed.
        var checkIndex = PackageScript.IndexOf("checksum mismatch", StringComparison.Ordinal);
        var runIndex = PackageScript.IndexOf("/VERYSILENT", StringComparison.Ordinal);
        Assert.True(checkIndex > 0 && runIndex > checkIndex, "The checksum must be verified before execution.");
    }

    /// <summary>
    /// The installer must ship the payload the portable gate already verified,
    /// so the two builds cannot drift.
    /// </summary>
    [Fact]
    public void TheInstallerShipsTheVerifiedPortablePayload()
    {
        Assert.Contains("staging\\UsageBar", PackageScript, StringComparison.Ordinal);
        Assert.Contains("Run scripts/package.ps1 first", PackageScript, StringComparison.Ordinal);
        Assert.Contains("Source: \"{#PayloadDir}\\*\"", InstallerScript, StringComparison.Ordinal);
    }

    // MARK: - Boundary

    /// <summary>
    /// Nothing in the installer may reach outside the Windows tree — least of all
    /// into the macOS application.
    /// </summary>
    [Theory]
    [InlineData("Sources/")]
    [InlineData("Package.swift")]
    [InlineData("build.sh")]
    [InlineData("Info.plist")]
    [InlineData(".icns")]
    [InlineData("UsageBar.app")]
    public void TheInstallerNeverReferencesMacOsFiles(string forbidden)
    {
        Assert.DoesNotContain(forbidden, InstallerScript, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain(forbidden, PackageScript, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void TheApplicationIconIsAWindowsIcoNotAMacOsBundleIcon()
    {
        var icon = RepositoryFile("windows/installer/UsageBar.ico");
        var bytes = File.ReadAllBytes(icon);

        // ICO header: reserved 0, type 1, then the image count.
        Assert.True(bytes.Length > 6);
        Assert.Equal(0, bytes[0]);
        Assert.Equal(0, bytes[1]);
        Assert.Equal(1, bytes[2]);
        Assert.Equal(0, bytes[3]);
        Assert.True(BitConverter.ToUInt16(bytes, 4) >= 4, "The icon should carry several sizes.");

        Assert.Contains("SetupIconFile=", InstallerScript, StringComparison.Ordinal);
    }
}
