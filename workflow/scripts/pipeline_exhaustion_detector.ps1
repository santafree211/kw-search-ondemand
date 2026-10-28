<#
.SYNOPSIS
    pipeline_exhaustion_detector.ps1
    Single Responsibility: Detect and classify API exhaustion (429/403/limits) vs transient timeouts from batch output.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-BatchExhaustionStatus {
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$OutputLines = @(),

        [Parameter(Mandatory=$false)]
        [string]$CurrentGender = ""
    )

    $outText = if ($OutputLines) { $OutputLines -join "`n" } else { "" }
    $isBatchExhausted = $false
    $candErr = ""

    if ($outText -match "PHYSICAL API EXHAUSTION DETECTED:\s*(.+)") {
        $candErr = $matches[1].Trim()
        $isBatchExhausted = $true
    } elseif ($outText -match "Physical Exhausted\s*:\s*True") {
        if ($outText -match "Exhaustion (?:Reason|Evidence)\s*:\s*(.+)") {
            $candErr = $matches[1].Trim()
        } else {
            $candErr = "Physical exhaustion reported by batch runner."
        }
        $isBatchExhausted = $true
    }

    $isPhysicalLimit = $false
    $isTransient = $false

    if ($isBatchExhausted) {
        if ($candErr -match "(?i)daily report.*limit|HTTP 429|HTTP 403|quota is exhausted") {
            $isPhysicalLimit = $true
            Write-Warning "Physical API exhaustion verified during $CurrentGender batch: $candErr"
        } elseif ($candErr -match "(?i)timed out|rate limited|temporarily unavailable") {
            $isTransient = $true
            Write-Warning "Transient API timeout/rate limit encountered during $CurrentGender batch. Allowing circuit breaker / retry: '$candErr'"
        } else {
            Write-Warning "False exhaustion trigger ignored: '$candErr'"
        }
    }

    return [PSCustomObject]@{
        IsExhausted     = $isBatchExhausted
        IsPhysicalLimit = $isPhysicalLimit
        IsTransient     = $isTransient
        ErrorText       = $candErr
    }
}
