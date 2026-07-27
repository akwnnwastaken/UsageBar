using System.Runtime.Versioning;
using Microsoft.Win32;

namespace UsageBar.Windows.Infrastructure.Startup;

public enum AutoStartStatus
{
    /// <summary>No UsageBar entry exists.</summary>
    Disabled,

    /// <summary>An entry exists and points at this executable.</summary>
    Enabled,

    /// <summary>An entry exists but points somewhere else — a moved or stale copy.</summary>
    EnabledForDifferentPath,

    /// <summary>The setting could not be read, e.g. because policy blocks it.</summary>
    Unavailable
}

public sealed record AutoStartState(AutoStartStatus Status, bool LastOperationFailed = false)
{
    public bool IsOn => Status is AutoStartStatus.Enabled or AutoStartStatus.EnabledForDifferentPath;
}

/// <summary>
/// Starting UsageBar with Windows. Kept behind an interface so the portable ZIP
/// build's registry Run entry can later be swapped for an MSIX StartupTask
/// without touching the UI.
/// </summary>
public interface IAutoStartService
{
    AutoStartState GetState();

    AutoStartState Enable();

    AutoStartState Disable();
}

/// <summary>
/// Current-user auto-start through
/// <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c>.
///
/// This never needs administrator rights, never writes outside the current
/// user's hive, and only ever touches UsageBar's own value — an unrelated
/// startup entry is never read, rewritten or removed.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class RegistryAutoStartService : IAutoStartService
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private const string ValueName = "UsageBar";

    private readonly string _executablePath;

    public RegistryAutoStartService(string? executablePath = null) =>
        _executablePath = executablePath ?? ResolveExecutablePath();

    /// <summary>The quoted command line Windows will run at sign-in.</summary>
    internal string CommandLine => Quote(_executablePath);

    public AutoStartState GetState()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            var value = key?.GetValue(ValueName) as string;
            if (string.IsNullOrWhiteSpace(value))
            {
                return new AutoStartState(AutoStartStatus.Disabled);
            }

            return new AutoStartState(
                PointsAtThisExecutable(value)
                    ? AutoStartStatus.Enabled
                    : AutoStartStatus.EnabledForDifferentPath);
        }
        catch (Exception exception) when (
            exception is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return new AutoStartState(AutoStartStatus.Unavailable);
        }
    }

    public AutoStartState Enable()
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true);
            if (key is null)
            {
                return new AutoStartState(AutoStartStatus.Unavailable, LastOperationFailed: true);
            }

            key.SetValue(ValueName, CommandLine, RegistryValueKind.String);
            return GetState();
        }
        catch (Exception exception) when (
            exception is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return new AutoStartState(AutoStartStatus.Unavailable, LastOperationFailed: true);
        }
    }

    public AutoStartState Disable()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            if (key is null)
            {
                return new AutoStartState(AutoStartStatus.Disabled);
            }

            // Only UsageBar's own value is removed, and only if it is there.
            if (key.GetValue(ValueName) is not null)
            {
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            }

            return GetState();
        }
        catch (Exception exception) when (
            exception is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return new AutoStartState(AutoStartStatus.Unavailable, LastOperationFailed: true);
        }
    }

    /// <summary>
    /// Compares a stored command line with this executable. The stored value may
    /// or may not be quoted and may carry arguments, so only the leading program
    /// path is compared.
    /// </summary>
    internal bool PointsAtThisExecutable(string storedValue) =>
        string.Equals(
            NormalizePath(ExtractProgramPath(storedValue)),
            NormalizePath(_executablePath),
            StringComparison.OrdinalIgnoreCase);

    internal static string ExtractProgramPath(string commandLine)
    {
        var trimmed = commandLine.Trim();
        if (trimmed.StartsWith('"'))
        {
            var closing = trimmed.IndexOf('"', 1);
            return closing > 0 ? trimmed[1..closing] : trimmed[1..];
        }

        var space = trimmed.IndexOf(' ');
        return space > 0 ? trimmed[..space] : trimmed;
    }

    private static string NormalizePath(string path)
    {
        try
        {
            return Path.GetFullPath(path.Trim()).TrimEnd(Path.DirectorySeparatorChar);
        }
        catch (Exception exception) when (
            exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return path.Trim();
        }
    }

    private static string Quote(string path) => $"\"{path}\"";

    private static string ResolveExecutablePath()
    {
        // The published app is an .exe; Environment.ProcessPath points at it.
        // The fallback keeps this usable when hosted (for example under a test
        // runner), where ProcessPath is the host rather than UsageBar.
        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath) &&
            Path.GetExtension(processPath).Equals(".exe", StringComparison.OrdinalIgnoreCase))
        {
            return processPath;
        }

        var candidate = Path.Combine(AppContext.BaseDirectory, "UsageBar.Windows.App.exe");
        return File.Exists(candidate) ? candidate : processPath ?? candidate;
    }
}
