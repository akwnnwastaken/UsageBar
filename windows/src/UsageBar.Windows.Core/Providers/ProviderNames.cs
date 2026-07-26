namespace UsageBar.Windows.Core.Providers;

/// <summary>
/// The provider identifiers UsageBar uses everywhere: preference keys, history
/// keys, summary selection and diagnostics. They are deliberately identical to
/// the macOS application's provider names so the behavior rules read the same.
/// </summary>
public static class ProviderNames
{
    public const string Codex = "Codex";
    public const string ClaudeCode = "Claude Code";

    public static IReadOnlyList<string> All { get; } = new[] { Codex, ClaudeCode };

    /// <summary>Short diagnostics/settings key for a provider name.</summary>
    public static string Key(string providerName) =>
        providerName == ClaudeCode ? "claude" : "codex";
}
