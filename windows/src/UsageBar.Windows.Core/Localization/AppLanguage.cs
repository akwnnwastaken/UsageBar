namespace UsageBar.Windows.Core.Localization;

public enum AppLanguage
{
    Turkish,
    English
}

public static class AppLanguages
{
    /// <summary>Turkish when the UI culture starts with <c>tr</c>, English otherwise.</summary>
    public static AppLanguage Preferred(IEnumerable<string>? preferredLanguages)
    {
        var first = preferredLanguages?.FirstOrDefault();
        return first is not null && first.StartsWith("tr", StringComparison.OrdinalIgnoreCase)
            ? AppLanguage.Turkish
            : AppLanguage.English;
    }

    /// <summary>Parses a stored language value; null when it is not recognized.</summary>
    public static AppLanguage? Resolve(string? storedValue) => storedValue switch
    {
        "turkish" => AppLanguage.Turkish,
        "english" => AppLanguage.English,
        _ => null
    };

    /// <summary>An explicit stored language wins; otherwise the system culture decides.</summary>
    public static AppLanguage Effective(string? storedValue, IEnumerable<string>? preferredLanguages) =>
        Resolve(storedValue) ?? Preferred(preferredLanguages);

    public static string StorageValue(this AppLanguage language) =>
        language == AppLanguage.Turkish ? "turkish" : "english";
}
