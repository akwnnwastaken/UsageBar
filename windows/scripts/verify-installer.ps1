<#
.SYNOPSIS
    Security and correctness gate for the UsageBar Windows Setup EXE.

.DESCRIPTION
    Two kinds of check run here, and the report says which is which:

      * checks against the compiled Setup EXE — its checksum, its manifest, the
        version metadata and icon it carries;
      * checks against the installer definition and the payload it was built
        from — the install scope, the stable AppId, and the absence of symbols,
        test assemblies, source or macOS output.

    The payload checks read the staging directory rather than unpacking the
    installer, because that directory *is* the installer's payload: the same one
    the portable package gate already verified. Anything that reached the ZIP
    reached the Setup EXE, and nothing else did.
#>
[CmdletBinding()]
param(
    [string] $SetupPath,
    [string] $StagingDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$windowsRoot = Split-Path -Parent $PSScriptRoot
$installerSource = Join-Path $windowsRoot 'installer\UsageBar.iss'
$iconPath = Join-Path $windowsRoot 'installer\UsageBar.ico'

if (-not $SetupPath) { $SetupPath = Join-Path $windowsRoot 'artifacts\UsageBar-Setup-x64.exe' }
if (-not $StagingDirectory) { $StagingDirectory = Join-Path $windowsRoot 'artifacts\staging\UsageBar' }

$SetupPath = [System.IO.Path]::GetFullPath($SetupPath)
$StagingDirectory = [System.IO.Path]::GetFullPath($StagingDirectory)
$hashPath = "$SetupPath.sha256"

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

Write-Host "Verifying $SetupPath"
Write-Host ''

# --- the artifact itself ----------------------------------------------------

Test-Requirement 'The Setup EXE exists' (Test-Path -LiteralPath $SetupPath)
Test-Requirement 'The SHA-256 file exists' (Test-Path -LiteralPath $hashPath)

if (-not (Test-Path -LiteralPath $SetupPath)) {
    Write-Error 'Nothing to verify: the Setup EXE is missing.'
    exit 1
}

$setupItem = Get-Item -LiteralPath $SetupPath
Test-Requirement 'The Setup EXE is not empty' ($setupItem.Length -gt 1MB) "(size $($setupItem.Length) bytes)"
Test-Requirement 'The file name is deterministic' ($setupItem.Name -eq 'UsageBar-Setup-x64.exe') "(got $($setupItem.Name))"

if (Test-Path -LiteralPath $hashPath) {
    $recorded = ((Get-Content -LiteralPath $hashPath -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $SetupPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-Requirement 'The recorded SHA-256 matches the Setup EXE' ($recorded -eq $actual) "(recorded $recorded, actual $actual)"
}

# --- the compiled binary ----------------------------------------------------

$bytes = [System.IO.File]::ReadAllBytes($SetupPath)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
Test-Requirement 'The Setup EXE is a PE image' ([System.Text.Encoding]::ASCII.GetString($bytes, $peOffset, 2) -eq 'PE')

$subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
Test-Requirement 'The Setup EXE is a GUI subsystem binary' ($subsystem -eq 2) "(subsystem $subsystem)"

# The embedded manifest is plain XML, so the requested execution level can be
# read directly out of the file.
$text = [System.Text.Encoding]::UTF8.GetString($bytes)
Test-Requirement 'The installer requests no administrator privileges' (-not ($text -match 'requireAdministrator'))
Test-Requirement 'The installer requests asInvoker' ($text -match 'asInvoker')
Test-Requirement 'The installer does not request highestAvailable' (-not ($text -match 'highestAvailable'))

# VERSIONINFO lives uncompressed in the resource section as UTF-16.
$wide = [System.Text.Encoding]::Unicode.GetString($bytes)
Test-Requirement 'Version metadata carries the product name' ($wide -match 'UsageBar')
Test-Requirement 'Version metadata carries a publisher' ($wide -match 'UsageBar contributors')
Test-Requirement 'Version metadata carries a product version' ($wide -match 'ProductVersion')
Test-Requirement 'Version metadata carries a file version' ($wide -match 'FileVersion')

# No runner or user path may be baked into the artifact.
foreach ($leak in @('runneradmin', 'D:\a\UsageBar', 'C:\Users\', '/home/')) {
    Test-Requirement "The Setup EXE does not embed '$leak'" (-not $text.Contains($leak))
}

foreach ($secret in @('ANTHROPIC_API_KEY', 'sk-ant-', 'BEGIN PRIVATE KEY', 'password=')) {
    Test-Requirement "The Setup EXE does not embed '$secret'" (-not $text.Contains($secret))
}

# --- the installer definition ----------------------------------------------

Test-Requirement 'The installer script exists' (Test-Path -LiteralPath $installerSource)
$iss = if (Test-Path -LiteralPath $installerSource) { Get-Content -LiteralPath $installerSource -Raw } else { '' }

Test-Requirement 'The install is current-user only' ($iss -match '(?m)^\s*PrivilegesRequired\s*=\s*lowest\s*$')
Test-Requirement 'Elevation cannot be selected' (-not ($iss -match '(?m)^\s*PrivilegesRequiredOverridesAllowed\s*='))
Test-Requirement 'The destination is under the user profile' ($iss -match '(?m)^\s*DefaultDirName\s*=\s*\{localappdata\}\\Programs\\')
Test-Requirement 'The installer targets x64' ($iss -match '(?m)^\s*ArchitecturesInstallIn64BitMode\s*=\s*x64compatible\s*$')
Test-Requirement 'A stable AppId is declared' ($iss -match '(?m)^\s*AppId=\{\{[0-9A-Fa-f-]{36}\}')
Test-Requirement 'Uninstall support is enabled' ($iss -match '(?m)^\s*Uninstallable\s*=\s*yes\s*$')
Test-Requirement 'A Start Menu shortcut is created' ($iss -match '\{autoprograms\}')
Test-Requirement 'The desktop shortcut is optional and unchecked' ($iss -match 'Name:\s*"desktopicon".*Flags:\s*unchecked')
Test-Requirement 'The launch-after-install option uses the Start Menu shortcut' (
    $iss -match '(?m)^Filename: "\{autoprograms\}\\\{#AppName\}\.lnk".*postinstall')
Test-Requirement 'The launch uses ShellExecute as the original user' (
    $iss -match '(?m)^Filename:.*postinstall.*shellexec.*runasoriginaluser')
Test-Requirement 'Setup never launches the executable directly' (
    -not ($iss -match '(?m)^Filename: "\{app\}.*postinstall'))
Test-Requirement 'The shortcut has a working directory' ($iss -match 'WorkingDir: "\{app\}"')
Test-Requirement 'A skipped launch is reported rather than faked' (
    $iss -match 'Check: LaunchShortcutAvailable')
Test-Requirement 'The application icon is used for setup' ($iss -match '(?m)^\s*SetupIconFile\s*=')
Test-Requirement 'A running instance is detected by mutex' ($iss -match '(?m)^\s*AppMutex\s*=\s*Local\\UsageBar')

# The installer must not take over anything the application owns, or touch the
# machine beyond its own files.
foreach ($forbidden in @(
        '\[Registry\]',
        'HKLM',
        'CurrentVersion\\Run',
        '\{userstartup\}',
        '\{commonstartup\}',
        'schtasks',
        '\{commonpf',
        '\{pf\}',
        '\{sys\}',
        'ChangesEnvironment')) {
    Test-Requirement "The installer does not use '$forbidden'" (-not ($iss -match $forbidden))
}

# User data must be outside anything the uninstaller removes.
Test-Requirement 'No user data directory is deleted on uninstall' (-not ($iss -match '(?m)^\s*Type:\s*filesandordirs'))

Test-Requirement 'The application icon exists' (Test-Path -LiteralPath $iconPath)
if (Test-Path -LiteralPath $iconPath) {
    $icon = [System.IO.File]::ReadAllBytes($iconPath)
    $isIcon = $icon.Length -gt 6 -and $icon[0] -eq 0 -and $icon[1] -eq 0 -and $icon[2] -eq 1 -and $icon[3] -eq 0
    Test-Requirement 'The application icon is a valid multi-size ICO' ($isIcon -and [BitConverter]::ToUInt16($icon, 4) -ge 4)
}

# --- the payload ------------------------------------------------------------

Test-Requirement 'The payload directory exists' (Test-Path -LiteralPath $StagingDirectory)

if (Test-Path -LiteralPath $StagingDirectory) {
    $payload = Get-ChildItem -LiteralPath $StagingDirectory -Recurse -File
    $relative = $payload | ForEach-Object {
        $_.FullName.Substring($StagingDirectory.Length).TrimStart('\', '/').Replace('\', '/')
    }

    Test-Requirement 'The payload contains UsageBar.exe' (@($relative | Where-Object { $_ -eq 'UsageBar.exe' }).Count -eq 1)
    Test-Requirement 'The payload contains the application assemblies' (@($relative | Where-Object { $_ -eq 'UsageBar.Windows.Core.dll' }).Count -eq 1)

    foreach ($pattern in @('\.pdb$', '\.cs$', '\.csproj$', '\.sln$', '\.ps1$', '\.iss$', 'Tests\.dll$', '(^|/)fixtures?/', '(^|/)obj/', '(^|/)ref/')) {
        $hits = @($relative | Where-Object { $_ -match $pattern })
        Test-Requirement "The payload has no entries matching '$pattern'" ($hits.Count -eq 0) "(found $($hits -join ', '))"
    }

    foreach ($pattern in @('\.app/', '\.dylib$', '\.swift$', '\.icns$', 'Contents/MacOS/')) {
        $hits = @($relative | Where-Object { $_ -match $pattern })
        Test-Requirement "The payload has no macOS artifact matching '$pattern'" ($hits.Count -eq 0) "(found $($hits -join ', '))"
    }

    $installedExe = Join-Path $StagingDirectory 'UsageBar.exe'
    if (Test-Path -LiteralPath $installedExe) {
        $appBytes = [System.IO.File]::ReadAllBytes($installedExe)
        $appPe = [BitConverter]::ToInt32($appBytes, 0x3C)
        $appSubsystem = [BitConverter]::ToUInt16($appBytes, $appPe + 24 + 68)
        $appMachine = [BitConverter]::ToUInt16($appBytes, $appPe + 4)

        Test-Requirement 'The installed UsageBar.exe is a GUI subsystem binary' ($appSubsystem -eq 2) "(subsystem $appSubsystem)"
        Test-Requirement 'The installed UsageBar.exe is x64' ($appMachine -eq 0x8664) "(machine 0x$($appMachine.ToString('X4')))"

        $appText = [System.Text.Encoding]::UTF8.GetString($appBytes)
        Test-Requirement 'The installed UsageBar.exe requests asInvoker' ($appText -match 'asInvoker')
        Test-Requirement 'The installed UsageBar.exe does not request administrator' (-not ($appText -match 'requireAdministrator'))
    }
}

# --- result -----------------------------------------------------------------

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) of $checks installer checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host "All $checks installer checks passed." -ForegroundColor Green
Write-Host 'Note: the installer is not code signed. SmartScreen will warn on first run.'
exit 0
