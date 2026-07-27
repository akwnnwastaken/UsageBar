using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using UsageBar.Windows.Core.Diagnostics;

namespace UsageBar.Windows.Infrastructure.Diagnostics;

/// <summary>
/// Reports what kind of process started UsageBar — an installer, the shell, or
/// something else.
///
/// This exists because physical testing showed provider discovery behaving
/// differently depending on how UsageBar was launched. Knowing which context a
/// diagnostics report came from turns "it works from the Start Menu" into
/// something a report can state.
///
/// Only the classification is ever exposed. The parent's executable name, path
/// and process id stay inside this type.
/// </summary>
[SupportedOSPlatform("windows")]
public static class ProcessParentInspector
{
    /// <summary>Names that mean "an installer started us".</summary>
    private static readonly string[] SetupNames = { "setup", "install", "unins" };

    private static readonly string[] ShellNames = { "explorer.exe" };

    public static ProcessParentKind Classify()
    {
        var name = ParentExecutableName();
        if (name is null)
        {
            return ProcessParentKind.Unknown;
        }

        var lower = name.ToLowerInvariant();

        if (ShellNames.Contains(lower, StringComparer.Ordinal))
        {
            return ProcessParentKind.Shell;
        }

        return SetupNames.Any(marker => lower.Contains(marker, StringComparison.Ordinal))
            ? ProcessParentKind.Setup
            : ProcessParentKind.Other;
    }

    /// <summary>
    /// The parent's file name, or null when it cannot be determined — a parent
    /// that has already exited is normal and not an error.
    /// </summary>
    private static string? ParentExecutableName()
    {
        var snapshot = IntPtr.Zero;
        try
        {
            snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
            if (snapshot == InvalidHandle)
            {
                return null;
            }

            var entry = new PROCESSENTRY32W { dwSize = Marshal.SizeOf<PROCESSENTRY32W>() };
            if (!Process32FirstW(snapshot, ref entry))
            {
                return null;
            }

            var currentId = Environment.ProcessId;
            var parentId = 0;
            var names = new Dictionary<int, string>();

            do
            {
                names[(int)entry.th32ProcessID] = entry.szExeFile;
                if ((int)entry.th32ProcessID == currentId)
                {
                    parentId = (int)entry.th32ParentProcessID;
                }
            }
            while (Process32NextW(snapshot, ref entry));

            return parentId != 0 && names.TryGetValue(parentId, out var name) ? name : null;
        }
        catch (Exception exception) when (
            exception is DllNotFoundException or EntryPointNotFoundException or ExternalException)
        {
            return null;
        }
        finally
        {
            if (snapshot != IntPtr.Zero && snapshot != InvalidHandle)
            {
                CloseHandle(snapshot);
            }
        }
    }

    private const uint TH32CS_SNAPPROCESS = 0x00000002;

    private static readonly IntPtr InvalidHandle = new(-1);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32W
    {
        public int dwSize;
        public uint cntUsage;
        public uint th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID;
        public uint cntThreads;
        public uint th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string szExeFile;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint dwFlags, uint th32ProcessID);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32FirstW(IntPtr hSnapshot, ref PROCESSENTRY32W lppe);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32NextW(IntPtr hSnapshot, ref PROCESSENTRY32W lppe);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);
}
