using System.Runtime.Versioning;
using System.Text;
using UsageBar.Windows.Infrastructure.Process;

namespace UsageBar.Windows.Infrastructure.Wsl;

/// <summary>
/// Runs <c>wsl.exe</c> through the same Job Object launcher every other provider
/// uses, so a WSL command and everything it starts inside the distribution is
/// torn down with the job on timeout, cancellation or application exit.
///
/// Commands are always given as an explicit argument array and executed with
/// <c>--exec</c>, which runs the target directly instead of through the
/// distribution's login shell. No <c>bash -lc</c>, no interactive startup files,
/// no cmd.exe or PowerShell in between.
/// </summary>
[SupportedOSPlatform("windows")]
public sealed class WslCommandRunner
{
    private readonly string _wslPath;

    public WslCommandRunner(string? wslPath = null) =>
        _wslPath = wslPath ?? System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.System),
            "wsl.exe");

    /// <summary>True when wsl.exe exists at all. Says nothing about distributions.</summary>
    public bool IsInstalled => File.Exists(_wslPath);

    public string ExecutablePath => _wslPath;

    /// <summary>
    /// Builds the argument array for running a command inside a distribution.
    /// Exposed so tests can assert the exact shape without spawning anything.
    /// </summary>
    public static IReadOnlyList<string> BuildExecArguments(
        string? distribution,
        bool useHomeDirectory,
        IReadOnlyList<string> command)
    {
        ArgumentNullException.ThrowIfNull(command);

        var arguments = new List<string>(command.Count + 6);
        if (!string.IsNullOrWhiteSpace(distribution))
        {
            arguments.Add("--distribution");
            arguments.Add(distribution);
        }

        if (useHomeDirectory)
        {
            // The Linux user's home. It is not a project directory, and using it
            // means UsageBar never has to learn — or store — the home path
            // itself: the Claude binary is addressed relative to it.
            arguments.Add("--cd");
            arguments.Add("~");
        }

        // --exec runs the target directly. Everything after it is the argument
        // array, which WSL passes through without shell re-parsing.
        arguments.Add("--exec");
        arguments.AddRange(command);
        return arguments;
    }

    public async Task<WslCommandResult> RunAsync(
        string? distribution,
        bool useHomeDirectory,
        IReadOnlyList<string> command,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        if (!IsInstalled)
        {
            return new WslCommandResult
            {
                StandardOutput = Array.Empty<byte>(),
                StandardError = Array.Empty<byte>(),
                LaunchFailure = "wsl.exe not present"
            };
        }

        var result = await ProviderProcessLauncher.RunAsync(
            new ProviderProcessRequest
            {
                ExecutablePath = _wslPath,
                Arguments = BuildExecArguments(distribution, useHomeDirectory, command),
                Timeout = timeout,
                CloseStandardInputAfterWrite = true
            },
            cancellationToken).ConfigureAwait(false);

        return new WslCommandResult
        {
            StandardOutput = result.StandardOutput,
            StandardError = result.StandardError,
            OutputExceeded = result.OutputExceeded || result.ErrorExceeded,
            TimedOut = result.TimedOut,
            Cancelled = result.Canceled,
            ExitCode = result.ExitCode,
            LaunchFailure = result.LaunchFailure
        };
    }

    /// <summary>
    /// Lists installed distributions with <c>--list --quiet</c>. This is a
    /// management command, so it does not go through <c>--exec</c>.
    /// </summary>
    public async Task<IReadOnlyList<string>> ListDistributionsAsync(CancellationToken cancellationToken)
    {
        if (!IsInstalled)
        {
            return Array.Empty<string>();
        }

        var result = await ProviderProcessLauncher.RunAsync(
            new ProviderProcessRequest
            {
                ExecutablePath = _wslPath,
                Arguments = new[] { "--list", "--quiet" },
                Timeout = ClaudeQueryTimeouts.DistributionListTimeout,
                CloseStandardInputAfterWrite = true
            },
            cancellationToken).ConfigureAwait(false);

        if (!result.Launched || result.TimedOut || result.Canceled)
        {
            return Array.Empty<string>();
        }

        return ParseDistributions(result.StandardOutput);
    }

    /// <summary>
    /// Decodes and splits a distribution listing.
    ///
    /// wsl.exe writes UTF-16LE on most Windows builds and UTF-8 on some newer
    /// ones, so the encoding is detected from the bytes rather than assumed.
    /// </summary>
    public static IReadOnlyList<string> ParseDistributions(byte[] output)
    {
        ArgumentNullException.ThrowIfNull(output);

        return DecodeWslText(output)
            .Split('\n', '\r')
            .Select(line => line.Trim().Trim('﻿', '\0'))
            .Where(line => line.Length is > 0 and <= 64)
            .ToList();
    }

    /// <summary>Detects UTF-16LE (which is full of NUL bytes) and falls back to UTF-8.</summary>
    public static string DecodeWslText(byte[] output)
    {
        ArgumentNullException.ThrowIfNull(output);

        if (output.Length == 0)
        {
            return string.Empty;
        }

        var inspected = Math.Min(output.Length, 512);
        var nulCount = 0;
        for (var index = 0; index < inspected; index++)
        {
            if (output[index] == 0)
            {
                nulCount++;
            }
        }

        // UTF-16LE ASCII text is roughly half NUL bytes; real UTF-8 output has
        // essentially none.
        return nulCount * 4 > inspected
            ? Encoding.Unicode.GetString(output).TrimStart('﻿')
            : Encoding.UTF8.GetString(output).TrimStart('﻿');
    }
}

public sealed record WslCommandResult
{
    public required byte[] StandardOutput { get; init; }

    public required byte[] StandardError { get; init; }

    public bool OutputExceeded { get; init; }

    public bool TimedOut { get; init; }

    public bool Cancelled { get; init; }

    public int ExitCode { get; init; }

    public string? LaunchFailure { get; init; }

    public bool Launched => LaunchFailure is null;
}

internal static class ClaudeQueryTimeouts
{
    public static TimeSpan DistributionListTimeout { get; } = TimeSpan.FromSeconds(15);
}
