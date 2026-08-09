using System.Globalization;
using System.Text;

namespace UsageBar.Windows.Infrastructure.LocalApi;

internal enum StrictHttpRequestParseResultKind
{
    Incomplete,
    Accepted,
    Rejected
}

internal readonly record struct StrictHttpRequestParseResult(
    StrictHttpRequestParseResultKind Kind,
    LocalUsageApiHttpStatus? Status = null)
{
    public static StrictHttpRequestParseResult Incomplete() =>
        new(StrictHttpRequestParseResultKind.Incomplete);

    public static StrictHttpRequestParseResult Accepted() =>
        new(StrictHttpRequestParseResultKind.Accepted);

    public static StrictHttpRequestParseResult Rejected(LocalUsageApiHttpStatus status) =>
        new(StrictHttpRequestParseResultKind.Rejected, status);
}

internal sealed class StrictHttpRequestParser
{
    public const int MaximumRequestLineBytes = 1024;
    public const int MaximumHeaderSectionBytes = 8192;
    public const int MaximumHeaderCount = 32;
    public const int MaximumHeaderLineBytes = 1024;
    public const int MaximumBufferedRequestBytes =
        MaximumRequestLineBytes + MaximumHeaderSectionBytes + 1;

    private readonly string _expectedHost;

    public StrictHttpRequestParser(string expectedHost)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedHost);
        _expectedHost = expectedHost;
    }

    public StrictHttpRequestParseResult Parse(ReadOnlySpan<byte> data)
    {
        if (ContainsBareLineFeed(data) || ContainsMalformedCarriageReturn(data))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        var requestLineEnd = IndexOf(data, CrLf, 0);
        if (requestLineEnd < 0)
        {
            return data.Length >= MaximumRequestLineBytes
                ? StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.UriTooLong)
                : StrictHttpRequestParseResult.Incomplete();
        }

        var requestLineBytes = requestLineEnd + CrLf.Length;
        if (requestLineBytes > MaximumRequestLineBytes)
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.UriTooLong);
        }

        var headerStart = requestLineBytes;
        var headerTerminator = IndexOf(data, HeaderTerminator, requestLineEnd);
        if (headerTerminator < 0)
        {
            return data.Length - headerStart >= MaximumHeaderSectionBytes
                ? StrictHttpRequestParseResult.Rejected(
                    LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge)
                : StrictHttpRequestParseResult.Incomplete();
        }

        var headerEnd = headerTerminator + HeaderTerminator.Length;
        if (headerEnd - headerStart > MaximumHeaderSectionBytes)
        {
            return StrictHttpRequestParseResult.Rejected(
                LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
        }

        if (!TryAscii(data[..requestLineEnd], out var requestLine))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        var requestParts = requestLine.Split(' ', StringSplitOptions.None);
        if (requestParts.Length != 3 ||
            requestParts.Any(string.IsNullOrEmpty) ||
            requestParts.Any(part => part.Contains('\t')) ||
            !IsToken(requestParts[0]))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        var method = requestParts[0];
        var target = requestParts[1];
        var version = requestParts[2];
        if (!IsSyntacticallyValidHttpVersion(version))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        if (!string.Equals(version, "HTTP/1.1", StringComparison.Ordinal))
        {
            return StrictHttpRequestParseResult.Rejected(
                LocalUsageApiHttpStatus.HttpVersionNotSupported);
        }

        var headers = new List<(string Name, string Value)>();
        var cursor = headerStart;
        while (cursor < headerTerminator)
        {
            var lineEnd = IndexOf(data, CrLf, cursor);
            if (lineEnd < cursor || lineEnd > headerTerminator)
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            var lineByteCount = lineEnd - cursor + CrLf.Length;
            if (lineByteCount > MaximumHeaderLineBytes)
            {
                return StrictHttpRequestParseResult.Rejected(
                    LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
            }

            if (!TryAscii(data[cursor..lineEnd], out var line) ||
                line.Length == 0 ||
                char.IsWhiteSpace(line[0]))
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            var colon = line.IndexOf(':');
            if (colon < 0)
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            var name = line[..colon];
            if (!IsToken(name))
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            var value = line[(colon + 1)..];
            if (value.StartsWith(' '))
            {
                value = value[1..];
            }

            if ((value.Length == 0 && !name.Equals("Content-Length", StringComparison.OrdinalIgnoreCase)) ||
                value.StartsWith(' ') ||
                value.EndsWith(' ') ||
                value.Any(character => character is < (char)0x20 or > (char)0x7e))
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            headers.Add((name, value));
            if (headers.Count > MaximumHeaderCount)
            {
                return StrictHttpRequestParseResult.Rejected(
                    LocalUsageApiHttpStatus.RequestHeaderFieldsTooLarge);
            }

            cursor = lineEnd + CrLf.Length;
        }

        var hosts = Values("Host", headers);
        if (hosts.Count != 1 || !string.Equals(hosts[0], _expectedHost, StringComparison.Ordinal))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        if (Values("Origin", headers).Count != 0)
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        var fetchSites = Values("Sec-Fetch-Site", headers);
        if (fetchSites.Count > 1 ||
            (fetchSites.Count == 1 && !string.Equals(fetchSites[0], "none", StringComparison.Ordinal)))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        if (Values("Transfer-Encoding", headers).Count != 0)
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        var contentLengths = Values("Content-Length", headers);
        if (contentLengths.Count > 1)
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        if (contentLengths.Count == 1)
        {
            var contentLength = contentLengths[0];
            if (contentLength.Length == 0 || contentLength.Any(character => character is < '0' or > '9'))
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }

            if (contentLength == "0")
            {
                // The only accepted body framing.
            }
            else if (contentLength[0] == '0')
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }
            else if (ulong.TryParse(contentLength, NumberStyles.None, CultureInfo.InvariantCulture, out _))
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.ContentTooLarge);
            }
            else
            {
                return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
            }
        }

        if (data.Length != headerEnd)
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.BadRequest);
        }

        if (!string.Equals(method, "GET", StringComparison.Ordinal))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.MethodNotAllowed);
        }

        if (!string.Equals(target, "/v1/usage", StringComparison.Ordinal))
        {
            return StrictHttpRequestParseResult.Rejected(LocalUsageApiHttpStatus.NotFound);
        }

        return StrictHttpRequestParseResult.Accepted();
    }

    private static List<string> Values(
        string expectedName,
        IEnumerable<(string Name, string Value)> headers) =>
        headers
            .Where(header => header.Name.Equals(expectedName, StringComparison.OrdinalIgnoreCase))
            .Select(header => header.Value)
            .ToList();

    private static bool IsToken(string value) =>
        value.Length > 0 && value.All(character => character switch
        {
            '!' or '#' or '$' or '%' or '&' or '\'' or '*' or '+' or '-' or '.' or
            '^' or '_' or '`' or '|' or '~' => true,
            >= '0' and <= '9' => true,
            >= 'A' and <= 'Z' => true,
            >= 'a' and <= 'z' => true,
            _ => false
        });

    private static bool IsSyntacticallyValidHttpVersion(string value)
    {
        var slash = value.Split('/', StringSplitOptions.None);
        if (slash.Length != 2 || slash[0] != "HTTP")
        {
            return false;
        }

        var numbers = slash[1].Split('.', StringSplitOptions.None);
        return numbers.Length == 2 &&
               numbers.All(number =>
                   number.Length > 0 && number.All(character => character is >= '0' and <= '9'));
    }

    private static bool ContainsBareLineFeed(ReadOnlySpan<byte> data)
    {
        for (var index = 0; index < data.Length; index += 1)
        {
            if (data[index] == 0x0a && (index == 0 || data[index - 1] != 0x0d))
            {
                return true;
            }
        }

        return false;
    }

    private static bool ContainsMalformedCarriageReturn(ReadOnlySpan<byte> data)
    {
        for (var index = 0; index < data.Length; index += 1)
        {
            if (data[index] == 0x0d && index + 1 < data.Length && data[index + 1] != 0x0a)
            {
                return true;
            }
        }

        return false;
    }

    private static bool TryAscii(ReadOnlySpan<byte> bytes, out string value)
    {
        foreach (var item in bytes)
        {
            if (item > 0x7f)
            {
                value = string.Empty;
                return false;
            }
        }

        value = Encoding.ASCII.GetString(bytes);
        return true;
    }

    private static int IndexOf(ReadOnlySpan<byte> data, ReadOnlySpan<byte> needle, int start)
    {
        if (start < 0 || start > data.Length)
        {
            return -1;
        }

        var relative = data[start..].IndexOf(needle);
        return relative < 0 ? -1 : start + relative;
    }

    private static ReadOnlySpan<byte> CrLf => new byte[] { 0x0d, 0x0a };

    private static ReadOnlySpan<byte> HeaderTerminator =>
        new byte[] { 0x0d, 0x0a, 0x0d, 0x0a };
}
