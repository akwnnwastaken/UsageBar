<a id="top"></a>

<p align="center">
  <img src="docs/assets/usagebar-icon.png" width="144" height="144" alt="UsageBar app icon">
</p>

<h1 align="center">UsageBar</h1>

<p align="center">
  <strong>Codex &amp; Claude Code usage, at a glance.</strong>
</p>

<p align="center">
  A native, local menu bar and system tray app for macOS and Windows.<br>
  See remaining percentages, reset times, and every usage window in one click.
</p>

<p align="center">
  <img alt="macOS 13 or later, Apple Silicon" src="https://img.shields.io/badge/macOS-13%2B_%7C_Apple_Silicon-000000?logo=apple&amp;logoColor=white">
  <img alt="Windows 10 version 1809 or later, x64" src="https://img.shields.io/badge/Windows-10_1809%2B_%7C_x64-0078D4?logo=windows11&amp;logoColor=white">
  <img alt="Codex and Claude Code" src="https://img.shields.io/badge/providers-Codex_%2B_Claude_Code-6B5CE7">
</p>

<p align="center">
  <a href="https://github.com/akwnnwastaken/UsageBar/releases/download/v2.3.0/UsageBar-2.3.0-macOS-arm64.zip"><strong>Download for macOS</strong></a>
  &nbsp;·&nbsp;
  <a href="https://github.com/akwnnwastaken/UsageBar/releases/download/windows-v2.3.0/UsageBar-Setup-x64.exe"><strong>Download for Windows</strong></a>
  &nbsp;·&nbsp;
  <a href="docs/mobile/SELF_BUILD.md"><strong>Build for iPhone</strong></a>
</p>

---

UsageBar shows the selected provider's remaining usage in the macOS menu bar or Windows system tray. Its detail panel brings usage windows, reset times, and local history charts together in one place.

## Features

- **Codex + Claude Code:** Track both providers from one app.
- **Remaining usage:** See the percentage left, not the percentage used.
- **Multiple windows:** List five-hour, weekly, and any other duration returned by the provider.
- **Reset times:** Show the local clock time and the countdown together for every window that reports a reset; for example `Resets: 6:45 PM · 3h 12m`.
- **Local history:** Keep up to 24 hours of remaining-percentage history for each provider/window pair.
- **Resilient status:** Keep the last successful value visible with its timestamp and failure reason during temporary errors.
- **Provider selection:** Pin a provider or rotate every 30 seconds with `Auto | Codex | Claude`.
- **Collect usage:** Pause and resume collection per provider without disconnecting it (macOS: the provider's submenu; Windows: Settings and the tray menu). A paused provider stays connected and is marked **Paused**; its last readings and recorded history are kept, and the menu bar or tray value follows the providers still being collected.
- **Show details:** Hide or show each provider's detail body (window values, remaining percentages, reset lines, history summaries and charts) separately; on by default. It is presentation only: connection, collection and history recording are unaffected, and the heading, the paused marker where it applies, and any active issue line stay visible. The preference is stored per provider, independently of **Collect usage**.
- **Flexible display:** Disable colors, choose from three alert-threshold profiles, and refresh every 1, 2, or 5 minutes.
- **Launch at login:** Start automatically with the signed-in user when enabled.
- **Two languages, two platforms:** Turkish and English UI on macOS and Windows.
- **macOS + Windows:** A native menu bar app on macOS, a system tray app on Windows.
- **iPhone companion:** Build [UsageBar Mobile](docs/mobile/SELF_BUILD.md) yourself and read the same numbers on your phone, in Home and Lock Screen widgets and in Control Center — served by your own Mac over your own Tailscale network. Off by default, and there is no cloud backend.
- **Local-first:** Reuse the provider sessions you already have, and keep raw provider output out of history.

## Downloads

Version **2.3.0** is current for both platforms. macOS and Windows use separate release tags.

**macOS 2.3.0 includes Mobile Sync**, so a normal `UsageBar.app` can serve your usage to your iPhone. **Windows 2.3.0 is a version-synchronization release** — same behaviour as 2.2.0, and it cannot host the phone.

| Platform | Package | Download | Release notes |
| --- | --- | --- | --- |
| macOS 13+ · Apple Silicon | `UsageBar-2.3.0-macOS-arm64.zip` | [Download ZIP](https://github.com/akwnnwastaken/UsageBar/releases/download/v2.3.0/UsageBar-2.3.0-macOS-arm64.zip) | [`v2.3.0`](https://github.com/akwnnwastaken/UsageBar/releases/tag/v2.3.0) |
| Windows 10 1809+ · x64 | `UsageBar-Setup-x64.exe` | [Download installer](https://github.com/akwnnwastaken/UsageBar/releases/download/windows-v2.3.0/UsageBar-Setup-x64.exe) | [`windows-v2.3.0`](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v2.3.0) |
| Windows 10 1809+ · x64 | `UsageBar-Windows-x64.zip` | [Download portable ZIP](https://github.com/akwnnwastaken/UsageBar/releases/download/windows-v2.3.0/UsageBar-Windows-x64.zip) | [`windows-v2.3.0`](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v2.3.0) |
| iPhone · iOS 18+ | **UsageBar Mobile** — source | [Build it yourself](docs/mobile/SELF_BUILD.md) | included in this repository |

> [!NOTE]
> The iPhone companion is distributed as **source**, not as an `.ipa`: you build it once in Xcode and sign it with your own Apple account. There is no App Store listing and no TestFlight build.

> [!NOTE]
> The `main` branch contains the source for both platforms. Release packages, signing status, and first-launch guidance differ by platform; read the matching installation section below.

---

## How is the percentage calculated?

The displayed value is the **remaining percentage, not the used percentage**.

- **Claude Code:** Uses the five-hour window when available and falls back to weekly only when five-hour data is missing.
- **Codex:** Uses the lowest remaining percentage among the windows available on the account. If the account exposes only a weekly window, UsageBar uses that window.

Click the icon to inspect every window returned for the selected provider. UsageBar only shows windows actually available on the account.

## Data sources and refresh behavior

- **Codex:** Uses the installed Codex tool's local `account/rateLimits/read` interface.
- **Claude Code:** Reads the output of Claude Code's local usage command. The command leaves no session record and consumes no model quota.

UsageBar does not sign in to provider websites itself. It uses the existing Codex and Claude Code sessions on your computer.

Usage can refresh every 1, 2, or 5 minutes; the default is 5 minutes.

Opening the panel also starts a refresh when the displayed data is more than 30 seconds old. When both providers are connected and `Auto` is selected, the displayed provider changes every 30 seconds; rotation itself does not run a new provider query.

## Usage history and data stability

When mini charts are enabled, UsageBar stores only the measurement time and remaining percentage for each provider/window pair, locally.

Data is pruned on launch and after each measurement using 24-hour, series-count, sample-count, and encoded-size limits. Provider responses, raw command output, and credentials are never written to history.

The chart starts at the most recent reset to keep the current usage period readable. A large jump back toward 100% starts a new period. Adaptive scaling makes small changes visible.

Providers round percentages to whole numbers, so a value can flicker between 41 and 42. A newly started reader can also receive a cached snapshot behind the live value.

Rises below the reset threshold are held until the same value persists across three consecutive readings; large resets appear immediately. Recorded history always keeps the raw measurement.

Hovering a chart selects the real recorded sample nearest in time to that horizontal position.

UsageBar shows a vertical guide, highlighted point, local time, and remaining percentage; it never invents an interpolated value. Each chart owns independent hover state.

If a provider temporarily fails, the last successful value remains visible with its timestamp and safe failure reason. A stale value is never recorded again as a new history sample.

## Platform notes

#### macOS

- Runs only in the menu bar, without a Dock icon or main window.
- Reads the ChatGPT app or an installed Codex CLI for Codex, and an installed Claude Code CLI for Claude.
- Launch at login uses the macOS **Login Items** system.
- Provider commands run in a separate process group.
- Distributed for Apple Silicon (`arm64`).
- Can act as the host for the iPhone companion — see below.

#### iPhone

- **UsageBar Mobile** is distributed as **source**, not as an `.ipa`: you build it once in Xcode and sign it with your own Apple account. A free **Personal Team** works, with Apple's roughly **7-day** development provisioning limit.
- The phone never talks to Codex or Claude and holds no provider credentials. Its only input is a sanitized snapshot from your Mac.
- **Tailscale is required**, with the Mac and the iPhone on the same tailnet. Reachability comes from your own network; there is no UsageBar server anywhere in the path, and Tailscale Funnel is never used.
- The Mac side is UsageBar itself. **Mobile Sync is off until you enable it**, and while it is off UsageBar opens no listener, runs no Tailscale command and stores no mobile credential. There is no separate Mac application to install.
- Pairing is a QR code carrying a one-time code, scanned once. The Mac stores only digests, never the credential itself.
- UsageBar's listener binds `127.0.0.1` and nothing else. **You configure the `tailscale serve` route yourself** — UsageBar never creates, changes or removes Tailscale configuration; it only reads `tailscale status`.
- Home Screen widgets, Lock Screen widgets and Control Center controls are part of the same build.
- **Windows cannot host the phone yet.** The host side is macOS only.
- Start at [docs/mobile/SELF_BUILD.md](docs/mobile/SELF_BUILD.md), then [docs/mobile/TAILSCALE_SETUP.md](docs/mobile/TAILSCALE_SETUP.md).

#### Windows

- A native **C# / .NET 8 / WPF** system tray application with no taskbar button or main window.
- Supports Codex's official Windows installation and Claude Code's native Windows installation.
- Can read Claude Code through **WSL**; that path is still not physically validated as of the 2.3.0 release.
- Distributed as a portable ZIP and a per-user installer.
- The installer does not require administrator permission and does not launch UsageBar automatically when setup finishes.
- Provider processes start through `CreateProcessW` without a shell and are contained in a **Job Object**.
- No service, driver, scheduled task, or `PATH` modification is used.

## Requirements

Only the provider you want to track needs to be installed and signed in.

| Platform | System | Provider | Build from source |
| --- | --- | --- | --- |
| macOS | macOS 13+, Apple Silicon (`arm64`) | ChatGPT app or signed-in Codex CLI; signed-in Claude Code CLI | Xcode Command Line Tools |
| Windows | Windows 10 version 1809+ (including Windows 11), x64 | Signed-in official Windows Codex installation; native Claude Code or supported WSL path | .NET 8 SDK |

Windows end-user packages are self-contained; no separate .NET Runtime installation is required.

## Installation

#### macOS

1. Download `UsageBar-2.3.0-macOS-arm64.zip` from the [`v2.3.0` release](https://github.com/akwnnwastaken/UsageBar/releases/tag/v2.3.0).
2. Extract the ZIP and move `UsageBar.app` to the **Applications** folder.
3. Open UsageBar and connect a provider from the `%—` icon in the menu bar.

> [!WARNING]
> This package is for Apple Silicon (`arm64`) only. It is ad hoc signed but not yet notarized by Apple, so macOS may show a verification warning on first launch. Follow the steps below only for the official Release file from this repository.

**Approve the first-launch warning safely**

1. Try to open UsageBar once.
2. In the verification warning, click **Done** instead of **Move to Bin**.
3. Open Apple menu → **System Settings** → **Privacy & Security**.
4. In the **Security** section, click **Open Anyway** for UsageBar.
5. Authenticate with Touch ID or your Mac login password, then click **Open**.

Approval is required only on the first launch of the same app. If **Open Anyway** is missing, try opening UsageBar again and return to the same section; macOS exposes the option for about one hour after the launch attempt.

> [!CAUTION]
> Do not disable Gatekeeper globally or run arbitrary `sudo`, `spctl`, or `xattr` commands from the internet. If macOS reports known malware, do not continue; delete the file and download it again from the official Release.

Apple's official guidance: [Open an app Apple cannot check for malicious software](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

#### Windows installer — recommended

1. Open the [`windows-v2.3.0` release](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v2.3.0).
2. Download `UsageBar-Setup-x64.exe`.
3. Optionally complete the verification steps below.
4. Run the installer. It installs for the current user only and does not request administrator permission.
5. When setup finishes, search for `UsageBar` in the Start menu and open it.
6. If the icon is hidden, check the `^` overflow area on the taskbar.

The installer deliberately does not launch UsageBar automatically. The autostart preference belongs to the app and is stored only in the current user's settings.

> [!WARNING]
> Windows packages are currently unsigned. SmartScreen may warn on first run. Verify the SHA-256 before continuing; do not disable SmartScreen globally.

#### Windows portable

1. Download [`UsageBar-Windows-x64.zip`](https://github.com/akwnnwastaken/UsageBar/releases/download/windows-v2.3.0/UsageBar-Windows-x64.zip).
2. Extract it to a permanent, writable folder.
3. Do not run the app directly from inside the ZIP.
4. Run `UsageBar.exe`.

## Package verification

#### macOS

Compare the download with the `.sha256` file on the Release page:

```sh
shasum -a 256 ~/Downloads/UsageBar-2.3.0-macOS-arm64.zip
```

Verify GitHub build provenance for the CI-produced package:

```sh
gh attestation verify ~/Downloads/UsageBar-2.3.0-macOS-arm64.zip \
  --repo akwnnwastaken/UsageBar \
  --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml
```

SHA-256 checks that the file did not change; attestation checks that the package was produced by this repository's GitHub Actions workflow.

#### Windows

In PowerShell, from the folder containing the downloads:

```powershell
Get-FileHash .\UsageBar-Setup-x64.exe -Algorithm SHA256
Get-FileHash .\UsageBar-Windows-x64.zip -Algorithm SHA256
```

Compare each result with the matching `.sha256` file on the same Release page and the value in the release notes. All three values should match.

## Usage and privacy

1. Open UsageBar and click the `%—` icon.
2. Choose **Connect Codex** or **Connect Claude Code**.
3. If both are connected, choose a view with `Auto | Codex | Claude`.
4. Customize appearance, colors, history, and refresh interval in settings.
5. When reporting a problem, use **Copy diagnostics**.

UsageBar does not query either provider on first launch; access begins only after you click a connection button. Connecting saves a local preference only. UsageBar does not store passwords, API keys, access tokens, or session tokens.

Provider commands run in an app-specific temporary directory with a restricted environment. Project settings, plugins, MCP servers, Chrome integration, and shell startup files are not loaded.

Timeouts terminate child processes, output is limited to 2 MiB, and provider executables are validated before use.

**macOS permissions**

UsageBar does not require Full Disk Access, Documents/Desktop access, network volume access, Screen Recording, Accessibility, or Automation.

When connecting Claude Code, macOS may ask for access to the existing `Claude Code-credentials` Keychain item; choose **Always Allow** once to prevent repeated prompts.

**Windows behavior**

The installer does not require administrator permission, install a service, driver, or scheduled task, or modify `PATH`. It has no telemetry or crash-reporting dependency.

Autostart only manages UsageBar's current-user `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry.

The diagnostic summary is limited to version, operating-system version, connection state, window kinds, and fixed safe error codes. It excludes raw CLI output, file paths, user names, and credentials.

## Troubleshooting

- **Windows icon is missing:** Check the `^` overflow area on the taskbar.
- **macOS blocks the app:** Use only the **Privacy & Security → Open Anyway** flow above; do not disable Gatekeeper.
- **SmartScreen warns:** Verify the download with SHA-256. Do not disable SmartScreen globally.
- **A provider will not connect:** Confirm that the corresponding Codex or Claude Code installation is signed in, then try again in UsageBar.
- **UsageBar shows stale data:** The panel's timestamp and safe failure reason explain why the last successful measurement was preserved. Check the provider installation and refresh manually.
- **You moved the portable Windows build:** If autostart still points to the old location, turn the preference off and enable it again from the new location.
- **When asking for help:** Share **Copy diagnostics** output; do not send tokens, credentials, raw provider output, or private file paths.

See the [Windows port notes](docs/windows-port.md) for discovery and physical-validation detail. Report sensitive vulnerabilities through the private process in the [security policy](SECURITY.md), not a public Issue.

## Build from source

#### macOS

```sh
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

`build.sh` uses the canonical SwiftPM graph, runs XCTest and packaged-binary self-tests, then applies an ad hoc signature to the clean bundle for local use.

Additional checks:

```sh
./tests/build_regression.sh
./tests/security_acceptance.sh
```

#### Windows

Run commands from `windows/`; `windows/global.json` pins the SDK to .NET 8.

```powershell
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar/windows
dotnet restore UsageBar.Windows.sln
dotnet build UsageBar.Windows.sln --configuration Release --no-restore
dotnet test UsageBar.Windows.sln --configuration Release
```

Run the app directly:

```powershell
dotnet run --project src/UsageBar.Windows.App/UsageBar.Windows.App.csproj -c Release
```

Package and verify:

```powershell
./scripts/package.ps1
./scripts/package-installer.ps1
./scripts/verify-package.ps1
./scripts/verify-installer.ps1
```

`package.ps1` creates the self-contained portable ZIP; `package-installer.ps1` creates the Inno Setup installer. `Core` and `Core.Tests` target `net8.0`; Windows-specific tests are skipped on other platforms.

## Repository map

```text
UsageBar/
├── Sources/UsageBar/                       # macOS app and provider readers
├── Sources/UsageBarCore/                   # Shared pure policies and models
├── Sources/UsageBarProcessLauncher/        # Shell-free process-group launcher
├── Sources/UsageBarSync/                   # Schema-v1 mobile snapshot model
├── Sources/UsageBarSyncTransport/          # Loopback-only HTTP listener
├── Sources/UsageBarPairing/                # QR pairing wire format, Mac + iPhone
├── Sources/UsageBarMobileSyncHost/         # Mobile Sync: auth, pairing, lifecycle
├── ios/UsageBarMobileLab/                  # iPhone app, widgets and controls
├── shared/sync-schema/                     # Mobile wire schema and parity fixtures
├── docs/mobile/                            # iPhone setup, privacy and design docs
├── Package.swift                           # Canonical SwiftPM build definition
├── Info.plist                              # macOS app and version metadata
├── build.sh                                # macOS build, tests, and local signing
├── tests/                                  # XCTest and macOS acceptance scripts
├── windows/
│   ├── UsageBar.Windows.sln                # Windows solution
│   ├── src/                                # Core, Infrastructure, and WPF tray app
│   ├── tests/                              # xUnit tests
│   ├── scripts/                            # Packaging and verification scripts
│   └── installer/                          # Inno Setup definition and Windows icon
├── shared/fixtures/                        # Provider samples shared across platforms
├── docs/windows-port.md                    # Windows design and validation notes
├── .github/workflows/                      # macOS, Windows, and release workflows
├── SECURITY.md                             # Bilingual security policy
└── LICENSE                                 # MIT License
```

## Development and license

Changes are developed through separate commits and pull requests. UsageBar is available under the [MIT License](LICENSE).

<p align="right"><a href="#top">Back to top ↑</a></p>
