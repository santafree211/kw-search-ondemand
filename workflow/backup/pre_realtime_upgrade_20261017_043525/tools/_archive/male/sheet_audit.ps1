<#
.SYNOPSIS
    tools/male/sheet_audit.ps1
    Male Dedicated CLI Tool: Audit male spreadsheet against 50:25:25 Normal State Standard.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$EnforceApiLog = $false,

    [Parameter(Mandatory=$false)]
    [switch]$EnforceUniqueKeywords = $true
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
. "$toolsDir\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$toolsDir\..\workflow\scripts\sheet_data_reader.ps1"
. "$toolsDir\..\workflow\scripts\guard_normal_state.ps1"

$profile = Resolve-SheetProfile -ProfileName "male"
$data = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
$eval = Test-NormalStateStandard -SheetRows $data.RawValues -EnforceApiLog:$EnforceApiLog -EnforceUniqueKeywords:$EnforceUniqueKeywords

[PSCustomObject]@{
    Profile = $profile.Profile
    Title = $profile.Title
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
} | ConvertTo-Json -Depth 5
