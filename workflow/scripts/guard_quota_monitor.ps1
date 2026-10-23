<#
.SYNOPSIS
    guard_quota_monitor.ps1
    Responsibility: Detect API exhaustion objectively and generate verifiable physical evidence.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-ApiExhaustion {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ErrorString
    )

    # Genuine physical quota exhaustion only: 403, 429, daily report limit reached, quota exhausted
    if ($ErrorString -match "(?i)daily report.*limit" -or 
        $ErrorString -match "(?i)quota is exhausted" -or 
        $ErrorString -match "\b429\b" -or 
        $ErrorString -match "\b403\b" -or 
        $ErrorString -match "Too Many Requests" -or 
        $ErrorString -match "Forbidden") {
        # Discard false positive if it's a successful JSON result
        if ($ErrorString -match '"result":\s*\{' -and -not ($ErrorString -match '"error":\s*\{')) {
            return $false
        }
        return $true
    }
    return $false
}

function Get-ExhaustionReport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LastErrorMessage,

        [Parameter(Mandatory=$false)]
        $Logs = @()
    )

    $isExhausted = Test-ApiExhaustion -ErrorString $LastErrorMessage

    $breakdown = @{}
    $total = 0

    foreach ($log in $Logs) {
        $tool = if ($log.ToolName) { [string]$log.ToolName } else { "other" }
        if (-not $breakdown.ContainsKey($tool)) {
            $breakdown[$tool] = 0
        }
        $breakdown[$tool]++
        $total++
    }

    return [PSCustomObject]@{
        IsExhausted = $isExhausted
        ExhaustionEvidence = if ($isExhausted) { $LastErrorMessage.Trim() } else { "None" }
        TotalRealCalls = $total
        CallBreakdown = $breakdown
    }
}


