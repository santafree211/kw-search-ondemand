<#
.SYNOPSIS
    tools/guard_realtime_commit.ps1
    Responsibility: Monitor and verify real-time commit health during/after research runs.
    Ensures that real-time API queries directly lead to spreadsheet row additions without relying on offline DB harvesting.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$MinExpectedCalls = 10,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\guard_normal_state.ps1"
. "$projectRoot\workflow\scripts\guard_quota_archive.ps1"

# 1. Inspect today's API calls via guard_quota_archive
$quotaUsage = Get-DailyApiQuotaUsage
$totalApiCallsToday = $quotaUsage.TotalRealCallsToday
$todayWindowStr = $quotaUsage.WindowStartTimeJst

# 2. Check profiles
$profilesToCheck = @()
if ($Gender -eq "both" -or $Gender -eq "all") {
    $profilesToCheck += @{ Name = "male"; Profile = (Resolve-SheetProfile -Gender "male") }
    $profilesToCheck += @{ Name = "female"; Profile = (Resolve-SheetProfile -Gender "female") }
} else {
    $profilesToCheck += @{ Name = $Gender; Profile = (Resolve-SheetProfile -Gender $Gender) }
}

$results = @()
$hasAnomaly = $false

foreach ($entry in $profilesToCheck) {
    $gName = $entry.Name
    $prof = $entry.Profile
    $sheetId = $prof.SpreadsheetId
    $sheetData = Read-SheetData -SheetId $sheetId
    $rawRows = $sheetData.RawValues
    $contentRows = $sheetData.Rows
    
    # Evaluate Golden Ratio via standard guard
    $normEval = Test-NormalStateStandard -SheetRows $rawRows
    
    # Check shelved stock count
    $shelvedCount = 0
    $stockPath = $prof.StockPath
    if (Test-Path $stockPath) {
        try {
            $sRaw = [System.IO.File]::ReadAllText($stockPath, [System.Text.Encoding]::UTF8)
            $sJson = $sRaw | ConvertFrom-Json
            if ($sJson -is [array]) { $shelvedCount = $sJson.Count }
        } catch {}
    }
    
    $results += [PSCustomObject]@{
        Gender = $gName
        Title = $prof.Title
        SpreadsheetId = $sheetId
        TotalSites = $contentRows.Count
        TotalKeywords = $normEval.TotalKeywords
        Star3Count = $normEval.Star3Count
        Star2Count = $normEval.Star2Count
        Star1Count = $normEval.Star1Count
        Star3Percent = $normEval.Star3Percent
        Star2Percent = $normEval.Star2Percent
        Star1Percent = $normEval.Star1Percent
        GoldenRatioPassed = $normEval.Passed
        Errors = $normEval.Errors
        ShelvedStockCount = $shelvedCount
    }
}

# 3. Anomaly Evaluation
$status = "HEALTHY"
$message = "Real-time pipeline is operating normally."

if ($totalApiCallsToday -ge 100 -and $results[0].TotalKeywords -eq 0) {
    $status = "CRITICAL_STARVATION"
    $message = "Substantial API calls were executed ($totalApiCallsToday calls), but 0 keywords are registered in spreadsheet!"
    $hasAnomaly = $true
}

$outputReport = [PSCustomObject]@{
    Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    ApiWindowStart = $todayWindowStr
    TotalApiCallsToday = $totalApiCallsToday
    Status = $status
    Message = $message
    Sheets = $results
}

if ($Json) {
    $outputReport | ConvertTo-Json -Depth 5
} else {
    Write-Output "================================================================================"
    Write-Output "               REAL-TIME COMMIT HEALTH AUDIT REPORT"
    Write-Output "================================================================================"
    Write-Output "Timestamp             : $($outputReport.Timestamp)"
    Write-Output "API Window Start (JST): $($outputReport.ApiWindowStart)"
    Write-Output "Total Real Calls Today: $($outputReport.TotalApiCallsToday)"
    Write-Output "Health Status         : $($outputReport.Status)"
    Write-Output "Message               : $($outputReport.Message)"
    Write-Output "--------------------------------------------------------------------------------"
    foreach ($s in $results) {
        Write-Output "Profile: $($s.Gender.ToUpper()) ($($s.Title))"
        Write-Output "  Total Sites         : $($s.TotalSites)"
        Write-Output "  Total Keywords      : $($s.TotalKeywords)"
        Write-Output "  Ratio (3+/2/1)      : $($s.Star3Percent)% / $($s.Star2Percent)% / $($s.Star1Percent)% (Passed: $($s.GoldenRatioPassed))"
        Write-Output "  Shelved Stock       : $($s.ShelvedStockCount)"
        if ($s.Errors -and $s.Errors.Count -gt 0) {
            Write-Output "  Errors              : $($s.Errors -join '; ')"
        }
        Write-Output "--------------------------------------------------------------------------------"
    }
    Write-Output "================================================================================"
}
