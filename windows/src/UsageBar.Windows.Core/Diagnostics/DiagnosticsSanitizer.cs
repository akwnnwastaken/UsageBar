namespace UsageBar.Windows.Core.Diagnostics;

/// <summary>
/// Last line of defense for the diagnostics summary. Any value that looks like a
/// path, a URL, an environment expansion, a command line or a secret is replaced
/// with <see cref="Redacted"/> instead of being printed.
///
/// This runs on <em>every</em> emitted value, so a future caller that
/// accidentally passes an executable path or a token cannot leak it.
/// </summary>
public static class DiagnosticsSanitizer
{
    public const string Redacted = "redacted";

    public const string None = "none";

    /// <summary>Values longer than this are assumed to be data, not a label.</summary>
    public const int MaximumTokenLength = 48;

    private static readonly char[] ForbiddenCharacters =
    {
        '/', '\\', ':', '%', '$', '~', '"', '\'', '=', ',', ';', '|', '&', '<', '>', '\n', '\r', '\t', '\0'
    };

    private static readonly string[] ForbiddenSubstrings =
    {
        "http", "sk-", "bearer", "token", "secret", "password", "passwd", "apikey", "api_key",
        "users", "home", "appdata", "program files", "\\\\"
    };

    public static string SafeToken(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return None;
        }

        var trimmed = value.Trim();
        if (trimmed.Length > MaximumTokenLength)
        {
            return Redacted;
        }

        if (trimmed.IndexOfAny(ForbiddenCharacters) >= 0)
        {
            return Redacted;
        }

        if (trimmed.Any(char.IsWhiteSpace))
        {
            return Redacted;
        }

        var lower = trimmed.ToLowerInvariant();
        if (ForbiddenSubstrings.Any(forbidden => lower.Contains(forbidden, StringComparison.Ordinal)))
        {
            return Redacted;
        }

        return trimmed;
    }

    /// <summary>True when a value would survive <see cref="SafeToken"/> unchanged.</summary>
    public static bool IsSafeToken(string? value) =>
        value is not null && SafeToken(value) == value.Trim();
}
