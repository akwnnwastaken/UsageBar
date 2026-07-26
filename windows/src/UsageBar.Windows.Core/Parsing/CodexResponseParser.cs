using System.Globalization;
using System.Text.Json;
using UsageBar.Windows.Core.Providers;

namespace UsageBar.Windows.Core.Parsing;

/// <summary>
/// Parses one JSON-RPC line from <c>codex app-server --stdio</c>. Only the
/// response to request id 2 (<c>account/rateLimits/read</c>) is accepted, so
/// interleaved notifications and other responses are ignored rather than
/// mistaken for usage.
///
/// Every returned window is preserved and classified by its duration; nothing is
/// dropped and no primary/secondary meaning is assumed.
/// </summary>
public static class CodexResponseParser
{
    private const int RateLimitsRequestId = 2;

    /// <summary>Parses a single line. Returns null when the line is not the usage response.</summary>
    public static ProviderUsage? ParseLine(ReadOnlySpan<byte> line)
    {
        if (line.IsEmpty)
        {
            return null;
        }

        JsonDocument document;
        try
        {
            var reader = new Utf8JsonReader(line);
            if (!JsonDocument.TryParseValue(ref reader, out var parsed) || parsed is null)
            {
                return null;
            }

            document = parsed;
        }
        catch (JsonException)
        {
            return null;
        }

        using (document)
        {
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object)
            {
                return null;
            }

            if (!root.TryGetProperty("id", out var id) ||
                id.ValueKind != JsonValueKind.Number ||
                !id.TryGetInt32(out var requestId) ||
                requestId != RateLimitsRequestId)
            {
                return null;
            }

            if (root.TryGetProperty("error", out var error) && error.ValueKind is not JsonValueKind.Null)
            {
                return ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexUsageUnavailable);
            }

            if (!root.TryGetProperty("result", out var result) ||
                result.ValueKind != JsonValueKind.Object ||
                !result.TryGetProperty("rateLimits", out var limits) ||
                limits.ValueKind != JsonValueKind.Object)
            {
                return ProviderUsage.Unavailable(ProviderNames.Codex, ProviderIssue.CodexLimitMissing);
            }

            var windows = new List<UsageWindow>(2);
            var positions = new[] { "primary", "secondary" };
            for (var position = 0; position < positions.Length; position++)
            {
                if (limits.TryGetProperty(positions[position], out var element) &&
                    RateWindow(element, position) is { } window)
                {
                    windows.Add(window);
                }
            }

            return new ProviderUsage(ProviderNames.Codex, windows, error: null);
        }
    }

    /// <summary>
    /// Scans accumulated newline-delimited output for the usage response. Used
    /// while draining so the fetch can stop as soon as the answer arrives.
    /// </summary>
    public static ProviderUsage? ParseStream(ReadOnlySpan<byte> output)
    {
        while (!output.IsEmpty)
        {
            var newline = output.IndexOf((byte)'\n');
            var line = newline < 0 ? output : output[..newline];
            if (ParseLine(Trim(line)) is { } usage)
            {
                return usage;
            }

            if (newline < 0)
            {
                break;
            }

            output = output[(newline + 1)..];
        }

        return null;
    }

    private static ReadOnlySpan<byte> Trim(ReadOnlySpan<byte> line)
    {
        while (!line.IsEmpty && (line[^1] == (byte)'\r' || line[^1] == (byte)' '))
        {
            line = line[..^1];
        }

        return line;
    }

    private static UsageWindow? RateWindow(JsonElement element, int position)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        if (Number(element, "usedPercent") is not double used)
        {
            return null;
        }

        var resetSeconds = Number(element, "resetsAt");
        var duration = Number(element, "windowDurationMins");

        return UsageWindow.Classified(
            Math.Clamp((int)Math.Round(used, MidpointRounding.AwayFromZero), 0, 100),
            resetSeconds is double seconds
                ? DateTimeOffset.FromUnixTimeMilliseconds((long)(seconds * 1000))
                : null,
            duration is double minutes ? (int)minutes : null,
            position);
    }

    private static double? Number(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetDouble(out var number) => number,
            JsonValueKind.String when double.TryParse(
                value.GetString(),
                NumberStyles.Float,
                CultureInfo.InvariantCulture,
                out var parsed) => parsed,
            _ => null
        };
    }
}
