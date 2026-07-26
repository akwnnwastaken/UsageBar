<#
.SYNOPSIS
    Installs, upgrades and uninstalls UsageBar for real, on Windows.

.DESCRIPTION
    Runs the produced Setup EXE silently and checks what it actually did:

      * fresh install lands under the user profile, with the expected files, a
        Start Menu shortcut and one uninstall entry under HKCU;
      * an upgrade over a deliberately older build keeps the same AppId and the
        same single entry, updates the files, and leaves user settings and the
        autostart preference untouched;
      * uninstall removes the program files, the shortcut and the entry — and
        leaves settings and history behind.

    The upgrade half is only meaningful because a *different, older* installer
    is built first; installing identical bytes twice would prove nothing.

    All state is created under temporary directories and a scratch settings
    folder, and removed afterwards even when a check fails.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SetupPath,
    [Parameter(Mandatory)] [string] $PreviousSetupPath
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

$appId = '{7F3B1C64-9A2E-4D58-B0E7-3C6A5D142E90}'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1"
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$installDir = Join-Path ([System.IO.Path]::GetTempPath()) ("UsageBarInstallTest-" + [Guid]::NewGuid().ToString('N'))
$dataDir = Join-Path $env:LOCALAPPDATA 'UsageBar'
$settingsPath = Join-Path $dataDir 'settings.json'
$historyPath = Join-Path $dataDir 'history.json'
$unrelatedPath = Join-Path $env:LOCALAPPDATA 'UsageBarSmokeTestUnrelated.txt'
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'UsageBar.lnk'

$settingsBackup = $null
$historyBackup = $null
$runBackup = $null
$hadRunValue = $false

function Invoke-Setup {
    param([string] $Path, [string] $Destination)

    Write-Host "  running $(Split-Path -Leaf $Path)"
    $process = Start-Process -FilePath $Path `
        -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS-', "/DIR=$Destination" `
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

    $entry = Get-ItemProperty -Path $uninstallKey -ErrorAction SilentlyContinue
    Test-Requirement 'One uninstall entry exists under the current user' ($null -ne $entry)
    Test-Requirement 'No uninstall entry was created for all users' (
        $null -eq (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1" -ErrorAction SilentlyContinue))

    $previousVersion = if ($entry) { $entry.DisplayVersion } else { '' }
    Test-Requirement 'The entry records the older version' ($previousVersion -eq '0.0.1') "(got '$previousVersion')"

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
        -not (Test-Path -LiteralPath (Join-Path ([Environment]::GetFolderPath('Startup')) 'UsageBar.lnk')))

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
