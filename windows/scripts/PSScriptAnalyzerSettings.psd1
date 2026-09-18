# PSScriptAnalyzer baseline for windows/scripts/*.ps1.
#
# Consumed explicitly by the "Static analysis (PowerShell)" step in
# .github/workflows/windows-ci.yml (-Settings scripts/PSScriptAnalyzerSettings.psd1).
# Every rule left enabled is blocking at every severity. Only known, deliberate
# repository patterns are exempted below; a real defect must never be added here.
@{
    ExcludeRules = @(
        # Imperative CI/package scripts: Write-Host is their deliberate
        # operator/status output surface, not a misuse of the pipeline.
        'PSAvoidUsingWriteHost'

        # The scripts target pwsh / PowerShell 7 and are UTF-8 without a BOM,
        # which pwsh reads correctly. No encoding churn for 5.1-oriented guidance.
        'PSUseBOMForUnicodeEncodedFile'

        # The flagged functions are private packaging helpers, not interactive
        # public cmdlets; Confirm/WhatIf semantics would be behaviour churn.
        'PSUseShouldProcessForStateChangingFunctions'
    )

    Rules = @{
        # Invoke-Step takes script blocks; without this the parameters used
        # inside them (-Configuration, -Runtime) are reported as unused.
        PSReviewUnusedParameter = @{
            CommandsToTraverse = @(
                'Invoke-Step'
            )
        }

        # Test-Requirement is an intentional compact internal assertion DSL.
        PSAvoidUsingPositionalParameters = @{
            CommandAllowList = @(
                'Test-Requirement'
            )
        }

        # Keep the rule for future functions; only the intentional test-helper
        # noun in Test-Throws is exempt.
        PSUseSingularNouns = @{
            Enable = $true
            NounAllowList = @(
                'Throws'
            )
        }
    }
}
