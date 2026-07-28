<#
.SYNOPSIS
    Focused regression tests for the Windows source-revision resolution.

.DESCRIPTION
    Exercises the functions in source-revision.ps1 directly — the same ones
    package.ps1 and both verification gates use — so the rules that keep a
    synthetic pull-request merge SHA out of the artifacts are actually proven
    rather than assumed:

      * a valid full SHA is accepted and drives the embedded build id;
      * two different revisions produce two different build ids;
      * short, empty, non-hex and over-long values are rejected outright;
      * with no explicit revision the checked-out commit is used;
      * the verification gate reads back the build id an assembly carries and
        rejects a mismatch.

    No test framework: the same Test-Requirement reporting the packaging gates
    use, so this runs anywhere PowerShell does.

.PARAMETER RepositoryRoot
    The checkout used for the local-fallback test. Defaults to this repository.
#>
[CmdletBinding()]
param(
    [string] $RepositoryRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'source-revision.ps1')

$windowsRoot = Split-Path -Parent $PSScriptRoot
if (-not $RepositoryRoot) { $RepositoryRoot = Split-Path -Parent $windowsRoot }
$RepositoryRoot = [System.IO.Path]::GetFullPath($RepositoryRoot)

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

<# True when the scriptblock throws, which is how every rejection is asserted. #>
function Test-Throws {
    param([Parameter(Mandatory)] [scriptblock] $Action)

    try {
        & $Action | Out-Null
        return $false
    }
    catch {
        return $true
    }
}

# Deterministic stand-ins. Never the current commit: a test pinned to HEAD would
# have to be edited on every ordinary commit.
$firstRevision = '0123456789abcdef0123456789abcdef01234567'
$secondRevision = 'fedcba9876543210fedcba9876543210fedcba98'

Write-Host "Repository : $RepositoryRoot"
Write-Host ''

# ------------------------------------------------------------- accepted -----

Write-Host '==> A supplied revision is accepted' -ForegroundColor Cyan

$resolved = Resolve-UsageBarSourceRevision -SourceRevision $firstRevision -RepositoryRoot $RepositoryRoot
Test-Requirement 'A full 40-character SHA is accepted unchanged' ($resolved -eq $firstRevision) "(got '$resolved')"
Test-Requirement 'An upper-case SHA is normalized to lower case' (
    (Resolve-UsageBarSourceRevision -SourceRevision $firstRevision.ToUpperInvariant() -RepositoryRoot $RepositoryRoot) -eq $firstRevision)
Test-Requirement 'Surrounding whitespace is tolerated' (
    (Resolve-UsageBarSourceRevision -SourceRevision "  $firstRevision  " -RepositoryRoot $RepositoryRoot) -eq $firstRevision)

# -------------------------------------------------------------- build id -----

Write-Host ''
Write-Host '==> The build id is the first seven characters' -ForegroundColor Cyan

$firstBuildId = Get-UsageBarBuildId -SourceRevision $firstRevision
$secondBuildId = Get-UsageBarBuildId -SourceRevision $secondRevision

Test-Requirement 'The build id is the revision prefix' ($firstBuildId -eq $firstRevision.Substring(0, 7)) "(got '$firstBuildId')"
Test-Requirement 'The build id is seven characters' ($firstBuildId.Length -eq 7) "(length $($firstBuildId.Length))"
Test-Requirement 'A different revision yields a different build id' ($firstBuildId -ne $secondBuildId) "($firstBuildId vs $secondBuildId)"
Test-Requirement 'The second build id is its own prefix' ($secondBuildId -eq $secondRevision.Substring(0, 7)) "(got '$secondBuildId')"

# -------------------------------------------------------------- rejected -----

Write-Host ''
Write-Host '==> Anything that is not a full commit SHA is rejected' -ForegroundColor Cyan

$invalid = [ordered]@{
    'a short SHA'          = $firstRevision.Substring(0, 7)
    'a 39-character SHA'   = $firstRevision.Substring(0, 39)
    'a 41-character SHA'   = "$firstRevision" + '0'
    'a non-hex SHA'        = '0123456789abcdef0123456789abcdef0123456z'
    'a branch name'        = 'refs/heads/main'
    'arbitrary text'       = 'HEAD'
    'a version number'     = '2.0.0'
    'the word unknown'     = 'unknown'
}

foreach ($case in $invalid.GetEnumerator()) {
    Test-Requirement "Resolution rejects $($case.Key)" (
        Test-Throws { Resolve-UsageBarSourceRevision -SourceRevision $case.Value -RepositoryRoot $RepositoryRoot })
    Test-Requirement "The build id refuses $($case.Key)" (
        Test-Throws { Get-UsageBarBuildId -SourceRevision $case.Value })
    Test-Requirement "Validation refuses $($case.Key)" (-not (Test-UsageBarSourceRevision $case.Value))
}

Test-Requirement 'Resolution fails when no revision can be found at all' (
    Test-Throws {
        Resolve-UsageBarSourceRevision -SourceRevision '' -RepositoryRoot ([System.IO.Path]::GetTempPath())
    })

# -------------------------------------------------------------- fallback -----

Write-Host ''
Write-Host '==> Local builds fall back to the checked-out commit' -ForegroundColor Cyan

$head = (& git -C $RepositoryRoot rev-parse HEAD).Trim().ToLowerInvariant()
$fallback = Resolve-UsageBarSourceRevision -SourceRevision '' -RepositoryRoot $RepositoryRoot

Test-Requirement 'No explicit revision resolves the checked-out commit' ($fallback -eq $head) "(got '$fallback', HEAD $head)"
Test-Requirement 'The fallback is a full commit SHA' (Test-UsageBarSourceRevision $fallback)
Test-Requirement 'An explicit revision still wins over the checkout' (
    (Resolve-UsageBarSourceRevision -SourceRevision $firstRevision -RepositoryRoot $RepositoryRoot) -ne $head)

# ------------------------------------------------------ verification gate -----

Write-Host ''
Write-Host '==> The verification gate reads back what an assembly carries' -ForegroundColor Cyan

# Assemblies store the informational version as UTF-8 metadata, which is what
# the gate reads out of the packaged bytes.
function New-AssemblyBytesWithBuildId {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $InformationalVersion)

    return [System.Text.Encoding]::UTF8.GetBytes("MZ...metadata...$InformationalVersion...more")
}

$stamped = New-AssemblyBytesWithBuildId "2.0.0+$firstBuildId"
Test-Requirement 'The embedded build id is read back' (
    (Get-UsageBarEmbeddedBuildId -AssemblyBytes $stamped) -eq $firstBuildId)
Test-Requirement 'The embedded build id matches its own revision' (
    (Get-UsageBarEmbeddedBuildId -AssemblyBytes $stamped) -eq (Get-UsageBarBuildId -SourceRevision $firstRevision))
Test-Requirement 'A different revision does not match the embedded build id' (
    (Get-UsageBarEmbeddedBuildId -AssemblyBytes $stamped) -ne (Get-UsageBarBuildId -SourceRevision $secondRevision))

# A full 40-character suffix still reports the seven the application shows.
$stampedLong = New-AssemblyBytesWithBuildId "2.0.0+$firstRevision"
Test-Requirement 'A full-length suffix reports its first seven characters' (
    (Get-UsageBarEmbeddedBuildId -AssemblyBytes $stampedLong) -eq $firstBuildId)

Test-Requirement 'An assembly with no build id reports none' (
    (Get-UsageBarEmbeddedBuildId -AssemblyBytes (New-AssemblyBytesWithBuildId '2.0.0')) -eq '')

# --------------------------------------------------------------- result -----

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) of $checks source-revision checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host "All $checks source-revision checks passed." -ForegroundColor Green
exit 0
