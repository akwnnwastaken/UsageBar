using System.Globalization;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace UsageBar.Windows.Infrastructure.Diagnostics;

/// <summary>
/// The few environment facts diagnostics is allowed to report.
///
/// Deliberately narrow: a version number and two architecture names. No machine
/// name, no user name, no install paths, no locale-specific product string
/// (<c>RuntimeInformation.OSDescription</c> contains spaces and marketing text
/// and is not used).
/// </summary>
[SupportedOSPlatform("windows")]
public static class WindowsEnvironmentInfo
{
    /// <summary>Dotted build number, e.g. <c>10.0.22631.0</c>.</summary>
    public static string Version => Environment.OSVersion.Version.ToString();

    public static string OsArchitecture =>
        RuntimeInformation.OSArchitecture.ToString().ToLowerInvariant();

    public static string ProcessArchitecture =>
        RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant();

    /// <summary>
    /// True on Windows 10 1809 or newer, the oldest release UsageBar targets.
    /// </summary>
    public static bool IsSupportedWindowsVersion =>
        OperatingSystem.IsWindowsVersionAtLeast(10, 0, 17763);

    /// <summary>The application version shown in the panel and in diagnostics.</summary>
    public static string ApplicationVersion
    {
        get
        {
            var version = typeof(WindowsEnvironmentInfo).Assembly.GetName().Version;
            return version is null
                ? "0.0.0"
                : string.Create(
                    CultureInfo.InvariantCulture,
                    $"{version.Major}.{version.Minor}.{version.Build}");
        }
    }

    /// <summary>
    /// The UI languages Windows reports, most preferred first. Used only to
    /// choose Turkish or English.
    /// </summary>
    public static IReadOnlyList<string> PreferredLanguages =>
        new[] { CultureInfo.CurrentUICulture.Name };
}
