using System.Text.Json;
using System.Text.Json.Serialization;

namespace UsageBar.Windows.Core.History;

/// <summary>
/// One recorded point: a timestamp and the remaining integer percentage. Nothing
/// else is ever stored — no provider output, no account data.
/// </summary>
public sealed record UsageHistorySample
{
    [JsonConstructor]
    public UsageHistorySample(DateTimeOffset recordedAt, int remainingPercent)
    {
        RecordedAt = recordedAt;
        RemainingPercent = remainingPercent;
    }

    [JsonPropertyName("recordedAt")]
    public DateTimeOffset RecordedAt { get; }

    [JsonPropertyName("remainingPercent")]
    public int RemainingPercent { get; }
}

/// <summary>
/// Retention, sampling and sanitization rules for the local 24-hour history.
/// The limits are the macOS limits.
/// </summary>
public static class UsageHistoryModel
{
    public static TimeSpan RetentionInterval { get; } = TimeSpan.FromHours(24);

    public static TimeSpan MinimumSampleInterval { get; } = TimeSpan.FromMinutes(1);

    public const int MaximumSamplesPerSeries = 24 * 60 + 1;

    public const int MaximumSeries = 16;

    public const int MaximumEncodedBytes = 1 * 1024 * 1024;

    public const int MaximumSeriesKeyLength = 128;

    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = false,
        DefaultIgnoreCondition = JsonIgnoreCondition.Never
    };

    /// <summary>History series key: provider name plus quota-window kind, nothing else.</summary>
    public static string SeriesKey(string providerName, Providers.UsageWindowKind windowKind) =>
        $"{providerName}|{windowKind.HistoryKey}";

    public static IReadOnlyList<UsageHistorySample> Adding(
        int remainingPercent,
        DateTimeOffset at,
        IReadOnlyList<UsageHistorySample> existing)
    {
        ArgumentNullException.ThrowIfNull(existing);

        var cutoff = at - RetentionInterval;
        var samples = existing
            .Where(sample => sample.RecordedAt >= cutoff && sample.RecordedAt <= at)
            .ToList();

        var addition = new UsageHistorySample(at, Math.Clamp(remainingPercent, 0, 100));
        if (samples.Count > 0 && at - samples[^1].RecordedAt < MinimumSampleInterval)
        {
            samples[^1] = addition;
        }
        else
        {
            samples.Add(addition);
        }

        return Suffix(samples, MaximumSamplesPerSeries);
    }

    /// <summary>
    /// Enforces every limit on load and after each new sample: maximum age,
    /// maximum sample count, maximum series count, key length and value range.
    /// </summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> Sanitized(
        IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history,
        DateTimeOffset now)
    {
        ArgumentNullException.ThrowIfNull(history);

        var cutoff = now - RetentionInterval;
        var latestAllowed = now + MinimumSampleInterval;
        var result = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);

        var keys = history.Keys.OrderBy(key => key, StringComparer.Ordinal).Take(MaximumSeries);
        foreach (var key in keys)
        {
            if (key.Length > MaximumSeriesKeyLength)
            {
                continue;
            }

            var candidates = (history[key] ?? Array.Empty<UsageHistorySample>())
                .Where(sample => sample.RecordedAt >= cutoff && sample.RecordedAt <= latestAllowed)
                .OrderBy(sample => sample.RecordedAt)
                .ToList();

            var samples = new List<UsageHistorySample>(candidates.Count);
            foreach (var candidate in candidates)
            {
                var normalized = new UsageHistorySample(
                    candidate.RecordedAt,
                    Math.Clamp(candidate.RemainingPercent, 0, 100));

                if (samples.Count > 0 &&
                    normalized.RecordedAt - samples[^1].RecordedAt < MinimumSampleInterval)
                {
                    samples[^1] = normalized;
                }
                else
                {
                    samples.Add(normalized);
                }
            }

            if (samples.Count > 0)
            {
                result[key] = Suffix(samples, MaximumSamplesPerSeries);
            }
        }

        return result;
    }

    public static byte[]? Encode(IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> history)
    {
        try
        {
            return JsonSerializer.SerializeToUtf8Bytes(history, SerializerOptions);
        }
        catch (NotSupportedException)
        {
            return null;
        }
    }

    /// <summary>
    /// Decodes stored history. Oversized, truncated or malformed data yields an
    /// empty history instead of throwing — a corrupt file must never crash
    /// UsageBar or wipe out an otherwise healthy launch.
    /// </summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<UsageHistorySample>> Decode(byte[]? data)
    {
        var empty = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);
        if (data is null || data.Length == 0 || data.Length > MaximumEncodedBytes)
        {
            return empty;
        }

        try
        {
            var decoded = JsonSerializer.Deserialize<Dictionary<string, List<UsageHistorySample>?>>(
                data,
                SerializerOptions);
            if (decoded is null)
            {
                return empty;
            }

            var result = new Dictionary<string, IReadOnlyList<UsageHistorySample>>(StringComparer.Ordinal);
            foreach (var (key, samples) in decoded)
            {
                if (samples is null)
                {
                    continue;
                }

                result[key] = samples.Where(sample => sample is not null).ToList();
            }

            return result;
        }
        catch (JsonException)
        {
            return empty;
        }
        catch (NotSupportedException)
        {
            return empty;
        }
    }

    private static IReadOnlyList<UsageHistorySample> Suffix(List<UsageHistorySample> samples, int maximum)
    {
        if (samples.Count <= maximum)
        {
            return samples;
        }

        return samples.GetRange(samples.Count - maximum, maximum);
    }
}
