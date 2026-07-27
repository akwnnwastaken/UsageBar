using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// A test that needs a real Windows kernel (Job Objects, CreateProcessW, ACLs).
/// It is skipped rather than failed elsewhere, so the same suite can be compiled
/// and partially run on a developer machine while the full set runs on Windows
/// CI. Skipped tests are reported as skipped — never as passed.
/// </summary>
public sealed class WindowsFactAttribute : FactAttribute
{
    public WindowsFactAttribute()
    {
        if (!OperatingSystem.IsWindows())
        {
            Skip = "Requires Windows: this test exercises Win32 process containment.";
        }
    }
}

/// <summary>Theory counterpart of <see cref="WindowsFactAttribute"/>.</summary>
public sealed class WindowsTheoryAttribute : TheoryAttribute
{
    public WindowsTheoryAttribute()
    {
        if (!OperatingSystem.IsWindows())
        {
            Skip = "Requires Windows: this test exercises Win32 process containment.";
        }
    }
}
