<#
.SYNOPSIS
    tools/run_pipeline.ps1 - 50ジャンル均等底上げ自律リサーチメインパイプライン

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務 (Single Responsibility):
       男女スプレッドシートの登録進捗（件数）を監視し、女性・男性を交互に自動ローテーションしながら
       50ジャンルの均等底上げ探索・SerpApiリアルタイム照合・終了監査を统括実行する自律メイン司令塔。
    2. 準拠ルール (GEMINI.md Standards):
       - 第1条: 50ジャンル均等底上げ（男女比率・ジャンル間格差の是正）。
       - 第2条: 黄金比率（50:25:25）の維持。
       - 第5条: デイリー上限完全活用（物理的429/403枯渇まで自律継続）。
       - 第3条: 終了時監査義務（終了時にsheet_reconcile.ps1で3者突合検証）。
    3. 構成モジュール (Delegation Architecture):
       - pipeline_preflight_guard.ps1     : 起動前のAPI疎通・デイリー残枠事前確認
       - pipeline_gender_balancer.ps1     : シート件数比較・開始性別決定・男女交代
       - research_engine.ps1              : ジャンル別ロングテール展開・芋づる個人ブログ発掘
       - pipeline_exhaustion_detector.ps1 : 出力ログからの物理枯渇(403/429)と一時的通信遅延の分類
       - pipeline_serp_sync.ps1           : Google実測SERP照合・0星パージ同期
       - sheet_reconcile.ps1              : 終了時3者突合監査
    4. 入力パラメータ (Parameters):
       - Gender               : "both" | "female" | "male" (デフォルト: both)
       - MaxTotalCalls        : 本日許容する最大APIリクエスト数 (デフォルト: 5000)
       - MaleBatchCalls       : 男性1バッチあたりのAPIコール枠 (デフォルト: 1600)
       - FemaleBatchCalls     : 女性1バッチあたりのAPIコール枠 (デフォルト: 960)
       - MaxKwsPerGenreBatch  : 1ジャンルあたり一度に処理する最大KW数 (デフォルト: 160)
       - GenreMinId / MaxId   : 探索対象ジャンル範囲 (1〜50)
       - DryRun               : スイッチ (APIリクエストやスプシ書き込みを行わないシミュレーション)
    5. 不変条件・修正時の注意点 (Guardrails for AI):
       - 一時的な通信遅延（タイムアウト）でプロセスを即座に落とさず、自己修復リトライを継続すること。
       - 探索終了時は必ず男女両シートの3者突合監査（sheet_reconcile.ps1）を実行すること。
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 5000,

    [Parameter(Mandatory=$false)]
    [int]$BatchCallsPerGender = 960,

    [Parameter(Mandatory=$false)]
    [int]$MaleBatchCalls = 1600,

    [Parameter(Mandatory=$false)]
    [int]$FemaleBatchCalls = 960,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 160,

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

# Load single-responsibility modules
. "$projectRoot\workflow\scripts\pipeline_state_manager.ps1"
. "$projectRoot\workflow\scripts\pipeline_serp_sync.ps1"
. "$projectRoot\workflow\scripts\pipeline_gender_balancer.ps1"
. "$projectRoot\workflow\scripts\pipeline_preflight_guard.ps1"
. "$projectRoot\workflow\scripts\pipeline_exhaustion_detector.ps1"

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

# 1. Determine starting gender rotation (closing keyword gap first)
$rotationInfo = Get-StartingGenderRotation -TargetGender $Gender
$currentGender = $rotationInfo.StartingGender

# 2. Pre-flight API Connectivity Health Check
$preflight = Test-PipelinePreflightHealth
$exhausted = $preflight.IsExhausted
$exhaustionError = $preflight.ExhaustionError
$totalCallsDone = 0
$consecutiveZeroYieldSessions = 0
$prevCallsDone = 0

# 3. Main Exploration Loop
while (-not $exhausted) {
    $remainingCalls = $MaxTotalCalls - $totalCallsDone
    if ($remainingCalls -le 0) {
        $MaxTotalCalls += 1000
        $remainingCalls = $MaxTotalCalls - $totalCallsDone
        Write-Output "Auto-extending MaxTotalCalls to $MaxTotalCalls to continue search until genuine 403 quota exhaustion."
    }

    $batchTarget = if ($Gender -ne "both") {
        $remainingCalls
    } else {
        $cfgBatch = if ($currentGender -eq "male") { $MaleBatchCalls } else { $FemaleBatchCalls }
        [Math]::Min($cfgBatch, $remainingCalls)
    }

    Write-Output "`n=========================================================="
    Write-Output "STARTING BATCH: $($currentGender.ToUpper()) (Budget: $batchTarget calls)"
    Write-Output "=========================================================="

    try {
        $engineParams = @{
            Gender               = $currentGender
            MaxTotalCalls        = $batchTarget
            MaxKwsPerGenreBatch  = $MaxKwsPerGenreBatch
            GenreMinId           = $GenreMinId
            GenreMaxId           = $GenreMaxId
        }
        if ($DryRun) {
            $engineParams["DryRun"] = $true
        }

        # Live line streaming execution
        $resLines = New-Object System.Collections.Generic.List[string]
        & $engineScript @engineParams | ForEach-Object {
            $line = [string]$_
            Write-Output $line
            $resLines.Add($line)
        }

        # Classify exhaustion status via detector module
        $exStatus = Test-BatchExhaustionStatus -OutputLines $resLines.ToArray() -CurrentGender $currentGender
        if ($exStatus.IsPhysicalLimit) {
            $exhausted = $true
            $exhaustionError = $exStatus.ErrorText
            break
        }

        # Track calls accurately via actual database logs
        try {
            $quotaJson = & $inspectQuotaScript
            $quotaObj = $quotaJson | ConvertFrom-Json
            if ($quotaObj -and $null -ne $quotaObj.TotalRealCallsToday) {
                $totalCallsDone = [int]$quotaObj.TotalRealCallsToday
                Write-Output "Real-Time Quota Status: $totalCallsDone total real calls logged today."
            } elseif (($resLines -join "`n") -match "Total API Calls Made\s*:\s*(\d+)") {
                $totalCallsDone += [int]$matches[1]
            }
        } catch {
            if (($resLines -join "`n") -match "Total API Calls Made\s*:\s*(\d+)") {
                $totalCallsDone += [int]$matches[1]
            }
        }

        # Update heartbeat and calls in persistent run state
        Set-PipelineState -LastHeartbeat (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -TotalCallsDone $totalCallsDone -CurrentGender $currentGender | Out-Null

        # Handle transient timeouts without halting the entire pipeline
        if ($exStatus.IsTransient) {
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

        # Google Real SERP Verification & Sheet Cleanup
        Invoke-PipelineSerpSync -TargetGender $currentGender -IsDryRun:$DryRun

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

    # Alternate gender
    $currentGender = Switch-PipelineGender -CurrentGender $currentGender -Mode $Gender
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
