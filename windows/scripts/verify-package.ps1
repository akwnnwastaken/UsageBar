<#
.SYNOPSIS
    Security and hygiene gate for the packaged Windows UsageBar ZIP.

.DESCRIPTION
    Inspects the produced archive before it is offered for download. Every check
    fails the script, so a package that leaks build paths, ships symbols, ships
    test assets, requests administrator rights or would open a console window
    can never reach a user.

    Run by Windows CI immediately after packaging, and usable locally against
    the same artifacts.

.PARAMETER ZipPath
    The archive to inspect. Defaults to windows/artifacts/UsageBar-Windows-x64.zip.

.PARAMETER ExpectedSourceRevision
    The full 40-character commit SHA the package is supposed to have been built
    from. When supplied, the packaged assemblies must carry its first seven
    characters as their build id, so an archive stamped with the wrong revision
    — a stale build, or GitHub's synthetic pull-request merge commit — fails
    here instead of being published.
#>
[CmdletBinding()]
param(
    [string] $ZipPath,
    [string] $ExpectedSourceRevision
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'source-revision.ps1')

$windowsRoot = Split-Path -Parent $PSScriptRoot

if (-not $ZipPath) {
    $ZipPath = Join-Path $windowsRoot 'artifacts/UsageBar-Windows-x64.zip'
}

$ZipPath = [System.IO.Path]::GetFullPath($ZipPath)
$hashPath = "$ZipPath.sha256"

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

Write-Host "Verifying $ZipPath"
Write-Host ''

# ------------------------------------------------------------ existence -----

Test-Requirement 'The archive exists' (Test-Path -LiteralPath $ZipPath)
Test-Requirement 'The SHA-256 file exists' (Test-Path -LiteralPath $hashPath)

if (-not (Test-Path -LiteralPath $ZipPath)) {
    Write-Host ''
    Write-Error 'Nothing to verify: the archive is missing.'
    exit 1
}

$zipItem = Get-Item -LiteralPath $ZipPath
Test-Requirement 'The archive is not empty' ($zipItem.Length -gt 1MB) "(size $($zipItem.Length) bytes)"

if (Test-Path -LiteralPath $hashPath) {
    $recorded = ((Get-Content -LiteralPath $hashPath -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    Test-Requirement 'The recorded SHA-256 matches the archive' ($recorded -eq $actual) "(recorded $recorded, actual $actual)"
}

# -------------------------------------------------------------- entries -----

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    $names = $archive.Entries | ForEach-Object { $_.FullName }

    Test-Requirement 'The archive contains files' ($names.Count -gt 0) "(entries $($names.Count))"
    Test-Requirement 'UsageBar.exe is present' (@($names | Where-Object { $_ -match '(^|/)UsageBar\.exe$' }).Count -eq 1)

    $pdbs = @($names | Where-Object { $_ -like '*.pdb' })
    Test-Requirement 'No debug symbols are shipped' ($pdbs.Count -eq 0) "(found $($pdbs -join ', '))"

    # Test assets, build intermediates and source must never be in a user package.
    $forbiddenPatterns = @(
        '(^|/)obj/', '(^|/)ref/', '(^|/)\.git/', '(^|/)fixtures?/',
        '(^|/)testhost', 'Tests\.dll$', 'Tests\.deps\.json$',
        '\.cs$', '\.csproj$', '\.sln$', '\.ps1$', '\.trx$'
    )
    foreach ($pattern in $forbiddenPatterns) {
        $hits = @($names | Where-Object { $_ -match $pattern })
        Test-Requirement "No entries match '$pattern'" ($hits.Count -eq 0) "(found $($hits -join ', '))"
    }

    # macOS build output must never end up in the Windows package.
    $macPatterns = @('\.app/', '\.dylib$', '\.swift$', '\.swiftmodule', 'Contents/MacOS/', '\.icns$', '\.plist$')
    foreach ($pattern in $macPatterns) {
        $hits = @($names | Where-Object { $_ -match $pattern })
        Test-Requirement "No macOS artifact matches '$pattern'" ($hits.Count -eq 0) "(found $($hits -join ', '))"
    }

    # Entry names must be relative: no home directory, no runner workspace, no
    # drive letter, no UNC path.
    $leakPatterns = @('^[A-Za-z]:', '^/', '^\\\\', 'Users/', 'runneradmin', 'home/')
    foreach ($pattern in $leakPatterns) {
        $hits = @($names | Where-Object { $_ -match $pattern })
        Test-Requirement "No entry path leaks '$pattern'" ($hits.Count -eq 0) "(found $($hits -join ', '))"
    }

    # ------------------------------------------------------------ binary -----

    $exeEntry = $archive.Entries | Where-Object { $_.FullName -match '(^|/)UsageBar\.exe$' } | Select-Object -First 1
    if ($exeEntry) {
        $memory = [System.IO.MemoryStream]::new()
        $stream = $exeEntry.Open()
        try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
        $bytes = $memory.ToArray()
        $memory.Dispose()

        # PE layout: e_lfanew at 0x3C, then "PE\0\0" (4) + COFF header (20),
        # so the optional header starts at peOffset + 24. Subsystem sits at
        # offset 68 within the optional header for both PE32 and PE32+.
        $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
        $signature = [System.Text.Encoding]::ASCII.GetString($bytes, $peOffset, 2)
        Test-Requirement 'UsageBar.exe is a PE image' ($signature -eq 'PE')

        $subsystem = [BitConverter]::ToUInt16($bytes, $peOffset + 24 + 68)
        # 2 = IMAGE_SUBSYSTEM_WINDOWS_GUI, 3 = IMAGE_SUBSYSTEM_WINDOWS_CUI
        Test-Requirement 'UsageBar.exe is a GUI subsystem binary (no console window)' ($subsystem -eq 2) "(subsystem $subsystem)"

        $machine = [BitConverter]::ToUInt16($bytes, $peOffset + 4)
        # 0x8664 = IMAGE_FILE_MACHINE_AMD64
        Test-Requirement 'UsageBar.exe is x64' ($machine -eq 0x8664) "(machine 0x$($machine.ToString('X4')))"

        # The manifest is embedded as plain XML, so it can be inspected directly.
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        Test-Requirement 'The manifest does not request administrator rights' (-not ($text -match 'requireAdministrator'))
        Test-Requirement 'The manifest requests asInvoker' ($text -match 'asInvoker')

        foreach ($leak in @('runneradmin', 'D:\a\UsageBar', '/home/', 'C:\Users\')) {
            Test-Requirement "UsageBar.exe does not embed '$leak'" (-not $text.Contains($leak))
        }
    }
    else {
        Test-Requirement 'UsageBar.exe could be read for inspection' $false
    }

    # ---------------------------------------------------- source revision -----

    # Which commit the shipped assemblies actually came from. The managed
    # assemblies carry it as the `+` suffix of their informational version, and
    # that is what the application reports as its BuildId.
    $expectedBuildId = ''
    if ($ExpectedSourceRevision) {
        Test-Requirement 'The expected source revision is a full commit SHA' (
            Test-UsageBarSourceRevision $ExpectedSourceRevision) "(got '$ExpectedSourceRevision')"

        if (Test-UsageBarSourceRevision $ExpectedSourceRevision) {
            $expectedBuildId = Get-UsageBarBuildId -SourceRevision $ExpectedSourceRevision
            Write-Host "  Expected build id: $expectedBuildId (from $($ExpectedSourceRevision.ToLowerInvariant()))"
        }
    }

    $stampedAssemblies = 0
    foreach ($assembly in @('UsageBar.dll', 'UsageBar.Windows.Core.dll', 'UsageBar.Windows.Infrastructure.dll')) {
        $entry = $archive.Entries |
            Where-Object { $_.FullName -match "(^|/)$([regex]::Escape($assembly))$" } |
            Select-Object -First 1

        Test-Requirement "$assembly is present" ($null -ne $entry)
        if (-not $entry) { continue }

        $memory = [System.IO.MemoryStream]::new()
        $stream = $entry.Open()
        try { $stream.CopyTo($memory) } finally { $stream.Dispose() }
        $assemblyBytes = $memory.ToArray()
        $memory.Dispose()

        $embedded = Get-UsageBarEmbeddedBuildId -AssemblyBytes $assemblyBytes
        Test-Requirement "$assembly carries a build id" ($embedded -ne '') '(none embedded)'
        if ($embedded) { $stampedAssemblies++ }

        if ($expectedBuildId) {
            Test-Requirement "$assembly was built from the expected source revision" (
                $embedded -eq $expectedBuildId) "(expected $expectedBuildId, embedded '$embedded')"
        }
    }

    Test-Requirement 'The packaged assemblies identify their source revision' ($stampedAssemblies -gt 0)
}
finally {
    $archive.Dispose()
}

# --------------------------------------------------------------- result -----

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "$($failures.Count) of $checks checks failed:" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  - $failure" -ForegroundColor Red
    }

    exit 1
}

Write-Host "All $checks package checks passed." -ForegroundColor Green
Write-Host 'Note: the package is not code signed. SmartScreen will warn on first run.'
exit 0
