<#
.SYNOPSIS
    tools\guard_check_catchup.ps1
    Responsibility: Verify whether today's keyword discovery & sheet commit is completed (Rule 1: Auto-Catchup).
    Cutoff: 09:00:00 JST of the current Ubersuggest quota cycle.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ProfileName = "",

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"

$profile = Resolve-SheetProfile -ProfileName $ProfileName -SpreadsheetId $SpreadsheetId -Gender $Gender

# 1. Calculate 9:00 AM JST cutoff window
$now = [DateTime]::UtcNow.AddHours(9)
$cutoff = Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0
if ($now -lt $cutoff) {
    $cutoff = $cutoff.AddDays(-1)
}

# 2. Check pipeline state file
$statePath = $profile.PipelineStatePath
$lastState = $null
$lastRunTime = [DateTime]::MinValue
$stateExists = Test-Path $statePath

if ($stateExists) {
    try {
        $raw = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8)
        $lastState = $raw | ConvertFrom-Json
        $fileInfo = Get-Item $statePath
        $lastRunTime = $fileInfo.LastWriteTime
    } catch {}
}

# 3. Check spreadsheet latest rows
$sheetData = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
$siteCount = $sheetData.SiteCount

# Determine whether catchup is needed
# Catchup is required if no successful pipeline run has executed after 9:00 AM JST cutoff
$hasRunAfterCutoff = ($lastRunTime -ge $cutoff)
$needsCatchup = (-not $hasRunAfterCutoff)

$output = [PSCustomObject]@{
    Profile = $profile.Profile
    Gender = $profile.Gender
    SpreadsheetId = $profile.SpreadsheetId
    SheetTitle = $profile.Title
    CurrentTimeJst = $now.ToString("yyyy-MM-dd HH:mm:ss")
    CutoffTimeJst = $cutoff.ToString("yyyy-MM-dd HH:mm:ss")
    LastRunTime = if ($lastRunTime -gt [DateTime]::MinValue) { $lastRunTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
    HasRunAfterCutoff = $hasRunAfterCutoff
    NeedsCatchup = $needsCatchup
    RegisteredSites = $siteCount
    LastPipelineState = if ($lastState) { $lastState.Status } else { "None" }
    RecommendedAction = if ($needsCatchup) { "Execute pipeline to catch up today's discovery task." } else { "Today's quota cycle task is already completed." }
}

$output | ConvertTo-Json -Depth 5
