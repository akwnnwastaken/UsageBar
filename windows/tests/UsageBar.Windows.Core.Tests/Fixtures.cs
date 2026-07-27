namespace UsageBar.Windows.Core.Tests;

/// <summary>
/// Loads the shared provider fixtures copied next to the test assembly from
/// <c>shared/fixtures</c>.
/// </summary>
internal static class Fixtures
{
    public static string ReadText(string relativePath) =>
        File.ReadAllText(Path(relativePath));

    public static byte[] ReadBytes(string relativePath) =>
        File.ReadAllBytes(Path(relativePath));

    /// <summary>Resolves a fixture to a fully native path, separators normalized.</summary>
    public static string Path(string relativePath)
    {
        var segments = relativePath.Split('/', '\\', StringSplitOptions.RemoveEmptyEntries);

        var candidate = System.IO.Path.Combine(
            new[] { AppContext.BaseDirectory, "fixtures" }.Concat(segments).ToArray());
        if (File.Exists(candidate))
        {
            return System.IO.Path.GetFullPath(candidate);
        }

        // Fall back to the repository layout so the tests also run from a plain
        // `dotnet test` in a source checkout without a prior copy step.
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
