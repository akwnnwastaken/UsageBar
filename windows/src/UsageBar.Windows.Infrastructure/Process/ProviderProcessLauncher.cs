using System.IO.Pipes;
using System.Runtime.Versioning;

namespace UsageBar.Windows.Infrastructure.Process;

/// <summary>What to run, with an explicit executable and argument array.</summary>
public sealed record ProviderProcessRequest
{
    public required string ExecutablePath { get; init; }

    public required IReadOnlyList<string> Arguments { get; init; }

    /// <summary>Bytes written to the child's stdin before draining begins.</summary>
    public byte[]? StandardInput { get; init; }

    /// <summary>Whether stdin is closed after the initial write.</summary>
    public bool CloseStandardInputAfterWrite { get; init; } = true;

    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(15);

    public int MaximumOutputBytes { get; init; } = 2 * 1024 * 1024;

    /// <summary>Diagnostic stderr is captured separately and far more tightly.</summary>
    public int MaximumErrorBytes { get; init; } = 64 * 1024;

    public IReadOnlyDictionary<string, string>? AdditionalEnvironment { get; init; }

    /// <summary>
    /// Overrides the private working directory. Only tests set this; providers
    /// always run from UsageBar's own directory.
    /// </summary>
    public string? WorkingDirectory { get; init; }

    /// <summary>
    /// Called with everything captured so far whenever new output arrives.
    /// Returning true ends the run early — the Codex adapter uses it to stop as
    /// soon as the usage response has been seen.
    /// </summary>
    public Func<ReadOnlyMemory<byte>, bool>? IsComplete { get; init; }
}

public sealed record ProviderProcessResult
{
    public required byte[] StandardOutput { get; init; }

    public required byte[] StandardError { get; init; }

    public bool OutputExceeded { get; init; }

    public bool ErrorExceeded { get; init; }

    public bool TimedOut { get; init; }

    public bool Canceled { get; init; }

    public int ExitCode { get; init; }

    /// <summary>Set when the process could not be started at all.</summary>
    public string? LaunchFailure { get; init; }

    public bool Launched => LaunchFailure is null;
}

/// <summary>
/// Runs a provider CLI under full containment and returns its bounded output.
///
/// No shell is involved at any point: no cmd.exe, no PowerShell, no CMD AutoRun,
/// no profile scripts. The executable path and argument array are passed to
/// CreateProcessW directly, the process starts suspended inside a Job Object,
/// and the whole tree is terminated when the run ends for any reason.
/// </summary>
[SupportedOSPlatform("windows")]
public static class ProviderProcessLauncher
{
    public static async Task<ProviderProcessResult> RunAsync(
        ProviderProcessRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        var output = new BoundedOutputCapture(request.MaximumOutputBytes);
        var error = new BoundedOutputCapture(request.MaximumErrorBytes);

        ProviderProcessSession session;
        try
        {
            session = ProviderProcessSession.Start(request);
        }
        catch (Exception exception) when (
            exception is ProviderLaunchException or InvalidOperationException or IOException)
        {
            return new ProviderProcessResult
            {
                StandardOutput = Array.Empty<byte>(),
                StandardError = Array.Empty<byte>(),
                LaunchFailure = exception.Message
            };
        }

        using (session)
        {
            using var completion = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            completion.CancelAfter(request.Timeout);

            var writeTask = WriteStandardInputAsync(session.StandardInput, request, completion.Token);
            var outputTask = DrainAsync(session.StandardOutput, output, request.IsComplete, completion);
            var errorTask = DrainAsync(session.StandardError, error, isComplete: null, completion);

            var exited = await session.WaitForExitAsync(completion.Token).ConfigureAwait(false);

            // Give the readers a moment to flush what the child wrote just before
            // exiting, then stop regardless of what they are doing.
            await IgnoringCancellation(
                    Task.WhenAll(outputTask, errorTask, writeTask),
                    TimeSpan.FromSeconds(1))
                .ConfigureAwait(false);

            // Read the exit code before disposal tears the tree down.
            var exitCode = exited ? session.ExitCode : 0;
            var (outputData, outputExceeded) = output.Snapshot();
            var (errorData, errorExceeded) = error.Snapshot();

            return new ProviderProcessResult
            {
                StandardOutput = outputData,
                StandardError = errorData,
                OutputExceeded = outputExceeded,
                ErrorExceeded = errorExceeded,
                // A run stopped by the caller is a cancellation; a run stopped by
                // our own deadline is a timeout. A run that finished early
                // because the answer arrived is neither.
                TimedOut = !exited &&
                           !cancellationToken.IsCancellationRequested &&
                           !outputExceeded &&
                           !SawCompleteAnswer(request, outputData),
                Canceled = cancellationToken.IsCancellationRequested,
                ExitCode = exitCode
            };
        }
    }

    private static bool SawCompleteAnswer(ProviderProcessRequest request, byte[] output) =>
        request.IsComplete is not null && request.IsComplete(output);

    private static async Task WriteStandardInputAsync(
        AnonymousPipeServerStream standardInput,
        ProviderProcessRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            if (request.StandardInput is { Length: > 0 } payload)
            {
                await standardInput.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
                await standardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
            }

            if (request.CloseStandardInputAfterWrite)
            {
                standardInput.Dispose();
            }
        }
        catch (Exception exception) when (
            exception is IOException or ObjectDisposedException or OperationCanceledException)
        {
            // A provider that exits before reading stdin is a normal outcome.
        }
    }

    private static async Task DrainAsync(
        AnonymousPipeServerStream pipe,
        BoundedOutputCapture capture,
        Func<ReadOnlyMemory<byte>, bool>? isComplete,
        CancellationTokenSource completion)
    {
        var buffer = new byte[16 * 1024];
        try
        {
            while (true)
            {
                var read = await pipe.ReadAsync(buffer, completion.Token).ConfigureAwait(false);
                if (read <= 0)
                {
                    return;
                }

                if (!capture.Append(buffer.AsSpan(0, read)))
                {
                    // Over the limit: end the run instead of reading more.
                    await completion.CancelAsync().ConfigureAwait(false);
                    return;
                }

                if (isComplete is not null && isComplete(capture.Snapshot().Data))
                {
                    await completion.CancelAsync().ConfigureAwait(false);
                    return;
                }
            }
        }
        catch (Exception exception) when (
            exception is IOException or ObjectDisposedException or OperationCanceledException)
        {
            // Pipe closed or the run ended; whatever was captured still counts.
        }
    }

    private static async Task IgnoringCancellation(Task task, TimeSpan grace)
    {
        try
        {
            await task.WaitAsync(grace).ConfigureAwait(false);
        }
        catch (Exception exception) when (exception is OperationCanceledException or TimeoutException)
        {
        }
    }
}
