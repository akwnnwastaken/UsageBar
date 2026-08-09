using System.Text;
using UsageBar.Windows.Infrastructure.LocalApi;
using Xunit;

namespace UsageBar.Windows.Infrastructure.Tests;

public sealed class WindowsLocalUsageApiParserTests
{
    private const string ExpectedHost = "127.0.0.1:54132";
    private readonly StrictHttpRequestParser _parser = new(ExpectedHost);

    [Fact]
    public void ExactGetAndBrowserMetadataPolicyMatchMacOs()
    {
        AssertAccepted(Request());
        AssertAccepted(Request(headers: new[] { "Sec-Fetch-Site: none" }));
        AssertRejected(Request(headers: new[] { "Origin: https://example.invalid" }), LocalUsageApiHttpStatus.BadRequest);
        AssertRejected(Request(headers: new[] { "Sec-Fetch-Site: same-origin" }), LocalUsageApiHttpStatus.BadRequest);
        AssertRejected(
            Request(headers: new[] { "Sec-Fetch-Site: none", "Sec-Fetch-Site: none" }),
            LocalUsageApiHttpStatus.BadRequest);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("localhost:54132")]
    [InlineData("127.0.0.1")]
    [InlineData("127.0.0.1:1")]
    [InlineData("[::1]:54132")]
    [InlineData("2130706433:54132")]
    [InlineData(" 127.0.0.1:54132")]
    [InlineData("127.0.0.1:54132 ")]
    [InlineData("127.0.0.1:54132,localhost:54132")]
    public void HostMustBeExactlyOneConfiguredValue(string? host)
    {
        var request = host is null
            ? Request(includeHost: false)
            : Request(host: host);
        AssertRejected(request, LocalUsageApiHttpStatus.BadRequest);
    }

    [Fact]
    public void DuplicateHostIsRejected()
    {
        AssertRejected(
            Request(headers: new[] { $"Host: {ExpectedHost}" }),
            LocalUsageApiHttpStatus.BadRequest);
    }

    [Theory]
    [InlineData("POST", "/v1/usage", "HTTP/1.1", 405)]
    [InlineData("HEAD", "/v1/usage", "HTTP/1.1", 405)]
    [InlineData("OPTIONS", "/v1/usage", "HTTP/1.1", 405)]
    [InlineData("GET", "/unknown", "HTTP/1.1", 404)]
    [InlineData("GET", "/v1/usage?x=y", "HTTP/1.1", 404)]
    [InlineData("GET", "/v1/usage/", "HTTP/1.1", 404)]
    [InlineData("GET", "http://127.0.0.1:54132/v1/usage", "HTTP/1.1", 404)]
    [InlineData("GET", "/v1/usage", "HTTP/1.0", 505)]
    [InlineData("GET", "/v1/usage", "HTTP/2.0", 505)]
    public void MethodTargetAndVersionUseFrozenStatuses(
        string method,
        string target,
        string version,
        int expected)
    {
        AssertRejected(Request(method, target, version), (LocalUsageApiHttpStatus)expected);
    }

    [Theory]
    [InlineData("GET  /v1/usage HTTP/1.1")]
    [InlineData("GET\t/v1/usage HTTP/1.1")]
    [InlineData("GET /v1/usage")]
    [InlineData("GET /v1/usage HTTX/1.1")]
    [InlineData("GET /v1/usage HTTP/1")]
    [InlineData("GE(T /v1/usage HTTP/1.1")]
    public void MalformedRequestLineIsBadRequest(string line)
    {
        AssertRejected(
            Encoding.ASCII.GetBytes($"{line}\r\nHost: {ExpectedHost}\r\n\r\n"),
            LocalUsageApiHttpStatus.BadRequest);
    }

    [Fact]
    public void RequestLineLimitIncludesCrLf()
    {
        var exactTarget = "/" + new string('a', StrictHttpRequestParser.MaximumRequestLineBytes - 16);
        var exact = Request(target: exactTarget);
        Assert.Equal(StrictHttpRequestParser.MaximumRequestLineBytes, FirstLineLength(exact));
        AssertRejected(exact, LocalUsageApiHttpStatus.NotFound);

        var overTarget = exactTarget + "a";
        AssertRejected(Request(target: overTarget), LocalUsageApiHttpStatus.UriTooLong);

        var incomplete = Encoding.ASCII.GetBytes(new string('G', StrictHttpRequestParser.MaximumRequestLineBytes));
        AssertRejected(incomplete, LocalUsageApiHttpStatus.UriTooLong);
    }

    [Fact]
    public void HeaderCountBoundaryIsExact()
    {
        var thirtyTwo = Enumerable.Range(0, 31).Select(index => $"X-{index}: a").ToArray();
        AssertAccepted(Request(headers: thirtyTwo));

        var thirtyThree = Enumerable.Range(0, 32).Select(index => $"X-{index}: a").ToArray();
        AssertRejected(Request(headers: thirtyThree), LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
    }

    [Fact]
    public void IndividualHeaderLineBoundaryIsExact()
    {
        var exact = "X:" + new string('a', StrictHttpRequestParser.MaximumHeaderLineBytes - 4);
        Assert.Equal(StrictHttpRequestParser.MaximumHeaderLineBytes, Encoding.ASCII.GetByteCount(exact) + 2);
        AssertAccepted(Request(headers: new[] { exact }));

        var over = exact + "a";
        AssertRejected(Request(headers: new[] { over }), LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
    }

    [Fact]
    public void CompleteHeaderSectionBoundaryIsExact()
    {
        var exact = RequestWithHeaderSectionSize(StrictHttpRequestParser.MaximumHeaderSectionBytes);
        AssertAccepted(exact);

        var over = RequestWithHeaderSectionSize(StrictHttpRequestParser.MaximumHeaderSectionBytes + 1);
        AssertRejected(over, LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
    }

    [Theory]
    [InlineData(null, 0)]
    [InlineData("Content-Length: 0", 0)]
    [InlineData("Content-Length: 1", 413)]
    [InlineData("Content-Length: 01", 400)]
    [InlineData("Content-Length: -1", 400)]
    [InlineData("Content-Length: +1", 400)]
    [InlineData("Content-Length: 1, 1", 400)]
    [InlineData("Content-Length: 18446744073709551616", 400)]
    [InlineData("Transfer-Encoding: chunked", 400)]
    public void ZeroBodyAndFramingPolicy(string? header, int expected)
    {
        var headers = header is null ? Array.Empty<string>() : new[] { header };
        if (expected == 0)
        {
            AssertAccepted(Request(headers: headers));
        }
        else
        {
            AssertRejected(Request(headers: headers), (LocalUsageApiHttpStatus)expected);
        }
    }

    [Fact]
    public void DuplicateLengthAndTransferEncodingCombinationAreRejected()
    {
        AssertRejected(
            Request(headers: new[] { "Content-Length: 0", "Content-Length: 0" }),
            LocalUsageApiHttpStatus.BadRequest);
        AssertRejected(
            Request(headers: new[] { "Content-Length: 0", "Transfer-Encoding: chunked" }),
            LocalUsageApiHttpStatus.BadRequest);
    }

    [Theory]
    [InlineData(" Folded: value")]
    [InlineData("Bad Name: value")]
    [InlineData("Host : 127.0.0.1:54132")]
    [InlineData("X:\tvalue")]
    [InlineData("X:  value")]
    [InlineData("X: value ")]
    [InlineData("X")]
    public void AmbiguousHeaderSyntaxIsRejected(string header)
    {
        AssertRejected(Request(headers: new[] { header }), LocalUsageApiHttpStatus.BadRequest);
    }

    [Fact]
    public void ControlCharactersBareLfMalformedCrBodyAndPipelineAreRejected()
    {
        AssertRejected(
            Encoding.ASCII.GetBytes($"GET /v1/usage HTTP/1.1\nHost: {ExpectedHost}\n\n"),
            LocalUsageApiHttpStatus.BadRequest);
        AssertRejected(
            Encoding.ASCII.GetBytes($"GET /v1/usage HTTP/1.1\rX: y\r\nHost: {ExpectedHost}\r\n\r\n"),
            LocalUsageApiHttpStatus.BadRequest);

        var control = Request(headers: new[] { "X: value" });
        control[Array.LastIndexOf(control, (byte)'v')] = 0x01;
        AssertRejected(control, LocalUsageApiHttpStatus.BadRequest);

        AssertRejected(Request(suffix: "x"), LocalUsageApiHttpStatus.BadRequest);
        AssertRejected(
            Request(suffix: $"GET /v1/usage HTTP/1.1\r\nHost: {ExpectedHost}\r\n\r\n"),
            LocalUsageApiHttpStatus.BadRequest);
    }

    [Fact]
    public void IncompleteRequestRemainsBounded()
    {
        var partial = Encoding.ASCII.GetBytes($"GET /v1/usage HTTP/1.1\r\nHost: {ExpectedHost}\r\n");
        Assert.Equal(StrictHttpRequestParseResultKind.Incomplete, _parser.Parse(partial).Kind);

        var oversized = Encoding.ASCII.GetBytes(
            $"GET /v1/usage HTTP/1.1\r\nHost: {ExpectedHost}\r\n" +
            new string('a', StrictHttpRequestParser.MaximumHeaderSectionBytes));
        AssertRejected(oversized, LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
    }

    private void AssertAccepted(byte[] request) =>
        Assert.Equal(StrictHttpRequestParseResultKind.Accepted, _parser.Parse(request).Kind);

    private void AssertRejected(byte[] request, LocalUsageApiHttpStatus status)
    {
        var result = _parser.Parse(request);
        Assert.Equal(StrictHttpRequestParseResultKind.Rejected, result.Kind);
        Assert.Equal(status, result.Status);
    }

    private static byte[] Request(
        string method = "GET",
        string target = "/v1/usage",
        string version = "HTTP/1.1",
        string host = ExpectedHost,
        bool includeHost = true,
        IEnumerable<string>? headers = null,
        string suffix = "")
    {
        var lines = new List<string> { $"{method} {target} {version}" };
        if (includeHost)
        {
            lines.Add($"Host: {host}");
        }

        if (headers is not null)
        {
            lines.AddRange(headers);
        }

        return Encoding.ASCII.GetBytes(string.Join("\r\n", lines) + "\r\n\r\n" + suffix);
    }

    private static int FirstLineLength(byte[] request) =>
        request.AsSpan().IndexOf("\r\n"u8) + 2;

    private static byte[] RequestWithHeaderSectionSize(int totalBytes)
    {
        var host = $"Host: {ExpectedHost}\r\n";
        var remaining = totalBytes - Encoding.ASCII.GetByteCount(host) - 2;
        var lineCount = (int)Math.Ceiling(remaining / (double)StrictHttpRequestParser.MaximumHeaderLineBytes);
        var baseLength = remaining / lineCount;
        var extra = remaining % lineCount;
        var headers = new List<string>(lineCount);

        for (var index = 0; index < lineCount; index += 1)
        {
            var lineLength = baseLength + (index < extra ? 1 : 0);
            var name = $"X{index}:";
            var valueLength = lineLength - name.Length - 2;
            Assert.True(valueLength > 0);
            headers.Add(name + new string('a', valueLength));
        }

        var request = Request(headers: headers);
        var requestLineEnd = request.AsSpan().IndexOf("\r\n"u8) + 2;
        Assert.Equal(totalBytes, request.Length - requestLineEnd);
        return request;
    }
}
