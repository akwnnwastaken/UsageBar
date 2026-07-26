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
    /// How long the helper is given to start and report its child. PowerShell's
    /// cold start on a CI runner has been observed at over 25 seconds, so this
    /// is deliberately generous: it is test plumbing, not the behavior under
    /// test.
    /// </summary>
    private static readonly TimeSpan ChildReportDeadline = TimeSpan.FromSeconds(120);

    /// <summary>
    /// Starts a parent that spawns a long-running child and prints the child's
    /// process id, so the test can assert on both by id rather than by name.
    ///
    /// The child is started with <c>[Diagnostics.Process]::Start</c> rather than
    /// the <c>Start-Process</c> cmdlet, and the id is written straight to the
    /// console and flushed, so it arrives as soon as the child exists instead of
    /// sitting in PowerShell's formatting pipeline. Only single quotes appear in
    /// the script: the launcher escapes double quotes the way
    /// CommandLineToArgvW expects, which PowerShell would then mis-read.
    /// </summary>
    private static ProviderProcessRequest ParentSpawningChildRequest(TimeSpan? timeout = null) => new()
    {
        ExecutablePath = PowerShellPath,
        Arguments = new[]
        {
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "$i = New-Object System.Diagnostics.ProcessStartInfo; " +
            "$i.FileName = '" + PingPath + "'; " +
            "$i.Arguments = '-n 300 127.0.0.1'; " +
            "$i.UseShellExecute = $false; " +
            "$c = [System.Diagnostics.Process]::Start($i); " +
            "[Console]::Out.WriteLine($c.Id); " +
            "[Console]::Out.Flush(); " +
            "Start-Sleep -Seconds 300"
        },
        Timeout = timeout ?? TimeSpan.FromSeconds(180)
    };

    /// <summary>
    /// Starts PowerShell once so its cold start is not charged to the tests that
    /// have to bound their own runtime. This only removes runtime variance from
    /// the harness; nothing about the containment behavior changes.
    /// </summary>
    private static readonly SemaphoreSlim WarmUpGate = new(1, 1);

    private static bool _warmedUp;

    private static async Task WarmUpPowerShellAsync()
    {
        await WarmUpGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_warmedUp)
            {
                return;
            }

            await ProviderProcessLauncher.RunAsync(new ProviderProcessRequest
            {
                ExecutablePath = PowerShellPath,
                Arguments = new[] { "-NoProfile", "-NonInteractive", "-Command", "exit" },
                Timeout = TimeSpan.FromSeconds(180)
            }).ConfigureAwait(false);

            _warmedUp = true;
        }
        finally
        {
            WarmUpGate.Release();
        }
    }

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
        await WarmUpPowerShellAsync().ConfigureAwait(false);

        // Long enough for the helper to report its child, short enough that the
        // deadline is what ends the run.
        var timeout = TimeSpan.FromSeconds(30);
        var before = DateTimeOffset.UtcNow;
        var result = await ProviderProcessLauncher
            .RunAsync(ParentSpawningChildRequest(timeout))
            .ConfigureAwait(false);
        var elapsed = DateTimeOffset.UtcNow - before;

        Assert.True(result.Launched);
        Assert.True(result.TimedOut, "A run that outlived its deadline must be classified as a timeout.");
        Assert.True(elapsed < timeout + TimeSpan.FromSeconds(30), $"The deadline was not enforced (took {elapsed}).");

        // The assertion is not allowed to pass vacuously: the child must have
        // been observed, and it must be gone.
        var childId = ParseFirstProcessId(result.StandardOutput);
        Assert.True(childId is not null, "The helper never reported a child, so nothing was verified.");
        Assert.True(
            await WaitUntilGoneAsync(childId!.Value).ConfigureAwait(false),
            "The child outlived the timeout.");
    }

    [WindowsFact]
    public async Task CancellationTerminatesTheTreeAndIsNotReportedAsATimeout()
    {
        await WarmUpPowerShellAsync().ConfigureAwait(false);

        using var cancellation = new CancellationTokenSource();
        int? childId = null;

        // Cancel the moment the tree actually exists, so the test proves that
        // cancellation tears down a live parent and child rather than racing
        // against startup. Returning false keeps this from counting as a
        // completed answer.
        var request = ParentSpawningChildRequest() with
        {
            IsComplete = output =>
            {
                if (childId is null && ParseFirstProcessId(output.ToArray()) is int id)
                {
                    childId = id;
                    cancellation.Cancel();
                }

                return false;
            }
        };

        var result = await ProviderProcessLauncher.RunAsync(request, cancellation.Token).ConfigureAwait(false);

        Assert.True(result.Canceled);
        Assert.False(result.TimedOut);
        Assert.True(childId is not null, "The helper never reported a child, so nothing was verified.");
        Assert.True(
            await WaitUntilGoneAsync(childId!.Value).ConfigureAwait(false),
            "The child outlived the cancellation.");
    }

    private static async Task<int> ReadChildProcessIdAsync(ProviderProcessSession session)
    {
        var buffer = new byte[256];
        var text = new StringBuilder();
        using var deadline = new CancellationTokenSource(ChildReportDeadline);

        try
        {
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
        }
        catch (OperationCanceledException)
        {
            // Fall through to the explicit failure below so the message says
            // what the helper actually produced.
        }

        throw new InvalidOperationException(
            $"The helper did not report a child id within {ChildReportDeadline}. Output: {text}");
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
