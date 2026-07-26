# UsageBar — Windows port

A native Windows system-tray build of UsageBar, living beside the macOS
application in the same repository.

The macOS application is the behavioral source of truth and is **read-only** for
this port. Nothing under `Sources/`, `tests/`, `Package.swift`, `build.sh`,
`Info.plist`, `README.md`, `SECURITY.md`, `.github/workflows/ci.yml` or
`.github/workflows/release-candidate.yml` is modified by the Windows work.

> **Status.** Codex works end to end. **Claude Code is not implemented on
> Windows yet** — it is shown disabled and explicitly labeled as unsupported in
> the tray menu and the panel. No placeholder value is ever displayed for it.

---

## 1. Where everything lives

```text
UsageBar/
├── Sources/                              macOS app          (read-only)
├── tests/                                macOS tests        (read-only)
├── Package.swift, build.sh, Info.plist   macOS build        (read-only)
├── shared/fixtures/                      provider fixtures used by the Windows tests
│   ├── codex/
│   └── claude/
├── docs/windows-port.md                  this document
├── .github/workflows/windows-ci.yml      Windows CI
└── windows/
    ├── UsageBar.Windows.sln
    ├── Directory.Build.props             settings scoped to the Windows build only
    ├── src/
    │   ├── UsageBar.Windows.Core/            net8.0        platform-independent behavior
    │   ├── UsageBar.Windows.Infrastructure/  net8.0-windows platform mechanics
    │   └── UsageBar.Windows.App/             net8.0-windows WPF tray application
    └── tests/
        ├── UsageBar.Windows.Core.Tests/
        └── UsageBar.Windows.Infrastructure.Tests/
```

### Architecture

| Project | Contains | May reference |
| --- | --- | --- |
| **Core** | models, policies, parsers, localization, safe diagnostics, tray-guidance decision | nothing platform-specific |
| **Infrastructure** | Job Object containment, secure process launch, executable discovery/trust, provider adapters, persistence, auto-start, environment facts | Win32, registry, filesystem |
| **App** | WPF lifecycle, tray icon, popup panel, settings window, timers, history chart | Core + Infrastructure |

Core deliberately references no WPF, Windows Forms, registry, Win32 process,
tray or Job Object API. Every behavior rule is therefore testable on any
platform, which is why the Core suite runs identically on macOS and Windows.

---

## 2. macOS behavior used as reference

| Rule | macOS source | Windows source | Windows test |
| --- | --- | --- | --- |
| Remaining, never used, percentage | `UsageWindow` | `Providers/UsageWindow.cs` | `BehaviorParityTests` |
| Claude five-hour, weekly fallback | `UsageSummaryCalculator` | `Policies/UsageSummaryCalculator.cs` | `ClaudeUsageParserTests`, `BehaviorParityTests` |
| Codex most-constrained window | `UsageSummaryCalculator` | same | `CodexResponseParserTests` |
| Display noise filter (hold sub-reset rises) | `UsageDisplayNoiseFilter` | `Policies/UsageDisplayNoiseFilter.cs` | `UsageDisplayNoiseFilterTests` |
| Alert presets 10/5, 20/10, 30/15 | `UsageAlertPreset` | `Policies/UsageAlertPolicy.cs` | `BehaviorParityTests` |
| Refresh 1/2/5 minutes, default 5 | `UsageRefreshInterval` | `Policies/RefreshPolicies.cs` | `BehaviorParityTests` |
| 30-second panel-open staleness | `UsageRefreshPolicy` | same | `BehaviorParityTests` |
| 30-second provider rotation | `ProviderRotation` | same | `BehaviorParityTests` |
| Disconnect selection / auto-rotate | `ProviderConnectionTransition` | same | `BehaviorParityTests` |
| Stale data keeps the last good value | `ProviderUsage.stale` | `Providers/ProviderUsage.cs` | `BehaviorParityTests` |
| 24 h history, 1 sample/minute, caps | `UsageHistoryModel` | `History/UsageHistoryModel.cs` | `UsageHistoryTests` |
| Chart restarts at the last reset | `UsageHistoryChartModel` | `History/UsageHistoryChartModel.cs` | `UsageHistoryTests` |
| Codex outcome ordering (timeout wins) | `CodexFetchOutcome` | `Policies/CodexFetchOutcome.cs` | `CodexResponseParserTests`, `CodexUsageReaderTests` |
| Codex JSON-RPC parsing | `UsageParser.codexResponse` | `Parsing/CodexResponseParser.cs` | `CodexResponseParserTests` |
| Claude print-mode parsing | `UsageParser.claudePrintUsage` | `Parsing/ClaudeUsageParser.cs` | `ClaudeUsageParserTests` |
| Reset parsing in the reset's own zone, DST-aware | `parseClaudeReset` | `Parsing/ClaudeResetParser.cs` | `ClaudeResetParserTests` |
| Turkish/English strings, complete durations | `Localizer` | `Localization/Localizer.cs` | `LocalizationAndTrayPresentationTests` |
| Safe diagnostic codes | `ProviderIssue.diagnosticCode` | `Providers/ProviderIssue.cs` | `DiagnosticsTests` |

The Claude parser is ported and fully tested even though no Windows Claude
adapter exists yet: the parsing rules are the part that is expensive to get
right, and having them in place keeps the eventual adapter small.

---

## 3. Intentional platform differences

| # | Difference | Why |
| --- | --- | --- |
| 1 | The percentage is drawn **inside** the tray icon instead of shown as menu-bar text. | Windows has no persistent text label beside a notification-area icon. |
| 2 | The reset countdown appears in the tooltip rather than next to the icon. | Same reason; a 16 px icon cannot hold `42 · 1h 18m`. |
| 3 | A popup **panel** replaces the macOS menu. | Windows tray menus cannot host rich content such as a chart. |
| 4 | Settings are a separate child window. | Keeps the panel compact; the panel stays open while it has focus. |
| 5 | Settings and history are JSON files under `%LOCALAPPDATA%\UsageBar\` instead of `UserDefaults`. | Windows has no `UserDefaults`. Same fields, same limits, same sanitization. |
| 6 | History timestamps are ISO-8601 instead of Apple reference-date offsets. | File-format detail only; retention behavior is identical. |
| 7 | Auto-start uses `HKCU\…\Run` instead of `SMAppService`. | Behind `IAutoStartService`, so a future MSIX `StartupTask` can replace it. |
| 8 | Containment uses a Job Object rather than a POSIX process group. | Job Objects are the Windows equivalent, and kill-on-job-close is stronger. |
| 9 | Executable trust checks ACLs rather than POSIX mode bits. | Same intent: reject anything a wider group than the current user can write. |
| 10 | An extra `unsupported_installation` issue code exists. | Windows can install a CLI as a shell-only `.cmd` shim, which macOS cannot. |
| 11 | Minute-less reset times resolve with seconds pinned to zero. | Sub-minute detail never reaches a countdown displayed in minutes. |
| 12 | The Claude parser also accepts a colon-less label and a reset on the following line. | Cheap resilience; the print-mode shape is still what the adapter will use. |
| 13 | First-run tray-visibility guidance exists. | New tray icons can land in the `^` overflow menu, which has no macOS equivalent. |
| 14 | **Claude Code is not available at all in this build.** | The Windows adapters are not written yet. Shown disabled, never faked. |

---

## 4. Process isolation model

Providers are started through `ProviderProcessSession`, in this order:

1. Create the three redirected pipes and a **Job Object** configured with
   `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
2. `CreateProcessW` with `CREATE_SUSPENDED | CREATE_NO_WINDOW |
   CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT`, an explicit
   executable path, an argument array, and a `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`
   restricting inheritance to exactly those three pipe handles.
3. `AssignProcessToJobObject`.
4. `ResumeThread` — only now does the process run its first instruction.

Because the process is contained before it executes, nothing it spawns can
escape the job. Closing the job handle terminates the entire tree, and that is
what happens on success, on timeout, on cancellation and on application exit.

Also enforced:

- **No shell, ever.** No `cmd.exe`, no `powershell -Command`, no CMD AutoRun, no
  PowerShell profiles. Arguments are encoded from an explicit array with the
  documented `CommandLineToArgvW` rules, verified by a round-trip test against
  the real Win32 parser.
- **Its own directory.** Providers run from `%LOCALAPPDATA%\UsageBar\provider-run`,
  never the user's project or the folder UsageBar was launched from.
- **A small environment.** Rebuilt from an allowlist with a system-only `PATH`,
  so a directory the user prepended to their own `PATH` cannot resolve a
  provider, and no unrelated variable is inherited.
- **Bounded output.** 2 MiB of stdout, 64 KiB of stderr, captured separately.
  Overflow ends the run and is reported as `output_too_large`.
- **Deadlines.** 15 seconds by default. A run stopped by its own deadline is a
  timeout even though UsageBar's termination leaves a non-zero exit code — that
  code is never read as a command failure.
- **SafeHandle everywhere.** Job, process, thread and the process-attribute list
  are all `SafeHandle` subclasses, so an exception during creation cannot leak a
  handle.

---

## 5. Executable discovery and trust

A candidate is accepted only when it:

- resolves (through symlinks and junctions) to an existing regular file;
- lives inside the installation root that candidate is expected in;
- is a directly executable type (`.exe`/`.com`);
- is not writable by a group wider than the current user (Everyone, Users,
  Authenticated Users, Interactive, Guests, Anonymous).

The current working directory is never a candidate, and the user's `PATH` is
never used to pick a winner.

### Supported Codex installation formats

| Format | Location | Adapter |
| --- | --- | --- |
| Native per-user | `%LOCALAPPDATA%\Programs\codex\codex.exe` | `native_exe` |
| Native machine-wide | `%ProgramFiles%\codex\codex.exe` | `native_exe` |
| ChatGPT desktop bundle | `%LOCALAPPDATA%\Programs\ChatGPT\resources\codex.exe` | `native_exe` |
| WinGet link | `%LOCALAPPDATA%\Microsoft\WinGet\Links\codex.exe` | `native_exe` |
| Scoop shim | `%USERPROFILE%\scoop\shims\codex.exe` | `native_exe` |
| Cargo | `%USERPROFILE%\.cargo\bin\codex.exe` | `native_exe` |
| npm global | `%APPDATA%\npm\node_modules\@openai\codex\bin\codex.js` + a validated `node.exe` | `node_launcher` |
| User-selected | any path, validated identically | `native_exe` |

For the npm layout the `.cmd` shim is deliberately **ignored** — running it would
mean invoking `cmd.exe`. The script and a real `node.exe` are validated
separately and Node is started directly with the script as its first argument.

### Supported Claude installation formats

**None yet.** The layering is planned as native Windows → Git for Windows →
optional WSL, and the print-mode parser is already in place, but no adapter
exists in this build.

### Unsupported installation formats

- A bare `.cmd`, `.bat`, `.ps1` or `.vbs` shim with no resolvable interpreter.
  Reported as `unsupported_installation`; UsageBar does not fall back to a shell.
- An npm install with no discoverable `node.exe`.
- Anything outside the documented roots, or writable by a wider group than the
  current user.

---

## 6. Privacy model

Stored under `%LOCALAPPDATA%\UsageBar\`:

- `settings.json` — connection choices, language, refresh interval, colour and
  threshold preferences, history toggle, tray-guidance version, and an optional
  user-selected executable path.
- `history.json` — timestamp plus remaining integer percentage per quota window.

Never stored, never logged, never transmitted: passwords, API keys, access or
session tokens, credential-store contents, raw provider output, environment
dumps, project paths or command lines. UsageBar makes no network requests of its
own, never signs in to a provider website, uses no browser automation, no
unofficial web endpoints, no telemetry and no crash-reporting SDK.

The copied diagnostic summary may contain only: UsageBar version, Windows build
number, OS and process architecture, language, connection state, adapter kind,
executable state, quota-window kinds, last refresh time, a fixed error code,
tray-guidance version, auto-start state and history counts. Every emitted value
passes through `DiagnosticsSanitizer`, which replaces anything resembling a
path, URL, environment expansion, command line or secret with `redacted`, and
issue codes are validated against a closed set. `DiagnosticsTests` feeds it real
paths, tokens and command lines and asserts none survive.

---

## 7. Tray-visibility guidance

Windows may place a new notification-area icon under the `^` overflow menu.

UsageBar **never** attempts to pin itself. It does not modify Explorer's
`TrayNotify` state, does not touch another application's tray settings, does not
restart Explorer, does not simulate dragging, does not move the mouse and does
not generate synthetic input.

Instead, after the icon has been created successfully on first launch, it shows
one non-modal balloon:

| | Turkish | English |
| --- | --- | --- |
| Title | UsageBar'ı görünür tutun | Keep UsageBar visible |
| Body | UsageBar simgesini sürekli görmek için görev çubuğundaki ^ simgesini açıp UsageBar'ı saat yanına sürükleyin. | To keep UsageBar visible, open the ^ menu on the taskbar and drag UsageBar next to the clock. |
| Manual action | Sistem tepsisi yönlendirmesini yeniden göster | Show system tray guidance again |

`trayGuidanceVersionShown` is recorded only after the notification request was
issued. A stored version equal to or newer than the current one does not show
it again and is never rolled back; an older one shows the updated guidance once.
The manual action always shows it, and recording the version leaves every other
setting untouched — all asserted in `TrayGuidanceTests`.

---

## 8. Building and running locally

Requirements: Windows 10 1809 (x64) or newer and the .NET 8 SDK.

```powershell
dotnet restore windows/UsageBar.Windows.sln
dotnet build   windows/UsageBar.Windows.sln --configuration Release --no-restore
dotnet test    windows/UsageBar.Windows.sln --configuration Release --no-build
```

Run the tray application:

```powershell
dotnet run --project windows/src/UsageBar.Windows.App/UsageBar.Windows.App.csproj -c Release
```

`Core` and `Core.Tests` target `net8.0` and build and run on any platform.
`Infrastructure`, `App` and `Infrastructure.Tests` target `net8.0-windows`; they
**compile** on macOS or Linux (`EnableWindowsTargeting` is set) but the tests
that need a real Windows kernel are marked `[WindowsFact]` / `[WindowsTheory]`
and report as **skipped** — never as passed — anywhere else.

## 9. Packaging

The first milestone ships a portable ZIP. No installer, no MSIX, no Microsoft
Store, no auto-update, no ARM64.

```powershell
dotnet publish windows/src/UsageBar.Windows.App/UsageBar.Windows.App.csproj `
  --configuration Release `
  --runtime win-x64 `
  --self-contained true
```

**Decision: self-contained folder publish, not single-file.** WPF plus the
Windows Forms `NotifyIcon` needs native resources extracted at runtime, and
single-file adds an extraction step that has historically caused tray-icon and
native-resource problems for exactly this combination. The folder publish is
larger (~145 MB) but has no such failure mode. Single-file can be revisited once
the tray behavior is confirmed on real machines.

The published `UsageBar.exe` is a PE32+ **GUI**-subsystem binary, so no console
window is ever created, with the PerMonitorV2 DPI manifest embedded.

## 10. Continuous integration

`.github/workflows/windows-ci.yml` runs on `windows-latest` and performs restore,
Release build and the full test suite, uploading the `.trx` results.

Its job is named **`windows-build-and-test`**, deliberately *not*
`build-and-test`: that context name is the required status check the macOS
workflow owns on `main`, and a second job sharing it would make the protected
check ambiguous. The macOS workflows are untouched and keep their own triggers.

---

## 11. Known limitations

1. **Claude Code is not implemented.** Codex is the only working provider.
2. **No physical Windows verification.** Everything reported as verified was
   verified on a GitHub Actions `windows-latest` runner. That is a real Windows
   environment, but it is not a physical user machine: the tray icon, the popup
   placement, DPI changes, multi-monitor behavior, the balloon notification and
   the light/dark appearance have **not** been seen by a human on real hardware.
3. **No signed-in Codex has been exercised.** The adapter is tested against
   fixtures and against stock Windows executables standing in for the app
   server. A real signed-in Codex installation has not been read from.
4. Codex candidate locations come from documented installation layouts, not from
   observation on a machine with each one installed.
5. The ACL check treats an unreadable ACL as "not writable by others"; the path
   and file-type checks still apply.
6. Windows ARM64 is out of scope; the publish is x64 only.
7. The panel uses an opaque background. Mica/Acrylic is deliberately deferred.
8. `windows-ci.yml` does not yet publish or upload a ZIP artifact.
