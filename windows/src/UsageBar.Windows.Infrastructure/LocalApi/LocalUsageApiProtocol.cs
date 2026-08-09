using System.Globalization;
using System.Text;

namespace UsageBar.Windows.Infrastructure.LocalApi;

internal enum LocalUsageApiHttpStatus
{
    Ok = 200,
    BadRequest = 400,
    NotFound = 404,
    MethodNotAllowed = 405,
    ContentTooLarge = 413,
    UriTooLong = 414,
    TooManyRequests = 429,
    RequestHeaderFieldsTooLarge = 431,
    ServiceUnavailable = 503,
    HttpVersionNotSupported = 505
}

public delegate Task<byte[]> WindowsLocalUsageApiSnapshotProvider(
    DateTimeOffset observedAt,
    CancellationToken cancellationToken);

internal sealed class LocalUsageApiHttpResponseBuilder
{
    public byte[] Build(
        LocalUsageApiHttpStatus status,
        ReadOnlyMemory<byte> body,
        DateTimeOffset date)
    {
        var responseBody = status == LocalUsageApiHttpStatus.Ok ? body : ReadOnlyMemory<byte>.Empty;
        var lines = new List<string>
        {
            $"HTTP/1.1 {(int)status} {ReasonPhrase(status)}",
            $"Date: {HttpDate(date)}"
        };

        if (status == LocalUsageApiHttpStatus.Ok)
        {
            lines.Add("Content-Type: application/json; charset=utf-8");
        }

        lines.Add($"Content-Length: {responseBody.Length.ToString(CultureInfo.InvariantCulture)}");
        lines.Add("Connection: close");
        lines.Add("Cache-Control: no-store");
        lines.Add("X-Content-Type-Options: nosniff");

        if (status == LocalUsageApiHttpStatus.MethodNotAllowed)
        {
            lines.Add("Allow: GET");
        }

        if (status == LocalUsageApiHttpStatus.TooManyRequests)
        {
            lines.Add("Retry-After: 1");
        }

        lines.Add(string.Empty);
        lines.Add(string.Empty);

        var header = Encoding.ASCII.GetBytes(string.Join("\r\n", lines));
        var response = new byte[header.Length + responseBody.Length];
        header.CopyTo(response, 0);
        responseBody.Span.CopyTo(response.AsSpan(header.Length));
        return response;
    }

    public byte[] Build(LocalUsageApiHttpStatus status, DateTimeOffset date) =>
        Build(status, ReadOnlyMemory<byte>.Empty, date);

    internal static string HttpDate(DateTimeOffset date) =>
        date.UtcDateTime.ToString("R", CultureInfo.InvariantCulture);

    private static string ReasonPhrase(LocalUsageApiHttpStatus status) => status switch
    {
        LocalUsageApiHttpStatus.Ok => "OK",
        LocalUsageApiHttpStatus.BadRequest => "Bad Request",
        LocalUsageApiHttpStatus.NotFound => "Not Found",
        LocalUsageApiHttpStatus.MethodNotAllowed => "Method Not Allowed",
        LocalUsageApiHttpStatus.ContentTooLarge => "Content Too Large",
        LocalUsageApiHttpStatus.UriTooLong => "URI Too Long",
        LocalUsageApiHttpStatus.TooManyRequests => "Too Many Requests",
        LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge => "Request Header Fields Too Large",
        LocalUsageApiHttpStatus.ServiceUnavailable => "Service Unavailable",
        LocalUsageApiHttpStatus.HttpVersionNotSupported => "HTTP Version Not Supported",
        _ => throw new ArgumentOutOfRangeException(nameof(status))
    };
}

internal sealed class LocalUsageApiTokenBucket
{
    private readonly object _lock = new();
    private readonly double _rate;
    private readonly double _capacity;
    private double _tokens;
    private double _lastMonotonicTime;

    public LocalUsageApiTokenBucket(
        double initialMonotonicTime,
        double ratePerSecond = 4,
        int burst = 8)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(initialMonotonicTime);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(ratePerSecond);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(burst);
        _rate = ratePerSecond;
        _capacity = burst;
        _tokens = burst;
        _lastMonotonicTime = initialMonotonicTime;
    }

    public bool Admit(double monotonicTime)
    {
        lock (_lock)
        {
            var elapsed = Math.Max(0, monotonicTime - _lastMonotonicTime);
            _tokens = Math.Min(_capacity, _tokens + elapsed * _rate);
            _lastMonotonicTime = Math.Max(_lastMonotonicTime, monotonicTime);
            if (_tokens < 1)
            {
                return false;
            }

            _tokens -= 1;
            return true;
        }
    }
}

internal sealed class LocalUsageApiActiveConnectionGate
{
    private readonly object _lock = new();
    private readonly int _maximum;
    private int _active;

    public LocalUsageApiActiveConnectionGate(int maximum = 4)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(maximum);
        _maximum = maximum;
    }

    public bool TryAcquire()
    {
        lock (_lock)
        {
            if (_active >= _maximum)
            {
                return false;
            }

            _active += 1;
            return true;
        }
    }

    public void Release()
    {
        lock (_lock)
        {
            if (_active <= 0)
            {
                throw new InvalidOperationException("No active local API connection to release.");
            }

            _active -= 1;
        }
    }

    public int ActiveCount
    {
        get
        {
            lock (_lock)
            {
                return _active;
            }
        }
    }
}

internal interface ILocalUsageApiDeadline : IDisposable
{
    void Cancel();
}

internal interface ILocalUsageApiDeadlineScheduler
{
    ILocalUsageApiDeadline Schedule(TimeSpan delay, Action action);
}

internal sealed class TimerLocalUsageApiDeadlineScheduler : ILocalUsageApiDeadlineScheduler
{
    public ILocalUsageApiDeadline Schedule(TimeSpan delay, Action action) =>
        new TimerLocalUsageApiDeadline(delay, action);

    private sealed class TimerLocalUsageApiDeadline : ILocalUsageApiDeadline
    {
        private Timer? _timer;

        public TimerLocalUsageApiDeadline(TimeSpan delay, Action action)
        {
            ArgumentNullException.ThrowIfNull(action);
            _timer = new Timer(_ => action(), null, delay, Timeout.InfiniteTimeSpan);
        }

        public void Cancel() => Dispose();

        public void Dispose() => Interlocked.Exchange(ref _timer, null)?.Dispose();
    }
}

internal sealed class LocalUsageApiAbsoluteDeadline : IDisposable
{
    private readonly TimeSpan _delay;
    private readonly ILocalUsageApiDeadlineScheduler _scheduler;
    private ILocalUsageApiDeadline? _scheduled;

    public LocalUsageApiAbsoluteDeadline(
        TimeSpan delay,
        ILocalUsageApiDeadlineScheduler scheduler)
    {
        _delay = delay;
        _scheduler = scheduler;
    }

    public void Start(Action action)
    {
        _scheduled ??= _scheduler.Schedule(_delay, action);
    }

    public void Cancel()
    {
        Interlocked.Exchange(ref _scheduled, null)?.Cancel();
    }

    public void Dispose() => Cancel();
}

internal readonly record struct LocalUsageApiProcessResult(bool IsComplete, byte[]? Response);

internal sealed class LocalUsageApiRequestProcessor
{
    public const int MaximumResponseBodyBytes = 16 * 1024;

    private readonly StrictHttpRequestParser _parser;
    private readonly LocalUsageApiHttpResponseBuilder _responseBuilder = new();
    private readonly Func<DateTimeOffset> _wallNow;
    private readonly WindowsLocalUsageApiSnapshotProvider _snapshotProvider;

    public LocalUsageApiRequestProcessor(
        string expectedHost,
        Func<DateTimeOffset> wallNow,
        WindowsLocalUsageApiSnapshotProvider snapshotProvider)
    {
        _parser = new StrictHttpRequestParser(expectedHost);
        _wallNow = wallNow;
        _snapshotProvider = snapshotProvider;
    }

    public async Task<LocalUsageApiProcessResult> ProcessAsync(
        ReadOnlyMemory<byte> request,
        CancellationToken cancellationToken = default)
    {
        var parsed = _parser.Parse(request.Span);
        if (parsed.Kind == StrictHttpRequestParseResultKind.Incomplete)
        {
            return new LocalUsageApiProcessResult(false, null);
        }

        if (parsed.Kind == StrictHttpRequestParseResultKind.Rejected)
        {
            return new LocalUsageApiProcessResult(
                true,
                Response(parsed.Status!.Value));
        }

        var observedAt = _wallNow();
        try
        {
            var body = await _snapshotProvider(observedAt, cancellationToken).ConfigureAwait(false);
            if (body.Length > MaximumResponseBodyBytes)
            {
                return new LocalUsageApiProcessResult(
                    true,
                    _responseBuilder.Build(LocalUsageApiHttpStatus.ServiceUnavailable, observedAt));
            }

            return new LocalUsageApiProcessResult(
                true,
                _responseBuilder.Build(LocalUsageApiHttpStatus.Ok, body, observedAt));
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            return new LocalUsageApiProcessResult(
                true,
                _responseBuilder.Build(LocalUsageApiHttpStatus.ServiceUnavailable, observedAt));
        }
    }

    public byte[] Response(LocalUsageApiHttpStatus status) =>
        _responseBuilder.Build(status, _wallNow());
}
