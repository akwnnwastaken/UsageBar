using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Infrastructure.Storage;

namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>
/// Keeps provider CLIs away from the folder UsageBar was launched from and from
/// the user's own environment.
///
/// Claude Code and Codex normally discover project files, hooks, MCP servers and
/// integrations from their working directory, and pick up configuration from
/// environment variables. A quota check needs none of that — only the existing
/// local login — so every provider runs from a private application-owned
/// directory with a deliberately small environment.
/// </summary>
[SupportedOSPlatform("windows")]
public static class ProviderProcessEnvironment
{
    /// <summary>
    /// Environment variables a provider is allowed to inherit. Everything else
    /// (project paths, proxies, API keys, tool configuration, PowerShell state)
    /// is dropped.
    /// </summary>
    private static readonly string[] InheritedVariables =
    {
        "SystemRoot",
        "SystemDrive",
        "windir",
        "COMSPEC",
        "PATHEXT",
        "NUMBER_OF_PROCESSORS",
        "PROCESSOR_ARCHITECTURE",
        "USERNAME",
        "USERPROFILE",
        "HOMEDRIVE",
        "HOMEPATH",
        "APPDATA",
        "LOCALAPPDATA",
        "ProgramData",
        "ProgramFiles",
        "ProgramFiles(x86)",
        "LANG",
        "LC_ALL"
    };

    /// <summary>
    /// The private working directory. Created under the application's own local
    /// data folder so it never coincides with a user project.
    /// </summary>
    public static string WorkingDirectory { get; } = CreateWorkingDirectory();

    /// <summary>
    /// Builds the restricted environment. PATH is rebuilt from system locations
    /// only, so a provider cannot be resolved through a directory the user (or a
    /// project) prepended to their own PATH.
    /// </summary>
    public static IReadOnlyDictionary<string, string> Build(
        IReadOnlyDictionary<string, string>? additionalVariables = null)
    {
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        foreach (var name in InheritedVariables)
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrEmpty(value))
            {
                environment[name] = value;
            }
        }

        var systemRoot = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
        environment["PATH"] = string.Join(
            ';',
            Path.Combine(systemRoot, "system32"),
            systemRoot,
            Path.Combine(systemRoot, "system32", "Wbem"),
            Path.Combine(systemRoot, "system32", "WindowsPowerShell", "v1.0"));

        environment["TEMP"] = WorkingDirectory;
        environment["TMP"] = WorkingDirectory;

        if (additionalVariables is not null)
        {
            foreach (var (name, value) in additionalVariables)
            {
                environment[name] = value;
            }
        }

        return environment;
    }

    /// <summary>
    /// Encodes an environment block for CREATE_UNICODE_ENVIRONMENT: NAME=VALUE
    /// pairs separated by NUL and terminated by a double NUL, sorted
    /// case-insensitively as Windows expects.
    /// </summary>
    public static char[] ToEnvironmentBlock(IReadOnlyDictionary<string, string> environment)
    {
        ArgumentNullException.ThrowIfNull(environment);

        var builder = new StringBuilder();
        foreach (var entry in environment.OrderBy(entry => entry.Key, StringComparer.OrdinalIgnoreCase))
        {
            if (entry.Key.Length == 0 || entry.Key.Contains('=', StringComparison.Ordinal))
            {
                continue;
            }

            builder.Append(entry.Key).Append('=').Append(entry.Value).Append('\0');
        }

        builder.Append('\0');
        return builder.ToString().ToCharArray();
    }

    /// <summary>
    /// The directory a provider is started in. It is resolved rather than
    /// assembled from a possibly empty folder path, so it can never come out
    /// relative — a relative working directory would put it beside whatever
    /// process started UsageBar.
    /// </summary>
    private static string CreateWorkingDirectory()
    {
        try
        {
            var directory = Path.Combine(
                UsageBarStorage.DefaultRootDirectory(),
                "provider-run");
            Directory.CreateDirectory(directory);
            return directory;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            var fallback = Path.Combine(Path.GetTempPath(), "UsageBar", "provider-run");
            Directory.CreateDirectory(fallback);
            return fallback;
        }
    }
}
