using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;
using UsageBar.Windows.Core.Contract;
using UsageBar.Windows.Core.Policies;
using UsageBar.Windows.Core.Providers;
using UsageBar.Windows.Core.Settings;
using Xunit;

namespace UsageBar.Windows.Core.Tests;

public sealed class UsageSnapshotV1Tests
{
    private static readonly DateTimeOffset ObservedAt =
        new(2030, 1, 1, 12, 0, 0, TimeSpan.Zero);

    private static readonly DateTimeOffset CodexSuccessAt =
        new(2030, 1, 1, 11, 59, 0, TimeSpan.Zero);

    private static readonly DateTimeOffset ClaudeSuccessAt =
        new(2030, 1, 1, 11, 58, 0, TimeSpan.Zero);

    private static readonly string[] FixtureNames =
    {
        "fresh-multiple-windows.json",
        "stale-and-disabled.json",
        "unavailable.json"
    };

    [Fact]
    public void SchemaProviderIdsStatesAndRequiredNullsUseExactWireValues()
    {
        var disabled = Project(codexEnabled: false, claudeEnabled: false);
        var unavailable = Project(codexEnabled: true, claudeEnabled: true);
        var fresh = Project(
            codexEnabled: true,
            claudeEnabled: false,
            usages: new Dictionary<string, ProviderUsage>
            {
                [ProviderNames.Codex] = Successful(
                    ProviderNames.Codex,
                    CodexSuccessAt,
                    Window(UsageWindowKind.FiveHour, 20, 300))
            });
        var stale = Project(
            codexEnabled: true,
            claudeEnabled: false,
            usages: new Dictionary<string, ProviderUsage>
            {
                [ProviderNames.Codex] = new ProviderUsage(
                    ProviderNames.Codex,
                    new[] { Window(UsageWindowKind.Weekly, 80, 10_080) },
                    ProviderIssue.CodexTimedOut,
                    CodexSuccessAt)
            });

        Assert.Equal(1, disabled.SchemaVersion);
        Assert.Equal(
            new[] { UsageProviderIdV1.Codex, UsageProviderIdV1.Claude },
            disabled.Providers.Select(provider => provider.Id));

        var documents = new[] { disabled, unavailable, fresh, stale }
            .Select(Json)
            .ToArray();
        Assert.Contains(documents, json => json.Contains("\"id\":\"codex\"", StringComparison.Ordinal));
        Assert.Contains(documents, json => json.Contains("\"id\":\"claude\"", StringComparison.Ordinal));
        Assert.Contains(documents, json => json.Contains("\"state\":\"disabled\"", StringComparison.Ordinal));
        Assert.Contains(documents, json => json.Contains("\"state\":\"unavailable\"", StringComparison.Ordinal));
        Assert.Contains(documents, json => json.Contains("\"state\":\"fresh\"", StringComparison.Ordinal));
        Assert.Contains(documents, json => json.Contains("\"state\":\"stale\"", StringComparison.Ordinal));

        var disabledNode = Node(disabled);
        var provider = ProviderNode(disabledNode, "codex");
        Assert.True(provider.ContainsKey("lastSuccessfulAt"));
        Assert.Null(provider["lastSuccessfulAt"]);
        Assert.True(provider.ContainsKey("error"));
        Assert.Null(provider["error"]);
    }

    [Fact]
    public void ProjectionExportsAllRawWindowsWithoutDisplaySelectionOrDerivedFields()
    {
        var codex = Successful(
            ProviderNames.Codex,
            CodexSuccessAt,
            Window(UsageWindowKind.FiveHour, 20, 300),
            Window(UsageWindowKind.Weekly, 82, 10_080),
            Window(UsageWindowKind.Duration(4_320), 47, 4_320),
            Window(UsageWindowKind.Unknown(3), 18, null));
        var claude = Successful(
            ProviderNames.ClaudeCode,
            ClaudeSuccessAt,
            Window(UsageWindowKind.FiveHour, 31, 300),
            Window(UsageWindowKind.Weekly, 91, 10_080));
        var usages = new Dictionary<string, ProviderUsage>
        {
            [ProviderNames.Codex] = codex,
            [ProviderNames.ClaudeCode] = claude
        };

        Assert.Equal(
            UsageWindowKind.Weekly,
            UsageSummaryCalculator.Summary(ProviderNames.Codex, usages)?.WindowKind);
        Assert.Equal(
            UsageWindowKind.FiveHour,
            UsageSummaryCalculator.Summary(ProviderNames.ClaudeCode, usages)?.WindowKind);

        var snapshot = Project(codexEnabled: true, claudeEnabled: true, usages: usages);
        Assert.Equal(new[] { 20, 82, 47, 18 }, Provider(snapshot, UsageProviderIdV1.Codex).Windows.Select(window => window.UsedPercent));
        Assert.Equal(new[] { 31, 91 }, Provider(snapshot, UsageProviderIdV1.Claude).Windows.Select(window => window.UsedPercent));
        Assert.Equal(
            new[]
            {
                UsageWindowKindV1.FiveHour,
                UsageWindowKindV1.Weekly,
                UsageWindowKindV1.Duration,
                UsageWindowKindV1.Unknown
            },
            Provider(snapshot, UsageProviderIdV1.Codex).Windows.Select(window => window.Kind));
        Assert.Equal(new int?[] { 300, 10_080, 4_320, null },
            Provider(snapshot, UsageProviderIdV1.Codex).Windows.Select(window => window.DurationMinutes));

        var json = Json(snapshot);
        foreach (var forbidden in new[]
        {
            "remainingPercent", "windowId", "nearLimit", "exhausted", "agentAvailable",
            "shouldRun", "scheduler", "job", "command", "source", "Codex", "Claude Code"
        })
        {
            Assert.DoesNotContain(forbidden, json, StringComparison.Ordinal);
        }

        Assert.DoesNotContain(
            typeof(UsageWindowV1).GetProperties(),
            property => property.Name.Equals("WindowId", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void WindowResetAndDurationNullsRemainExplicit()
    {
        var resetAt = new DateTimeOffset(2030, 1, 1, 13, 0, 0, TimeSpan.Zero);
        var codex = Successful(
            ProviderNames.Codex,
            CodexSuccessAt,
            Window(UsageWindowKind.FiveHour, 12, 300, resetAt),
            Window(UsageWindowKind.Unknown(1), 78, null));
        var snapshot = Project(
            codexEnabled: true,
            claudeEnabled: false,
            usages: new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = codex });
        var windows = ProviderNode(Node(snapshot), "codex")["windows"]!.AsArray();

        Assert.Equal("2030-01-01T13:00:00.000Z", windows[0]!["resetAt"]!.GetValue<string>());
        Assert.Null(windows[1]!["durationMinutes"]);
        Assert.Null(windows[1]!["resetAt"]);
        Assert.True(windows[1]!.AsObject().ContainsKey("durationMinutes"));
        Assert.True(windows[1]!.AsObject().ContainsKey("resetAt"));
    }

    [Fact]
    public void ObservedAtIsInjectedAndDoesNotReplaceProviderLastSuccess()
    {
        var codex = Successful(
            ProviderNames.Codex,
            CodexSuccessAt,
            Window(UsageWindowKind.Weekly, 40, 10_080));
        var input = UsageSnapshotV1ProjectionInput.FromSettings(
            new UsageBarSettings { CodexConnected = true, ClaudeConnected = false },
            new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = codex });
        var snapshot = UsageSnapshotV1Projection.Project(input, ObservedAt);

        Assert.Equal(ObservedAt, snapshot.ObservedAt);
        Assert.Equal(CodexSuccessAt, Provider(snapshot, UsageProviderIdV1.Codex).LastSuccessfulAt);
        Assert.NotEqual(snapshot.ObservedAt, Provider(snapshot, UsageProviderIdV1.Codex).LastSuccessfulAt);

        var node = Node(snapshot);
        Assert.Equal("2030-01-01T12:00:00.000Z", node["observedAt"]!.GetValue<string>());
        Assert.Equal(
            "2030-01-01T11:59:00.000Z",
            ProviderNode(node, "codex")["lastSuccessfulAt"]!.GetValue<string>());
    }

    [Fact]
    public void DisabledUnavailableFreshAndStaleSemanticsAreDistinct()
    {
        var current = Project(
            codexEnabled: true,
            claudeEnabled: false,
            usages: new Dictionary<string, ProviderUsage>
            {
                [ProviderNames.Codex] = Successful(
                    ProviderNames.Codex,
                    CodexSuccessAt,
                    Window(UsageWindowKind.FiveHour, 20, 300))
            });
        Assert.Equal(ProviderStateV1.Fresh, Provider(current, UsageProviderIdV1.Codex).State);
        Assert.Equal(ProviderStateV1.Disabled, Provider(current, UsageProviderIdV1.Claude).State);

        var failed = Project(
            codexEnabled: true,
            claudeEnabled: true,
            usages: new Dictionary<string, ProviderUsage>
            {
                [ProviderNames.Codex] = new ProviderUsage(
                    ProviderNames.Codex,
                    new[] { Window(UsageWindowKind.Weekly, 88, 10_080) },
                    ProviderIssue.CodexTimedOut,
                    CodexSuccessAt),
                [ProviderNames.ClaudeCode] = ProviderUsage.Unavailable(
                    ProviderNames.ClaudeCode,
                    ProviderIssue.ClaudeNotLoggedIn)
            });
        Assert.Equal(ProviderStateV1.Stale, Provider(failed, UsageProviderIdV1.Codex).State);
        Assert.Single(Provider(failed, UsageProviderIdV1.Codex).Windows);
        Assert.Equal(ProviderErrorCodeV1.TimedOut, Provider(failed, UsageProviderIdV1.Codex).Error?.Code);
        Assert.Equal(ProviderStateV1.Unavailable, Provider(failed, UsageProviderIdV1.Claude).State);
        Assert.Empty(Provider(failed, UsageProviderIdV1.Claude).Windows);
        Assert.Null(Provider(failed, UsageProviderIdV1.Claude).LastSuccessfulAt);
    }

    [Fact]
    public void FreeFormProviderErrorDetailNeverEntersJson()
    {
        const string privateDetail = "arbitrary-internal-error-detail-must-not-cross-wire";
        var usage = new ProviderUsage(
            ProviderNames.Codex,
            new[] { Window(UsageWindowKind.Weekly, 73, 10_080) },
            ProviderIssue.CodexLaunchFailed(privateDetail),
            CodexSuccessAt);
        var snapshot = Project(
            codexEnabled: true,
            claudeEnabled: false,
            usages: new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = usage });
        var json = Json(snapshot);

        Assert.DoesNotContain(privateDetail, json, StringComparison.Ordinal);
        Assert.DoesNotContain("CodexLaunchFailed", json, StringComparison.Ordinal);
        Assert.Contains("\"code\":\"launch_failed\"", json, StringComparison.Ordinal);
    }

    public static TheoryData<ProviderIssueCode, ProviderErrorCodeV1> ErrorMappings => new()
    {
        { ProviderIssueCode.Refreshing, ProviderErrorCodeV1.NoData },
        { ProviderIssueCode.NoData, ProviderErrorCodeV1.NoData },
        { ProviderIssueCode.CodexUsageUnavailable, ProviderErrorCodeV1.Unreadable },
        { ProviderIssueCode.CodexLimitMissing, ProviderErrorCodeV1.Unreadable },
        { ProviderIssueCode.CodexNotFound, ProviderErrorCodeV1.NotFound },
        { ProviderIssueCode.CodexUntrustedExecutable, ProviderErrorCodeV1.UntrustedExecutable },
        { ProviderIssueCode.CodexUnsupportedInstallation, ProviderErrorCodeV1.Incompatible },
        { ProviderIssueCode.CodexTimedOut, ProviderErrorCodeV1.TimedOut },
        { ProviderIssueCode.CodexEmptyResponse, ProviderErrorCodeV1.Unreadable },
        { ProviderIssueCode.CodexIncompatible, ProviderErrorCodeV1.Incompatible },
        { ProviderIssueCode.CodexCommandFailed, ProviderErrorCodeV1.CommandFailed },
        { ProviderIssueCode.CodexLaunchFailed, ProviderErrorCodeV1.LaunchFailed },
        { ProviderIssueCode.ClaudeNotFound, ProviderErrorCodeV1.NotFound },
        { ProviderIssueCode.ClaudeUntrustedExecutable, ProviderErrorCodeV1.UntrustedExecutable },
        { ProviderIssueCode.ClaudeUnsupportedInstallation, ProviderErrorCodeV1.Incompatible },
        { ProviderIssueCode.ClaudeNotLoggedIn, ProviderErrorCodeV1.NotAuthenticated },
        { ProviderIssueCode.ClaudeUsageUnreadable, ProviderErrorCodeV1.Unreadable },
        { ProviderIssueCode.ClaudeUsageTimedOut, ProviderErrorCodeV1.TimedOut },
        { ProviderIssueCode.ClaudeLaunchFailed, ProviderErrorCodeV1.LaunchFailed },
        { ProviderIssueCode.ClaudeCommandFailed, ProviderErrorCodeV1.CommandFailed },
        { ProviderIssueCode.ClaudeGitBashMissing, ProviderErrorCodeV1.Incompatible },
        { ProviderIssueCode.ClaudeWslUnavailable, ProviderErrorCodeV1.NotFound },
        { ProviderIssueCode.ClaudeWslDistributionUnavailable, ProviderErrorCodeV1.NotFound },
        { ProviderIssueCode.OutputTooLarge, ProviderErrorCodeV1.OutputTooLarge },
        { ProviderIssueCode.Cancelled, ProviderErrorCodeV1.CommandFailed }
    };

    [Theory]
    [MemberData(nameof(ErrorMappings))]
    public void EveryWindowsIssueMapsIntoTheFrozenAllowlist(
        ProviderIssueCode internalCode,
        ProviderErrorCodeV1 publicCode)
    {
        var issue = new ProviderIssue(internalCode, "detail-that-must-be-discarded");
        Assert.Equal(publicCode, UsageSnapshotV1Projection.ErrorCode(issue));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(101)]
    public void InvalidUsedPercentIsRejectedInsteadOfClamped(int value)
    {
        var usage = Successful(
            ProviderNames.Codex,
            CodexSuccessAt,
            Window(UsageWindowKind.Weekly, value, 10_080));

        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            Project(
                codexEnabled: true,
                claudeEnabled: false,
                usages: new Dictionary<string, ProviderUsage> { [ProviderNames.Codex] = usage }));
    }

    [Fact]
    public void InvalidDurationAndDurationKindWithoutDurationAreRejected()
    {
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new UsageWindowV1(UsageWindowKindV1.Duration, 0, 10, resetAt: null));
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new UsageWindowV1(UsageWindowKindV1.Duration, -1, 10, resetAt: null));
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new UsageWindowV1(UsageWindowKindV1.Duration, null, 10, resetAt: null));
    }

    [Fact]
    public void InvalidProviderStateCombinationsAreRejected()
    {
        var error = new ProviderErrorV1(ProviderErrorCodeV1.NoData);
        var windows = new[] { new UsageWindowV1(UsageWindowKindV1.Weekly, 10_080, 10, null) };

        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new ProviderSnapshotV1(UsageProviderIdV1.Codex, ProviderStateV1.Disabled, null, error, Array.Empty<UsageWindowV1>()));
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new ProviderSnapshotV1(UsageProviderIdV1.Codex, ProviderStateV1.Unavailable, null, null, Array.Empty<UsageWindowV1>()));
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new ProviderSnapshotV1(UsageProviderIdV1.Codex, ProviderStateV1.Fresh, CodexSuccessAt, null, Array.Empty<UsageWindowV1>()));
        Assert.Throws<UsageSnapshotV1ValidationException>(() =>
            new ProviderSnapshotV1(UsageProviderIdV1.Codex, ProviderStateV1.Stale, CodexSuccessAt, null, windows));
    }

    [Theory]
    [InlineData("lastSuccessfulAt")]
    [InlineData("error")]
    public void DecoderRejectsMissingRequiredNullableProviderFields(string field)
    {
        var node = Node(Project(codexEnabled: false, claudeEnabled: false));
        ProviderNode(node, "codex").Remove(field);

        Assert.ThrowsAny<Exception>(() => UsageSnapshotV1Json.Decode(node.ToJsonString()));
    }

    [Theory]
    [InlineData("durationMinutes")]
    [InlineData("resetAt")]
    public void DecoderRejectsMissingRequiredNullableWindowFields(string field)
    {
        var node = JsonNode.Parse(Fixtures.ReadText("contract/v1/fresh-multiple-windows.json"))!.AsObject();
        ProviderNode(node, "codex")["windows"]!.AsArray()[0]!.AsObject().Remove(field);

        Assert.ThrowsAny<Exception>(() => UsageSnapshotV1Json.Decode(node.ToJsonString()));
    }

    public static TheoryData<string> InvalidWireDocuments => new()
    {
        "schemaVersion",
        "providerId",
        "providerState",
        "windowKind",
        "errorCode",
        "usedPercent",
        "durationMinutes",
        "timestamp",
        "providerCardinality"
    };

    [Theory]
    [MemberData(nameof(InvalidWireDocuments))]
    public void DecoderRejectsIncompatibleOrMalformedWireData(string mutation)
    {
        var node = JsonNode.Parse(Fixtures.ReadText("contract/v1/stale-and-disabled.json"))!.AsObject();
        var codex = ProviderNode(node, "codex");
        switch (mutation)
        {
            case "schemaVersion":
                node["schemaVersion"] = 2;
                break;
            case "providerId":
                codex["id"] = "Codex";
                break;
            case "providerState":
                codex["state"] = "ready";
                break;
            case "windowKind":
                codex["windows"]!.AsArray()[0]!["kind"] = "month";
                break;
            case "errorCode":
                codex["error"]!["code"] = "raw_failure";
                break;
            case "usedPercent":
                codex["windows"]!.AsArray()[0]!["usedPercent"] = 101;
                break;
            case "durationMinutes":
                codex["windows"]!.AsArray()[0]!["durationMinutes"] = 0;
                break;
            case "timestamp":
                node["observedAt"] = "2030-02-01 09:30:00";
                break;
            case "providerCardinality":
                node["providers"]!.AsArray().RemoveAt(1);
                break;
            default:
                throw new InvalidOperationException("Unknown synthetic mutation.");
        }

        Assert.ThrowsAny<Exception>(() => UsageSnapshotV1Json.Decode(node.ToJsonString()));
    }

    [Theory]
    [MemberData(nameof(SharedFixtureNames))]
    public void SharedFixtureDecodesAndReserializesSemantically(string fixtureName)
    {
        var data = Fixtures.ReadBytes($"contract/v1/{fixtureName}");
        var original = JsonNode.Parse(data);
        Assert.NotNull(original);
        Assert.Equal(1, original!["schemaVersion"]!.GetValue<int>());

        var snapshot = UsageSnapshotV1Json.Decode(data);
        Assert.Equal(1, snapshot.SchemaVersion);
        Assert.Equal(
            new[] { UsageProviderIdV1.Codex, UsageProviderIdV1.Claude },
            snapshot.Providers.Select(provider => provider.Id));

        var reserialized = JsonNode.Parse(UsageSnapshotV1Json.Encode(snapshot));
        Assert.True(JsonNode.DeepEquals(original, reserialized), fixtureName);
    }

    public static TheoryData<string> SharedFixtureNames => new()
    {
        FixtureNames[0],
        FixtureNames[1],
        FixtureNames[2]
    };

    [Fact]
    public void SharedFixturesCoverAllStatesKindsAndNullableReset()
    {
        var snapshots = FixtureNames
            .Select(name => UsageSnapshotV1Json.Decode(Fixtures.ReadBytes($"contract/v1/{name}")))
            .ToArray();
        var providers = snapshots.SelectMany(snapshot => snapshot.Providers).ToArray();

        Assert.Equal(
            Enum.GetValues<ProviderStateV1>().Order(),
            providers.Select(provider => provider.State).Distinct().Order());
        Assert.Equal(
            Enum.GetValues<UsageWindowKindV1>().Order(),
            providers.SelectMany(provider => provider.Windows).Select(window => window.Kind).Distinct().Order());
        Assert.Contains(providers, provider =>
            provider.State == ProviderStateV1.Stale && provider.Windows.Count > 0 && provider.Error is not null);
        Assert.Contains(providers, provider =>
            provider.State == ProviderStateV1.Unavailable && provider.LastSuccessfulAt is null);
        Assert.Contains(providers.SelectMany(provider => provider.Windows), window => window.ResetAt is null);
    }

    [Fact]
    public void SerializationIsUtcMillisecondCultureIndependentAndDeterministic()
    {
        var offsetObservedAt = new DateTimeOffset(2030, 1, 1, 15, 0, 0, TimeSpan.FromHours(3));
        var snapshot = Project(codexEnabled: false, claudeEnabled: false, observedAt: offsetObservedAt);
        var originalCulture = CultureInfo.CurrentCulture;
        var originalUiCulture = CultureInfo.CurrentUICulture;

        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("tr-TR");
            var first = UsageSnapshotV1Json.Encode(snapshot);
            var second = UsageSnapshotV1Json.Encode(snapshot);

            Assert.Equal(first, second);
            Assert.Contains(
                "\"observedAt\":\"2030-01-01T12:00:00.000Z\"",
                Encoding.UTF8.GetString(first),
                StringComparison.Ordinal);
            Assert.True(JsonNode.DeepEquals(JsonNode.Parse(first), JsonNode.Parse(second)));
        }
        finally
        {
            CultureInfo.CurrentCulture = originalCulture;
            CultureInfo.CurrentUICulture = originalUiCulture;
        }
    }

    [Fact]
    public void SerializedContractContainsNoProviderImplementationOrSchedulerDetails()
    {
        var snapshot = Project(codexEnabled: true, claudeEnabled: true);
        var json = Json(snapshot);
        foreach (var forbidden in new[]
        {
            "ProviderIssue", "ProviderUsage", "DiagnosticCode", "executable", "stderr", "stdout",
            "adapter", "session", "history", "remainingPercent", "windowId", "scheduler", "AgentRunner"
        })
        {
            Assert.DoesNotContain(forbidden, json, StringComparison.OrdinalIgnoreCase);
        }
    }

    private static UsageSnapshotV1 Project(
        bool codexEnabled,
        bool claudeEnabled,
        IReadOnlyDictionary<string, ProviderUsage>? usages = null,
        DateTimeOffset? observedAt = null) =>
        UsageSnapshotV1Projection.Project(
            new UsageSnapshotV1ProjectionInput(
                codexEnabled,
                claudeEnabled,
                usages ?? new Dictionary<string, ProviderUsage>()),
            observedAt ?? ObservedAt);

    private static ProviderUsage Successful(
        string name,
        DateTimeOffset lastSuccessfulAt,
        params UsageWindow[] windows) =>
        new(name, windows, error: null, lastSuccessfulAt);

    private static UsageWindow Window(
        UsageWindowKind kind,
        int usedPercent,
        int? durationMinutes,
        DateTimeOffset? resetAt = null) =>
        new(kind, usedPercent, resetAt, durationMinutes);

    private static ProviderSnapshotV1 Provider(UsageSnapshotV1 snapshot, UsageProviderIdV1 id) =>
        snapshot.Providers.Single(provider => provider.Id == id);

    private static JsonObject Node(UsageSnapshotV1 snapshot) =>
        JsonNode.Parse(UsageSnapshotV1Json.Encode(snapshot))!.AsObject();

    private static JsonObject ProviderNode(JsonObject snapshot, string id) =>
        snapshot["providers"]!
            .AsArray()
            .Select(provider => provider!.AsObject())
            .Single(provider => provider["id"]!.GetValue<string>() == id);

    private static string Json(UsageSnapshotV1 snapshot) =>
        Encoding.UTF8.GetString(UsageSnapshotV1Json.Encode(snapshot));
}
