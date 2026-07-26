# UsageBar — Windows port

A native Windows system-tray build of UsageBar, living beside the macOS
application in the same repository.

The macOS application is the behavioral source of truth and is **read-only** for
this port. Nothing under `Sources/`, `tests/`, `Package.swift`, `build.sh`,
`Info.plist`, `README.md`, `SECURITY.md`, `.github/workflows/ci.yml` or
`.github/workflows/release-candidate.yml` is modified by the Windows work.

> **Status.** Codex works end to end and has been verified on a physical
> Windows machine. **Claude Code is implemented but has not been physically
> tested yet** — see the checklist in section 12.

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

| Claude outcome ordering (timeout/cancel win) | `ClaudeUsageFetcher` | `Policies/ClaudeFetchOutcome.cs` | `ClaudeUsageReaderTests` |
| Claude query flags (`-p /usage`, no session, no tools) | `ClaudeUsageFetcher` | `Providers/ClaudeQuery.cs` | `ClaudeUsageReaderTests` |

Claude's query is the same one macOS runs — `-p "/usage"` in print mode with
session persistence, setting sources, Chrome, MCP and tools all disabled — so
the reading costs no model quota, registers no session and leaves no transcript.
Output is parsed only after the process has finished, so a partially written
final line can never drop the weekly window.

---

## 3. Intentional platform differences

| # | Difference | Why |
| --- | --- | --- |
| 1 | The percentage is drawn **inside** the tray icon instead of shown as menu-bar text, with no border or plate around it. | Windows has no persistent text label beside a notification-area icon, and at 16 px a border steals the room the number needs. |
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
| 14 | The panel sizes itself to its content between a minimum and the monitor's working area, and its actions wrap onto further lines. | Turkish runs longer than English, and a fixed width clipped the footer buttons on a real machine. |
| 15 | Claude runs either as a native Windows executable or inside a WSL distribution, selectable in settings. | Windows has two supported Claude installation targets; macOS has one. |

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
| **Official native installer** | `%LOCALAPPDATA%\Programs\OpenAI\Codex\bin\codex.exe` | `native_exe` |
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

#### Findings from physical testing

**2026-07-26 — the official native installer was not discovered.**
On a real machine running `codex-cli 0.145.0`, `where.exe codex` resolved to
`C:\Users\<user>\AppData\Local\Programs\OpenAI\Codex\bin\codex.exe`, but
UsageBar reported
`codex=connected:true,executable:missing,adapter:none,state:error,windows:none,issue:codex_not_found`.

The candidate list had been written from the flatter per-user layouts and did
not include the vendor/product/`bin` nesting the official installer uses, so a
perfectly good installation looked absent. Fixed by adding that path as a
documented candidate with `…\Programs\OpenAI\Codex` as its trusted root.

The security model was **not** relaxed to fix it. There is still no PATH search,
no `where.exe` fallback, no shell fallback and no skipped trust validation — the
new location is validated exactly like every other candidate, and regression
tests cover the positive layout, the reported adapter kind, and rejection of an
identically named executable outside the trusted root.

This is the kind of gap only a physical machine finds: every automated test
passed both before and after, because no CI runner has Codex installed.

### Supported Claude installation formats

Taken from the official Claude Code setup and troubleshooting documentation, not
from guesswork. Each is covered by a discovery test.

| Format | Location | Adapter |
| --- | --- | --- |
| **Native installer** (recommended) | `%USERPROFILE%\.local\bin\claude.exe` | `native_exe` |
| WinGet | `%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe` | `native_exe` |
| npm global | the documented per-platform package `@anthropic-ai/claude-code-win32-x64` under `%APPDATA%\npm\node_modules` | `native_exe` |
| Legacy local install | `%USERPROFILE%\.claude\local` | `native_local` |
| WSL 1 / WSL 2 | `~/.local/bin/claude` inside a distribution, or `claude` on the distribution's default PATH | `wsl` |
| User-selected | any path, validated identically | `native_exe` |

Claude Code on Windows ships a **real native executable**: the documentation
states that the npm package installs the same binary as the standalone installer
and that the installed `claude` binary does not itself invoke Node. There is
therefore no Node-launcher path for Claude, unlike Codex.

Because the exact position of the binary inside the npm platform package and the
legacy local folder is not documented, those two are located by searching for
`claude.exe` **inside that documented package root only**, at most two
directories deep. The search never leaves the root and never consults PATH.

#### Git for Windows

**Not required.** The documentation is explicit that Git for Windows is
*optional* on native Windows: it enables Claude's own Bash tool, and without it
Claude uses the PowerShell tool instead. UsageBar's quota query runs with
`--tools ""`, so neither is used.

When a trusted `bash.exe` does exist in a documented Git for Windows root, its
path is passed through as `CLAUDE_CODE_GIT_BASH_PATH` — the variable Claude
documents for exactly this — so a Claude build that probes for it at start-up
finds it. **UsageBar never launches `bash.exe` itself**, and never falls back to
Git Bash to run the query.

`claude_git_bash_missing` is reported only when Claude's own output says it could
not find Git Bash. It is never inferred from Git for Windows being absent.

### Unsupported installation formats

- A bare `.cmd`, `.bat`, `.ps1` or `.vbs` shim with no resolvable interpreter.
  Reported as `unsupported_installation`; UsageBar does not fall back to a shell.
- An npm Codex install with no discoverable `node.exe`.
- Anything outside the documented roots, or writable by a wider group than the
  current user.
- A Claude installation reachable only through Git Bash or a login shell.
- A WSL build without `wsl.exe --cd` support, when Claude is installed under
  `~/.local/bin` inside the distribution. The PATH-based form still works there.

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

The settings window additionally shows the full explanation and, as a fallback
for builds where dragging is unavailable, the route through
**Windows Settings → Personalization → Taskbar → Other system tray icons**.

`trayGuidanceVersionShown` is recorded only after the notification request was
issued. A stored version equal to or newer than the current one does not show
it again and is never rolled back; an older one shows the updated guidance once.
The manual action always shows it, and recording the version leaves every other
setting untouched — all asserted in `TrayGuidanceTests`.

The current guidance version is **2**.

#### Finding from physical testing

**2026-07-26 — the icon moved successfully, but not next to the clock.**
Dragging UsageBar out of the `^` overflow menu worked, and the icon settled in
the visible tray area *beside the `^` button* rather than beside the clock.

That is normal Windows behavior: the shell decides the ordering within the tray,
and an application cannot and should not control it. The version 1 wording
("drag UsageBar next to the clock" / "saat yanına sürükleyin") promised a
position UsageBar does not control, so a correct outcome read like a failure.

The acceptance criterion is simply that **the icon is present in the visible
tray area**, wherever the shell places it within that area. The wording was
changed to ask for exactly that, the detailed text in settings states outright
that Windows may not put it next to the clock, and the guidance version was
raised to 2 so everyone sees the correction once.

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

### Tray icon

The number *is* the icon. There is no border, plate or chip around it: at 16 px
that chrome costs more than it conveys, and it left no room for three digits.

- **100** is drawn as `100`, at its own font size and compressed horizontally to
  fit. It is never replaced by a dot or any other stand-in — that substitution
  is what physical testing rejected.
- One and two digit values are drawn larger, so they stay crisp.
- The state is carried by a thin rule under the number, not by colour alone:
  none for normal, a short rule for warning, a full-width rule for critical, and
  a dashed rule for stale data. No-data (`—`) and refreshing (`↻`) have their own
  glyphs.
- Text uses grayscale anti-aliasing rather than ClearType. Subpixel rendering on
  a transparent bitmap produces coloured fringes, which is what made the icon
  look blurry once composited onto the taskbar.
- The glyph is centred on its measured ink rather than the font's line box, so
  it sits optically centred instead of high.

The layout decision lives in `Core/Policies/TrayIconGlyph.cs` and is unit-tested
there; the drawing lives in `Infrastructure/Tray/TrayIconRenderer.cs` and its
pixels are asserted on Windows CI — corners clear, `100` spanning the icon, each
state's rule distinguishable by shape.

#### Finding from physical testing

**2026-07-26 — the icon was a boxed chip, and 100 was a dot.** The renderer drew
a rounded square around every value and, because three digits did not fit inside
it, substituted `•` for 100. The box has been removed and 100 now renders as
itself.

### Installer

A conventional Setup EXE built with **Inno Setup 6.7.3**, pinned by version and
SHA-256 and downloaded from the official jrsoftware GitHub release. The checksum
is verified before the downloaded file is executed; no third-party action is
involved.

- **Per user, never elevated.** `PrivilegesRequired=lowest`, installing to
  `%LOCALAPPDATA%\Programs\UsageBar`. `PrivilegesRequiredOverridesAllowed` is
  deliberately unset, so an all-users or elevated install cannot be chosen even
  from the command line. Nothing is written to Program Files or HKLM, and no
  service, driver, scheduled task or PATH entry is created.
- **Stable identity.** A permanent AppId GUID, committed in the script and never
  regenerated, is what makes a newer installer upgrade the existing installation
  in place and keeps a single entry in Installed Apps.
- **One version source.** The version comes from `windows/Directory.Build.props`
  - the same property that stamps the assemblies - and is passed to the
  compiler. No script carries a second copy.
- **Same payload as the portable ZIP.** The installer is compiled from the
  staging directory the portable package gate already verified, so the installed
  and portable builds cannot drift.
- **A running instance is asked, not killed.** Inno waits on the application's
  own single-instance mutex, so it prompts to close UsageBar rather than matching
  a process name that might belong to something else.
- **User data is never touched.** Settings and history live in
  `%LOCALAPPDATA%\UsageBar`, beside the install directory rather than inside it,
  so an upgrade or an uninstall leaves them alone. The uninstaller deletes no
  data directory.
- **Autostart stays the application's.** The installer creates no Run entry, no
  Startup shortcut and no scheduled task, so the preference the application owns
  survives an upgrade untouched.
- **Unsigned.** See the note in the physical checklist.

The portable ZIP remains available and unchanged for users who prefer not to
install.

### Panel layout

The panel is not a fixed-size window. It uses `SizeToContent.WidthAndHeight`
between a **380 DIP minimum** — sized for Turkish, which runs longer than
English — and a maximum that is the smaller of 560 DIP and the monitor's
working area. Height grows to fit and is capped by the working area, after which
the usage list scrolls.

The footer actions are docked, not scrolled, so they stay reachable no matter
how long the list gets, and they live in a `WrapPanel` whose buttons measure to
their own text. A longer translation therefore moves a button onto a second line
rather than pushing it off the panel edge. The provider selector wraps for the
same reason. Horizontal scrolling is disabled outright, so content wraps instead
of hiding to the right.

Placement converts the monitor's working area into device-independent pixels
before use, which is what keeps the panel on screen at 125% and 150% scaling, on
a second monitor with a different scale, and with the taskbar on any edge.

#### Finding from physical testing

**2026-07-26 — the Turkish footer was clipped.** At the original fixed 340 DIP
width, `UsageBar'dan çık` ran past the panel edge and
`Tanılama özetini kopyala` squeezed the row. The layout above replaced the fixed
width and the single-line footer; nothing is tuned to the specific screen the
issue was found on.

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

### Packaging locally

```powershell
pwsh windows/scripts/package.ps1          # restore, build, test, publish, ZIP, SHA-256
pwsh windows/scripts/verify-package.ps1   # the same gate CI runs
```

`package.ps1` writes only inside `windows/artifacts/`, refuses to delete
anything outside it, and is reproducible: assemblies build deterministically,
no PDBs are produced, archive entries are added in sorted order and every entry
timestamp is pinned to the source commit date. The same commit built with the
same SDK produces a byte-identical ZIP — verified by building twice and
comparing the SHA-256.

### The package is not code signed

There is no Authenticode signature and no Apple-style notarization equivalent.
On first run Windows SmartScreen will show a "Windows protected your PC" prompt.

Verify the SHA-256 before running it, then choose **More info → Run anyway** for
that one file. **Do not disable SmartScreen or Windows Defender** — turning off
a machine-wide protection to run one unsigned utility is a far worse trade than
the warning it removes.

## 10. Continuous integration

`.github/workflows/windows-ci.yml` runs on `windows-latest`:

1. checkout
2. install the .NET 8 SDK
3. **verify the resolved SDK is 8.x** — the run fails otherwise
4. restore
5. Release build
6. Release test (uploads `.trx`)
7. `scripts/package.ps1 -SkipTests` (the suite just ran on the same tree)
8. `scripts/verify-package.ps1` — the package security gate
9. upload the artifact **`UsageBar-Windows-x64`**, containing
   `UsageBar-Windows-x64.zip` and `UsageBar-Windows-x64.zip.sha256`

Every step runs with `working-directory: windows` so `windows/global.json` is
the SDK the CLI resolves. Without it the muxer picks the newest SDK on the
runner, which is not the one the workflow installs.

The workflow does not create a tag, publish a GitHub Release, or push anywhere.

Its job is named **`windows-build-and-test`**, deliberately *not*
`build-and-test`: that context name is the required status check the macOS
workflow owns on `main`, and a second job sharing it would make the protected
check ambiguous. The macOS workflows are untouched and keep their own triggers.

---

## 11. Physical Windows Test Checklist

Everything below is **unverified**. It has been built, automatically tested and
packaged on a GitHub Actions `windows-latest` runner; no human has run it on a
physical Windows machine. This checklist is what turns that into real
verification.

Please do not paste tokens, credentials or full private file paths into any
report. The **Copy diagnostics** action already produces a summary that is safe
to share — use that instead of describing your setup by hand.

### Download and verify

- [ ] Open the green **Windows CI** run on the `agent/windows-port` branch and
      download the **`UsageBar-Windows-x64`** artifact.
- [ ] GitHub wraps artifacts in an outer ZIP — extract it to get
      `UsageBar-Windows-x64.zip` and `UsageBar-Windows-x64.zip.sha256`.
- [ ] Check the hash matches the `.sha256` file:
      ```powershell
      (Get-FileHash .\UsageBar-Windows-x64.zip -Algorithm SHA256).Hash.ToLower()
      Get-Content .\UsageBar-Windows-x64.zip.sha256
      ```
- [ ] Extract the ZIP. It contains a single `UsageBar\` folder.
- [ ] Right-click `UsageBar-Windows-x64.zip` → Properties → **Unblock** before
      extracting, if Windows marked it as downloaded.
- [ ] Run `UsageBar\UsageBar.exe`. SmartScreen will warn because the build is
      unsigned: **More info → Run anyway**. Do not disable SmartScreen or
      Defender.

### First launch

- [ ] No console window appears, not even briefly.
- [ ] No normal taskbar button appears.
- [ ] UsageBar appears in the notification area, or under the `^` overflow menu.
- [ ] The first-run guidance notification appears **once**, and says to move the
      icon to the *visible system tray area* — not "next to the clock".
- [ ] Closing and reopening the app does **not** show the guidance again.
- [ ] The icon can be dragged out of the `^` menu into the visible tray area,
      and stays there after a restart. **Windows deciding to place it beside the
      `^` button rather than beside the clock is expected, not a failure.**

### Tray and panel

- [ ] Left-click opens the panel; left-click again closes it.
- [ ] **In Turkish, every footer button is fully visible** — `Ayarlar`,
      `Tanılama özetini kopyala` and `UsageBar'dan çık` are all readable and
      none is clipped by the panel edge.
- [ ] In English the same holds for the longer labels.
- [ ] No button sits on top of another or runs past the right edge.
- [ ] Right-click opens the context menu.
- [ ] Clicking outside the panel closes it.
- [ ] Closing the panel leaves the app running in the tray.
- [ ] The percentage inside the icon is legible at your display scale.
- [ ] The tooltip shows the provider, the remaining percentage and — when the
      reset countdown setting is on — the window and time remaining.
- [ ] Switching Turkish ↔ English changes every visible string.
- [ ] The panel is readable in both light and dark Windows appearance.
- [ ] Opening **Settings** keeps the panel open rather than dismissing it.

### Codex

Requires Codex installed and signed in.

- [ ] **Connect Codex** succeeds.
- [ ] The percentage shown matches what `codex` itself reports.
- [ ] The five-hour and weekly windows are both listed, with the right values.
- [ ] The reset countdown is plausible and counts down.
- [ ] **Refresh now** updates the value.
- [ ] After ten refreshes in a row, Task Manager shows **no** leftover `codex`,
      `node`, `cmd` or `conhost` processes.
- [ ] With Codex not installed (or renamed), the panel shows a clear
      "Codex not found" message rather than a crash or a blank value.
- [ ] **Copy diagnostics** produces a summary with no path, token or raw output
      in it.

### Settings persistence

- [ ] The refresh interval survives a restart.
- [ ] The language choice survives a restart.
- [ ] The threshold profile survives a restart.
- [ ] The usage-colour toggle survives a restart.
- [ ] **Show system tray guidance again** shows the notification on demand.
- [ ] **Launch at startup** can be switched on and off without an administrator
      prompt, and the app really does start after a sign-out/sign-in.
- [ ] Usage history survives a restart, and **Clear history** empties the chart.

### Exit and process cleanup

- [ ] **Exit UsageBar** closes the application completely.
- [ ] The tray icon disappears immediately rather than lingering as a ghost.
- [ ] Task Manager shows no `UsageBar` process afterwards.
- [ ] Task Manager shows no leftover `codex`, `node`, `powershell` or WSL helper
      process.
- [ ] Quitting **during** a refresh also leaves nothing behind.

### Multiple monitors and DPI

- [ ] On the primary monitor the panel opens near the notification area, fully
      on screen.
- [ ] On a secondary monitor it opens on that monitor, fully on screen.
- [ ] At 100%, 125% and 150% scaling nothing is clipped and text stays sharp,
      in both Turkish and English.
- [ ] With a long error message, a stale-data warning, several usage windows and
      the history chart all showing at once, the panel still fits the screen and
      the footer actions stay visible.
- [ ] With the taskbar moved to the top, left or right edge, the panel still
      lands inside the working area.
- [ ] Dragging the panel's monitor between different scale factors does not
      leave it mispositioned.

### Reporting back

For anything that fails, the most useful report is: which checkbox, what
happened instead, and the output of **Copy diagnostics**.

## 12. Claude Code Physical Windows Test Checklist

**Unverified.** Claude support is built, unit-tested and packaged on CI, but no
human has run it against a real Claude Code installation. Codex has been
physically verified; Claude has not.

Please do not paste tokens, credential files, raw provider output or full
private paths into any report. **Copy diagnostics** already produces a summary
that is safe to share. When something fails, the useful reply is: which
checkbox, a screenshot, the safe diagnostics output, `claude --version`, the
adapter type shown in diagnostics, which installation form you use, your Windows
version, and — for WSL — the distribution name.

### Native Windows

- [ ] `claude --version` prints a version such as `2.1.211 (Claude Code)`.
- [ ] `Get-Command claude -All` and `where.exe claude` agree on one installation.
      If they show several, keep one — Claude's own troubleshooting guide
      recommends the native install at `%USERPROFILE%\.local\bin\claude.exe`.
- [ ] Claude Code is already signed in. **Do not** sign in through UsageBar: it
      never starts a login flow.
- [ ] In UsageBar, **Connect Claude Code** succeeds.
- [ ] Diagnostics show `claude=connected:true,executable:trusted,adapter:native_exe`
      (or `native_local` for a legacy install).
- [ ] Both the five-hour and weekly windows appear, with values matching what
      `claude` reports itself.
- [ ] The reset countdowns are plausible and count down.
- [ ] Ten refreshes in a row leave **no** stray `claude`, `node`, `bash`, `cmd`
      or `conhost` process in Task Manager.
- [ ] With Git for Windows installed, everything above still holds.
- [ ] With Git for Windows **not** installed, everything above still holds —
      it is optional for this query.
- [ ] Signing out of Claude (`/logout` in Claude Code) makes UsageBar show a
      clear "not signed in" message rather than a wrong number, and the message
      does not repeat as a popup on every automatic refresh.
- [ ] Signing back in restores the reading on the next refresh.

### WSL

- [ ] `wsl --list --verbose` lists your distributions and their state.
- [ ] In UsageBar settings, set **Claude Code installation** to **WSL** and pick
      the distribution.
- [ ] `claude --version` works *inside that distribution*.
- [ ] Claude is already signed in inside that distribution.
- [ ] UsageBar reads real usage; diagnostics show `adapter:wsl`.
- [ ] Diagnostics contain **no** Linux path — no `/home/...`, no `/mnt/...`.
- [ ] Switching to a distribution without Claude gives a clear
      "no WSL distribution with Claude Code" message, not a crash.
- [ ] Switching back to the working distribution recovers on the next refresh.
- [ ] Starting from a **stopped** distribution works (the first refresh may be
      slower while WSL starts it).
- [ ] Repeated refreshes do not start every distribution — only the selected one
      runs.
- [ ] Setting the mode back to **Automatic** still finds a working installation.
- [ ] Killing the query mid-flight (quit UsageBar during a refresh) leaves no
      `wsl.exe` behind.

### Both providers

- [ ] With Codex and Claude both connected, the **Auto** selector appears.
- [ ] Auto alternates the tray icon between the two roughly every 30 seconds.
- [ ] Selecting a single provider pins the tray to it.
- [ ] Disconnecting Claude leaves Codex working and **keeps** Claude's history
      until history is cleared explicitly.
- [ ] A failed Claude refresh keeps the last good value on screen with a stale
      warning, and the chart gains no new point for it.

## 13. Windows Installer Physical Test Checklist

**Unverified.** The installer is built, verified and install/upgrade/uninstall
smoke-tested on CI, but no human has run it on a physical machine.

The installer is **not code signed**. SmartScreen will show "Windows protected
your PC" on first run: choose **More info -> Run anyway** for that one file after
checking the SHA-256. Do not disable SmartScreen or Defender. Signing and Store
distribution are separate later phases.

Please do not share tokens, credential files, raw provider output or full
private paths. **Copy diagnostics** produces a summary that is safe to send.

### Fresh installation

- [ ] Download the **`UsageBar-Windows-Installer-x64`** artifact and extract the
      outer ZIP GitHub wraps it in.
- [ ] Verify the checksum:
      ```powershell
      (Get-FileHash .\UsageBar-Setup-x64.exe -Algorithm SHA256).Hash.ToLower()
      Get-Content .\UsageBar-Setup-x64.exe.sha256
      ```
- [ ] Double-click `UsageBar-Setup-x64.exe`.
- [ ] Note whether SmartScreen appears, and that **no UAC / administrator prompt
      does** - the install is per-user.
- [ ] Run it once in Turkish and once in English (the wizard should preselect
      from your Windows language).
- [ ] The destination shown is under `%LOCALAPPDATA%\Programs\UsageBar`.
- [ ] Leave the desktop shortcut unchecked the first time; check it the second.
- [ ] Finish with **Launch UsageBar** ticked.
- [ ] A Start Menu entry for UsageBar exists.
- [ ] The desktop shortcut appears only when you asked for it.
- [ ] UsageBar starts, and there is **exactly one** tray icon.
- [ ] Codex still reads real usage; Claude still reads real usage.
- [ ] Your settings, history, language and provider choices are as they were.

### Upgrade

- [ ] With UsageBar **running**, start the installer again.
- [ ] It asks you to close UsageBar rather than killing it, and closing it lets
      the install continue.
- [ ] Installed Apps shows **one** UsageBar entry, not two.
- [ ] The version shown in Installed Apps is the new one.
- [ ] Settings, usage history and provider connections are unchanged.
- [ ] The **Launch at startup** preference is exactly as you left it - still on
      if it was on, still off if it was off.
- [ ] After launching, there is exactly one tray icon and no leftover old
      process in Task Manager.

### Uninstall

- [ ] Uninstall from **Settings > Apps > Installed apps**.
- [ ] No administrator prompt.
- [ ] The program files and the Start Menu shortcut are gone.
- [ ] `%LOCALAPPDATA%\UsageBar` - your settings and history - is **still there**.
- [ ] Reinstall, and your previous settings and history come back.
- [ ] No reboot was ever requested.

## 14. Known limitations

1. **The installer is not physically verified.** It is built, verified and
   install/upgrade/uninstall smoke-tested on CI, but nobody has run it on a real
   machine. It is also unsigned, so SmartScreen warns on first run.
2. **Claude support is not physically verified.** It is implemented, unit-tested
   and packaged, but no human has run it against a real Claude installation.
   Section 12 is the checklist for it.
2. **No physical Windows verification.** Three distinct levels apply, and they
   must not be conflated:
   - *Compiled and automatically tested on Windows CI* — the whole solution,
     including the Job Object containment and process-tree teardown tests.
   - *Packaged on Windows CI* — the ZIP is produced and passes the package
     security gate.
   - *Tested by a person on a physical Windows machine* — ***not done.***
     Nobody has seen the tray icon, the popup placement, DPI or multi-monitor
     behavior, the balloon notification, the light/dark appearance, or a real
     signed-in Codex account being read. Section 11 is the checklist for it.
3. **No signed-in Codex has been exercised.** The adapter is tested against
   fixtures and against stock Windows executables standing in for the app
   server. A real signed-in Codex installation has not been read from.
4. Codex candidate locations come from documented installation layouts, not from
   observation on a machine with each one installed.
5. The ACL check treats an unreadable ACL as "not writable by others"; the path
   and file-type checks still apply.
6. Windows ARM64 is out of scope; the publish is x64 only.
7. The panel uses an opaque background. Mica/Acrylic is deliberately deferred.
8. **The package is unsigned.** No Authenticode certificate, so SmartScreen
   warns on first run. Verify the SHA-256 rather than disabling protection.
9. The portable ZIP is ~61 MB compressed / ~145 MB extracted because the .NET
   runtime is bundled. That is the cost of not requiring a .NET installation.
10. Reproducibility holds for the same commit **and** the same SDK feature band.
    A different 8.0.x SDK can emit different IL and change the hash.
