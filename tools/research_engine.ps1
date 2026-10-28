<#
.SYNOPSIS
    tools/research_engine.ps1 - 50ジャンル均等探索コア司令塔

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       50ジャンルの中から「最も水位（件数）が低いジャンル」を選定し、キーワード候補抽出・SERP実測評価・
       芋づる個人ブログ発見・星3先行コミットゲートを一連のループとしてオーケストレーションする。
    2. 準拠ルール:
       - GEMINI.md 第1条: 50ジャンル均等底上げ（最低水位ジャンルの優先探索）。
       - GEMINI.md 第2条: 黄金比率（☆☆☆ >= 50%）維持。
       - GEMINI.md 第3条: 実測エビデンス（Vol >= 1900, 弱席数完全一致）。
    3. 構成モジュール (Delegation Modules):
       - engine_dedup_tracker.ps1       : 全列URL・異性KW・SERPキャッシュの0ms HashSet重複排除
       - engine_water_level_selector.ps1 : 最低水位ジャンル選定とマイルストーン自動進捗管理
       - engine_candidate_sifter.ps1    : DB未検索KW抽出・シード拡張・悩み系Sランク優先ソート
       - engine_serp_evaluator.ps1      : キャッシュ/リモートSERP評価・個人ブログ判定
       - engine_potato_harvester.ps1    : 実測DA 1〜9個人ブログからの芋づる式KW抽出
       - engine_star3_gate.ps1          : 星3先行ゲート（星3を含むバッチのみコミット、他はストック退避）
    4. 入力パラメータ (Parameters):
       - Gender                : "female" | "male"
       - MaxTotalCalls         : 本バッチ許容最大API数
       - MaxKwsPerGenreBatch   : 1ジャンルあたりの連続探索KW数 (デフォルト: 5)
       - GenreMinId / MaxId    : 対象ジャンル番号 (1〜50)
       - DryRun                : シミュレーション実行フラグ
    5. 修正時の注意点:
       - 本スクリプト内に直接SQLクエリやHTTPリクエストを記述せず、必ず上記モジュールに委譲すること。
       - DryRun時は無限ループを防止するためコールカウンタを正しく進めること。
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Gender = "female",

    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 500,

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

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\engine_dedup_tracker.ps1"
. "$projectRoot\workflow\scripts\engine_water_level_selector.ps1"
. "$projectRoot\workflow\scripts\engine_candidate_sifter.ps1"
. "$projectRoot\workflow\scripts\engine_serp_evaluator.ps1"
. "$projectRoot\workflow\scripts\engine_potato_harvester.ps1"
. "$projectRoot\workflow\scripts\engine_star3_gate.ps1"

Write-Output "=========================================================="
Write-Output "=== 50-GENRE CORE RESEARCH ENGINE ==="
Write-Output "=========================================================="
Write-Output "Target Profile: $Gender ()"
Write-Output "Max Total Calls: $MaxTotalCalls"
Write-Output "Max KWs Per Genre Batch: $MaxKwsPerGenreBatch"
Write-Output "Genre Range    : $GenreMinId - $GenreMaxId"
Write-Output "DryRun Mode    : $DryRun"

$profile = Resolve-SheetProfile -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId
$targetSheetName = $profile.TargetSheetName

# 1. Initialize Deduplication Tracker
$tracker = Initialize-EngineDedupTracker -SpreadsheetId $SpreadsheetId -TargetSheetName $targetSheetName -Gender $Gender -KwStartCol $profile.KwStartCol

$totalApiCalls = 0
$exhausted = $false
$exhaustionError = ""
$sitesCommittedCount = 0
$visitedGenres = @{}

# 2. Main 50-Genre Exploration Loop
while ($totalApiCalls -lt $MaxTotalCalls -and -not $exhausted) {
    if ($DryRun -and $totalApiCalls -ge $MaxTotalCalls) { break }

    # Select next lowest water-level genre
    $targetGenre = Select-NextWaterLevelGenre -Gender $Gender -GenreMinId $GenreMinId -GenreMaxId $GenreMaxId -VisitedGenres $visitedGenres
    if ($null -eq $targetGenre) { break }

    # Sift and prioritize keyword candidates
    $siftResult = Get-PrioritizedGenreCandidates -TargetGenre $targetGenre -Gender $Gender -Tracker $tracker -MaxTotalCalls $MaxTotalCalls -CurrentApiCalls $totalApiCalls -DryRun:$DryRun
    $totalApiCalls += $siftResult.ApiCallsMade
    $orderedCandidates = $siftResult.Candidates

    if ($DryRun -and $siftResult.ApiCallsMade -eq 0) {
        # Advance call counter in DryRun to simulate work and prevent infinite loop
        $totalApiCalls++
    }

    if ($orderedCandidates.Count -eq 0) {
        Write-Warning "No qualified high-volume keywords found for genre '$($targetGenre.Name)'. Moving to next genre."
        continue
    }

    # SERP Inspection Loop per genre batch
    $genreBatchCount = 0
    foreach ($cand in $orderedCandidates) {
        if ($genreBatchCount -ge $MaxKwsPerGenreBatch -or $totalApiCalls -ge $MaxTotalCalls) { break }

        # Skip if already registered
        $tokens = $cand.Keyword -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $normCandKw = (($tokens | Sort-Object) -join " ").ToLower()
        if ($tracker.RegisteredKws.ContainsKey($normCandKw)) {
            Write-Output "  [Skip Registered] '$($cand.Keyword)' (already in sheet)"
            continue
        }

        # Evaluate SERP (cached or remote)
        $serpEval = Invoke-KeywordSerpEvaluation -Keyword $cand.Keyword -Volume $cand.Volume -Gender $Gender -TargetGenre $targetGenre -Tracker $tracker -MaxTotalCalls $MaxTotalCalls -CurrentApiCalls $totalApiCalls
        if ($serpEval.IsSkipped) { continue }

        $totalApiCalls += $serpEval.ApiCallsMade
        $genreBatchCount++

        if ($serpEval.IsExhausted) {
            $exhausted = $true
            $exhaustionError = $serpEval.ExhaustionError
            break
        }

        # If personal blog found in top 10, trigger potato-digging and star3 commit gate
        if ($serpEval.HitPersonalBlog) {
            $harvestRes = Invoke-PotatoBlogHarvest -HitEntry $serpEval.HitPersonalBlog -OriginEval $serpEval.EvalHit -OriginKw $cand.Keyword -Gender $Gender -Tracker $tracker -MaxTotalCalls $MaxTotalCalls -CurrentApiCalls $totalApiCalls
            $totalApiCalls += $harvestRes.ApiCallsMade
            if ($harvestRes.IsExhausted) {
                $exhausted = $true
                $exhaustionError = $harvestRes.ExhaustionError
                break
            }

            $gateRes = Invoke-Star3FirstCommitGate -HarvestResult $harvestRes -TargetGenre $targetGenre -Gender $Gender -Profile $profile -Tracker $tracker -DryRun:$DryRun
            if ($gateRes.Committed) {
                $sitesCommittedCount++
            }
        }
    }
}

Write-Output "`n=========================================================="
Write-Output "50-GENRE WATER-LEVELING BATCH COMPLETED"
Write-Output "Total API Calls Made : $totalApiCalls"
Write-Output "Sites Committed      : $sitesCommittedCount"
Write-Output "Physical Exhausted   : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Reason    : $exhaustionError"
}
Write-Output "=========================================================="

if ($exhausted) {
    Write-Output "`nExecuting Auto-Audit on Exit..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\guard_check_exhaustion.ps1" -ErrorText $exhaustionError
} else {
    Write-Output "`nRunning Genre Balance Inspection..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\genre_inspect.ps1" -Gender $Gender
}
