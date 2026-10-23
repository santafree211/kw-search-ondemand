<#
.SYNOPSIS
    tools/sheet_audit.ps1
    Responsibility: Audit spreadsheet(s) (male, female, or both) against the 50:25:25 Normal State Standard.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [switch]$EnforceApiLog = $false,

    [Parameter(Mandatory=$false)]
    [switch]$AllowHealing = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\guard_normal_state.ps1"

$gendersToAudit = if ($Gender -eq "both") { @("female", "male") } else { @($Gender) }
$auditReports = @()

foreach ($g in $gendersToAudit) {
    $profile = Resolve-SheetProfile -Gender $g
    $data = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
    $eval = Test-NormalStateStandard -SheetRows $data.RawValues -EnforceApiLog:$EnforceApiLog -AllowHealing:$AllowHealing

    $rep = [PSCustomObject]@{
        Gender = $g
        Title = $profile.SheetTitle
        SpreadsheetId = $profile.SpreadsheetId
        Passed = $eval.Passed
        SiteCount = $eval.SiteCount
        TotalKeywords = $eval.TotalKeywords
        Star3Count = $eval.Star3Count
        Star2Count = $eval.Star2Count
        Star1Count = $eval.Star1Count
        Star3Percent = $eval.Star3Percent
        Star2Percent = $eval.Star2Percent
        Star1Percent = $eval.Star1Percent
        ErrorsCount = $eval.Errors.Count
        Errors = $eval.Errors
    }
    $auditReports += $rep

    if (-not $Json) {
        Write-Output "`n=========================================================="
        Write-Output "=== $($g.ToUpper()) SHEET AUDIT REPORT ($($profile.SheetTitle)) ==="
        Write-Output "=========================================================="
        Write-Output "Passed         : $($eval.Passed)"
        Write-Output "Sites Registered: $($eval.SiteCount)"
        Write-Output "Total Keywords : $($eval.TotalKeywords)"
        Write-Output "Star3+ Ratio   : $($eval.Star3Percent)% ($($eval.Star3Count) KWs) [Target: >= 50%]"
        Write-Output "Star2 Ratio    : $($eval.Star2Percent)% ($($eval.Star2Count) KWs) [Target: <= 25%]"
        Write-Output "Star1 Ratio    : $($eval.Star1Percent)% ($($eval.Star1Count) KWs) [Target: <= 25%]"
        if ($eval.Errors.Count -gt 0) {
            Write-Warning "Errors Found ($($eval.Errors.Count)):"
            foreach ($e in $eval.Errors) {
                Write-Warning "  * $e"
            }
        } else {
            Write-Output "Healthy State: No ratio or format errors found."
        }
    }
}

if ($Json) {
    $auditReports | ConvertTo-Json -Depth 5
}
