<#
.SYNOPSIS
    potato_chain_reactor.ps1 - 当たり判定＆次世代個人ブログ自動収穫連鎖モジュール (Pure ASCII)
.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SKILL.md (potato_digging_research) ステップ3 & ステップ4に完全準拠。
       抽出されたキーワードのSERP（上位10位）を調査し、
       - 弱競合席数（実測DA 1〜9個人ブログ ＋ 弱競合UGC）から星数（☆〜☆☆☆☆☆）を決定論的に確定。
       - 上位10位内に存在する「別の実測DA 1〜9個人ブログ」を自動検出し、
         SQLiteの discovered_sites (status = 'candidate') へ即座に保存して次回の芋づる起点とする。
    2. 準拠ルール:
       - GEMINI.md 第3条: 実測生データに基づく星数確定（推測・仮置き厳禁）。
       - GEMINI.md 第2条: 行登録の主語は実測DA 1〜9の独立個人ブログのみ。
    3. 入力・出力仕様:
       - Invoke-PotatoKeywordSerpChain:
           - Inputs : [string]$Keyword, [int]$Volume, [string]$Gender, [int]$OriginGenreId, [hashtable]$Tracker, [switch]$DryRun
           - Outputs: PSCustomObject @{
               Keyword, Volume, StarCount, FormattedValue, IsStar3Plus,
               NewDiscoveredBlogs, ApiCallsMade, IsExhausted, ExhaustionError
             }
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

function Invoke-PotatoKeywordSerpChain {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$true)]
        [int]$Volume,

        [Parameter(Mandatory=$false)]
        [string]$Gender = "both",

        [Parameter(Mandatory=$false)]
        [int]$OriginGenreId = 0,

        [Parameter(Mandatory=$false)]
        $Tracker = $null,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $kw = $Keyword.Trim()
    $vol = $Volume
    $apiCallsMade = 0
    $isExhausted = $false
    $exhaustionError = ""
    $entries = $null
    $newDiscovered = @()

    Write-Output "    >>> [POTATO STEP 3 & 4] Evaluating SERP and harvesting new blogs for: '$kw' ($vol)..."

    if ($DryRun) {
        Write-Output "    [DryRun] serp_analysis API call skipped for '$kw'."
        return [PSCustomObject]@{
            Keyword            = $kw
            Volume             = $vol
            StarCount          = 0
            FormattedValue     = ""
            IsStar3Plus        = $false
            NewDiscoveredBlogs = @()
            ApiCallsMade       = 0
            IsExhausted        = $false
            ExhaustionError    = ""
        }
    }

    # 1. SERP取得 (キャッシュまたはAPI)
    $arch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $kw
    if ($arch -and $arch.Data) {
        $archData = $arch.Data
        if ($archData.serpEntries) { $entries = $archData.serpEntries }
        elseif ($archData.serp_table) { $entries = $archData.serp_table }
        elseif ($archData.result -and $archData.result.serp_table) { $entries = $archData.result.serp_table }
        if ($entries) {
            Write-Output "    [0s DB-Cache Hit] ($vol) SERP: '$kw'..."
        }
    }

    if (-not $entries) {
        if ($Tracker -and $Tracker.SearchedSerpKeywords -and $Tracker.SearchedSerpKeywords.Contains($kw)) {
            Write-Output "    [Skip In-Memory Already Queried] '$kw'"
            return [PSCustomObject]@{ ApiCallsMade = 0; IsSkipped = $true }
        }

        $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
        if ($null -ne $serp) {
            if ($Tracker -and $Tracker.SearchedSerpKeywords) {
                [void]$Tracker.SearchedSerpKeywords.Add($kw)
            }
            if ($serp.IsDuplicate) {
                return [PSCustomObject]@{ ApiCallsMade = 0; IsSkipped = $true }
            }
            if (-not $serp.IsCached) {
                $apiCallsMade++
            }
            if ($serp.IsExhausted) {
                return [PSCustomObject]@{
                    Keyword            = $kw
                    Volume             = $vol
                    StarCount          = 0
                    FormattedValue     = ""
                    IsStar3Plus        = $false
                    NewDiscoveredBlogs = @()
                    ApiCallsMade       = $apiCallsMade
                    IsExhausted        = $true
                    ExhaustionError    = $serp.Error
                }
            }
            $entries = $serp.serpEntries
            if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }
        }
    }

    if (-not $entries) {
        return [PSCustomObject]@{
            Keyword            = $kw
            Volume             = $vol
            StarCount          = 0
            FormattedValue     = ""
            IsStar3Plus        = $false
            NewDiscoveredBlogs = @()
            ApiCallsMade       = $apiCallsMade
            IsExhausted        = $false
            ExhaustionError    = ""
        }
    }

    # 2. 星数厳格判定
    $isMale = ($Gender -eq "male")
    $eval = if ($isMale) {
        Get-StrictStarEvaluationMale -Keyword $kw -SearchVolume $vol -SerpEntries $entries
    } else {
        Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries
    }

    # 3. 連鎖反応 (Step 4): 上位10位の別の実測DA 1〜9個人ブログを機械的自動収穫
    $top10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
    foreach ($ent in $top10) {
        $eDa = [int]$ent.domainAuthority
        $eDom = ([string]$ent.domain).ToLower().Trim()
        if ([string]::IsNullOrWhiteSpace($eDom) -or $eDom -eq "nodomain") { continue }

        $ugcCheck = if ($isMale) { Test-WeakCompetitorMale -Domain $eDom } else { Test-WeakCompetitor -Domain $eDom }
        if ($eDa -ge 1 -and $eDa -le 9 -and -not $ugcCheck.IsWeakCompetitor) {
            $eTitle = if (-not [string]::IsNullOrWhiteSpace($ent.title)) { $ent.title.Trim() } else { $eDom }
            $entBlogCheck = Test-KeywordEntertainmentEligibility -Keyword "$eDom $eTitle"
            if ($entBlogCheck.IsEntertainment) { continue }

            $eUrl = [string]$ent.url
            $safeDom = $eDom.Replace("'", "''")
            $safeTitle = $eTitle.Replace("'", "''")
            $safeUrl = $eUrl.Replace("'", "''")
            $safeKw = $kw.Replace("'", "''")
            $gidStr = if ($OriginGenreId -gt 0) { [string]$OriginGenreId } else { "NULL" }

            # SQLiteへ次世代個人ブログを自動補充
            try {
                $insSql = "INSERT OR IGNORE INTO discovered_sites (domain, site_name, url, da, site_type, gender, status, discovered_from_kw, discovered_at, genre_id) VALUES ('$safeDom', '$safeTitle', '$safeUrl', $eDa, 'personal_blog', '$Gender', 'candidate', '$safeKw', datetime('now','localtime'), $gidStr);"
                Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null
                $newDiscovered += $eDom
            } catch {}
        }
    }

    if ($newDiscovered.Count -gt 0) {
        Write-Output "    -> [CHAIN REACTION] Harvested $($newDiscovered.Count) next-gen personal blogs into candidate queue: $($newDiscovered -join ', ')"
    }

    $starCount = if ($eval.IsHit) { [int]$eval.StarCount } else { 0 }
    $isStar3 = ($starCount -ge 3)

    return [PSCustomObject]@{
        Keyword            = $kw
        Volume             = $vol
        StarCount          = $starCount
        FormattedValue     = if ($eval.IsHit) { [string]$eval.FormattedValue } else { "" }
        IsStar3Plus        = $isStar3
        NewDiscoveredBlogs = $newDiscovered
        ApiCallsMade       = $apiCallsMade
        IsExhausted        = $false
        ExhaustionError    = ""
    }
}
