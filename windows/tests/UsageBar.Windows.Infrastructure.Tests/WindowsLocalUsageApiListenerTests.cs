using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using UsageBar.Windows.Infrastructure.LocalApi;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

public sealed class WindowsLocalUsageApiListenerTests
{
    private static readonly DateTimeOffset ObservedAt =
        new(2030, 1, 1, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void ProductionEndpointIsExactNumericIpv4Loopback()
    {
        var configuration = WindowsLocalUsageApiConfiguration.Production;

        Assert.Equal(IPAddress.Loopback, configuration.Address);
        Assert.Equal(AddressFamily.InterNetwork, configuration.Address.AddressFamily);
        Assert.Equal(54132, configuration.Port);
        Assert.Throws<ArgumentException>(
            () => new WindowsLocalUsageApiConfiguration(IPAddress.IPv6Loopback, 0));
        Assert.Throws<ArgumentException>(
            () => new WindowsLocalUsageApiConfiguration(IPAddress.Any, 0));
    }

    [Fact]
    public void FactoryFailureMovesStartingToTerminalFailedWithoutRetry()
    {
        var factoryCalls = 0;
        var diagnostics = new List<WindowsLocalUsageApiDiagnostic>();
        WindowsLocalUsageApiListener? listener = null;
        listener = new WindowsLocalUsageApiListener(
            new WindowsLocalUsageApiConfiguration(IPAddress.Loopback, 0),
            () => ObservedAt,
            () => 0,
            (_, _) => Task.FromResult(SnapshotBody()),
            diagnostics.Add,
            _ =>
            {
                factoryCalls += 1;
                Assert.Equal(WindowsLocalUsageApiListenerState.Starting, listener!.State);
                throw new InvalidOperationException("synthetic_bind_failure");
            },
            new TimerLocalUsageApiDeadlineScheduler());
        using (listener)
        {
            listener.Start();
            Assert.Equal(WindowsLocalUsageApiListenerState.Failed, listener.State);
            listener.Start();
            Assert.Equal(1, factoryCalls);
            Assert.Equal(
                new[] { WindowsLocalUsageApiDiagnostic.ListenerBindFailed },
                diagnostics);
        }
    }

    [WindowsFact]
    public async Task RealValidGetReturnsV1JsonFromIpv4LoopbackAndCloses()
    {
        var snapshotCalls = 0;
        using var listener = CreateListener((_, _) =>
        {
            snapshotCalls += 1;
            return Task.FromResult(SnapshotBody());
        });

        listener.Start();
        Assert.Equal(WindowsLocalUsageApiListenerState.Listening, listener.State);
        var port = Assert.IsType<int>(listener.BoundPort);

        var response = await SendAsync(port, Request(port));
        var parsed = WindowsLocalUsageApiResponseTests.ParseResponse(response);

        Assert.Equal(200, parsed.Status);
        Assert.Equal(1, snapshotCalls);
        using var json = JsonDocument.Parse(parsed.Body);
        Assert.Equal(1, json.RootElement.GetProperty("schemaVersion").GetInt32());
        Assert.Equal("close", parsed.Headers["Connection"]);
        await listener.StopAsync();
        Assert.Equal(WindowsLocalUsageApiListenerState.Stopped, listener.State);
    }

    [WindowsTheory]
    [InlineData("GET /v1/usage HTTP/1.1\r\nHost: localhost:{0}\r\n\r\n", 400)]
    [InlineData("GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:{0}\r\nOrigin: https://example.invalid\r\n\r\n", 400)]
    [InlineData("GET /unknown HTTP/1.1\r\nHost: 127.0.0.1:{0}\r\n\r\n", 404)]
    public async Task RealSocketRejectsWrongHostOriginAndUnknownPath(
        string requestTemplate,
        int expectedStatus)
    {
        var snapshotCalls = 0;
        using var listener = CreateListener((_, _) =>
        {
            snapshotCalls += 1;
            return Task.FromResult(SnapshotBody());
        });
        listener.Start();
        var port = Assert.IsType<int>(listener.BoundPort);

        var response = await SendAsync(
            port,
            string.Format(System.Globalization.CultureInfo.InvariantCulture, requestTemplate, port));

        Assert.Equal(
            expectedStatus,
            WindowsLocalUsageApiResponseTests.ParseResponse(response).Status);
        Assert.Equal(0, snapshotCalls);
        await listener.StopAsync();
    }

    [WindowsFact]
    public async Task NinthEligibleRequestIsRateLimitedProcessWide()
    {
        using var listener = CreateListener((_, _) => Task.FromResult(SnapshotBody()));
        listener.Start();
        var port = Assert.IsType<int>(listener.BoundPort);

        for (var index = 0; index < 8; index += 1)
        {
            var accepted = WindowsLocalUsageApiResponseTests.ParseResponse(
                await SendAsync(port, Request(port)));
            Assert.Equal(200, accepted.Status);
        }

        var rejected = WindowsLocalUsageApiResponseTests.ParseResponse(
            await SendAsync(port, Request(port)));
        Assert.Equal(429, rejected.Status);
        Assert.Equal("1", rejected.Headers["Retry-After"]);
        await listener.StopAsync();
    }

    [WindowsFact]
    public async Task CollisionFailsSecondAuthorityWithoutStoppingFirst()
    {
        using var first = CreateListener((_, _) => Task.FromResult(SnapshotBody()));
        first.Start();
        var port = Assert.IsType<int>(first.BoundPort);
        var diagnostics = new List<WindowsLocalUsageApiDiagnostic>();
        using var second = CreateListener(
            (_, _) => Task.FromResult(SnapshotBody()),
            port,
            diagnostics.Add);

        second.Start();

        Assert.Equal(WindowsLocalUsageApiListenerState.Failed, second.State);
        Assert.Contains(WindowsLocalUsageApiDiagnostic.ListenerBindFailed, diagnostics);
        Assert.Equal(
            200,
            WindowsLocalUsageApiResponseTests.ParseResponse(
                await SendAsync(port, Request(port))).Status);
        await first.StopAsync();
    }

    [WindowsFact]
    public async Task StopReleasesEndpointAndRepeatedLifecycleDoesNotLeak()
    {
        using var listener = CreateListener((_, _) => Task.FromResult(SnapshotBody()));
        listener.Start();
        var port = Assert.IsType<int>(listener.BoundPort);
        await listener.StopAsync();
        Assert.Null(listener.BoundPort);

        using (var replacement = CreateListener(
                   (_, _) => Task.FromResult(SnapshotBody()),
                   port))
        {
            replacement.Start();
            Assert.Equal(WindowsLocalUsageApiListenerState.Listening, replacement.State);
            await replacement.StopAsync();
        }

        listener.Start();
        Assert.Equal(WindowsLocalUsageApiListenerState.Listening, listener.State);
        Assert.NotNull(listener.BoundPort);
        await listener.StopAsync();
        Assert.Equal(WindowsLocalUsageApiListenerState.Stopped, listener.State);
    }

    [WindowsFact]
    public async Task FifthActiveConnectionIsClosedBeforeRequestProcessing()
    {
        using var listener = CreateListener((_, _) => Task.FromResult(SnapshotBody()));
        listener.Start();
        var port = Assert.IsType<int>(listener.BoundPort);
        var held = new List<TcpClient>();

        try
        {
            for (var index = 0; index < 4; index += 1)
            {
                var client = new TcpClient(AddressFamily.InterNetwork);
                await client.ConnectAsync(IPAddress.Loopback, port);
                held.Add(client);
                await WaitUntilAsync(() => listener.ActiveConnectionCount == held.Count);
            }

            using var fifth = new TcpClient(AddressFamily.InterNetwork);
            await fifth.ConnectAsync(IPAddress.Loopback, port);
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            var read = await fifth.GetStream().ReadAsync(new byte[1], cancellation.Token);
            Assert.Equal(0, read);
        }
        finally
        {
            foreach (var client in held)
            {
                client.Dispose();
            }

            await listener.StopAsync();
        }
    }

    private static WindowsLocalUsageApiListener CreateListener(
        WindowsLocalUsageApiSnapshotProvider snapshotProvider,
        int port = 0,
        Action<WindowsLocalUsageApiDiagnostic>? diagnostic = null) =>
        new(
            new WindowsLocalUsageApiConfiguration(IPAddress.Loopback, port),
            () => ObservedAt,
            () => 0,
            snapshotProvider,
            diagnostic ?? (_ => { }),
            endpoint => new TcpListener(endpoint),
            new TimerLocalUsageApiDeadlineScheduler());

    private static async Task<byte[]> SendAsync(int port, string request)
    {
        using var client = new TcpClient(AddressFamily.InterNetwork);
        await client.ConnectAsync(IPAddress.Loopback, port);
        var stream = client.GetStream();
        var requestBytes = Encoding.ASCII.GetBytes(request);
        await stream.WriteAsync(requestBytes);

        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        using var output = new MemoryStream();
        var buffer = new byte[4096];
        while (true)
        {
            var count = await stream.ReadAsync(buffer, cancellation.Token);
            if (count == 0)
            {
                return output.ToArray();
            }

            await output.WriteAsync(buffer.AsMemory(0, count), cancellation.Token);
        }
    }

    private static string Request(int port) =>
        $"GET /v1/usage HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n\r\n";

    private static async Task WaitUntilAsync(Func<bool> condition)
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition())
        {
            cancellation.Token.ThrowIfCancellationRequested();
            await Task.Yield();
        }
    }

    private static byte[] SnapshotBody() => Encoding.UTF8.GetBytes(
        "{\"schemaVersion\":1,\"observedAt\":\"2030-01-01T12:00:00.000Z\"," +
        "\"providers\":[{\"id\":\"codex\",\"state\":\"unavailable\"," +
        "\"lastSuccessfulAt\":null,\"error\":\"no_data\",\"windows\":[]}," +
        "{\"id\":\"claude\",\"state\":\"disabled\",\"lastSuccessfulAt\":null," +
        "\"error\":null,\"windows\":[]}]}" );
}
