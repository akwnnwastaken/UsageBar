using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace UsageBar.Windows.Infrastructure.Discovery;

public enum WindowsKnownFolder
{
    LocalApplicationData,
    UserProfile,
    RoamingApplicationData,
    ProgramFiles
}

/// <summary>
/// Supplies the user's known-folder roots that provider discovery builds
/// candidate paths from.
/// </summary>
public interface IKnownFolderResolver
{
    /// <summary>
    /// Every distinct, existing root this folder resolves to, best source
    /// first. Empty when the folder cannot be resolved at all.
    /// </summary>
    IReadOnlyList<string> Resolve(WindowsKnownFolder folder);

    /// <summary>
    /// The same resolution with the source identities kept, for diagnostics.
    /// Discovery uses <see cref="KnownFolderSources.Roots"/> and nothing else, so
    /// this cannot change which candidates are tried.
    ///
    /// Implementations that only know roots fall back to attributing them in the
    /// best-source-first order this interface already promises.
    /// </summary>
    KnownFolderSources ResolveSources(WindowsKnownFolder folder) =>
        KnownFolderSources.FromRoots(Resolve(folder));
}

/// <summary>
/// Resolves known folders through the shell first, and only then through
/// <see cref="Environment.GetFolderPath"/>.
///
/// Physical testing showed Codex being found when UsageBar was launched from the
/// Start Menu and not found when Setup launched it, on the same files. The
/// official Codex candidate is built from Local AppData, so a context where that
/// folder resolves to nothing would explain it exactly: the candidate is never
/// constructed, and the provider looks absent rather than untrusted.
///
/// Asking the shell directly removes that dependency on one API in one context.
/// Both sources are validated the same way — fully qualified and actually
/// present — and the results are de-duplicated, so a candidate is tried once
/// however many sources agree on it.
///
/// The <c>LOCALAPPDATA</c> environment variable is deliberately not a source:
/// it is inherited, so a parent process could point discovery anywhere. Trust
/// comes from the shell or the framework, never from an inherited string.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WindowsKnownFolderResolver : IKnownFolderResolver
{
    private static readonly Guid LocalAppDataId = new("F1B32785-6FBA-4FCF-9D55-7B8E7F157091");
    private static readonly Guid ProfileId = new("5E6C858F-0E22-4760-9AFE-EA3317B67173");
    private static readonly Guid RoamingAppDataId = new("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D");
    private static readonly Guid ProgramFilesId = new("905E63B6-C1BF-494E-B29C-65B732D3D21A");

    private readonly Func<WindowsKnownFolder, string?> _shell;
    private readonly Func<WindowsKnownFolder, string?> _framework;
    private readonly Func<string, bool> _directoryExists;

    public WindowsKnownFolderResolver()
        : this(FromShell, FromFramework, Directory.Exists)
    {
    }

    internal WindowsKnownFolderResolver(
        Func<WindowsKnownFolder, string?> shell,
        Func<WindowsKnownFolder, string?> framework,
        Func<string, bool>? directoryExists = null)
    {
        _shell = shell;
        _framework = framework;
        _directoryExists = directoryExists ?? Directory.Exists;
    }

    /// <summary>
    /// Resolved on every call. Nothing is cached, so a folder that could not be
    /// resolved once is never treated as permanently absent — a later refresh
    /// simply asks again.
    /// </summary>
    public IReadOnlyList<string> Resolve(WindowsKnownFolder folder) => ResolveSources(folder).Roots;

    /// <summary>
    /// The same resolution, with what each source individually returned kept
    /// beside the de-duplicated result. Discovery reads only the roots; the
    /// source identities exist so a diagnostic summary can say which source is
    /// responsible when a context resolves the folder to the wrong place.
    /// </summary>
    public KnownFolderSources ResolveSources(WindowsKnownFolder folder)
    {
        var shell = Ask(_shell, folder);
        var framework = Ask(_framework, folder);

        var roots = new List<string>(2);
        foreach (var source in new[] { shell, framework })
        {
            if (source.Root is { } root && !roots.Contains(root, StringComparer.OrdinalIgnoreCase))
            {
                roots.Add(root);
            }
        }

        return new KnownFolderSources(shell, framework, roots);
    }

    private KnownFolderSourceResult Ask(Func<WindowsKnownFolder, string?> source, WindowsKnownFolder folder)
    {
        string? candidate;
        try
        {
            candidate = source(folder);
        }
        catch (Exception exception) when (
            exception is InvalidOperationException or PlatformNotSupportedException or ExternalException)
        {
            return KnownFolderSourceResult.Silent;
        }

        if (string.IsNullOrWhiteSpace(candidate))
        {
            return KnownFolderSourceResult.Silent;
        }

        // The source named something. Whether that something survives validation
        // is a different fact, and one worth being able to report.
        return Normalize(candidate) is { } normalized
            ? KnownFolderSourceResult.Accepted(normalized)
            : KnownFolderSourceResult.Rejected;
    }

    /// <summary>A root only counts when it is fully qualified and really there.</summary>
    private string? Normalize(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        try
        {
            var full = Path.GetFullPath(path.Trim());
            if (!Path.IsPathFullyQualified(full) || !_directoryExists(full))
            {
                return null;
            }

            return full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
        catch (Exception exception) when (
            exception is ArgumentException or NotSupportedException or PathTooLongException or IOException)
        {
            return null;
        }
    }

    private static string? FromShell(WindowsKnownFolder folder)
    {
        var id = folder switch
        {
            WindowsKnownFolder.UserProfile => ProfileId,
            WindowsKnownFolder.RoamingApplicationData => RoamingAppDataId,
            WindowsKnownFolder.ProgramFiles => ProgramFilesId,
            _ => LocalAppDataId
        };

        var pointer = IntPtr.Zero;
        try
        {
            // KF_FLAG_DEFAULT, current user's token.
            if (SHGetKnownFolderPath(ref id, 0, IntPtr.Zero, out pointer) != 0)
            {
                return null;
            }

            return pointer == IntPtr.Zero ? null : Marshal.PtrToStringUni(pointer);
        }
        catch (DllNotFoundException)
        {
            return null;
        }
        catch (EntryPointNotFoundException)
        {
            return null;
        }
        finally
        {
            if (pointer != IntPtr.Zero)
            {
                CoTaskMemFree(pointer);
            }
        }
    }

    private static string? FromFramework(WindowsKnownFolder folder) => folder switch
    {
        WindowsKnownFolder.UserProfile => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
        WindowsKnownFolder.RoamingApplicationData =>
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        WindowsKnownFolder.ProgramFiles => Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
        _ => Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)
    };

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    private static extern int SHGetKnownFolderPath(
        ref Guid rfid,
        uint dwFlags,
        IntPtr hToken,
        out IntPtr ppszPath);

    [DllImport("ole32.dll", ExactSpelling = true)]
    private static extern void CoTaskMemFree(IntPtr pv);
}

/// <summary>Resolver factories, including the ones the tests drive.</summary>
public static class KnownFolderResolvers
{
    /// <summary>A resolver that returns exactly what it is given, in order.</summary>
    public static IKnownFolderResolver FromRoots(
        IReadOnlyDictionary<WindowsKnownFolder, IReadOnlyList<string>> roots) =>
        new FixedResolver(roots);

    private sealed class FixedResolver : IKnownFolderResolver
    {
        private readonly IReadOnlyDictionary<WindowsKnownFolder, IReadOnlyList<string>> _roots;

        public FixedResolver(IReadOnlyDictionary<WindowsKnownFolder, IReadOnlyList<string>> roots) =>
            _roots = roots;

        public IReadOnlyList<string> Resolve(WindowsKnownFolder folder) =>
            _roots.TryGetValue(folder, out var roots) ? roots : Array.Empty<string>();
    }
}

/// <summary>
/// Adapts the older special-folder/environment callbacks the discovery tests
/// use onto the resolver interface, so those tests keep exercising the same
/// candidate construction the shell path does.
/// </summary>
internal static class LegacyResolver
{
    public static IKnownFolderResolver From(
        Func<Environment.SpecialFolder, string> specialFolder,
        Func<string, string?> environmentVariable)
    {
        return KnownFolderResolvers.FromRoots(new Dictionary<WindowsKnownFolder, IReadOnlyList<string>>
        {
            [WindowsKnownFolder.LocalApplicationData] =
                Single(specialFolder(Environment.SpecialFolder.LocalApplicationData)),
            [WindowsKnownFolder.UserProfile] =
                Single(specialFolder(Environment.SpecialFolder.UserProfile)),
            [WindowsKnownFolder.ProgramFiles] =
                Single(specialFolder(Environment.SpecialFolder.ProgramFiles)),
            [WindowsKnownFolder.RoamingApplicationData] = Single(environmentVariable("APPDATA"))
        });
    }

    private static IReadOnlyList<string> Single(string? root) =>
        string.IsNullOrWhiteSpace(root) ? Array.Empty<string>() : new[] { root };
}
