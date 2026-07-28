<#
.SYNOPSIS
    Resolves and validates the source revision Windows builds are stamped with.

.DESCRIPTION
    Dot-sourced by the packaging and verification scripts so build, packaging
    and verification cannot disagree about which commit an artifact came from.

    Why this exists: GitHub checks out `refs/pull/N/merge` for a pull request —
    a synthetic merge commit created for that run and thrown away afterwards.
    Reading `git rev-parse HEAD` there stamps artifacts with a SHA nobody can
    look up: UsageBar 2.0.0 shipped as `2.0.0+14bea7e` for exactly that reason,
    although its tree matched the approved source commit. The authoritative
    revision is therefore supplied by the caller (the workflow reads it from the
    event) and only falls back to the checked-out commit for local builds.

    A revision is accepted only as a full 40-character hexadecimal commit SHA.
    Nothing is ever substituted for a bad value: no `unknown`, no empty string,
    no application version, no branch name. An unresolvable revision throws.
#>

Set-StrictMode -Version Latest

<#
    The one shape a source revision may have. Deliberately strict: a short SHA,
    a branch name, a tag or arbitrary text are all rejected, so nothing that is
    not a commit identity can reach an artifact.
#>
function Test-UsageBarSourceRevision {
    [OutputType([bool])]
    param([AllowEmptyString()] [AllowNull()] [string] $SourceRevision)

    return [bool]($SourceRevision -match '^[0-9a-fA-F]{40}$')
}

<#
    The authoritative full revision for this build.

    $SourceRevision wins when supplied (CI passes the pull-request head or the
    pushed commit). Otherwise the checked-out commit is used, which is correct
    locally and is never the synthetic merge commit, because CI always supplies
    the value explicitly.
#>
function Resolve-UsageBarSourceRevision {
    [OutputType([string])]
    param(
        [AllowEmptyString()] [AllowNull()] [string] $SourceRevision,
        [Parameter(Mandatory)] [string] $RepositoryRoot
    )

    $candidate = if ($SourceRevision) { $SourceRevision.Trim() } else { '' }
    $origin = 'the supplied -SourceRevision'

    if (-not $candidate) {
        $origin = "the checked-out git commit in $RepositoryRoot"
        try {
            $head = (& git -C $RepositoryRoot rev-parse HEAD 2>$null)
            $code = if (Test-Path variable:global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
            if ($code -eq 0 -and $head) { $candidate = ([string]$head).Trim() }
        }
        catch {
            $candidate = ''
        }
    }

    if (-not (Test-UsageBarSourceRevision $candidate)) {
        throw ("Could not resolve a source revision from ${origin}: expected a full " +
            "40-character hexadecimal git commit SHA, got '$candidate'. " +
            'Pass -SourceRevision <sha> explicitly.')
    }

    return $candidate.ToLowerInvariant()
}

<#
    The build id embedded in the assemblies and shown in diagnostics: the first
    seven characters of the authoritative revision, keeping the established
    `2.0.0+abc1234` informational-version format. WindowsEnvironmentInfo.BuildId
    reports the same seven characters back to the user.
#>
function Get-UsageBarBuildId {
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $SourceRevision)

    if (-not (Test-UsageBarSourceRevision $SourceRevision)) {
        throw "Refusing to derive a build id from '$SourceRevision': it is not a full 40-character commit SHA."
    }

    return $SourceRevision.ToLowerInvariant().Substring(0, 7)
}

<#
    The build id a compiled assembly actually carries, read back out of it.

    The informational version is stored in metadata as UTF-8, so it can be read
    from the raw bytes without loading the assembly — which matters because
    these are win-x64 assemblies inspected from whatever host runs the gate.
    Returns an empty string when the assembly carries no build id at all.
#>
function Get-UsageBarEmbeddedBuildId {
    [OutputType([string])]
    param([Parameter(Mandatory)] [byte[]] $AssemblyBytes)

    $text = [System.Text.Encoding]::UTF8.GetString($AssemblyBytes)
    $match = [regex]::Match($text, '\d+\.\d+\.\d+\+(?<id>[0-9a-fA-F]{7,40})')
    if (-not $match.Success) { return '' }

    # Mirrors WindowsEnvironmentInfo.BuildId, which reports the first seven
    # characters of the suffix however long it was stamped.
    return $match.Groups['id'].Value.ToLowerInvariant().Substring(0, 7)
}
