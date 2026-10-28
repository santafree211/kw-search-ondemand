<#
.SYNOPSIS
    engine_candidate_sifter.ps1 - ジャンル候補キーワード抽出・シード拡張・Sランク優先ソート

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       指定ジャンルについて、ローカルDB未検索KWの走査 ➔ 不足時の自動シード拡張 ➔ ポリシー除外（YMYL/エンタメ/性別）
       ➔ 未検索/キャッシュ分離 ➔ 悩み・比較等のSランク修飾子優先ソートを行い、高確率な候補リストを生成する。
    2. 準拠ルール:
       - GEMINI.md 第1条: カタログシード消化時の自律深掘り（同一ジャンル内でのロングテール展開）。
       - GEMINI.md 第2条: ☆☆☆以上50%以上を達成するための「悩み・トラブル解決・比較」優先選定。
    3. 入力・出力仕様:
       - Inputs : $TargetGenre, $Gender, $Tracker, $MaxTotalCalls, $CurrentApiCalls, $DryRun
       - Outputs: PSCustomObject @{ Candidates (優先順リスト), ApiCallsMade (実行コール数) }
    4. 修正時の注意点:
       - プレフィックス重複チェックを実施し、同一単語でSQLiteクエリが連打されないようキャッシュすること。
       - 未検索KWが3件未満の場合は `Expand-GenreLongtailKeywords` を呼び出して新規単語を自律補充すること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\genre_seed_expander.ps1"
. "$PSScriptRoot\research_serp_fetcher.ps1"
. "$PSScriptRoot\store_api_query.ps1"

function Get-PrioritizedGenreCandidates {
    param(
        [Parameter(Mandatory=$true)]
        $TargetGenre,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        $Tracker,

        [Parameter(Mandatory=$false)]
        [int]$MaxTotalCalls = 500,

        [Parameter(Mandatory=$false)]
        [int]$CurrentApiCalls = 0,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $seeds = $TargetGenre.Seeds
    $genreKws = @()
    $totalApiCallsMade = 0

    # 1. Check DB first for UNSEARCHED keywords (not yet in serp_cache)
    $checkedPrefixes = @{}
    foreach ($s in $seeds) {
        $tokens = $s -split "\s+"
        $token = $tokens[0]
        if ($checkedPrefixes.ContainsKey($token)) { continue }
        $checkedPrefixes[$token] = $true
        $safeToken = $token.Replace("'", "''")
        $dbQuery = "SELECT vk.keyword, vk.volume FROM verified_keywords vk LEFT JOIN serp_cache sc ON vk.keyword = sc.keyword WHERE vk.volume >= 1900 AND (vk.gender = '$Gender' OR vk.gender = 'common') AND vk.keyword LIKE '%$safeToken%' AND sc.keyword IS NULL ORDER BY vk.volume DESC LIMIT 20;"
        try {
            $dbRes = Invoke-SqliteQuery -SqlQuery $dbQuery
            if ($dbRes) {
                foreach ($row in $dbRes) {
                    if ($null -ne $row -and -not [string]::IsNullOrWhiteSpace($row.keyword)) {
                        $genreKws += @{ Keyword = ([string]$row.keyword).Trim(); Volume = [int]$row.volume }
                    }
                }
            }
        } catch {}
    }

    # 2. If not enough keywords in DB, expand seeds via API
    if ($genreKws.Count -lt 5 -and ($CurrentApiCalls + $totalApiCallsMade) -lt $MaxTotalCalls) {
        $expandSeeds = @()
        foreach ($s in $seeds) {
            $expandSeeds += $s
            $toks = $s -split "\s+"
            if ($toks.Count -ge 2) { $expandSeeds += "$($toks[0]) $($toks[1])" }
            if ($toks.Count -ge 1 -and $toks[0].Length -ge 2) { $expandSeeds += $toks[0] }
        }
        $expandSeeds = @($expandSeeds | Select-Object -Unique | Select-Object -First 5)
        Write-Output "Expanding Seeds via Expand-BulkKeywords: $($expandSeeds -join ', ')..."
        $bulkRes = Expand-BulkKeywords -SeedKeywords $expandSeeds -MinVolume 1900 -BatchSize 2 -DryRun:$DryRun
        if ($bulkRes) {
            $actualCalls = if ($null -ne $bulkRes.BatchesProcessed) { [int]$bulkRes.BatchesProcessed } else { 0 }
            $totalApiCallsMade += $actualCalls
            if ($bulkRes.IsExhausted) {
                if ($bulkRes.ExhaustionError -match "(?i)429|403|Daily report.*limit") {
                    Write-Warning "Bulk expand match_keywords quota reached ($($bulkRes.ExhaustionError)). Continuing SERP inspection with existing DB unqueried keywords..."
                } else {
                    Write-Warning "Bulk expand timed out (handled by MCP retries). Skipping to next step..."
                }
            }
            if ($bulkRes.EligibleCandidates) {
                foreach ($c in $bulkRes.EligibleCandidates) {
                    if ($null -ne $c -and -not [string]::IsNullOrWhiteSpace($c.Keyword)) {
                        $cVol = if ($null -ne $c.Volume -and [int]$c.Volume -gt 0) { [int]$c.Volume } elseif ($null -ne $c.SearchVolume) { [int]$c.SearchVolume } else { 0 }
                        $genreKws += @{ Keyword = ([string]$c.Keyword).Trim(); Volume = $cVol }
                    }
                }
            }
        }
    }

    # 3. Deduplicate and filter YMYL / Entertainment / Gender
    $uniqueKws = @{}
    $filteredKws = @()
    foreach ($item in $genreKws) {
        $kText = if ($null -ne $item.Keyword) { ([string]$item.Keyword).Trim() } else { "" }
        if ([string]::IsNullOrWhiteSpace($kText)) { continue }
        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kText
        if (-not $gCheck.IsAllowed) { continue }
        $yCheck = Test-KeywordYmylEligibility -Keyword $kText
        if ($yCheck.IsYmyl) { continue }
        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kText
        if ($eCheck.IsEntertainment) { continue }
        if (-not $uniqueKws.ContainsKey($kText)) {
            $uniqueKws[$kText] = $true
            $filteredKws += $item
        }
    }

    # 4. Separate unsearched vs cached
    $unsearchedKws = @()
    $cachedKws = @()
    foreach ($cand in $filteredKws) {
        $cText = [string]$cand.Keyword
        if ($Tracker.SearchedSerpKeywords.Contains($cText)) {
            $cachedKws += $cand
        } else {
            $archCheck = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cText
            if ($archCheck -and $archCheck.Data) {
                $cachedKws += $cand
            } else {
                $unsearchedKws += $cand
            }
        }
    }

    # 5. Longtail auto-expander if unsearched < 3
    if ($unsearchedKws.Count -lt 3) {
        Write-Output "  -> [Auto-Expander] Truly unsearched pool low ($($unsearchedKws.Count)). Deriving genre long-tail keywords for '$($TargetGenre.Name)'..."
        $expRes = Expand-GenreLongtailKeywords -GenreObj $TargetGenre -Gender $Gender -MinVolume 1900 -Limit 10 -ExcludeKeywords $Tracker.RegisteredKws -ExcludeSerpKeywords $Tracker.SearchedSerpKeywords -DryRun:$DryRun
        if ($expRes) {
            if ($null -ne $expRes.ApiCalls) {
                $totalApiCallsMade += [int]$expRes.ApiCalls
            }
            if ($expRes.IsExhausted) {
                Write-Warning "Auto-Expander match_keywords quota reached ($($expRes.ExhaustionError)). Continuing SERP inspection with existing DB unqueried keywords..."
            }
            $derived = $expRes.Keywords
            if ($derived -and $derived.Count -gt 0) {
                foreach ($dk in $derived) {
                    $dkText = if ($null -ne $dk.Keyword) { ([string]$dk.Keyword).Trim() } else { "" }
                    if (-not [string]::IsNullOrWhiteSpace($dkText) -and -not $uniqueKws.ContainsKey($dkText)) {
                        $uniqueKws[$dkText] = $true
                        $filteredKws += $dk
                        $dkArch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $dkText
                        if ($dkArch -and $dkArch.Data) {
                            $cachedKws += $dk
                        } else {
                            $unsearchedKws += $dk
                        }
                    }
                }
                Write-Output "  -> [Auto-Expander] Truly unsearched pool now: $($unsearchedKws.Count) keywords for '$($TargetGenre.Name)'."
            }
        }
    }

    # 6. S-Rank Priority sorting
    $troubleRegex = '外れ防止|落ちる|外れる|壊れた|ちぎれた|取れない|浮いてくる|割れた|代わり|代用|自作|身近なもの|裏ワザ|付け方|外し方|直し方|自分で直す|理由|知恵袋|ブログ|違い|原因|対処|やり方|コツ|比較|口コミ|手入れ|長持ち|初心者|選び方'
    $sRankKws = @()
    $otherUnsearched = @()
    foreach ($cand in $unsearchedKws) {
        if ($cand.Keyword -match $troubleRegex) {
            $sRankKws += $cand
        } else {
            $otherUnsearched += $cand
        }
    }

    $freshCached = @($cachedKws | Select-Object -First 5)
    $ordered = @($sRankKws) + @($otherUnsearched) + @($freshCached)

    Write-Output "  [Star3-Priority Sorter] S-Rank High-Probability KWs: $($sRankKws.Count) / General: $($otherUnsearched.Count)"
    Write-Output "Available Keywords for Genre: $($ordered.Count) (Truly Unsearched: $($unsearchedKws.Count), Cached: $($cachedKws.Count))"

    return [PSCustomObject]@{
        Candidates    = $ordered
        ApiCallsMade  = $totalApiCallsMade
    }
}
