<#
.SYNOPSIS
    Builds, tests and packages the portable Windows UsageBar ZIP.

.DESCRIPTION
    Produces UsageBar-Windows-x64.zip and its SHA-256 file from a clean staging
    directory. The package is a self-contained win-x64 folder publish: the user
    extracts it and runs UsageBar.exe, with no .NET installation required and no
    installer.

    Single-file publishing is deliberately not used. WPF plus the Windows Forms
    NotifyIcon relies on native resources being present on disk, and single-file
    adds a runtime extraction step that has historically caused tray-icon and
    native-resource failures for exactly that combination. See
    docs/windows-port.md.

    Reproducibility: assemblies are built deterministically, PDBs are not
    produced, entries are added to the archive in a stable sorted order, and
    every entry timestamp is pinned to the source commit date (or to a fixed
    epoch when git is unavailable). The same commit built with the same SDK
    therefore yields a byte-identical archive.

    The script only ever writes inside the repository's windows/artifacts
    directory. It refuses to delete anything else.

.PARAMETER Configuration
    Build configuration. Release by default.

.PARAMETER Runtime
    Runtime identifier. win-x64 by default; the first milestone is x64 only.

.PARAMETER SkipTests
    Skips the test run. Intended for iterating locally, never for a release.

.PARAMETER OutputDirectory
    Where the ZIP is written. Defaults to windows/artifacts.

.PARAMETER SourceRevision
    The authoritative full 40-character commit SHA the build came from. CI
    supplies it — for a pull request that is the head commit, never the
    synthetic merge commit GitHub checks out. Omitted locally, where the
    checked-out commit is used instead.

.EXAMPLE
    pwsh windows/scripts/package.ps1

.EXAMPLE
    pwsh windows/scripts/package.ps1 -SourceRevision 0123456789abcdef0123456789abcdef01234567
#>
[CmdletBinding()]
param(
    [string] $Configuration = 'Release',
    [string] $Runtime = 'win-x64',
    [switch] $SkipTests,
    [string] $OutputDirectory,
    [string] $SourceRevision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# ---------------------------------------------------------------- paths -----

$windowsRoot = Split-Path -Parent $PSScriptRoot
$repositoryRoot = Split-Path -Parent $windowsRoot
$solution = Join-Path $windowsRoot 'UsageBar.Windows.sln'
$appProject = Join-Path $windowsRoot 'src/UsageBar.Windows.App/UsageBar.Windows.App.csproj'

if (-not (Test-Path -LiteralPath $solution)) {
    throw "Solution not found at $solution."
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $windowsRoot 'artifacts'
}

$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$publishDirectory = Join-Path $OutputDirectory 'publish'
$stagingDirectory = Join-Path $OutputDirectory 'staging'
$packageName = 'UsageBar-Windows-x64'
$zipPath = Join-Path $OutputDirectory "$packageName.zip"
$hashPath = "$zipPath.sha256"

<#
    Guards every destructive operation: a path is only removable when it sits
    inside the artifacts directory, so a mistyped parameter can never delete
    the repository or anything of the user's.
#>
function Remove-ArtifactDirectory {
    param([Parameter(Mandatory)] [string] $Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($OutputDirectory)

    if ($full -eq $root) {
        # Removing the artifacts root itself is allowed only when it is inside
        # the repository.
        if (-not $full.StartsWith([System.IO.Path]::GetFullPath($repositoryRoot), [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to delete ${full}: it is outside the repository."
        }
    }
    elseif (-not $full.StartsWith($root + [System.IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to delete ${full}: it is outside ${root}."
    }

    if (Test-Path -LiteralPath $full) {
        Write-Host "Cleaning $full"
        Remove-Item -LiteralPath $full -Recurse -Force
    }
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )

    Write-Host ''
    Write-Host "==> $Name" -ForegroundColor Cyan
    & $Action

    $code = if (Test-Path variable:global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
    if ($code -ne 0) {
        throw "$Name failed with exit code $code."
    }
}

# ------------------------------------------------------------ provenance -----

# The short commit is embedded in the assembly's informational version so the
# running application can report which revision it came from. Nothing else about
# the build machine is recorded.
#
# The revision is resolved once here and used for every build, publish and
# timestamp below, so the packaged assemblies and the archive can never describe
# different commits. It is never read from HEAD in CI: a pull-request checkout
# is GitHub's synthetic merge commit, which is what stamped UsageBar 2.0.0 as
# `2.0.0+14bea7e`.
. (Join-Path $PSScriptRoot 'source-revision.ps1')

$resolvedRevision = Resolve-UsageBarSourceRevision -SourceRevision $SourceRevision -RepositoryRoot $repositoryRoot
$buildId = Get-UsageBarBuildId -SourceRevision $resolvedRevision
$revisionOrigin = if ($SourceRevision) { 'supplied explicitly' } else { 'checked-out git commit' }

# Dated from the resolved revision rather than from HEAD, so a pull-request
# build does not date the archive by its throwaway merge commit. When that
# object is not in the checkout — a shallow CI clone has only the merge
# commit — the fixed epoch keeps the archive reproducible.
$commitDate = $null
try {
    $raw = (& git -C $repositoryRoot show -s --format=%cI $resolvedRevision 2>$null)
    $code = if (Test-Path variable:global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
    if ($code -eq 0 -and $raw) {
        $commitDate = [datetimeoffset]::Parse($raw).UtcDateTime
    }
}
catch {
    $commitDate = $null
}

if (-not $commitDate) {
    # A fixed timestamp keeps the archive reproducible outside a git checkout.
    $commitDate = [datetime]::SpecifyKind([datetime]::Parse('2020-01-01T00:00:00'), [datetimekind]::Utc)
}

Write-Host "Repository : $repositoryRoot"
Write-Host "Revision   : $resolvedRevision ($revisionOrigin)"
Write-Host "Build id   : $buildId"
Write-Host "Output     : $OutputDirectory"

# ------------------------------------------------------------- pipeline -----

# Every dotnet command runs from windows/ so windows/global.json pins the SDK.
Push-Location $windowsRoot
try {
    Invoke-Step 'dotnet --version' { dotnet --version }

    Invoke-Step 'Restore' { dotnet restore $solution }

    Invoke-Step 'Build' {
        dotnet build $solution --configuration $Configuration --no-restore `
            -p:SourceRevisionId=$buildId
    }

    if (-not $SkipTests) {
        Invoke-Step 'Test' {
            dotnet test $solution --configuration $Configuration --no-build
        }
    }
    else {
        Write-Warning 'Tests skipped. Never ship a package built this way.'
    }

    Remove-ArtifactDirectory $publishDirectory
    Remove-ArtifactDirectory $stagingDirectory
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

    Invoke-Step 'Publish (self-contained folder)' {
        # DebugType=none keeps PDBs out of the user package entirely rather than
        # producing them and filtering them out later.
        dotnet publish $appProject `
            --configuration $Configuration `
            --runtime $Runtime `
            --self-contained true `
            --output $publishDirectory `
            -p:DebugType=none `
            -p:DebugSymbols=false `
            -p:GenerateDocumentationFile=false `
            -p:SourceRevisionId=$buildId
    }
}
finally {
    Pop-Location
}

# --------------------------------------------------------------- staging ----

Write-Host ''
Write-Host '==> Staging' -ForegroundColor Cyan

$stagedRoot = Join-Path $stagingDirectory 'UsageBar'
New-Item -ItemType Directory -Path $stagedRoot -Force | Out-Null

<#
    Only runtime files reach the user package. Anything that is a build
    artifact, a test asset, a fixture or a symbol file is excluded, and the
    exclusion is by pattern rather than by hand so a new file cannot slip in.
#>
$excludedExtensions = @('.pdb', '.xml', '.trx', '.log', '.tmp', '.cs', '.csproj', '.sln', '.user')
$excludedNames = @('appsettings.Development.json')
$excludedDirectorySegments = @('fixtures', 'testhost', 'obj', 'ref', 'runtimes-test', '.git')

$published = Get-ChildItem -LiteralPath $publishDirectory -Recurse -File
$staged = 0

foreach ($file in $published) {
    $relative = $file.FullName.Substring($publishDirectory.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, '/')

    if ($excludedExtensions -contains $file.Extension.ToLowerInvariant()) { continue }
    if ($excludedNames -contains $file.Name) { continue }

    $segments = $relative -split '[\\/]'
    $skip = $false
    foreach ($segment in $segments) {
        if ($excludedDirectorySegments -contains $segment.ToLowerInvariant()) { $skip = $true; break }
        if ($segment -like '*Tests*') { $skip = $true; break }
    }

    if ($skip) { continue }

    $target = Join-Path $stagedRoot $relative
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
    }

    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $staged++
}

if (-not (Test-Path -LiteralPath (Join-Path $stagedRoot 'UsageBar.exe'))) {
    throw 'UsageBar.exe is missing from the staged package.'
}

Write-Host "Staged $staged files."

# Pin every timestamp so the archive is reproducible.
Get-ChildItem -LiteralPath $stagingDirectory -Recurse | ForEach-Object {
    $_.LastWriteTimeUtc = $commitDate
    $_.CreationTimeUtc = $commitDate
}

# --------------------------------------------------------------- archive ----

Write-Host ''
Write-Host '==> Archive' -ForegroundColor Cyan

if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
if (Test-Path -LiteralPath $hashPath) { Remove-Item -LiteralPath $hashPath -Force }

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Built entry by entry rather than with Compress-Archive: that lets the entry
# order and timestamps be fixed, which is what makes the output reproducible.
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $entries = Get-ChildItem -LiteralPath $stagingDirectory -Recurse -File |
        ForEach-Object {
            [pscustomobject]@{
                FullName = $_.FullName
                Relative = $_.FullName.Substring($stagingDirectory.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, '/').Replace('\', '/')
            }
        } | Sort-Object -Property Relative -CaseSensitive

    foreach ($entry in $entries) {
        $zipEntry = $archive.CreateEntry($entry.Relative, [System.IO.Compression.CompressionLevel]::Optimal)
        $zipEntry.LastWriteTime = [datetimeoffset]::new($commitDate, [timespan]::Zero)

        $source = [System.IO.File]::OpenRead($entry.FullName)
        try {
            $destination = $zipEntry.Open()
            try { $source.CopyTo($destination) } finally { $destination.Dispose() }
        }
        finally {
            $source.Dispose()
        }
    }
}
finally {
    $archive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
# sha256sum-compatible so it can be checked on any platform.
$line = "$hash  $packageName.zip"
[System.IO.File]::WriteAllText($hashPath, $line + "`n", [System.Text.UTF8Encoding]::new($false))

$zipSize = (Get-Item -LiteralPath $zipPath).Length

Write-Host ''
Write-Host 'Package ready.' -ForegroundColor Green
Write-Host "  source : $resolvedRevision (build id $buildId)"
Write-Host "  zip    : $zipPath"
Write-Host "  size   : $([math]::Round($zipSize / 1MB, 1)) MB ($zipSize bytes)"
Write-Host "  sha256 : $hash"
Write-Host "  files  : $(@($entries).Count)"
Write-Host ''
Write-Host 'The package is NOT code signed. Windows SmartScreen will warn on first run.'
Write-Host 'Verify the SHA-256 above before running it; do not disable SmartScreen or Defender.'
