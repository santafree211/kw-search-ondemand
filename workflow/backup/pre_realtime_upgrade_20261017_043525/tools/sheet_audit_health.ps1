<#
.SYNOPSIS
    tools/sheet_audit_health.ps1
    Responsibility: Audit spreadsheet against Normal State Standard (ratio, volume, blanks, stars).
    Output: Token-optimized JSON summary.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SheetName = "",

    [Parameter(Mandatory=$false)]
    [switch]$EnforceApiLog = $false
)

$ErrorActionPreference = "Stop"

# Load modules
. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"
. "$PSScriptRoot\..\workflow\scripts\guard_normal_state.ps1"

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$targetSheetId = $profile.SpreadsheetId

$data = Read-SheetData -SheetId $targetSheetId -TargetSheetName $SheetName
$eval = Test-NormalStateStandard -SheetRows $data.RawValues -EnforceApiLog:$EnforceApiLog

[PSCustomObject]@{
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
} | ConvertTo-Json -Depth 5
