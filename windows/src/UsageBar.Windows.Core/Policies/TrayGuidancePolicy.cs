namespace UsageBar.Windows.Core.Policies;

/// <summary>
/// Decides whether the one-time "keep UsageBar visible" notification should be
/// shown.
///
/// Windows may place a new notification-area icon under the <c>^</c> overflow
/// menu. UsageBar never tries to pin itself — it does not touch Explorer's
/// TrayNotify state, restart Explorer, or synthesize input. It only explains,
/// once per guidance version, how the user can drag the icon out themselves.
/// </summary>
public static class TrayGuidancePolicy
{
    /// <summary>
    /// Current guidance version. Increment whenever the wording changes, so
    /// everyone sees the new text once.
    ///
    /// Version 2 followed physical testing: version 1 told the user to drag the
    /// icon "next to the clock", but Windows placed it beside the `^` button
    /// instead. That is normal Windows ordering, not a failure, so the wording
    /// now asks for the visible tray area rather than an exact position.
    /// </summary>
    public const int CurrentGuidanceVersion = 2;

    /// <summary>
    /// Automatic guidance is shown when nothing has been recorded yet or when
    /// the recorded version is older than the current one. A recorded version
    /// that is newer (a settings file from a future build) is left alone: it is
    /// never downgraded and never re-shown.
    /// </summary>
    public static bool ShouldShowAutomatically(int? versionShown, int currentVersion = CurrentGuidanceVersion)
    {
        if (versionShown is not int shown)
        {
            return true;
        }

        return shown < currentVersion;
    }

    /// <summary>The manual "show tray guidance again" action always shows it.</summary>
    public static bool ShouldShowManually() => true;

    /// <summary>
    /// The version to record after the notification request was successfully
    /// issued. A newer recorded version is preserved rather than rolled back.
    /// </summary>
    public static int VersionAfterShowing(int? versionShown, int currentVersion = CurrentGuidanceVersion) =>
        versionShown is int shown && shown > currentVersion ? shown : currentVersion;
}
