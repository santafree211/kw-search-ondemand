<#
.SYNOPSIS
    tools/run_pipeline.ps1
    Responsibility: Single Unified Autonomous Pipeline Runner for 50-genre water-leveling research.
    Features:
      1. Dual-gender alternating parallel water-leveling by default (or single-gender if specified).
      2. Automatically closes the keyword gap by starting with the gender with fewer registered keywords.
      3. Fully delegates research to tools/research_engine.ps1 with autonomous long-tail expansion.
      4. Automatic dual-gender 3-way reconciliation audit on completion.
    Usage:
      # Standard dual-gender autonomous run until physical quota exhaustion:
      powershell -ExecutionPolicy Bypass -File tools\run_pipeline.ps1

      # Dry-run simulation (no sheets modified):
      powershell -ExecutionPolicy Bypass -File tools\run_pipeline.ps1 -DryRun

      # Single-gender targeted run:
      powershell -ExecutionPolicy Bypass -File tools\run_pipeline.ps1 -Gender male
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 2500,

    [Parameter(Mandatory=$false)]
    [int]$BatchCallsPerGender = 30,

    [Parameter(Mandatory=$false)]
    [int]$MaleBatchCalls = 50,

    [Parameter(Mandatory=$false)]
    [int]$FemaleBatchCalls = 20,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 5,

    [Parameter(Mandatory=$false)]
    [int]$GenreMinId = 1,

    [Parameter(Mandatory=$false)]
    [int]$GenreMaxId = 50,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

if ($PSBoundParameters.ContainsKey('BatchCallsPerGender')) {
    if (-not $PSBoundParameters.ContainsKey('MaleBatchCalls')) { $MaleBatchCalls = $BatchCallsPerGender }
    if (-not $PSBoundParameters.ContainsKey('FemaleBatchCalls')) { $FemaleBatchCalls = $BatchCallsPerGender }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$engineScript = Join-Path $PSScriptRoot "research_engine.ps1"
$inspectQuotaScript = Join-Path $PSScriptRoot "guard_inspect_daily_quota.ps1"
. "$projectRoot\workflow\scripts\pipeline_state_manager.ps1"

Set-PipelineState -Status "RUNNING" -ProcessId $PID -TargetMode $Gender -StartTime (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Out-Null

Write-Output "=========================================================="
Write-Output "=== UNIFIED AUTONOMOUS RESEARCH PIPELINE RUNNER ==="
Write-Output "=========================================================="
Write-Output "Target Mode        : $Gender"
Write-Output "Max Total Calls    : $MaxTotalCalls"
Write-Output "Male Batch Calls   : $MaleBatchCalls"
Write-Output "Female Batch Calls : $FemaleBatchCalls"
Write-Output "Max KWs Per Batch  : $MaxKwsPerGenreBatch"
Write-Output "Genre Range        : $GenreMinId - $GenreMaxId"
Write-Output "DryRun Mode        : $DryRun"

# 1. SerpApi Star Verification & Sheet Purge Engine Definition
. "$projectRoot\workflow\scripts\serpapi_client.ps1"

function Invoke-SerpAndSheetSync {
    param(
        [string]$TargetGender = "both",
        [switch]$IsDryRun = $false
    )

    Write-Output "`n----------------------------------------------------------"
    Write-Output ">>> [CYCLE 2-4: SERP & SHEET CLEANUP] Verifying & Purging via Google Real SERP..."
    Write-Output "----------------------------------------------------------"

    $serpConfig = Get-SerpApiConfig
    if (-not [string]::IsNullOrWhiteSpace($serpConfig.api_key)) {
        $serpUsage = Get-SerpApiDailyUsage -DailyLimit $serpConfig.daily_limit -MonthlyLimit $serpConfig.monthly_limit
        if (-not $serpUsage.IsLimitReached -and $serpUsage.RemainingCalls -gt 0) {
            Write-Output "SerpApi available quota: $($serpUsage.RemainingCalls) calls today (Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit))."
            Write-Output "Running Google real-time SERP verification: Deleting 0-stars, purging dead sites, confirming true stars..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$PSScriptRoot\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-Limit", $serpUsage.RemainingCalls
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {
                Write-Warning "SerpApi verification encountered an error: $_"
            }
        } else {
            Write-Output "SerpApi quota currently at limit (Today: $($serpUsage.CallsToday)/$($serpUsage.DailyLimit), Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit)). Syncing cached SERP evidence..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$PSScriptRoot\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-SyncCached"
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {}
        }
    } else {
        Write-Output "SerpApi key not detected in Windows environment. Skipping SERP verification phase."
    }
}

# 2. Read sheet status to determine starting gender
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

$femaleProfile = Resolve-SheetProfile -Gender "female"
$maleProfile   = Resolve-SheetProfile -Gender "male"

$femaleData = Read-SheetData -SheetId $femaleProfile.SpreadsheetId -TargetSheetName $femaleProfile.TargetSheetName
$maleData   = Read-SheetData -SheetId $maleProfile.SpreadsheetId -TargetSheetName $maleProfile.TargetSheetName

Write-Output "`n[Sheet State]"
Write-Output "  Female Sheet: $($femaleData.SiteCount) Sites, $($femaleData.ValidKeywordCount) Keywords"
Write-Output "  Male Sheet  : $($maleData.SiteCount) Sites, $($maleData.ValidKeywordCount) Keywords"

# Determine starting rotation
$currentGender = if ($Gender -eq "both") {
    if ($maleData.ValidKeywordCount -le $femaleData.ValidKeywordCount) { "male" } else { "female" }
} else {
    $Gender
}
Write-Output "Starting rotation with: $currentGender (closing keyword gap first)"

# 3. Pre-flight API Connectivity Health Check
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

$consecutiveZeroYieldSessions = 0
$prevCallsDone = $totalCallsDone

while (-not $exhausted) {
    $remainingCalls = $MaxTotalCalls - $totalCallsDone
    if ($remainingCalls -le 0) {
        $MaxTotalCalls += 1000
        $remainingCalls = $MaxTotalCalls - $totalCallsDone
        Write-Output "Auto-extending MaxTotalCalls to $MaxTotalCalls to continue search until genuine 403 quota exhaustion."
    }
    $batchTarget = if ($Gender -ne "both") {
        # Single-gender mode: run persistently without cold-start batch fragmentation
        $remainingCalls
    } else {
        if ($currentGender -eq "male") { $MaleBatchCalls } else { $FemaleBatchCalls }
    }
    $callsForThisBatch = [Math]::Min($batchTarget, $remainingCalls)

    Write-Output "`n=========================================================="
    Write-Output ">>> RUNNING [$($currentGender.ToUpper())] IN-PROCESS SESSION ($callsForThisBatch calls max)..."
    Write-Output "=========================================================="

    try {
        $engineParams = @{
            Gender = $currentGender
            MaxTotalCalls = $callsForThisBatch
            MaxKwsPerGenreBatch = $MaxKwsPerGenreBatch
            GenreMinId = $GenreMinId
            GenreMaxId = $GenreMaxId
        }
        if ($DryRun) {
            $engineParams["DryRun"] = $true
        }

        # Zero cold-start: In-process direct execution with live line streaming
        $resLines = New-Object System.Collections.Generic.List[string]
        & $engineScript @engineParams | ForEach-Object {
            $line = [string]$_
            Write-Output $line
            $resLines.Add($line)
        }
        $res = $resLines.ToArray()

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
            if ($candErr -match "(?i)daily report.*limit|HTTP 429|HTTP 403|quota is exhausted") {
                $exhausted = $true
                $exhaustionError = $candErr
                Write-Warning "Physical API exhaustion verified during $currentGender batch: $exhaustionError"
                break
            } elseif ($candErr -match "(?i)timed out|rate limited|temporarily unavailable") {
                Write-Warning "Transient API timeout/rate limit encountered during $currentGender batch. Allowing circuit breaker / retry: '$candErr'"
            } else {
                Write-Warning "False exhaustion trigger ignored: '$candErr'"
            }
        }

        # Track calls accurately via actual database logs
        try {
            $quotaJson = & $inspectQuotaScript
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

        # Update heartbeat and calls in persistent run state
        Set-PipelineState -LastHeartbeat (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -TotalCallsDone $totalCallsDone -CurrentGender $currentGender | Out-Null

        # Handle transient timeouts without halting the entire pipeline
        if ($isBatchExhausted -and ($candErr -match "(?i)timed out|temporarily unavailable")) {
            Write-Warning "Transient API delay/timeout encountered during $currentGender batch. Self-healing pause (10s) and continuing search..."
            Start-Sleep -Seconds 10
        }

        # Track session calls without prematurely breaking on saturation
        $callsInSession = $totalCallsDone - $prevCallsDone
        if ($callsInSession -le 0) {
            $consecutiveZeroYieldSessions++
            Write-Output "[$($currentGender.ToUpper()) Session] 0 new API calls produced ($consecutiveZeroYieldSessions cycle(s))."
            Write-Output "Continuing water-leveling exploration to ensure full daily quota usage (403)..."
        } else {
            $consecutiveZeroYieldSessions = 0
        }
        $prevCallsDone = $totalCallsDone

        # ----------------------------------------------------
        # ② SERPで整理 ＆ ③ シート整理 ＆ ④ 確定値のみ残す
        # ----------------------------------------------------
        Invoke-SerpAndSheetSync -TargetGender $currentGender -IsDryRun:$DryRun

    } catch {
        Write-Warning "Error during $currentGender batch execution: $_"
        if ($_ -match "(?i)HTTP 429|HTTP 403|daily report.*limit|quota is exhausted") {
            $exhausted = $true
            $exhaustionError = "$_"
            break
        } else {
            Write-Warning "Transient error encountered: $_. Waiting 5s and continuing pipeline towards genuine 403 limit..."
            Start-Sleep -Seconds 5
        }
    }

    # ----------------------------------------------------
    # ⑤ 次のリサーチサイクルへ（確定値のみのクリーンシートから次期KW発掘）
    # ----------------------------------------------------
    if ($Gender -eq "both") {
        $currentGender = if ($currentGender -eq "male") { "female" } else { "male" }
    }
}

Write-Output "`n=========================================================="
Write-Output "AUTONOMOUS RESEARCH RUN COMPLETED"
Write-Output "Total Run Calls Made : $totalCallsDone"
Write-Output "Physical Exhausted   : $exhausted"

$finalStatus = if ($exhausted) { "EXHAUSTED" } else { "COMPLETED" }
Set-PipelineState -Status $finalStatus -Exhausted $exhausted -ExhaustionError $exhaustionError -LastHeartbeat (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Out-Null
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

Write-Output "`nExecuting Dual-Gender 3-Way Reconciliation Audit..."
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\sheet_reconcile.ps1"

Write-Output "`nExecuting Real-Time Commit Health Guard..."
& powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\guard_realtime_commit.ps1"

Write-Output "=========================================================="
