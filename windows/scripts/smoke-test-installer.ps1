<#
.SYNOPSIS
    Installs, upgrades and uninstalls UsageBar for real, on Windows.

.DESCRIPTION
    Runs the produced Setup EXE silently and checks what it actually did:

      * fresh install lands under the user profile with exactly the verified
        payload (same relative files, same bytes) plus Inno's own uninstaller
        files, a Start Menu shortcut and one uninstall entry under HKCU;
      * an upgrade over a deliberately older build keeps the same AppId and the
        same single entry, leaves the installed tree matching the current
        verified payload, and leaves user settings and the autostart preference
        untouched;
      * uninstall removes the program files, the shortcut and the entry — and
        leaves settings and history behind.

    The upgrade half is only meaningful because a *different, older* installer
    is built first; installing identical bytes twice would prove nothing. That
    older installer is compiled from the same staging payload with only its
    version changed, so the payload checks prove what the current installer
    lays down — not that a file dropped from an older release would be removed.

    All state is created under temporary directories and a scratch settings
    folder, and removed afterwards even when a check fails.

.PARAMETER SetupPath
    The current Setup EXE under test.

.PARAMETER PreviousSetupPath
    The deliberately older Setup EXE the upgrade starts from.

.PARAMETER StagingDirectory
    The verified payload both installers were compiled from. Defaults to what
    package.ps1 produced, the same default package-installer.ps1 uses.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SetupPath,
    [Parameter(Mandatory)] [string] $PreviousSetupPath,
    [string] $StagingDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Test-Requirement {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $Condition,
        [string] $Detail = ''
    )

    $script:checks++
    if ($Condition) {
        Write-Host "  [ok]   $Name" -ForegroundColor Green
    }
    else {
        Write-Host "  [FAIL] $Name $Detail" -ForegroundColor Red
        $script:failures.Add("$Name $Detail".Trim())
    }
}

# --- installed payload parity ------------------------------------------------

<#
    Every file below a root, keyed by its root-relative path with "/" separators.
    Windows file identity is case-insensitive, so the keys compare that way.
    A file whose full path does not sit under the root is refused outright:
    nothing outside the two trees being compared may enter the comparison.
#>
function Get-RelativeFileMap {
    param([Parameter(Mandatory)] [string] $Root)

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    $map = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in @(Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force)) {
        if (-not $file.FullName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to compare '$($file.FullName)': it is not under '$rootFull'."
        }

        $map[$file.FullName.Substring($prefix.Length).Replace('\', '/')] = $file.FullName
    }

    return $map
}

<#
    Bounded, sorted diagnostics: enough to see what went wrong, never a dump.
#>
function Format-PathList {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[string]] $Paths)

    $sorted = $Paths.ToArray()
    [System.Array]::Sort($sorted, [System.StringComparer]::OrdinalIgnoreCase)
    $shown = @($sorted | Select-Object -First 20)
    $text = $shown -join ', '
    if ($sorted.Count -gt $shown.Count) {
        $text += ", … and $($sorted.Count - $shown.Count) more"
    }

    return "($text)"
}

<#
    The installed tree must be the verified payload and nothing else: no payload
    file missing, no file present that is neither payload nor one of the files
    Inno Setup itself writes beside it, those installer-owned files present, and
    every payload file byte-identical (SHA-256) to its staged original.
#>
function Test-InstalledPayloadParity {
    param(
        [Parameter(Mandatory)] [string] $Label,
        [Parameter(Mandatory)] [string] $StagingRoot,
        [Parameter(Mandatory)] [string] $InstallRoot,
        [Parameter(Mandatory)] [string[]] $InstallerOwnedFiles
    )

    $expected = Get-RelativeFileMap -Root $StagingRoot
    $installed = Get-RelativeFileMap -Root $InstallRoot

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $expected.Keys) {
        if (-not $installed.ContainsKey($relative)) { $missing.Add($relative) }
    }

    $unexpected = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $installed.Keys) {
        if ($expected.ContainsKey($relative)) { continue }
        if ($InstallerOwnedFiles -contains $relative) { continue }
        $unexpected.Add($relative)
    }

    $absentExtras = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $InstallerOwnedFiles) {
        if (-not $installed.ContainsKey($relative)) { $absentExtras.Add($relative) }
    }

    $mismatched = [System.Collections.Generic.List[string]]::new()
    foreach ($relative in $expected.Keys) {
        if (-not $installed.ContainsKey($relative)) { continue }
        $expectedHash = (Get-FileHash -LiteralPath $expected[$relative] -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath $installed[$relative] -Algorithm SHA256).Hash
        if ($expectedHash -ne $installedHash) {
            $mismatched.Add("$relative expected $($expectedHash.ToLowerInvariant()) installed $($installedHash.ToLowerInvariant())")
        }
    }

    Test-Requirement "${Label}: every verified payload file is installed" ($missing.Count -eq 0) (Format-PathList $missing)
    Test-Requirement "${Label}: nothing but the payload and the installer-owned files is installed" ($unexpected.Count -eq 0) (Format-PathList $unexpected)
    Test-Requirement "${Label}: the installer-owned files are present" ($absentExtras.Count -eq 0) (Format-PathList $absentExtras)
    Test-Requirement "${Label}: every payload file has the verified bytes" ($mismatched.Count -eq 0) (Format-PathList $mismatched)
}

$windowsRoot = Split-Path -Parent $PSScriptRoot

# The payload both installers were compiled from — the same default
# package-installer.ps1 resolves — and the reference every installed tree is
# compared against. Checked first, before any machine state is touched, so a
# missing payload fails the smoke test outright instead of silently weakening it.
if (-not $StagingDirectory) { $StagingDirectory = Join-Path $windowsRoot 'artifacts\staging\UsageBar' }
$StagingDirectory = [System.IO.Path]::GetFullPath($StagingDirectory)
if (-not (Test-Path -LiteralPath (Join-Path $StagingDirectory 'UsageBar.exe') -PathType Leaf)) {
    throw "No verified payload at ${StagingDirectory}: UsageBar.exe is missing. Run scripts/package.ps1 first."
}

# The files Inno Setup itself writes into {app} beside the payload: the
# uninstaller and its log (see [Setup] UninstallFilesDir). Root-relative and
# explicit on purpose — no wildcard, so any other file the installer lays down
# is reported rather than waved through.
$installerOwnedFiles = @('unins000.exe', 'unins000.dat')

$appId = '{7F3B1C64-9A2E-4D58-B0E7-3C6A5D142E90}'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1"
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$installDir = Join-Path ([System.IO.Path]::GetTempPath()) ("UsageBarInstallTest-" + [Guid]::NewGuid().ToString('N'))
$dataDir = Join-Path $env:LOCALAPPDATA 'UsageBar'
$settingsPath = Join-Path $dataDir 'settings.json'
$historyPath = Join-Path $dataDir 'history.json'
$unrelatedPath = Join-Path $env:LOCALAPPDATA 'UsageBarSmokeTestUnrelated.txt'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'UsageBar.lnk'
$startupShortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'UsageBar.lnk'
$installerSource = Join-Path $windowsRoot 'installer\UsageBar.iss'

$settingsBackup = $null
$historyBackup = $null
$runBackup = $null
$hadRunValue = $false

function Invoke-Setup {
    param([string] $Path, [string] $Destination)

    Write-Host "  running $(Split-Path -Leaf $Path)"
    $process = Start-Process -FilePath $Path `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$Destination" `
        -Wait -PassThru
    return $process.ExitCode
}

try {
    # --- preserve anything real on this machine ----------------------------

    if (Test-Path -LiteralPath $settingsPath) { $settingsBackup = Get-Content -LiteralPath $settingsPath -Raw }
    if (Test-Path -LiteralPath $historyPath) { $historyBackup = Get-Content -LiteralPath $historyPath -Raw }
    $existingRun = Get-ItemProperty -Path $runKey -Name 'UsageBar' -ErrorAction SilentlyContinue
    if ($existingRun) { $hadRunValue = $true; $runBackup = $existingRun.UsageBar }

    # --- fixtures the installer must not disturb ---------------------------

    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    $settingsFixture = '{"schemaVersion":1,"codexConnected":true,"language":"turkish","refreshInterval":"oneMinute","trayGuidanceVersionShown":2}'
    $historyFixture = '{"schemaVersion":1,"series":{"Codex|five-hour":[{"recordedAt":"2026-07-26T12:00:00+00:00","remainingPercent":65}]}}'
    Set-Content -LiteralPath $settingsPath -Value $settingsFixture -NoNewline
    Set-Content -LiteralPath $historyPath -Value $historyFixture -NoNewline
    Set-Content -LiteralPath $unrelatedPath -Value 'untouched' -NoNewline

    # The autostart preference the application owns. The installer must neither
    # create nor overwrite it.
    $autoStartValue = 'X:\SmokeTest\UsageBar.exe'
    Set-ItemProperty -Path $runKey -Name 'UsageBar' -Value $autoStartValue

    # --- fresh install ------------------------------------------------------

    Write-Host ''
    Write-Host '==> Fresh install' -ForegroundColor Cyan

    $exitCode = Invoke-Setup -Path $PreviousSetupPath -Destination $installDir
    Test-Requirement 'The older installer completes silently' ($exitCode -eq 0) "(exit $exitCode)"
    Test-Requirement 'UsageBar.exe is installed' (Test-Path -LiteralPath (Join-Path $installDir 'UsageBar.exe'))
    Test-Requirement 'The runtime is installed alongside it' (Test-Path -LiteralPath (Join-Path $installDir 'UsageBar.Windows.Core.dll'))
    Test-Requirement 'The destination is inside the user profile' ($installDir.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) "($installDir)"
    Test-Requirement 'Nothing was installed into Program Files' (-not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'UsageBar')))

    # The Start Menu shortcut is the only first-launch path, so it must exist and
    # point at the installed executable.
    Test-Requirement 'The Start Menu shortcut was created' (Test-Path -LiteralPath $startMenu)
    if (Test-Path -LiteralPath $startMenu) {
        $shell = New-Object -ComObject WScript.Shell
        try {
            $link = $shell.CreateShortcut($startMenu)
            Test-Requirement 'The shortcut targets the installed UsageBar.exe' (
                $link.TargetPath -ieq (Join-Path $installDir 'UsageBar.exe')) "($($link.TargetPath))"
            Test-Requirement 'The shortcut works from the application directory' (
                $link.WorkingDirectory.TrimEnd('\') -ieq $installDir.TrimEnd('\')) "($($link.WorkingDirectory))"
        }
        finally {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }

    # Setup has no [Run] section, so nothing should have been launched — and
    # nothing should appear a moment later either, which is what a delayed or
    # detached launch would look like.
    Test-Requirement 'A silent install does not launch UsageBar' (
        @(Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue).Count -eq 0)
    Start-Sleep -Seconds 3
    Test-Requirement 'Nothing starts a moment after the install either' (
        @(Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue).Count -eq 0)

    # The rejected alternative. If a build ever ships with the guard disabled to
    # make an auto-launch work, this fails rather than passing quietly.
    Test-Requirement 'Setup was not built with RedirectionGuard disabled' (
        (Test-Path -LiteralPath $installerSource) -and
        -not ((Get-Content -LiteralPath $installerSource -Raw) -match '(?i)RedirectionGuard\s*=\s*no'))

    # No other launch mechanism took its place.
    Test-Requirement 'No Startup-folder shortcut was created' (
        -not (Test-Path -LiteralPath $startupShortcut))

    if (Get-Command -Name 'Get-ScheduledTask' -ErrorAction SilentlyContinue) {
        $tasks = @(Get-ScheduledTask -TaskName 'UsageBar*' -ErrorAction SilentlyContinue)
        Test-Requirement 'No scheduled task was created' ($tasks.Count -eq 0) "(found $($tasks.Count))"
    }

    $entry = Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue
    Test-Requirement 'One uninstall entry exists under the current user' ($null -ne $entry)
    Test-Requirement 'No uninstall entry was created for all users' (
        $null -eq (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1" -ErrorAction SilentlyContinue))

    $previousVersion = if ($entry) { $entry.DisplayVersion } else { '' }
    Test-Requirement 'The entry records the older version' ($previousVersion -eq '0.0.1') "(got '$previousVersion')"

    # What the compiled installer actually laid down, compared with the
    # verified staging payload it was compiled from: same relative files, same
    # bytes, and only the installer-owned files beside them.
    Test-InstalledPayloadParity -Label 'Installed tree matches the verified payload' `
        -StagingRoot $StagingDirectory -InstallRoot $installDir -InstallerOwnedFiles $installerOwnedFiles

    # --- upgrade ------------------------------------------------------------

    Write-Host ''
    Write-Host '==> Upgrade over the older build' -ForegroundColor Cyan

    $exitCode = Invoke-Setup -Path $SetupPath -Destination $installDir
    Test-Requirement 'The current installer completes silently' ($exitCode -eq 0) "(exit $exitCode)"

    $entries = @(Get-ChildItem -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' |
        Where-Object { $_.PSChildName -like "*$appId*" })
    Test-Requirement 'The upgrade did not create a duplicate entry' ($entries.Count -eq 1) "(found $($entries.Count))"

    $upgraded = Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue
    Test-Requirement 'The stable AppId is unchanged' ($null -ne $upgraded)
    if ($upgraded) {
        Test-Requirement 'The recorded version moved forward' ($upgraded.DisplayVersion -ne $previousVersion) `
            "(was '$previousVersion', now '$($upgraded.DisplayVersion)')"
        Test-Requirement 'The install location is unchanged' (
            $upgraded.InstallLocation.TrimEnd('\') -ieq $installDir.TrimEnd('\')) "($($upgraded.InstallLocation))"
    }

    Test-Requirement 'Settings survived the upgrade' (
        (Test-Path -LiteralPath $settingsPath) -and (Get-Content -LiteralPath $settingsPath -Raw) -eq $settingsFixture)
    Test-Requirement 'Usage history survived the upgrade' (
        (Test-Path -LiteralPath $historyPath) -and (Get-Content -LiteralPath $historyPath -Raw) -eq $historyFixture)

    $runAfter = Get-ItemProperty -Path $runKey -Name 'UsageBar' -ErrorAction SilentlyContinue
    Test-Requirement 'The autostart preference was not overwritten' (
        $runAfter -and $runAfter.UsageBar -eq $autoStartValue) "(got '$($runAfter.UsageBar)')"
    Test-Requirement 'The installer added no second autostart entry' (
        -not (Test-Path -LiteralPath $startupShortcut))

    # An upgrade must not start UsageBar either, silently or a moment later.
    Test-Requirement 'An upgrade does not launch UsageBar' (
        @(Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue).Count -eq 0)
    Start-Sleep -Seconds 3
    Test-Requirement 'Nothing starts a moment after the upgrade either' (
        @(Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue).Count -eq 0)

    # The resulting installed tree must again be exactly the current verified
    # payload. This proves what the upgrade leaves behind — nothing more: the
    # older installer is compiled from this same payload with only its version
    # changed, so no file exists that the current payload lacks, and the check
    # cannot tell whether a file dropped from an older release would be removed.
    # Inno Setup does not remove such files unless told to; that question is
    # deliberately out of scope here.
    Test-InstalledPayloadParity -Label 'Upgraded installed tree matches the current verified payload' `
        -StagingRoot $StagingDirectory -InstallRoot $installDir -InstallerOwnedFiles $installerOwnedFiles

    # --- uninstall ----------------------------------------------------------

    Write-Host ''
    Write-Host '==> Uninstall' -ForegroundColor Cyan

    $uninstaller = Join-Path $installDir 'unins000.exe'
    Test-Requirement 'An uninstaller was generated' (Test-Path -LiteralPath $uninstaller)

    if (Test-Path -LiteralPath $uninstaller) {
        $process = Start-Process -FilePath $uninstaller `
            -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
        Test-Requirement 'The uninstaller completes silently' ($process.ExitCode -eq 0) "(exit $($process.ExitCode))"

        # Inno's uninstaller detaches to delete itself; give it a moment.
        for ($attempt = 0; $attempt -lt 40 -and (Test-Path -LiteralPath (Join-Path $installDir 'UsageBar.exe')); $attempt++) {
            Start-Sleep -Milliseconds 250
        }

        Test-Requirement 'The application files were removed' (-not (Test-Path -LiteralPath (Join-Path $installDir 'UsageBar.exe')))
        Test-Requirement 'The Start Menu shortcut was removed' (-not (Test-Path -LiteralPath $startMenu))
        Test-Requirement 'The uninstall entry was removed' (
            $null -eq (Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue))
    }

    Test-Requirement 'Settings survived the uninstall' (
        (Test-Path -LiteralPath $settingsPath) -and (Get-Content -LiteralPath $settingsPath -Raw) -eq $settingsFixture)
    Test-Requirement 'Usage history survived the uninstall' (
        (Test-Path -LiteralPath $historyPath) -and (Get-Content -LiteralPath $historyPath -Raw) -eq $historyFixture)
    Test-Requirement 'Unrelated Local AppData files were untouched' (
        (Test-Path -LiteralPath $unrelatedPath) -and (Get-Content -LiteralPath $unrelatedPath -Raw) -eq 'untouched')
    Test-Requirement 'No UsageBar process is left running' (
        @(Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue).Count -eq 0)
}
finally {
    # --- clean up, whatever happened ---------------------------------------

    Write-Host ''
    Write-Host '==> Cleaning up test state'

    Get-Process -Name 'UsageBar' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-Item -LiteralPath $unrelatedPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $startMenu -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue

    # Put back whatever was really there before the test.
    if ($null -ne $settingsBackup) { Set-Content -LiteralPath $settingsPath -Value $settingsBackup -NoNewline }
    else { Remove-Item -LiteralPath $settingsPath -Force -ErrorAction SilentlyContinue }

    if ($null -ne $historyBackup) { Set-Content -LiteralPath $historyPath -Value $historyBackup -NoNewline }
    else { Remove-Item -LiteralPath $historyPath -Force -ErrorAction SilentlyContinue }

    if ($hadRunValue) { Set-ItemProperty -Path $runKey -Name 'UsageBar' -Value $runBackup }
    else { Remove-ItemProperty -Path $runKey -Name 'UsageBar' -ErrorAction SilentlyContinue }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) of $checks installer smoke checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host "All $checks installer smoke checks passed." -ForegroundColor Green
exit 0
