using System.Text.Json;

namespace UsageBar.Windows.Infrastructure.Storage;

/// <summary>
/// Reads and writes small JSON documents so a crash or a power loss can never
/// leave a half-written file behind.
///
/// A write goes to a temporary file first, is flushed all the way to disk, and
/// only then replaces the real file in one operation. A read that finds
/// anything unusable — missing, truncated, malformed, oversized — reports
/// "nothing stored" rather than throwing: UsageBar must always start.
/// </summary>
public static class AtomicJsonFile
{
    /// <summary>Anything larger than this is treated as corrupt and ignored.</summary>
    public const int MaximumBytes = 4 * 1024 * 1024;

    public static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true,
        AllowTrailingCommas = true,
        ReadCommentHandling = JsonCommentHandling.Skip
    };

    public static T? Read<T>(string path)
        where T : class
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.Length == 0 || info.Length > MaximumBytes)
            {
                return null;
            }

            using var stream = new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete);
            return JsonSerializer.Deserialize<T>(stream, Options);
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or JsonException
                or NotSupportedException
                or System.Security.SecurityException)
        {
            return null;
        }
    }

    /// <summary>Returns false when the value could not be persisted.</summary>
    public static bool Write<T>(string path, T value)
    {
        var temporaryPath = path + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.Create,
                       FileAccess.Write,
                       FileShare.None))
            {
                JsonSerializer.Serialize(stream, value, Options);
                stream.Flush(flushToDisk: true);
            }

            // Replace preserves the original file's ACLs; Move covers the
            // first write, when there is nothing to replace yet.
            if (File.Exists(path))
            {
                File.Replace(temporaryPath, path, destinationBackupFileName: null);
            }
            else
            {
                File.Move(temporaryPath, path);
            }

            return true;
        }
        catch (Exception exception) when (
            exception is IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or System.Security.SecurityException)
        {
            TryDelete(temporaryPath);
            return false;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
        }
    }
}
