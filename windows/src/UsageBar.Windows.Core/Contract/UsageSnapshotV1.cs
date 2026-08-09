using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;

namespace UsageBar.Windows.Core.Contract;

/// <summary>Stable public provider identifiers for the v1 telemetry protocol.</summary>
[JsonConverter(typeof(UsageProviderIdV1JsonConverter))]
public enum UsageProviderIdV1
{
    Codex,
    Claude
}

/// <summary>Provider collection state, independent of presentation state.</summary>
[JsonConverter(typeof(ProviderStateV1JsonConverter))]
public enum ProviderStateV1
{
    Disabled,
    Unavailable,
    Fresh,
    Stale
}

/// <summary>Stable semantic kinds for normalized quota windows.</summary>
[JsonConverter(typeof(UsageWindowKindV1JsonConverter))]
public enum UsageWindowKindV1
{
    FiveHour,
    Weekly,
    Duration,
    Unknown
}

/// <summary>
/// Small, privacy-safe public failure taxonomy. Internal error details never
/// cross this boundary.
/// </summary>
[JsonConverter(typeof(ProviderErrorCodeV1JsonConverter))]
public enum ProviderErrorCodeV1
{
    NoData,
    NotFound,
    UntrustedExecutable,
    NotAuthenticated,
    TimedOut,
    Unreadable,
    Incompatible,
    CommandFailed,
    LaunchFailed,
    OutputTooLarge
}

/// <summary>Explicit failure from v1 projection or wire validation.</summary>
public sealed class UsageSnapshotV1ValidationException : Exception
{
    public UsageSnapshotV1ValidationException(string reason)
        : base($"Invalid UsageSnapshotV1: {reason}.")
    {
        Reason = reason;
    }

    public string Reason { get; }
}

public sealed record ProviderErrorV1
{
    [JsonConstructor]
    public ProviderErrorV1(ProviderErrorCodeV1 code)
    {
        Code = code;
    }

    [JsonPropertyName("code")]
    [JsonPropertyOrder(0)]
    public ProviderErrorCodeV1 Code { get; }
}

public sealed record UsageWindowV1
{
    [JsonConstructor]
    public UsageWindowV1(
        UsageWindowKindV1 kind,
        int? durationMinutes,
        int usedPercent,
        DateTimeOffset? resetAt)
    {
        if (!Enum.IsDefined(kind))
        {
            throw new UsageSnapshotV1ValidationException("unsupported_window_kind");
        }

        if (usedPercent is < 0 or > 100)
        {
            throw new UsageSnapshotV1ValidationException("invalid_used_percent");
        }

        if (durationMinutes is <= 0)
        {
            throw new UsageSnapshotV1ValidationException("invalid_duration_minutes");
        }

        if (kind == UsageWindowKindV1.Duration && durationMinutes is null)
        {
            throw new UsageSnapshotV1ValidationException("missing_duration_minutes");
        }

        Kind = kind;
        DurationMinutes = durationMinutes;
        UsedPercent = usedPercent;
        ResetAt = resetAt;
    }

    [JsonPropertyName("kind")]
    [JsonPropertyOrder(0)]
    public UsageWindowKindV1 Kind { get; }

    [JsonPropertyName("durationMinutes")]
    [JsonPropertyOrder(1)]
    public int? DurationMinutes { get; }

    [JsonPropertyName("usedPercent")]
    [JsonPropertyOrder(2)]
    public int UsedPercent { get; }

    [JsonPropertyName("resetAt")]
    [JsonPropertyOrder(3)]
    public DateTimeOffset? ResetAt { get; }
}

public sealed record ProviderSnapshotV1
{
    [JsonConstructor]
    public ProviderSnapshotV1(
        UsageProviderIdV1 id,
        ProviderStateV1 state,
        DateTimeOffset? lastSuccessfulAt,
        ProviderErrorV1? error,
        IReadOnlyList<UsageWindowV1> windows)
    {
        ArgumentNullException.ThrowIfNull(windows);

        if (!Enum.IsDefined(id) || !Enum.IsDefined(state))
        {
            throw new UsageSnapshotV1ValidationException("unsupported_provider_value");
        }

        var isValid = state switch
        {
            ProviderStateV1.Disabled =>
                lastSuccessfulAt is null && error is null && windows.Count == 0,
            ProviderStateV1.Unavailable =>
                lastSuccessfulAt is null && error is not null && windows.Count == 0,
            ProviderStateV1.Fresh =>
                lastSuccessfulAt is not null && error is null && windows.Count > 0,
            ProviderStateV1.Stale =>
                lastSuccessfulAt is not null && error is not null && windows.Count > 0,
            _ => false
        };
        if (!isValid)
        {
            throw new UsageSnapshotV1ValidationException("invalid_provider_state");
        }

        Id = id;
        State = state;
        LastSuccessfulAt = lastSuccessfulAt;
        Error = error;
        Windows = windows.ToArray();
    }

    [JsonPropertyName("id")]
    [JsonPropertyOrder(0)]
    public UsageProviderIdV1 Id { get; }

    [JsonPropertyName("state")]
    [JsonPropertyOrder(1)]
    public ProviderStateV1 State { get; }

    [JsonPropertyName("lastSuccessfulAt")]
    [JsonPropertyOrder(2)]
    public DateTimeOffset? LastSuccessfulAt { get; }

    [JsonPropertyName("error")]
    [JsonPropertyOrder(3)]
    public ProviderErrorV1? Error { get; }

    [JsonPropertyName("windows")]
    [JsonPropertyOrder(4)]
    public IReadOnlyList<UsageWindowV1> Windows { get; }
}

public sealed record UsageSnapshotV1
{
    public const int CurrentSchemaVersion = 1;

    public UsageSnapshotV1(
        DateTimeOffset observedAt,
        IReadOnlyList<ProviderSnapshotV1> providers)
        : this(CurrentSchemaVersion, observedAt, providers)
    {
    }

    [JsonConstructor]
    public UsageSnapshotV1(
        int schemaVersion,
        DateTimeOffset observedAt,
        IReadOnlyList<ProviderSnapshotV1> providers)
    {
        ArgumentNullException.ThrowIfNull(providers);

        if (schemaVersion != CurrentSchemaVersion)
        {
            throw new UsageSnapshotV1ValidationException("unsupported_schema_version");
        }

        foreach (var id in new[] { UsageProviderIdV1.Codex, UsageProviderIdV1.Claude })
        {
            if (providers.Count(provider => provider.Id == id) != 1)
            {
                throw new UsageSnapshotV1ValidationException("invalid_provider_cardinality");
            }
        }

        SchemaVersion = schemaVersion;
        ObservedAt = observedAt;
        Providers = new[]
        {
            providers.Single(provider => provider.Id == UsageProviderIdV1.Codex),
            providers.Single(provider => provider.Id == UsageProviderIdV1.Claude)
        };
    }

    [JsonPropertyName("schemaVersion")]
    [JsonPropertyOrder(0)]
    public int SchemaVersion { get; }

    [JsonPropertyName("observedAt")]
    [JsonPropertyOrder(1)]
    public DateTimeOffset ObservedAt { get; }

    [JsonPropertyName("providers")]
    [JsonPropertyOrder(2)]
    public IReadOnlyList<ProviderSnapshotV1> Providers { get; }
}

/// <summary>
/// Pure projection input. Connection flags remain separate because disabled
/// providers are absent from the existing in-memory usage dictionary.
/// </summary>
public sealed record UsageSnapshotV1ProjectionInput
{
    public UsageSnapshotV1ProjectionInput(
        bool codexIsEnabled,
        bool claudeIsEnabled,
        IReadOnlyDictionary<string, ProviderUsage> usages)
    {
        ArgumentNullException.ThrowIfNull(usages);
        CodexIsEnabled = codexIsEnabled;
        ClaudeIsEnabled = claudeIsEnabled;
        Usages = usages;
    }

    public bool CodexIsEnabled { get; }

    public bool ClaudeIsEnabled { get; }

    public IReadOnlyDictionary<string, ProviderUsage> Usages { get; }

    public static UsageSnapshotV1ProjectionInput FromSettings(
        UsageBarSettings settings,
        IReadOnlyDictionary<string, ProviderUsage> usages)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return new(settings.CodexConnected, settings.ClaudeConnected, usages);
    }
}

/// <summary>
/// Deterministically projects accepted raw Windows Core telemetry. It never
/// collects provider data, reads UI state, persists data, or consults a clock.
/// </summary>
public static class UsageSnapshotV1Projection
{
    public static UsageSnapshotV1 Project(
        UsageSnapshotV1ProjectionInput input,
        DateTimeOffset observedAt)
    {
        ArgumentNullException.ThrowIfNull(input);

        input.Usages.TryGetValue(ProviderNames.Codex, out var codex);
        input.Usages.TryGetValue(ProviderNames.ClaudeCode, out var claude);

        return new UsageSnapshotV1(
            observedAt,
            new[]
            {
                Provider(UsageProviderIdV1.Codex, input.CodexIsEnabled, codex),
                Provider(UsageProviderIdV1.Claude, input.ClaudeIsEnabled, claude)
            });
    }

    private static ProviderSnapshotV1 Provider(
        UsageProviderIdV1 id,
        bool isEnabled,
        ProviderUsage? usage)
    {
        if (!isEnabled)
        {
            return new ProviderSnapshotV1(
                id,
                ProviderStateV1.Disabled,
                lastSuccessfulAt: null,
                error: null,
                Array.Empty<UsageWindowV1>());
        }

        if (usage is null)
        {
            return Unavailable(id, issue: null);
        }

        if (usage.Windows.Count == 0)
        {
            if (usage.LastSuccessfulAt is not null)
            {
                throw new UsageSnapshotV1ValidationException("unavailable_with_last_success");
            }

            return Unavailable(id, usage.Error);
        }

        if (usage.LastSuccessfulAt is not { } lastSuccessfulAt)
        {
            throw new UsageSnapshotV1ValidationException("windows_without_last_success");
        }

        var windows = usage.Windows.Select(Window).ToArray();
        var error = usage.Error is null
            ? null
            : new ProviderErrorV1(ErrorCode(usage.Error));
        return new ProviderSnapshotV1(
            id,
            error is null ? ProviderStateV1.Fresh : ProviderStateV1.Stale,
            lastSuccessfulAt,
            error,
            windows);
    }

    private static ProviderSnapshotV1 Unavailable(
        UsageProviderIdV1 id,
        ProviderIssue? issue)
    {
        var code = issue is null ? ProviderErrorCodeV1.NoData : ErrorCode(issue);
        return new ProviderSnapshotV1(
            id,
            ProviderStateV1.Unavailable,
            lastSuccessfulAt: null,
            new ProviderErrorV1(code),
            Array.Empty<UsageWindowV1>());
    }

    private static UsageWindowV1 Window(UsageWindow window)
    {
        ArgumentNullException.ThrowIfNull(window);
        return new UsageWindowV1(
            window.Kind.CategoryKind switch
            {
                UsageWindowKind.Category.FiveHour => UsageWindowKindV1.FiveHour,
                UsageWindowKind.Category.Weekly => UsageWindowKindV1.Weekly,
                UsageWindowKind.Category.Duration => UsageWindowKindV1.Duration,
                UsageWindowKind.Category.Unknown => UsageWindowKindV1.Unknown,
                _ => throw new UsageSnapshotV1ValidationException("unsupported_window_kind")
            },
            window.DurationMinutes,
            window.UsedPercent,
            window.ResetsAt);
    }

    internal static ProviderErrorCodeV1 ErrorCode(ProviderIssue issue)
    {
        ArgumentNullException.ThrowIfNull(issue);
        return issue.Code switch
        {
            ProviderIssueCode.Refreshing or ProviderIssueCode.NoData =>
                ProviderErrorCodeV1.NoData,
            ProviderIssueCode.CodexNotFound or ProviderIssueCode.ClaudeNotFound or
                ProviderIssueCode.ClaudeWslUnavailable or
                ProviderIssueCode.ClaudeWslDistributionUnavailable =>
                ProviderErrorCodeV1.NotFound,
            ProviderIssueCode.CodexUntrustedExecutable or
                ProviderIssueCode.ClaudeUntrustedExecutable =>
                ProviderErrorCodeV1.UntrustedExecutable,
            ProviderIssueCode.ClaudeNotLoggedIn =>
                ProviderErrorCodeV1.NotAuthenticated,
            ProviderIssueCode.CodexTimedOut or ProviderIssueCode.ClaudeUsageTimedOut =>
                ProviderErrorCodeV1.TimedOut,
            ProviderIssueCode.CodexUsageUnavailable or ProviderIssueCode.CodexLimitMissing or
                ProviderIssueCode.CodexEmptyResponse or ProviderIssueCode.ClaudeUsageUnreadable =>
                ProviderErrorCodeV1.Unreadable,
            ProviderIssueCode.CodexIncompatible or
                ProviderIssueCode.CodexUnsupportedInstallation or
                ProviderIssueCode.ClaudeUnsupportedInstallation or
                ProviderIssueCode.ClaudeGitBashMissing =>
                ProviderErrorCodeV1.Incompatible,
            ProviderIssueCode.CodexCommandFailed or ProviderIssueCode.ClaudeCommandFailed or
                ProviderIssueCode.Cancelled =>
                ProviderErrorCodeV1.CommandFailed,
            ProviderIssueCode.CodexLaunchFailed or ProviderIssueCode.ClaudeLaunchFailed =>
                ProviderErrorCodeV1.LaunchFailed,
            ProviderIssueCode.OutputTooLarge =>
                ProviderErrorCodeV1.OutputTooLarge,
            _ => throw new UsageSnapshotV1ValidationException("unsupported_provider_issue")
        };
    }
}

/// <summary>
/// Canonical v1 JSON codec. Nullable fields are always present and timestamps
/// are UTC RFC 3339 strings with exactly millisecond precision.
/// </summary>
public static class UsageSnapshotV1Json
{
    private static readonly JsonSerializerOptions Options = CreateOptions();

    public static byte[] Encode(UsageSnapshotV1 snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        return JsonSerializer.SerializeToUtf8Bytes(snapshot, Options);
    }

    public static UsageSnapshotV1 Decode(ReadOnlySpan<byte> data)
    {
        ValidateRequiredFields(data);
        var snapshot = JsonSerializer.Deserialize<UsageSnapshotV1>(data, Options);
        return snapshot ?? throw new JsonException("Expected a v1 usage snapshot object.");
    }

    public static UsageSnapshotV1 Decode(string json)
    {
        ArgumentNullException.ThrowIfNull(json);
        ValidateRequiredFields(json);
        var snapshot = JsonSerializer.Deserialize<UsageSnapshotV1>(json, Options);
        return snapshot ?? throw new JsonException("Expected a v1 usage snapshot object.");
    }

    private static void ValidateRequiredFields(ReadOnlySpan<byte> data)
    {
        using var document = JsonDocument.Parse(data.ToArray());
        ValidateRequiredFields(document.RootElement);
    }

    private static void ValidateRequiredFields(string json)
    {
        using var document = JsonDocument.Parse(json);
        ValidateRequiredFields(document.RootElement);
    }

    private static void ValidateRequiredFields(JsonElement root)
    {
        RequireObjectProperties(root, "schemaVersion", "observedAt", "providers");
        var providers = root.GetProperty("providers");
        if (providers.ValueKind != JsonValueKind.Array)
        {
            throw new JsonException("Expected providers to be an array.");
        }

        foreach (var provider in providers.EnumerateArray())
        {
            RequireObjectProperties(provider, "id", "state", "lastSuccessfulAt", "error", "windows");
            var error = provider.GetProperty("error");
            if (error.ValueKind != JsonValueKind.Null)
            {
                RequireObjectProperties(error, "code");
            }

            var windows = provider.GetProperty("windows");
            if (windows.ValueKind != JsonValueKind.Array)
            {
                throw new JsonException("Expected windows to be an array.");
            }

            foreach (var window in windows.EnumerateArray())
            {
                RequireObjectProperties(window, "kind", "durationMinutes", "usedPercent", "resetAt");
            }
        }
    }

    private static void RequireObjectProperties(JsonElement element, params string[] names)
    {
        if (element.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException("Expected a v1 contract object.");
        }

        foreach (var name in names)
        {
            if (!element.TryGetProperty(name, out _))
            {
                throw new JsonException($"Missing required v1 field: {name}.");
            }
        }
    }

    private static JsonSerializerOptions CreateOptions()
    {
        var options = new JsonSerializerOptions
        {
            DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            PropertyNameCaseInsensitive = false,
            WriteIndented = false
        };
        options.Converters.Add(new CanonicalUtcDateTimeOffsetJsonConverter());
        return options;
    }
}

internal sealed class CanonicalUtcDateTimeOffsetJsonConverter : JsonConverter<DateTimeOffset>
{
    private const string Format = "yyyy-MM-dd'T'HH:mm:ss.fff'Z'";

    public override DateTimeOffset Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (value is null ||
            !DateTimeOffset.TryParseExact(
                value,
                Format,
                CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                out var timestamp))
        {
            throw new JsonException("Expected an RFC 3339 UTC timestamp with millisecond precision.");
        }

        return timestamp;
    }

    public override void Write(
        Utf8JsonWriter writer,
        DateTimeOffset value,
        JsonSerializerOptions options) =>
        writer.WriteStringValue(value.ToUniversalTime().ToString(Format, CultureInfo.InvariantCulture));
}

internal sealed class UsageProviderIdV1JsonConverter : JsonConverter<UsageProviderIdV1>
{
    public override UsageProviderIdV1 Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options) => reader.GetString() switch
        {
            "codex" => UsageProviderIdV1.Codex,
            "claude" => UsageProviderIdV1.Claude,
            _ => throw new JsonException("Unknown v1 provider id.")
        };

    public override void Write(Utf8JsonWriter writer, UsageProviderIdV1 value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            UsageProviderIdV1.Codex => "codex",
            UsageProviderIdV1.Claude => "claude",
            _ => throw new JsonException("Unknown v1 provider id.")
        });
}

internal sealed class ProviderStateV1JsonConverter : JsonConverter<ProviderStateV1>
{
    public override ProviderStateV1 Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options) => reader.GetString() switch
        {
            "disabled" => ProviderStateV1.Disabled,
            "unavailable" => ProviderStateV1.Unavailable,
            "fresh" => ProviderStateV1.Fresh,
            "stale" => ProviderStateV1.Stale,
            _ => throw new JsonException("Unknown v1 provider state.")
        };

    public override void Write(Utf8JsonWriter writer, ProviderStateV1 value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            ProviderStateV1.Disabled => "disabled",
            ProviderStateV1.Unavailable => "unavailable",
            ProviderStateV1.Fresh => "fresh",
            ProviderStateV1.Stale => "stale",
            _ => throw new JsonException("Unknown v1 provider state.")
        });
}

internal sealed class UsageWindowKindV1JsonConverter : JsonConverter<UsageWindowKindV1>
{
    public override UsageWindowKindV1 Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options) => reader.GetString() switch
        {
            "fiveHour" => UsageWindowKindV1.FiveHour,
            "weekly" => UsageWindowKindV1.Weekly,
            "duration" => UsageWindowKindV1.Duration,
            "unknown" => UsageWindowKindV1.Unknown,
            _ => throw new JsonException("Unknown v1 window kind.")
        };

    public override void Write(Utf8JsonWriter writer, UsageWindowKindV1 value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            UsageWindowKindV1.FiveHour => "fiveHour",
            UsageWindowKindV1.Weekly => "weekly",
            UsageWindowKindV1.Duration => "duration",
            UsageWindowKindV1.Unknown => "unknown",
            _ => throw new JsonException("Unknown v1 window kind.")
        });
}

internal sealed class ProviderErrorCodeV1JsonConverter : JsonConverter<ProviderErrorCodeV1>
{
    public override ProviderErrorCodeV1 Read(
        ref Utf8JsonReader reader,
        Type typeToConvert,
        JsonSerializerOptions options) => reader.GetString() switch
        {
            "no_data" => ProviderErrorCodeV1.NoData,
            "not_found" => ProviderErrorCodeV1.NotFound,
            "untrusted_executable" => ProviderErrorCodeV1.UntrustedExecutable,
            "not_authenticated" => ProviderErrorCodeV1.NotAuthenticated,
            "timed_out" => ProviderErrorCodeV1.TimedOut,
            "unreadable" => ProviderErrorCodeV1.Unreadable,
            "incompatible" => ProviderErrorCodeV1.Incompatible,
            "command_failed" => ProviderErrorCodeV1.CommandFailed,
            "launch_failed" => ProviderErrorCodeV1.LaunchFailed,
            "output_too_large" => ProviderErrorCodeV1.OutputTooLarge,
            _ => throw new JsonException("Unknown v1 provider error code.")
        };

    public override void Write(Utf8JsonWriter writer, ProviderErrorCodeV1 value, JsonSerializerOptions options) =>
        writer.WriteStringValue(value switch
        {
            ProviderErrorCodeV1.NoData => "no_data",
            ProviderErrorCodeV1.NotFound => "not_found",
            ProviderErrorCodeV1.UntrustedExecutable => "untrusted_executable",
            ProviderErrorCodeV1.NotAuthenticated => "not_authenticated",
            ProviderErrorCodeV1.TimedOut => "timed_out",
            ProviderErrorCodeV1.Unreadable => "unreadable",
            ProviderErrorCodeV1.Incompatible => "incompatible",
            ProviderErrorCodeV1.CommandFailed => "command_failed",
            ProviderErrorCodeV1.LaunchFailed => "launch_failed",
            ProviderErrorCodeV1.OutputTooLarge => "output_too_large",
            _ => throw new JsonException("Unknown v1 provider error code.")
        });
}
