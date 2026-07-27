using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Discovery;

/// <summary>
/// Validates a provider executable before it is ever started.
///
/// The Windows rules mirror the macOS ones: resolve the real target, require a
/// regular file inside an expected installation root, require a directly
/// executable file type, and refuse anything a broader group than the current
/// user can overwrite. The current working directory and the user's PATH are
/// never consulted — every candidate is an explicit, documented location.
/// </summary>
[SupportedOSPlatform("windows")]
public static class ExecutableTrust
{
    /// <summary>File types Windows can start directly, without any interpreter.</summary>
    private static readonly string[] NativeExtensions = { ".exe", ".com" };

    /// <summary>
    /// File types that only run through a shell. They are never executed as-is;
    /// the caller must resolve the underlying interpreter and script instead.
    /// </summary>
    private static readonly string[] ShellOnlyExtensions = { ".cmd", ".bat", ".ps1", ".psm1", ".vbs", ".js" };

    /// <summary>
    /// Well-known identities that must not have write access to a trusted
    /// executable. The current user and the administrative identities are
    /// deliberately allowed: a per-user install under %LOCALAPPDATA% is
    /// legitimate, exactly as an owner-writable file is on macOS.
    /// </summary>
    private static readonly WellKnownSidType[] ForbiddenWriters =
    {
        WellKnownSidType.WorldSid,
        WellKnownSidType.BuiltinUsersSid,
        WellKnownSidType.AuthenticatedUserSid,
        WellKnownSidType.InteractiveSid,
        WellKnownSidType.BuiltinGuestsSid,
        WellKnownSidType.AnonymousSid
    };

    private const FileSystemRights WriteRights =
        FileSystemRights.WriteData |
        FileSystemRights.AppendData |
        FileSystemRights.Write |
        FileSystemRights.Modify |
        FileSystemRights.FullControl |
        FileSystemRights.TakeOwnership |
        FileSystemRights.ChangePermissions;

    /// <summary>
    /// Validates a candidate. Returns null when the file does not exist so the
    /// caller can distinguish "missing" from "found but rejected".
    /// </summary>
    public static ExecutableLookup? Validate(
        string candidatePath,
        string allowedRoot,
        ProviderAdapterKind adapterKind = ProviderAdapterKind.NativeExecutable)
    {
        if (string.IsNullOrWhiteSpace(candidatePath))
        {
            return null;
        }

        string fullPath;
        string fullRoot;
        try
        {
            fullPath = System.IO.Path.GetFullPath(candidatePath);
            fullRoot = System.IO.Path.GetFullPath(allowedRoot);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return ExecutableLookup.Untrusted;
        }

        if (Directory.Exists(fullPath))
        {
            return ExecutableLookup.Untrusted;
        }

        if (!File.Exists(fullPath))
        {
            return null;
        }

        var resolvedPath = ResolveFinalTarget(fullPath);
        if (resolvedPath is null)
        {
            return ExecutableLookup.Untrusted;
        }

        if (!IsInside(resolvedPath, fullRoot))
        {
            return ExecutableLookup.Untrusted;
        }

        var extension = System.IO.Path.GetExtension(resolvedPath);
        if (ShellOnlyExtensions.Contains(extension, StringComparer.OrdinalIgnoreCase))
        {
            return ExecutableLookup.UnsupportedInstallation;
        }

        if (!NativeExtensions.Contains(extension, StringComparer.OrdinalIgnoreCase))
        {
            return ExecutableLookup.Untrusted;
        }

        if (IsWritableByOthers(resolvedPath))
        {
            return ExecutableLookup.Untrusted;
        }

        return ExecutableLookup.Found(
            new ResolvedExecutable(resolvedPath, Array.Empty<string>(), adapterKind));
    }

    /// <summary>
    /// Validates a data file (a launcher script) that will be handed to a
    /// separately validated interpreter. The file itself is never executed.
    /// </summary>
    public static bool IsTrustedScript(string scriptPath, string allowedRoot)
    {
        if (string.IsNullOrWhiteSpace(scriptPath) || !File.Exists(scriptPath))
        {
            return false;
        }

        try
        {
            var resolved = ResolveFinalTarget(System.IO.Path.GetFullPath(scriptPath));
            return resolved is not null &&
                   IsInside(resolved, System.IO.Path.GetFullPath(allowedRoot)) &&
                   !IsWritableByOthers(resolved);
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false;
        }
    }

    /// <summary>Follows symbolic links and junctions to the real file.</summary>
    private static string? ResolveFinalTarget(string path)
    {
        try
        {
            var info = new FileInfo(path);
            var target = info.ResolveLinkTarget(returnFinalTarget: true);
            var resolved = target?.FullName ?? info.FullName;
            return File.Exists(resolved) ? resolved : null;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            return null;
        }
    }

    private static bool IsInside(string path, string root)
    {
        var normalizedRoot = root.TrimEnd(
            System.IO.Path.DirectorySeparatorChar,
            System.IO.Path.AltDirectorySeparatorChar);

        return path.Equals(normalizedRoot, StringComparison.OrdinalIgnoreCase) ||
               path.StartsWith(
                   normalizedRoot + System.IO.Path.DirectorySeparatorChar,
                   StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>
    /// True when a group broader than the current user can modify the file. A
    /// machine whose ACLs cannot be read at all is not treated as hostile — the
    /// path and file-type checks still apply.
    /// </summary>
    private static bool IsWritableByOthers(string path)
    {
        try
        {
            var security = new FileInfo(path).GetAccessControl(AccessControlSections.Access);
            var rules = security.GetAccessRules(
                includeExplicit: true,
                includeInherited: true,
                typeof(SecurityIdentifier));

            foreach (FileSystemAccessRule rule in rules)
            {
                if (rule.AccessControlType != AccessControlType.Allow ||
                    (rule.FileSystemRights & WriteRights) == 0)
                {
                    continue;
                }

                if (rule.IdentityReference is SecurityIdentifier identity &&
                    ForbiddenWriters.Any(identity.IsWellKnown))
                {
                    return true;
                }
            }

            return false;
        }
        catch (Exception exception) when (
            exception is UnauthorizedAccessException
                or PrivilegeNotHeldException
                or IOException
                or PlatformNotSupportedException
                or NotSupportedException)
        {
            return false;
        }
    }
}
