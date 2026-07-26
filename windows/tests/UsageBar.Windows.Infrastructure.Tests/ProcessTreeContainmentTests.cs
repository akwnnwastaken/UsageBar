using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Infrastructure.Process;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

/// <summary>
/// The containment guarantee: closing the Job Object terminates the process
/// UsageBar started <b>and</b> everything it spawned.
///
/// The helper parent below is started through PowerShell purely because it is a
/// convenient way to create a real two-level process tree and report the child's
/// process id. Providers themselves are never launched through a shell — see
/// <see cref="ProviderProcessLauncher"/>.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class ProcessTreeContainmentTests
{
    private static string SystemDirectory =>
        Environment.GetFolderPath(Environment.SpecialFolder.System);

    private static string PowerShellPath =>
        Path.Combine(SystemDirectory, "WindowsPowerShell", "v1.0", "powershell.exe");

    private static string PingPath => Path.Combine(SystemDirectory, "PING.EXE");

    /// <summary>
    /// Starts a parent that spawns a long-running child and prints the child's
    /// process id, so the test can assert on both by id rather than by name.
    /// </summary>
    private static ProviderProcessRequest ParentSpawningChildRequest() => new()
    {
        ExecutablePath = PowerShellPath,
        Arguments = new[]
        {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$child = Start-Process -FilePath '" + PingPath +
            "' -ArgumentList '-n','300','127.0.0.1' -PassThru; " +
            "Write-Output $child.Id; " +
            "Start-Sleep -Seconds 300"
        },
        Timeout = TimeSpan.FromSeconds(60)
    };

    [WindowsFact]
    public async Task ClosingTheJobTerminatesParentAndChild()
    {
        int parentId;
        int childId;

        using (var session = ProviderProcessSession.Start(ParentSpawningChildRequest()))
        {
            parentId = session.ProcessId;
            childId = await ReadChildProcessIdAsync(session).ConfigureAwait(false);

            Assert.True(IsRunning(parentId), "The parent process should be running.");
            Assert.True(IsRunning(childId), "The child process should be running.");
            Assert.False(session.HasExited);

            // Disposal closes the Job Object, which is the tear-down mechanism.
        }

        Assert.True(await WaitUntilGoneAsync(parentId).ConfigureAwait(false), "The parent survived the job close.");
        Assert.True(await WaitUntilGoneAsync(childId).ConfigureAwait(false), "The child survived the job close.");
    }

    [WindowsFact]
    public async Task ATimedOutRunLeavesNoProcessesBehind()
    {
        var request = ParentSpawningChildRequest() with { Timeout = TimeSpan.FromSeconds(3) };

        var before = DateTimeOffset.UtcNow;
        var result = await ProviderProcessLauncher.RunAsync(request).ConfigureAwait(false);
        var elapsed = DateTimeOffset.UtcNow - before;

        Assert.True(result.Launched);
        Assert.True(result.TimedOut, "A run that outlived its deadline must be classified as a timeout.");
        Assert.True(elapsed < TimeSpan.FromSeconds(30), $"The deadline was not enforced (took {elapsed}).");

        // The child id the helper printed must also be gone.
        var childId = ParseFirstProcessId(result.StandardOutput);
        if (childId is int id)
        {
            Assert.True(await WaitUntilGoneAsync(id).ConfigureAwait(false), "The child outlived the timeout.");
        }
    }

    [WindowsFact]
    public async Task CancellationTerminatesTheTreeAndIsNotReportedAsATimeout()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(2));

        var result = await ProviderProcessLauncher
            .RunAsync(ParentSpawningChildRequest(), cancellation.Token)
            .ConfigureAwait(false);

        Assert.True(result.Canceled);
        Assert.False(result.TimedOut);

        var childId = ParseFirstProcessId(result.StandardOutput);
        if (childId is int id)
        {
            Assert.True(await WaitUntilGoneAsync(id).ConfigureAwait(false), "The child outlived the cancellation.");
        }
    }

    private static async Task<int> ReadChildProcessIdAsync(ProviderProcessSession session)
    {
        var buffer = new byte[256];
        var text = new StringBuilder();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(30));

        while (!deadline.IsCancellationRequested)
        {
            var read = await session.StandardOutput.ReadAsync(buffer, deadline.Token).ConfigureAwait(false);
            if (read <= 0)
            {
                break;
            }

            text.Append(Encoding.UTF8.GetString(buffer, 0, read));
            if (ParseFirstProcessId(Encoding.UTF8.GetBytes(text.ToString())) is int id)
            {
                return id;
            }
        }

        throw new InvalidOperationException($"The helper did not report a child id. Output: {text}");
    }

    private static int? ParseFirstProcessId(byte[] output)
    {
        foreach (var line in Encoding.UTF8.GetString(output).Split('\n'))
        {
            if (int.TryParse(line.Trim(), out var id) && id > 0)
            {
                return id;
            }
        }

        return null;
    }

    private static bool IsRunning(int processId)
    {
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById(processId);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private static async Task<bool> WaitUntilGoneAsync(int processId)
    {
        var deadline = DateTimeOffset.UtcNow + TimeSpan.FromSeconds(20);
        while (DateTimeOffset.UtcNow < deadline)
        {
            if (!IsRunning(processId))
            {
                return true;
            }

            await Task.Delay(100).ConfigureAwait(false);
        }

        return false;
    }
}
