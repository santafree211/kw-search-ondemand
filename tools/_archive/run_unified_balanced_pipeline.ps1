<#
.SYNOPSIS
    tools/run_unified_balanced_pipeline.ps1
    Responsibility: Execute dual-gender alternating parallel water-leveling research.
    Alternates between female and male spreadsheets in balanced batches (default 30-50 calls each),
    ensuring both sheets advance equally across 50 genres until physical quota exhaustion.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 2500,

    [Parameter(Mandatory=$false)]
    [int]$BatchCallsPerGender = 30,

    [Parameter(Mandatory=$false)]
    [int]$MaleBatchCalls = 50,

    [Parameter(Mandatory=$false)]
    [int]$FemaleBatchCalls = 20,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 5
)

$ErrorActionPreference = "Stop"

if ($PSBoundParameters.ContainsKey('BatchCallsPerGender')) {
    if (-not $PSBoundParameters.ContainsKey('MaleBatchCalls')) { $MaleBatchCalls = $BatchCallsPerGender }
    if (-not $PSBoundParameters.ContainsKey('FemaleBatchCalls')) { $FemaleBatchCalls = $BatchCallsPerGender }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$balancedScript = Join-Path $PSScriptRoot "research_balanced_genres.ps1"
$inspectQuotaScript = Join-Path $PSScriptRoot "guard_inspect_daily_quota.ps1"

Write-Output "=========================================================="
Write-Output "=== UNIFIED DUAL-GENDER BALANCED PIPELINE RUNNER ==="
Write-Output "=========================================================="
Write-Output "Max Total Calls: $MaxTotalCalls"
Write-Output "Male Batch Calls: $MaleBatchCalls"
Write-Output "Female Batch Calls: $FemaleBatchCalls"
Write-Output "Max KWs Per Genre Batch: $MaxKwsPerGenreBatch"

# 1. Read initial sheet status to determine starting gender
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

$femaleProfile = Resolve-SheetProfile -Gender "female"
$maleProfile   = Resolve-SheetProfile -Gender "male"

$femaleData = Read-SheetData -SheetId $femaleProfile.SpreadsheetId -TargetSheetName $femaleProfile.TargetSheetName
$maleData   = Read-SheetData -SheetId $maleProfile.SpreadsheetId -TargetSheetName $maleProfile.TargetSheetName

Write-Output "`n[Initial Sheet State]"
Write-Output "  Female Sheet: $($femaleData.SiteCount) Sites, $($femaleData.ValidKeywordCount) Keywords"
Write-Output "  Male Sheet  : $($maleData.SiteCount) Sites, $($maleData.ValidKeywordCount) Keywords"

# Prioritize the gender that has fewer keywords to close the gap
$currentGender = if ($maleData.ValidKeywordCount -le $femaleData.ValidKeywordCount) { "male" } else { "female" }
Write-Output "Starting rotation with: $currentGender (closing keyword gap first)"

# 2. Pre-flight API Connectivity Health Check
Write-Output "`n[Pre-flight Health Check] Testing Ubersuggest API connectivity..."
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"
$healthCheckKw = "健康 美容"
$healthCheckRes = Invoke-SerpAnalysisRemote -TargetKeyword $healthCheckKw

$totalCallsDone = 0
$exhausted = $false
$exhaustionError = ""
$consecutiveTimeoutBatches = 0

if ($null -ne $healthCheckRes -and $healthCheckRes.IsExhausted) {
    Write-Warning "PRE-FLIGHT CHECK FAILED: Ubersuggest API is currently unavailable or exhausted."
    Write-Warning "Error Detail: $($healthCheckRes.Error)"
    $exhausted = $true
    $exhaustionError = $healthCheckRes.Error
} else {
    Write-Output "Pre-flight Health Check Passed: Ubersuggest API is responsive."
}

while ($totalCallsDone -lt $MaxTotalCalls -and -not $exhausted) {
    $remainingCalls = $MaxTotalCalls - $totalCallsDone
    if ($remainingCalls -le 0) { break }
    $batchTarget = if ($currentGender -eq "male") { $MaleBatchCalls } else { $FemaleBatchCalls }
    $callsForThisBatch = [Math]::Min($batchTarget, $remainingCalls)

    Write-Output "`n=========================================================="
    Write-Output ">>> ROTATION SWITCH: Running [$($currentGender.ToUpper())] Balanced Batch ($callsForThisBatch calls max)..."
    Write-Output "=========================================================="

    try {
        $res = & powershell -ExecutionPolicy Bypass -File $balancedScript `
            -Gender $currentGender `
            -MaxTotalCalls $callsForThisBatch `
            -MaxKwsPerGenreBatch $MaxKwsPerGenreBatch

        $res | ForEach-Object { Write-Output $_ }

        # Check for exhaustion in output
        $outText = $res -join "`n"
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

        if ($isBatchExhausted) {
            if ($candErr -match "(?i)daily report.*limit|timed out|HTTP 429|HTTP 403|rate limited|temporarily unavailable") {
                $exhausted = $true
                $exhaustionError = $candErr
                Write-Warning "Physical API exhaustion verified during $currentGender batch: $exhaustionError"
                break
            } else {
                Write-Warning "False exhaustion trigger ignored: '$candErr'"
            }
        }

        # Track calls accurately via actual database logs
        try {
            $quotaJson = & powershell -ExecutionPolicy Bypass -File $inspectQuotaScript
            $quotaObj = $quotaJson | ConvertFrom-Json
            if ($quotaObj -and $null -ne $quotaObj.TotalRealCallsToday) {
                $totalCallsDone = [int]$quotaObj.TotalRealCallsToday
                Write-Output "Real-Time Quota Status: $totalCallsDone total real calls logged today."
            } elseif ($outText -match "Total API Calls Made\s*:\s*(\d+)") {
                $totalCallsDone += [int]$matches[1]
            }
        } catch {
            if ($outText -match "Total API Calls Made\s*:\s*(\d+)") {
                $totalCallsDone += [int]$matches[1]
            }
        }

        # Global Circuit Breaker: Only trip if consecutive batches genuinely failed due to physical exhaustion / severe timeouts
        if ($isBatchExhausted -and ($candErr -match "(?i)timed out|temporarily unavailable")) {
            $consecutiveTimeoutBatches++
            if ($consecutiveTimeoutBatches -ge 2) {
                $exhausted = $true
                $exhaustionError = "Remote Ubersuggest API request timed out across consecutive dual-gender batches: $candErr"
                Write-Warning "GLOBAL CIRCUIT BREAKER TRIPPED: Consecutive API timeouts across both genders. Halting runner."
                break
            }
        } else {
            $consecutiveTimeoutBatches = 0
        }
    } catch {
        Write-Warning "Error during $currentGender batch execution: $_"
        if ($_ -match "HTTP 429|HTTP 403|Rate limited|daily report limit|timed out") {
            $exhausted = $true
            $exhaustionError = "$_"
            break
        }
    }

    # Alternate gender for next batch
    $currentGender = if ($currentGender -eq "male") { "female" } else { "male" }
}

Write-Output "`n=========================================================="
Write-Output "DUAL-GENDER ROTATION RUN FINISHED"
Write-Output "Total Run Calls Made : $totalCallsDone"
Write-Output "Physical Exhausted   : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Evidence  : $exhaustionError"
    Write-Output "`nExecuting Unified Exit Audit..."
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\guard_check_exhaustion.ps1" -ErrorText $exhaustionError
} else {
    Write-Output "`nFinal Genre Status Inspection (Both Genders):"
    Write-Output "`n--- Female Progress ---"
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\genre_inspect.ps1" -Gender "female"
    Write-Output "`n--- Male Progress ---"
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\genre_inspect.ps1" -Gender "male"
}

Write-Output "`nExecuting Real-Time Commit Health Guard..."
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\guard_realtime_commit.ps1"

Write-Output "=========================================================="
