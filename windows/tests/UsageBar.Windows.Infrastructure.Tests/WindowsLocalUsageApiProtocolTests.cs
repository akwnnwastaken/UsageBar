using System.Globalization;
using System.Text;
using System.Text.Json;
using UsageBar.Windows.Core.Contract;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Infrastructure.LocalApi;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

public sealed class WindowsLocalUsageApiResponseTests
{
    private static readonly DateTimeOffset Now =
        new(2030, 1, 2, 3, 4, 5, TimeSpan.FromHours(3));

    [Fact]
    public void SuccessHeadersDateAndUtf8ContentLengthAreExactAndCultureIndependent()
    {
        var original = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
            var body = Encoding.UTF8.GetBytes("{\"label\":\"ölçüm\"}");
            var response = new LocalUsageApiHttpResponseBuilder()
                .Build(LocalUsageApiHttpStatus.Ok, body, Now);
            var parsed = ParseResponse(response);

            Assert.Equal(200, parsed.Status);
            Assert.Equal("Wed, 02 Jan 2030 00:04:05 GMT", parsed.Headers["Date"]);
            Assert.Equal("application/json; charset=utf-8", parsed.Headers["Content-Type"]);
            Assert.Equal(body.Length.ToString(CultureInfo.InvariantCulture), parsed.Headers["Content-Length"]);
            Assert.Equal("close", parsed.Headers["Connection"]);
            Assert.Equal("no-store", parsed.Headers["Cache-Control"]);
            Assert.Equal("nosniff", parsed.Headers["X-Content-Type-Options"]);
            Assert.Equal(body, parsed.Body);
            Assert.DoesNotContain("Server", parsed.Headers.Keys);
            Assert.DoesNotContain(parsed.Headers.Keys, name => name.StartsWith("Access-Control-", StringComparison.Ordinal));
            Assert.DoesNotContain("Transfer-Encoding", parsed.Headers.Keys);
            Assert.DoesNotContain("Location", parsed.Headers.Keys);
        }
        finally
        {
            CultureInfo.CurrentCulture = original;
        }
    }

    [Theory]
    [InlineData(400)]
    [InlineData(404)]
    [InlineData(405)]
    [InlineData(413)]
    [InlineData(414)]
    [InlineData(429)]
    [InlineData(431)]
    [InlineData(503)]
    [InlineData(505)]
    public void TransportErrorsAreEmptyAndUseOnlyFrozenHeaders(int statusCode)
    {
        var status = (LocalUsageApiHttpStatus)statusCode;
        var parsed = ParseResponse(new LocalUsageApiHttpResponseBuilder().Build(status, Now));

        Assert.Equal((int)status, parsed.Status);
        Assert.Empty(parsed.Body);
        Assert.Equal("0", parsed.Headers["Content-Length"]);
        Assert.Equal("close", parsed.Headers["Connection"]);
        Assert.Equal("no-store", parsed.Headers["Cache-Control"]);
        Assert.Equal("nosniff", parsed.Headers["X-Content-Type-Options"]);
        Assert.False(parsed.Headers.ContainsKey("Content-Type"));
        Assert.Equal(status == LocalUsageApiHttpStatus.MethodNotAllowed, parsed.Headers.ContainsKey("Allow"));
        Assert.Equal(status == LocalUsageApiHttpStatus.TooManyRequests, parsed.Headers.ContainsKey("Retry-After"));
        if (status == LocalUsageApiHttpStatus.MethodNotAllowed)
        {
            Assert.Equal("GET", parsed.Headers["Allow"]);
        }

        if (status == LocalUsageApiHttpStatus.TooManyRequests)
        {
            Assert.Equal("1", parsed.Headers["Retry-After"]);
        }
    }

    [Fact]
    public void BodyCannotInjectResponseHeaders()
    {
        var body = Encoding.UTF8.GetBytes("{\"value\":\"\\r\\nServer: injected\"}");
        var parsed = ParseResponse(
            new LocalUsageApiHttpResponseBuilder().Build(LocalUsageApiHttpStatus.Ok, body, Now));

        Assert.DoesNotContain("Server", parsed.Headers.Keys);
        Assert.Equal(body, parsed.Body);
    }

    internal static ParsedResponse ParseResponse(byte[] response)
    {
        var separator = response.AsSpan().IndexOf("\r\n\r\n"u8);
        Assert.True(separator >= 0);
        var header = Encoding.ASCII.GetString(response, 0, separator);
        var lines = header.Split("\r\n", StringSplitOptions.None);
        var statusParts = lines[0].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var headers = lines.Skip(1).Select(line => line.Split(": ", 2, StringSplitOptions.None))
            .ToDictionary(parts => parts[0], parts => parts[1], StringComparer.Ordinal);
        return new ParsedResponse(
            int.Parse(statusParts[1], CultureInfo.InvariantCulture),
            headers,
            response[(separator + 4)..]);
    }

    internal sealed record ParsedResponse(
        int Status,
        IReadOnlyDictionary<string, string> Headers,
        byte[] Body);
}

public sealed class WindowsLocalUsageApiTokenBucketTests
{
    [Fact]
    public void BurstNinthAdmissionPartialAndFullRefillAreDeterministic()
    {
        var bucket = new LocalUsageApiTokenBucket(initialMonotonicTime: 10);
        for (var index = 0; index < 8; index += 1)
        {
            Assert.True(bucket.Admit(10));
        }

        Assert.False(bucket.Admit(10));
        Assert.False(bucket.Admit(10.24));
        Assert.True(bucket.Admit(10.25));
        Assert.False(bucket.Admit(10.25));

        Assert.True(bucket.Admit(12.25));
        for (var index = 0; index < 7; index += 1)
        {
            Assert.True(bucket.Admit(12.25));
        }

        Assert.False(bucket.Admit(12.25));
    }

    [Fact]
    public void MonotonicRegressionDoesNotRefill()
    {
        var bucket = new LocalUsageApiTokenBucket(initialMonotonicTime: 10, burst: 1);
        Assert.True(bucket.Admit(10));
        Assert.False(bucket.Admit(9));
        Assert.False(bucket.Admit(10.24));
        Assert.True(bucket.Admit(10.25));
    }

    [Fact]
    public void OneBucketIsSharedAcrossIndependentCallers()
    {
        var bucket = new LocalUsageApiTokenBucket(initialMonotonicTime: 0, burst: 2);
        Assert.True(bucket.Admit(0));
        Assert.True(bucket.Admit(0));
        Assert.False(bucket.Admit(0));
    }
}

public sealed class WindowsLocalUsageApiConnectionGateTests
{
    [Fact]
    public void FourConnectionsAreAdmittedAndSlotsReleaseWithoutLeaking()
    {
        var gate = new LocalUsageApiActiveConnectionGate(maximum: 4);
        Assert.All(Enumerable.Range(0, 4), _ => Assert.True(gate.TryAcquire()));
        Assert.Equal(4, gate.ActiveCount);
        Assert.False(gate.TryAcquire());

        gate.Release();
        Assert.True(gate.TryAcquire());
        Assert.Equal(4, gate.ActiveCount);
        for (var index = 0; index < 4; index += 1)
        {
            gate.Release();
        }

        Assert.Equal(0, gate.ActiveCount);
        Assert.Throws<InvalidOperationException>(gate.Release);
    }
}

public sealed class WindowsLocalUsageApiRequestProcessorTests
{
    private const string Host = "127.0.0.1:54132";
    private static readonly DateTimeOffset ObservedAt =
        new(2030, 1, 1, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public async Task FreshStaleUnavailableAndDisabledSnapshotsRemainHttp200()
    {
        foreach (var body in SnapshotBodies())
        {
            var processor = Processor((_, _) => Task.FromResult(body));
            var result = await processor.ProcessAsync(Request());
            var response = WindowsLocalUsageApiResponseTests.ParseResponse(result.Response!);

            Assert.True(result.IsComplete);
            Assert.Equal(200, response.Status);
            _ = UsageSnapshotV1Json.Decode(response.Body);
        }
    }

    [Fact]
    public async Task FailureAndOversizeBecomeEmpty503WithoutPartialJson()
    {
        var failure = Processor((_, _) => throw new InvalidOperationException("synthetic_failure"));
        var failed = WindowsLocalUsageApiResponseTests.ParseResponse(
            (await failure.ProcessAsync(Request())).Response!);
        Assert.Equal(503, failed.Status);
        Assert.Empty(failed.Body);

        var oversized = Processor((_, _) => Task.FromResult(
            new byte[LocalUsageApiRequestProcessor.MaximumResponseBodyBytes + 1]));
        var tooLarge = WindowsLocalUsageApiResponseTests.ParseResponse(
            (await oversized.ProcessAsync(Request())).Response!);
        Assert.Equal(503, tooLarge.Status);
        Assert.Empty(tooLarge.Body);
    }

    [Fact]
    public async Task ObservedAtIsInjectedAndRepeatedReadsNeverRefreshOrMutate()
    {
        var snapshotCalls = 0;
        var refreshCalls = 0;
        var body = SnapshotBodies().First();
        var processor = Processor((observedAt, _) =>
        {
            snapshotCalls += 1;
            Assert.Equal(ObservedAt, observedAt);
            return Task.FromResult(body);
        });

        var first = await processor.ProcessAsync(Request());
        var second = await processor.ProcessAsync(Request());
        Assert.Equal(2, snapshotCalls);
        Assert.Equal(0, refreshCalls);
        Assert.Equal(
            WindowsLocalUsageApiResponseTests.ParseResponse(first.Response!).Body,
            WindowsLocalUsageApiResponseTests.ParseResponse(second.Response!).Body);
    }

    [Fact]
    public async Task RejectedRequestNeverCallsSnapshotProvider()
    {
        var snapshotCalls = 0;
        var processor = Processor((_, _) =>
        {
            snapshotCalls += 1;
            return Task.FromResult(Array.Empty<byte>());
        });
        var invalid = Encoding.ASCII.GetBytes("GET /v1/usage HTTP/1.1\r\nHost: localhost:54132\r\n\r\n");

        var result = await processor.ProcessAsync(invalid);
        Assert.Equal(400, WindowsLocalUsageApiResponseTests.ParseResponse(result.Response!).Status);
        Assert.Equal(0, snapshotCalls);
    }

    private static LocalUsageApiRequestProcessor Processor(WindowsLocalUsageApiSnapshotProvider provider) =>
        new(Host, () => ObservedAt, provider);

    private static byte[] Request() =>
        Encoding.ASCII.GetBytes($"GET /v1/usage HTTP/1.1\r\nHost: {Host}\r\n\r\n");

    private static IEnumerable<byte[]> SnapshotBodies()
    {
        var window = new UsageWindow(
            UsageWindowKind.FiveHour,
            usedPercent: 42,
            resetsAt: ObservedAt.AddHours(1),
            durationMinutes: 300);
        var success = new ProviderUsage(
            ProviderNames.Codex,
            new[] { window },
            error: null,
            lastSuccessfulAt: ObservedAt.AddMinutes(-1));
        var stale = new ProviderUsage(
            ProviderNames.Codex,
            new[] { window },
            ProviderIssue.CodexTimedOut,
            ObservedAt.AddMinutes(-5));

        yield return Encode(codexEnabled: true, claudeEnabled: false, success);
        yield return Encode(codexEnabled: true, claudeEnabled: false, stale);
        yield return Encode(
            codexEnabled: true,
            claudeEnabled: false,
            ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexNotFound));
        yield return Encode(codexEnabled: false, claudeEnabled: false, usage: null);
    }

    private static byte[] Encode(
        bool codexEnabled,
        bool claudeEnabled,
        ProviderUsage? usage)
    {
        var usages = usage is null
            ? new Dictionary<string, ProviderUsage>()
            : new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = usage };
        var input = new UsageSnapshotV1ProjectionInput(codexEnabled, claudeEnabled, usages);
        return UsageSnapshotV1Json.Encode(UsageSnapshotV1Projection.Project(input, ObservedAt));
    }
}

public sealed class WindowsLocalUsageApiDeadlineTests
{
    [Fact]
    public void AbsoluteDeadlineDoesNotResetOnByteProgress()
    {
        var scheduler = new ManualDeadlineScheduler();
        using var deadline = new LocalUsageApiAbsoluteDeadline(TimeSpan.FromSeconds(2), scheduler);
        var fired = 0;

        deadline.Start(() => fired += 1);
        deadline.Start(() => fired += 100);
        Assert.Single(scheduler.Entries);
        scheduler.Fire(0);
        Assert.Equal(1, fired);
    }

    [Fact]
    public void CompletionAndShutdownCancelReadOrWriteDeadline()
    {
        var scheduler = new ManualDeadlineScheduler();
        using var deadline = new LocalUsageApiAbsoluteDeadline(TimeSpan.FromSeconds(2), scheduler);
        deadline.Start(() => throw new Xunit.Sdk.XunitException("cancelled deadline fired"));
        deadline.Cancel();
        scheduler.Fire(0);
        Assert.True(scheduler.Entries[0].Deadline.IsCancelled);
    }

    private sealed class ManualDeadlineScheduler : ILocalUsageApiDeadlineScheduler
    {
        public List<(ManualDeadline Deadline, Action Action)> Entries { get; } = new();

        public ILocalUsageApiDeadline Schedule(TimeSpan delay, Action action)
        {
            Assert.Equal(TimeSpan.FromSeconds(2), delay);
            var deadline = new ManualDeadline();
            Entries.Add((deadline, action));
            return deadline;
        }

        public void Fire(int index)
        {
            var entry = Entries[index];
            if (!entry.Deadline.IsCancelled)
            {
                entry.Action();
            }
        }
    }

    private sealed class ManualDeadline : ILocalUsageApiDeadline
    {
        public bool IsCancelled { get; private set; }

        public void Cancel() => IsCancelled = true;

        public void Dispose() => Cancel();
    }
}
