namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// Loads the shared provider fixtures copied next to the test assembly from
/// <c>shared/fixtures</c>.
/// </summary>
internal static class Fixtures
{
    public static string ReadText(string relativePath) => File.ReadAllText(Path(relativePath));

    public static byte[] ReadBytes(string relativePath) => File.ReadAllBytes(Path(relativePath));

    public static string Path(string relativePath)
    {
        var candidate = System.IO.Path.Combine(AppContext.BaseDirectory, "fixtures", relativePath);
        if (File.Exists(candidate))
        {
            return candidate;
        }

        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var shared = System.IO.Path.Combine(directory.FullName, "shared", "fixtures", relativePath);
            if (File.Exists(shared))
            {
                return shared;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Fixture not found: {relativePath}", candidate);
    }
}
