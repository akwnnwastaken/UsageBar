using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace UsageBar.Windows.Infrastructure.LocalApi;

public sealed class WindowsLocalUsageApiConfiguration
{
    public const int ProductionPort = 54132;

    public static WindowsLocalUsageApiConfiguration Production { get; } =
        new(IPAddress.Loopback, ProductionPort);

    internal WindowsLocalUsageApiConfiguration(IPAddress address, int port)
    {
        ArgumentNullException.ThrowIfNull(address);
        if (address.AddressFamily != AddressFamily.InterNetwork || !address.Equals(IPAddress.Loopback))
        {
            throw new ArgumentException("The local usage API requires numeric IPv4 loopback.", nameof(address));
        }

        ArgumentOutOfRangeException.ThrowIfNegative(port);
        if (port > ushort.MaxValue)
        {
            throw new ArgumentOutOfRangeException(nameof(port));
        }

        Address = address;
        Port = port;
    }

    public IPAddress Address { get; }

    public int Port { get; }

    internal string ExpectedHost(int boundPort) => $"127.0.0.1:{boundPort}";
}

public enum WindowsLocalUsageApiListenerState
{
    Stopped,
    Starting,
    Listening,
    Failed,
    Stopping
}

public enum WindowsLocalUsageApiDiagnostic
{
    ListenerStarted,
    ListenerBindFailed,
    ListenerFailed,
    ListenerStopped,
    RequestRejected,
    RequestRateLimited,
    SnapshotUnavailable
}

public sealed class WindowsLocalUsageApiListener : IDisposable
{
    private static readonly TimeSpan ShutdownBudget = TimeSpan.FromSeconds(2);

    private readonly object _lock = new();
    private readonly WindowsLocalUsageApiConfiguration _configuration;
    private readonly Func<DateTimeOffset> _wallNow;
    private readonly Func<double> _monotonicNow;
    private readonly WindowsLocalUsageApiSnapshotProvider _snapshotProvider;
    private readonly Action<WindowsLocalUsageApiDiagnostic> _diagnostic;
    private readonly Func<IPEndPoint, TcpListener> _listenerFactory;
    private readonly ILocalUsageApiDeadlineScheduler _deadlineScheduler;
    private readonly LocalUsageApiActiveConnectionGate _connectionGate = new(maximum: 4);
    private readonly LocalUsageApiTokenBucket _tokenBucket;
    private readonly Dictionary<long, WindowsLocalUsageApiConnectionSession> _sessions = new();

    private WindowsLocalUsageApiListenerState _state = WindowsLocalUsageApiListenerState.Stopped;
    private TcpListener? _listener;
    private CancellationTokenSource? _lifetime;
    private Task? _acceptLoop;
    private Task? _stopTask;
    private int? _boundPort;
    private long _nextSessionId;
    private bool _disposed;

    public WindowsLocalUsageApiListener(
        WindowsLocalUsageApiSnapshotProvider snapshotProvider,
        Action<WindowsLocalUsageApiDiagnostic>? diagnostic = null)
        : this(
            WindowsLocalUsageApiConfiguration.Production,
            () => DateTimeOffset.UtcNow,
            MonotonicSeconds,
            snapshotProvider,
            diagnostic ?? (_ => { }),
            endpoint => new TcpListener(endpoint),
            new TimerLocalUsageApiDeadlineScheduler())
    {
    }

    internal WindowsLocalUsageApiListener(
        WindowsLocalUsageApiConfiguration configuration,
        Func<DateTimeOffset> wallNow,
        Func<double> monotonicNow,
        WindowsLocalUsageApiSnapshotProvider snapshotProvider,
        Action<WindowsLocalUsageApiDiagnostic> diagnostic,
        Func<IPEndPoint, TcpListener> listenerFactory,
        ILocalUsageApiDeadlineScheduler deadlineScheduler)
    {
        _configuration = configuration;
        _wallNow = wallNow;
        _monotonicNow = monotonicNow;
        _snapshotProvider = snapshotProvider;
        _diagnostic = diagnostic;
        _listenerFactory = listenerFactory;
        _deadlineScheduler = deadlineScheduler;
        _tokenBucket = new LocalUsageApiTokenBucket(monotonicNow());
    }

    public WindowsLocalUsageApiListenerState State
    {
        get
        {
            lock (_lock)
            {
                return _state;
            }
        }
    }

    public int? BoundPort
    {
        get
        {
            lock (_lock)
            {
                return _boundPort;
            }
        }
    }

    internal int ActiveConnectionCount => _connectionGate.ActiveCount;

    public void Start()
    {
        lock (_lock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (_state != WindowsLocalUsageApiListenerState.Stopped)
            {
                return;
            }

            _state = WindowsLocalUsageApiListenerState.Starting;
        }

        TcpListener? listener = null;
        try
        {
            listener = _listenerFactory(new IPEndPoint(_configuration.Address, _configuration.Port));
            listener.Server.ExclusiveAddressUse = true;
            listener.Server.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, false);
            listener.Start(backlog: 4);

            if (listener.LocalEndpoint is not IPEndPoint local ||
                !IsExactIpv4Loopback(local.Address))
            {
                throw new SocketException((int)SocketError.AddressNotAvailable);
            }

            var lifetime = new CancellationTokenSource();
            lock (_lock)
            {
                if (_state != WindowsLocalUsageApiListenerState.Starting)
                {
                    listener.Stop();
                    lifetime.Dispose();
                    return;
                }

                _listener = listener;
                _lifetime = lifetime;
                _boundPort = local.Port;
                _state = WindowsLocalUsageApiListenerState.Listening;
                _acceptLoop = AcceptLoopAsync(listener, lifetime.Token);
            }

            _diagnostic(WindowsLocalUsageApiDiagnostic.ListenerStarted);
        }
        catch (Exception exception) when (
            exception is SocketException or InvalidOperationException or ObjectDisposedException)
        {
            try
            {
                listener?.Stop();
            }
            catch (SocketException)
            {
            }

            lock (_lock)
            {
                _listener = null;
                _boundPort = null;
                _state = WindowsLocalUsageApiListenerState.Failed;
            }

            _diagnostic(WindowsLocalUsageApiDiagnostic.ListenerBindFailed);
        }
    }

    public Task StopAsync()
    {
        lock (_lock)
        {
            if (_state is WindowsLocalUsageApiListenerState.Stopped or
                WindowsLocalUsageApiListenerState.Failed)
            {
                return Task.CompletedTask;
            }

            if (_state == WindowsLocalUsageApiListenerState.Stopping)
            {
                return _stopTask ?? Task.CompletedTask;
            }

            _state = WindowsLocalUsageApiListenerState.Stopping;
            _stopTask = StopCoreAsync();
            return _stopTask;
        }
    }

    private async Task StopCoreAsync()
    {
        TcpListener? listener;
        CancellationTokenSource? lifetime;
        WindowsLocalUsageApiConnectionSession[] sessions;
        Task? acceptLoop;

        lock (_lock)
        {
            listener = _listener;
            lifetime = _lifetime;
            acceptLoop = _acceptLoop;
            sessions = _sessions.Values.ToArray();
        }

        lifetime?.Cancel();
        try
        {
            listener?.Stop();
        }
        catch (SocketException)
        {
        }

        foreach (var session in sessions)
        {
            session.Cancel();
        }

        var pending = sessions.Select(session => session.Completion).ToList();
        if (acceptLoop is not null)
        {
            pending.Add(acceptLoop);
        }

        if (pending.Count > 0)
        {
            _ = await Task.WhenAny(
                    Task.WhenAll(pending),
                    Task.Delay(ShutdownBudget))
                .ConfigureAwait(false);
        }

        foreach (var session in sessions)
        {
            session.Cancel();
        }

        lifetime?.Dispose();
        lock (_lock)
        {
            _sessions.Clear();
            _listener = null;
            _lifetime = null;
            _acceptLoop = null;
            _boundPort = null;
            _state = WindowsLocalUsageApiListenerState.Stopped;
            _stopTask = null;
        }

        _diagnostic(WindowsLocalUsageApiDiagnostic.ListenerStopped);
    }

    private async Task AcceptLoopAsync(TcpListener listener, CancellationToken cancellationToken)
    {
        try
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                var client = await listener.AcceptTcpClientAsync(cancellationToken).ConfigureAwait(false);
                if (!_connectionGate.TryAcquire())
                {
                    client.Dispose();
                    continue;
                }

                int boundPort;
                long sessionId;
                lock (_lock)
                {
                    if (_state != WindowsLocalUsageApiListenerState.Listening || _boundPort is not { } port)
                    {
                        _connectionGate.Release();
                        client.Dispose();
                        continue;
                    }

                    boundPort = port;
                    sessionId = ++_nextSessionId;
                }

                var processor = new LocalUsageApiRequestProcessor(
                    _configuration.ExpectedHost(boundPort),
                    _wallNow,
                    _snapshotProvider);
                var session = new WindowsLocalUsageApiConnectionSession(
                    client,
                    boundPort,
                    new StrictHttpRequestParser(_configuration.ExpectedHost(boundPort)),
                    processor,
                    _tokenBucket,
                    _monotonicNow,
                    _deadlineScheduler,
                    _diagnostic,
                    cancellationToken,
                    () => SessionFinished(sessionId));

                lock (_lock)
                {
                    _sessions[sessionId] = session;
                }

                session.Start();
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception exception) when (
            exception is SocketException or InvalidOperationException or ObjectDisposedException)
        {
            FailUnexpectedly();
        }
    }

    private void SessionFinished(long sessionId)
    {
        lock (_lock)
        {
            _sessions.Remove(sessionId);
        }

        _connectionGate.Release();
    }

    private void FailUnexpectedly()
    {
        WindowsLocalUsageApiConnectionSession[] sessions;
        lock (_lock)
        {
            if (_state is WindowsLocalUsageApiListenerState.Stopping or
                WindowsLocalUsageApiListenerState.Stopped or
                WindowsLocalUsageApiListenerState.Failed)
            {
                return;
            }

            _state = WindowsLocalUsageApiListenerState.Failed;
            _boundPort = null;
            _lifetime?.Cancel();
            try
            {
                _listener?.Stop();
            }
            catch (SocketException)
            {
            }

            _listener = null;
            sessions = _sessions.Values.ToArray();
        }

        foreach (var session in sessions)
        {
            session.Cancel();
        }

        _diagnostic(WindowsLocalUsageApiDiagnostic.ListenerFailed);
    }

    public void Dispose()
    {
        lock (_lock)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
        }

        StopAsync().Wait(ShutdownBudget + TimeSpan.FromMilliseconds(100));
    }

    private static bool IsExactIpv4Loopback(IPAddress address) =>
        address.AddressFamily == AddressFamily.InterNetwork && address.Equals(IPAddress.Loopback);

    private static double MonotonicSeconds() =>
        (double)Stopwatch.GetTimestamp() / Stopwatch.Frequency;
}

internal sealed class WindowsLocalUsageApiConnectionSession
{
    private static readonly TimeSpan ReadDeadline = TimeSpan.FromSeconds(2);
    private static readonly TimeSpan WriteDeadline = TimeSpan.FromSeconds(2);

    private readonly TcpClient _client;
    private readonly int _expectedLocalPort;
    private readonly StrictHttpRequestParser _parser;
    private readonly LocalUsageApiRequestProcessor _processor;
    private readonly LocalUsageApiTokenBucket _tokenBucket;
    private readonly Func<double> _monotonicNow;
    private readonly Action<WindowsLocalUsageApiDiagnostic> _diagnostic;
    private readonly Action _onFinish;
    private readonly CancellationTokenSource _cancellation;
    private readonly LocalUsageApiAbsoluteDeadline _readDeadline;
    private readonly LocalUsageApiAbsoluteDeadline _writeDeadline;
    private readonly TaskCompletionSource _completion =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private int _finished;

    public WindowsLocalUsageApiConnectionSession(
        TcpClient client,
        int expectedLocalPort,
        StrictHttpRequestParser parser,
        LocalUsageApiRequestProcessor processor,
        LocalUsageApiTokenBucket tokenBucket,
        Func<double> monotonicNow,
        ILocalUsageApiDeadlineScheduler deadlineScheduler,
        Action<WindowsLocalUsageApiDiagnostic> diagnostic,
        CancellationToken listenerCancellation,
        Action onFinish)
    {
        _client = client;
        _expectedLocalPort = expectedLocalPort;
        _parser = parser;
        _processor = processor;
        _tokenBucket = tokenBucket;
        _monotonicNow = monotonicNow;
        _diagnostic = diagnostic;
        _onFinish = onFinish;
        _cancellation = CancellationTokenSource.CreateLinkedTokenSource(listenerCancellation);
        _readDeadline = new LocalUsageApiAbsoluteDeadline(ReadDeadline, deadlineScheduler);
        _writeDeadline = new LocalUsageApiAbsoluteDeadline(WriteDeadline, deadlineScheduler);
    }

    public Task Completion => _completion.Task;

    public void Start() => _ = RunAsync();

    public void Cancel()
    {
        try
        {
            _cancellation.Cancel();
        }
        catch (ObjectDisposedException)
        {
        }

        _client.Dispose();
    }

    private async Task RunAsync()
    {
        try
        {
            if (!HasApprovedEndpoints())
            {
                return;
            }

            var stream = _client.GetStream();
            var buffer = new byte[StrictHttpRequestParser.MaximumBufferedRequestBytes];
            var count = 0;
            _readDeadline.Start(Cancel);

            while (!_cancellation.IsCancellationRequested)
            {
                var remaining = buffer.Length - count;
                if (remaining <= 0)
                {
                    _readDeadline.Cancel();
                    await SendAsync(
                            stream,
                            _processor.Response(LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge))
                        .ConfigureAwait(false);
                    return;
                }

                var read = await stream
                    .ReadAsync(buffer.AsMemory(count, remaining), _cancellation.Token)
                    .ConfigureAwait(false);
                if (read == 0)
                {
                    _readDeadline.Cancel();
                    await SendAsync(stream, _processor.Response(LocalUsageApiHttpStatus.BadRequest))
                        .ConfigureAwait(false);
                    return;
                }

                count += read;
                var parsed = _parser.Parse(buffer.AsSpan(0, count));
                if (parsed.Kind == StrictHttpRequestParseResultKind.Incomplete)
                {
                    continue;
                }

                _readDeadline.Cancel();
                if (parsed.Kind == StrictHttpRequestParseResultKind.Rejected)
                {
                    _diagnostic(WindowsLocalUsageApiDiagnostic.RequestRejected);
                    await SendAsync(stream, _processor.Response(parsed.Status!.Value)).ConfigureAwait(false);
                    return;
                }

                if (!_tokenBucket.Admit(_monotonicNow()))
                {
                    _diagnostic(WindowsLocalUsageApiDiagnostic.RequestRateLimited);
                    await SendAsync(stream, _processor.Response(LocalUsageApiHttpStatus.TooManyRequests))
                        .ConfigureAwait(false);
                    return;
                }

                var processed = await _processor
                    .ProcessAsync(buffer.AsMemory(0, count), _cancellation.Token)
                    .ConfigureAwait(false);
                if (processed.Response is null)
                {
                    return;
                }

                if (StatusCode(processed.Response) == (int)LocalUsageApiHttpStatus.ServiceUnavailable)
                {
                    _diagnostic(WindowsLocalUsageApiDiagnostic.SnapshotUnavailable);
                }

                await SendAsync(stream, processed.Response).ConfigureAwait(false);
                return;
            }
        }
        catch (OperationCanceledException)
        {
        }
        catch (Exception exception) when (
            exception is IOException or SocketException or ObjectDisposedException or InvalidOperationException)
        {
        }
        finally
        {
            Finish();
        }
    }

    private async Task SendAsync(NetworkStream stream, byte[] response)
    {
        _writeDeadline.Start(Cancel);
        await stream.WriteAsync(response, _cancellation.Token).ConfigureAwait(false);
        _writeDeadline.Cancel();
    }

    private bool HasApprovedEndpoints()
    {
        return _client.Client.LocalEndPoint is IPEndPoint local &&
               _client.Client.RemoteEndPoint is IPEndPoint remote &&
               local.Port == _expectedLocalPort &&
               IsExactIpv4Loopback(local.Address) &&
               IsExactIpv4Loopback(remote.Address);
    }

    private void Finish()
    {
        if (Interlocked.Exchange(ref _finished, 1) != 0)
        {
            return;
        }

        _readDeadline.Dispose();
        _writeDeadline.Dispose();
        _client.Dispose();
        _cancellation.Dispose();
        _completion.TrySetResult();
        _onFinish();
    }

    private static bool IsExactIpv4Loopback(IPAddress address) =>
        address.AddressFamily == AddressFamily.InterNetwork && address.Equals(IPAddress.Loopback);

    private static int? StatusCode(ReadOnlySpan<byte> response)
    {
        var lineEnd = response.IndexOf("\r\n"u8);
        if (lineEnd < 0)
        {
            return null;
        }

        var firstLine = System.Text.Encoding.ASCII.GetString(response[..lineEnd]);
        var parts = firstLine.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length > 1 && int.TryParse(parts[1], out var status) ? status : null;
    }
}
