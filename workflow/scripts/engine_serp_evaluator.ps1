<#
.SYNOPSIS
    engine_serp_evaluator.ps1 - SERP取得・星数判定・個人ブログ検出モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       候補キーワードのSERP（検索結果上位10位）をキャッシュまたはリモートから取得し、厳格な星数評価
       （個人ブログDA 1〜9 ＋ 弱競合UGCの合計）を実施。上位10位に個人ブログが存在する場合は抽出して返す。
    2. 準拠ルール:
       - GEMINI.md 第3条: 実測エビデンスに基づく星数確定（推測・仮置きの厳禁）。
       - 0星キーワードの即時パージ・スキップ。
    3. 入力・出力仕様:
       - Inputs : $Keyword, $Volume, $Gender, $TargetGenre, $Tracker, $MaxTotalCalls, $CurrentApiCalls
       - Outputs: PSCustomObject @{
           Keyword, EvalHit, HitPersonalBlog, ApiCallsMade, IsSkipped, IsExhausted, ExhaustionError
         }
    4. 修正時の注意点:
       - 上位10位にDA 1〜9の個人ブログが含まれている場合のみ $HitPersonalBlog に格納し、芋づる発掘へと繋ぐこと。
       - 判定された個人ブログは SQLite の candidate_personal_blogs テーブルへ即座に記録すること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\research_serp_fetcher.ps1"
. "$PSScriptRoot\eval_star_calculator.ps1"
. "$PSScriptRoot\eval_star_calculator_male.ps1"
. "$PSScriptRoot\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\store_api_query.ps1"

function Invoke-KeywordSerpEvaluation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$true)]
        [int]$Volume,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        $TargetGenre,

        [Parameter(Mandatory=$true)]
        $Tracker,

        [Parameter(Mandatory=$false)]
        [int]$MaxTotalCalls = 500,

        [Parameter(Mandatory=$false)]
        [int]$CurrentApiCalls = 0
    )

    $kw = $Keyword
    $vol = $Volume
    $entries = $null
    $isFromCache = $false
    $apiCallsMade = 0
    $isExhausted = $false
    $exhaustionError = ""

    # 1. Instant evaluation of cached SERP
    $arch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $kw
    if ($arch -and $arch.Data) {
        $archData = $arch.Data
        if ($archData.serpEntries) { $entries = $archData.serpEntries }
        elseif ($archData.serp_table) { $entries = $archData.serp_table }
        elseif ($archData.result -and $archData.result.serp_table) { $entries = $archData.result.serp_table }
        if ($entries) {
            $isFromCache = $true
            Write-Output "  [0s DB-Cache Hit] ($vol) SERP: '$kw'..."
        }
    }

    # 2. Remote SERP Query if not in cache
    if (-not $isFromCache) {
        if ($Tracker.SearchedSerpKeywords.Contains($kw)) {
            Write-Output "  [Skip In-Memory Already Queried] '$kw'"
            return [PSCustomObject]@{ IsSkipped = $true }
        }
        if (($CurrentApiCalls + $apiCallsMade) -ge $MaxTotalCalls) {
            return [PSCustomObject]@{ IsSkipped = $true }
        }

        $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
        if ($null -ne $serp) {
            [void]$Tracker.SearchedSerpKeywords.Add($kw)
            if ($serp.IsDuplicate) { return [PSCustomObject]@{ IsSkipped = $true } }
            if (-not $serp.IsCached) {
                $apiCallsMade++
                Write-Output "  [$($CurrentApiCalls + $apiCallsMade)] ($vol) Remote SERP: '$kw'..."
            }
            if ($serp.IsExhausted) {
                if ($serp.Error -match "(?i)429|403|Daily report.*limit") {
                    $isExhausted = $true
                    $exhaustionError = $serp.Error
                    Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($serp.Error)"
                } else {
                    Write-Warning "Keyword '$kw' timed out. Transient network issue - waiting 5s..."
                    Start-Sleep -Seconds 5
                }
            }
            $entries = $serp.serpEntries
            if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }
        }
    }

    $hitPersonalBlog = $null
    $evalHit = $null

    if ($entries) {
        # Log discovered personal blogs into SQLite
        try {
            $allTop10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
            foreach ($ent in $allTop10) {
                $eDa = [int]$ent.domainAuthority
                $eDom = ([string]$ent.domain).ToLower().Trim()
                if ([string]::IsNullOrWhiteSpace($eDom) -or $eDom -eq "nodomain") { continue }
                $eUgc = if ($Gender -eq "male") { Test-WeakCompetitorMale -Domain $eDom } else { Test-WeakCompetitor -Domain $eDom }
                if ($eDa -ge 1 -and $eDa -le 9 -and -not $eUgc.IsWeakCompetitor) {
                    $eTitle = if (-not [string]::IsNullOrWhiteSpace($ent.title)) { $ent.title.Trim() } else { $eDom }
                    $entBlogCheck = Test-KeywordEntertainmentEligibility -Keyword "$eDom $eTitle"
                    if ($entBlogCheck.IsEntertainment) { continue }
                    $eUrl = [string]$ent.url
                    $safeDom = $eDom.Replace("'", "''")
                    $safeTitle = $eTitle.Replace("'", "''")
                    $safeUrl = $eUrl.Replace("'", "''")
                    $safeKw = $kw.Replace("'", "''")
                    $gid = if ($TargetGenre -and $TargetGenre.Id) { [int]$TargetGenre.Id } else { "NULL" }
                    $insSql = "INSERT OR IGNORE INTO discovered_sites (domain, site_name, url, da, site_type, gender, status, discovered_from_kw, discovered_at, genre_id) VALUES ('$safeDom', '$safeTitle', '$safeUrl', $eDa, 'personal_blog', '$Gender', 'candidate', '$safeKw', datetime('now','localtime'), $gid);"
                    Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null
                }
            }
        } catch {}

        # Evaluate Star Rating
        $eval = if ($Gender -eq "male") {
            Get-StrictStarEvaluationMale -Keyword $kw -SearchVolume $vol -SerpEntries $entries
        } else {
            Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries
        }

        if ($eval.IsHit) {
            Write-Output "    -> HIT: $($eval.FormattedValue) (Stars: $($eval.StarCount))"
            $evalHit = $eval

            $top10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
            $candidateBlogs = @()
            foreach ($e in $top10) {
                $cDa = [int]$e.domainAuthority
                $cDom = ([string]$e.domain).ToLower().Trim()
                if ([string]::IsNullOrWhiteSpace($cDom) -or $cDom -eq "nodomain") { continue }
                $cugcCheck = if ($Gender -eq "male") { Test-WeakCompetitorMale -Domain $cDom } else { Test-WeakCompetitor -Domain $cDom }
                if ($cDa -ge 1 -and $cDa -le 9 -and -not $cugcCheck.IsWeakCompetitor -and -not $Tracker.RegisteredUrls.ContainsKey($cDom)) {
                    $candidateBlogs += $e
                }
            }

            if ($candidateBlogs.Count -gt 0) {
                $hitPersonalBlog = ($candidateBlogs | Sort-Object { [int]$_.domainAuthority })[0]
            }
        }
    }

    return [PSCustomObject]@{
        IsSkipped       = $false
        ApiCallsMade    = $apiCallsMade
        IsExhausted     = $isExhausted
        ExhaustionError = $exhaustionError
        EvalHit         = $evalHit
        HitPersonalBlog = $hitPersonalBlog
    }
}
