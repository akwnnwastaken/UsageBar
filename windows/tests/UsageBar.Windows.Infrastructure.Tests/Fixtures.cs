namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Loads the shared provider fixtures copied next to the test assembly from
/// <c>shared/fixtures</c>.
/// </summary>
internal static class Fixtures
{
    public static string ReadText(string relativePath) => File.ReadAllText(Path(relativePath));

    public static byte[] ReadBytes(string relativePath) => File.ReadAllBytes(Path(relativePath));

    /// <summary>
    /// Resolves a fixture to a fully native path. The separators are normalized
    /// on purpose: .NET accepts a mixed path like <c>...\fixtures\codex/a.jsonl</c>,
    /// but a Windows command-line tool reads the <c>/a.jsonl</c> part as a switch,
    /// so any fixture path handed to a child process must use backslashes only.
    /// </summary>
    public static string Path(string relativePath)
    {
        var segments = relativePath.Split('/', '\\', StringSplitOptions.RemoveEmptyEntries);

        var candidate = System.IO.Path.Combine(
            new[] { AppContext.BaseDirectory, "fixtures" }.Concat(segments).ToArray());
        if (File.Exists(candidate))
        {
            return System.IO.Path.GetFullPath(candidate);
        }

        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var shared = System.IO.Path.Combine(
                new[] { directory.FullName, "shared", "fixtures" }.Concat(segments).ToArray());
            if (File.Exists(shared))
            {
                return System.IO.Path.GetFullPath(shared);
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Fixture not found: {relativePath}", candidate);
    }
}
