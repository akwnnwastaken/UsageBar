<#
.SYNOPSIS
    Compiles the UsageBar Windows Setup EXE with Inno Setup.

.DESCRIPTION
    Produces UsageBar-Setup-x64.exe and its SHA-256 from the same staging
    directory the portable ZIP was built from, so the installed build and the
    portable build can never drift apart. Run package.ps1 first.

    Inno Setup is pinned to an exact version, downloaded from the official
    jrsoftware release, and its SHA-256 is verified before it is executed. No
    third-party action is involved.

.PARAMETER StagingDirectory
    The verified payload. Defaults to what package.ps1 produced.

.PARAMETER OutputDirectory
    Where the Setup EXE is written. Defaults to windows/artifacts.

.PARAMETER VersionOverride
    Builds a deliberately older installer for the upgrade smoke test. Never used
    for a real package.

.PARAMETER OutputBaseName
    Overrides the output file name, again only for the upgrade smoke test.
#>
[CmdletBinding()]
param(
    [string] $StagingDirectory,
    [string] $OutputDirectory,
    [string] $VersionOverride,
    [string] $OutputBaseName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- pinned toolchain -------------------------------------------------------

# Inno Setup 6.7.3, the current release of the established Inno Setup 6 line,
# published by jrsoftware on GitHub. The checksum was taken from that download
# and is verified before the installer is executed.
$innoVersion = '6.7.3'
$innoUrl = 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe'
$innoSha256 = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'

# --- paths ------------------------------------------------------------------

$windowsRoot = Split-Path -Parent $PSScriptRoot
$installerSource = Join-Path $windowsRoot 'installer\UsageBar.iss'

if (-not $OutputDirectory) { $OutputDirectory = Join-Path $windowsRoot 'artifacts' }
if (-not $StagingDirectory) { $StagingDirectory = Join-Path $OutputDirectory 'staging\UsageBar' }

$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$StagingDirectory = [System.IO.Path]::GetFullPath($StagingDirectory)
$toolsDirectory = Join-Path $OutputDirectory 'tools'

if (-not (Test-Path -LiteralPath $installerSource)) {
    throw "Installer script not found at $installerSource."
}

if (-not (Test-Path -LiteralPath (Join-Path $StagingDirectory 'UsageBar.exe'))) {
    throw "No verified payload at ${StagingDirectory}. Run scripts/package.ps1 first."
}

# --- version ----------------------------------------------------------------

<#
    One authoritative version source: windows/Directory.Build.props, the same
    property that stamps the assemblies. Nothing duplicates a version number.
#>
function Get-UsageBarVersion {
    $props = Join-Path $windowsRoot 'Directory.Build.props'
    $content = Get-Content -LiteralPath $props -Raw
    if ($content -notmatch '<Version>\s*([0-9]+\.[0-9]+\.[0-9]+)\s*</Version>') {
        throw "Could not read <Version> from $props."
    }

    return $Matches[1]
}

$version = if ($VersionOverride) { $VersionOverride } else { Get-UsageBarVersion }
$baseName = if ($OutputBaseName) { $OutputBaseName } else { 'UsageBar-Setup-x64' }

Write-Host "UsageBar version : $version"
Write-Host "Payload          : $StagingDirectory"
Write-Host "Inno Setup       : $innoVersion"

# --- toolchain --------------------------------------------------------------

function Get-InnoSetupCompiler {
    $installRoot = Join-Path $toolsDirectory "InnoSetup-$innoVersion"
    $compiler = Join-Path $installRoot 'ISCC.exe'

    if (Test-Path -LiteralPath $compiler) {
        Write-Host "Using the already-installed Inno Setup at $installRoot"
        return $compiler
    }

    New-Item -ItemType Directory -Path $toolsDirectory -Force | Out-Null
    $download = Join-Path $toolsDirectory "innosetup-$innoVersion.exe"

    if (-not (Test-Path -LiteralPath $download)) {
        Write-Host "Downloading Inno Setup $innoVersion from the official release"
        Invoke-WebRequest -Uri $innoUrl -OutFile $download -UseBasicParsing
    }

    # Verified before it is ever executed.
    $actual = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $innoSha256) {
        Remove-Item -LiteralPath $download -Force
        throw "Inno Setup checksum mismatch. Expected $innoSha256, got $actual. Refusing to run it."
    }

    Write-Host "Checksum verified: $actual"

    & $download /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /NOICONS "/DIR=$installRoot" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup installation failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $compiler)) {
        throw "ISCC.exe was not found at $compiler after installation."
    }

    return $compiler
}

$iscc = Get-InnoSetupCompiler

Write-Host ''
Write-Host '==> Inno Setup version in use' -ForegroundColor Cyan
# ISCC prints its banner and exits non-zero with no arguments; the banner is
# what we want recorded in the log.
& $iscc /? 2>&1 | Select-Object -First 3 | ForEach-Object { Write-Host $_ }

# --- compile ----------------------------------------------------------------

Write-Host ''
Write-Host '==> Compiling the installer' -ForegroundColor Cyan

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

& $iscc `
    "/DAppVersion=$version" `
    "/DPayloadDir=$StagingDirectory" `
    "/DOutputDir=$OutputDirectory" `
    "/F$baseName" `
    $installerSource

if ($LASTEXITCODE -ne 0) {
    throw "ISCC failed with exit code $LASTEXITCODE."
}

$setupPath = Join-Path $OutputDirectory "$baseName.exe"
if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "The installer was not produced at $setupPath."
}

# --- checksum ---------------------------------------------------------------

$hash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
$hashPath = "$setupPath.sha256"
# sha256sum-compatible so it can be checked on any platform.
[System.IO.File]::WriteAllText($hashPath, "$hash  $baseName.exe`n", [System.Text.UTF8Encoding]::new($false))

$size = (Get-Item -LiteralPath $setupPath).Length

Write-Host ''
Write-Host 'Installer ready.' -ForegroundColor Green
Write-Host "  setup      : $setupPath"
Write-Host "  size       : $([math]::Round($size / 1MB, 1)) MB ($size bytes)"
Write-Host "  sha256     : $hash"
Write-Host "  inno setup : $innoVersion"
Write-Host ''
Write-Host 'The installer is NOT code signed. Windows SmartScreen will warn on first run.'
Write-Host 'Verify the SHA-256 above before running it; do not disable SmartScreen or Defender.'
