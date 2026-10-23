<#
.SYNOPSIS
    tools/guard_check_exhaustion.ps1
    Responsibility: Check API error message against Hard Stop Criteria and generate required evidence.
                    Automatically triggers unified exit audit (Female & Male) upon exhaustion.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ErrorText = "",

    [Parameter(Mandatory=$false)]
    [string]$ErrorLogPath = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "both", "female", "male")]
    [string]$AuditGender = "all"
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\guard_quota_monitor.ps1"

$textToTest = $ErrorText
if (-not [string]::IsNullOrWhiteSpace($ErrorLogPath) -and (Test-Path $ErrorLogPath)) {
    $textToTest = [System.IO.File]::ReadAllText($ErrorLogPath, [System.Text.Encoding]::UTF8)
}

if ([string]::IsNullOrWhiteSpace($textToTest)) {
    throw "ErrorText or ErrorLogPath is required."
}

$isExhausted = Test-ApiExhaustion -ErrorString $textToTest

$auditData = $null
if ($isExhausted -and -not [string]::IsNullOrWhiteSpace($AuditGender)) {
    try {
        $reconcileScript = Join-Path $PSScriptRoot "..\workflow\scripts\guard_sheet_reconcile.ps1"
        if (Test-Path $reconcileScript) {
            . $reconcileScript
            $reconcileRes = Invoke-Sheet3WayReconciliation -ProfileName $AuditGender -Silent:$true
            if ($reconcileRes.Profiles) {
                $auditData = [PSCustomObject]@{
                    Mode = "Unified_All"
                    OverallPassed = $reconcileRes.OverallPassed
                    Female = [PSCustomObject]@{
                        AuditPassed = $reconcileRes.Female.OverallPassed
                        GoldenRatioPassed = $reconcileRes.Female.GoldenRatioPassed
                        GoldenRatio = $reconcileRes.Female.GoldenRatio
                        TotalViolations = $reconcileRes.Female.TotalViolations
                        LastRowAudited = if ($reconcileRes.Female.RowResults.Count -gt 0) { $reconcileRes.Female.RowResults[0].Row } else { $null }
                        LastSiteName = if ($reconcileRes.Female.RowResults.Count -gt 0) { $reconcileRes.Female.RowResults[0].SiteName } else { "" }
                    }
                    Male = [PSCustomObject]@{
                        AuditPassed = $reconcileRes.Male.OverallPassed
                        GoldenRatioPassed = $reconcileRes.Male.GoldenRatioPassed
                        GoldenRatio = $reconcileRes.Male.GoldenRatio
                        TotalViolations = $reconcileRes.Male.TotalViolations
                        LastRowAudited = if ($reconcileRes.Male.RowResults.Count -gt 0) { $reconcileRes.Male.RowResults[0].Row } else { $null }
                        LastSiteName = if ($reconcileRes.Male.RowResults.Count -gt 0) { $reconcileRes.Male.RowResults[0].SiteName } else { "" }
                    }
                }
            } else {
                $auditData = [PSCustomObject]@{
                    Profile = $reconcileRes.Profile
                    AuditPassed = $reconcileRes.OverallPassed
                    GoldenRatioPassed = $reconcileRes.GoldenRatioPassed
                    GoldenRatio = $reconcileRes.GoldenRatio
                    TotalViolations = $reconcileRes.TotalViolations
                    LastRowAudited = if ($reconcileRes.RowResults.Count -gt 0) { $reconcileRes.RowResults[0].Row } else { $null }
                    LastSiteName = if ($reconcileRes.RowResults.Count -gt 0) { $reconcileRes.RowResults[0].SiteName } else { "" }
                }
            }
        }
    } catch {
        Write-Warning "Exit audit on exhaustion encountered an issue: $_"
    }
}

[PSCustomObject]@{
    IsExhausted = $isExhausted
    HardStopAllowed = $isExhausted
    ExhaustionEvidence = if ($isExhausted) { $textToTest.Trim() } else { "None (Physical API error criteria not met. Stopping is prohibited.)" }
    Criteria = "HTTP 403 / HTTP 429 / Daily report limit / Remote API timeout"
    ExitAudit = $auditData
} | ConvertTo-Json -Depth 6
