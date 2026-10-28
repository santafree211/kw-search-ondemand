<#
.SYNOPSIS
    research_engine.ps1
    Responsibility: Single Unified Autonomous 50-Genre Core Research Engine.
    Architecture: Ultra-Lean High-level Orchestration Pattern delegating to single-responsibility modules:
      - engine_dedup_tracker.ps1 (URL, keyword & historical SERP deduplication state)
      - engine_water_level_selector.ps1 (Lowest water-level genre selection & milestone control)
      - engine_candidate_sifter.ps1 (Keyword selection, S-rank prioritization & auto-expansion)
      - engine_serp_evaluator.ps1 (SERP cache/remote evaluation & personal blog logging)
      - engine_potato_harvester.ps1 (Personal blog detection & domain keyword harvesting)
      - engine_star3_gate.ps1 (Star-3 First architecture & atomic sheet commit / stock shelving)
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
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
