<#
.SYNOPSIS
    tools/research_engine.ps1 - 個人ブログ起点・芋づる式自律リサーチ司令塔 (SKILL.md完全準拠)

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SKILL.md (potato_digging_research) に完全準拠し、
       「実測DA 1〜9の独立個人ブログ」を起点として、Google 1〜10位獲得KWを一括取得し、
       その検索結果から当たりKW判定および「次世代のDA一桁個人ブログ」を数珠つなぎに発掘・コミットする。
    2. 準拠ルール:
       - GEMINI.md 第1条: 50ジャンル均等底上げ。
       - GEMINI.md 第2条: 黄金比率（☆☆☆ >= 50%, ☆☆ <= 25%, ☆ <= 25%）の厳格維持。
       - GEMINI.md 第3条: 実測エビデンス主義（Vol >= 1900、実測DA 1〜9の個人ブログのみ行登録）。
    3. 構成モジュール (Delegation Modules):
       - engine_dedup_tracker.ps1     : 全列URL・異性KW・SERPキャッシュの0ms HashSet重複排除
       - potato_origin_fetcher.ps1    : Step 1 起点個人ブログ（実測DA 1〜9）抽出
       - potato_domain_sifter.ps1     : Step 2 個人ブログ流入KW（Google 1〜10位, Vol>=1900）一括抽出
       - potato_chain_reactor.ps1     : Step 3&4 星数確定 ＆ 次世代個人ブログ自動収穫
       - engine_star3_gate.ps1        : 黄金比率コミットゲート
    4. 禁止事項:
       - AI推測による合否判定、キーワードからの絨毯爆撃（match_keywords連打）の禁止。
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
. "$projectRoot\workflow\scripts\potato_origin_fetcher.ps1"
. "$projectRoot\workflow\scripts\potato_domain_sifter.ps1"
. "$projectRoot\workflow\scripts\potato_chain_reactor.ps1"
. "$projectRoot\workflow\scripts\engine_star3_gate.ps1"
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"

Write-Output "=========================================================="
Write-Output "=== POTATO-DIGGING AUTONOMOUS RESEARCH ENGINE ==="
Write-Output "=========================================================="
Write-Output "Target Profile: $Gender ()"
Write-Output "Max Total Calls: $MaxTotalCalls"
Write-Output "Max KWs Per Batch: $MaxKwsPerGenreBatch"
Write-Output "DryRun Mode    : $DryRun"

$profile = Resolve-SheetProfile -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId
$targetSheetName = $profile.TargetSheetName

# 1. 重複排除トラッカー初期化
$tracker = Initialize-EngineDedupTracker -SpreadsheetId $SpreadsheetId -TargetSheetName $targetSheetName -Gender $Gender -KwStartCol $profile.KwStartCol

$totalApiCalls = 0
$exhausted = $false
$exhaustionError = ""
$sitesCommittedCount = 0
$excludedDomains = @()

# 2. 完全な個人ブログ起点・芋づる一本道ループ (SKILL.md)
while ($totalApiCalls -lt $MaxTotalCalls -and -not $exhausted) {
    if ($DryRun -and $totalApiCalls -ge $MaxTotalCalls) { break }

    # Step 1: 起点となる実測DA 1〜9の独立個人ブログを取得
    $originBlog = Get-NextPotatoOriginBlog -Gender $Gender -ExcludeDomains $excludedDomains
    if ($null -eq $originBlog) {
        Write-Warning "No more unparsed DA 1-9 personal blogs found in candidate queue. Pipeline complete."
        break
    }

    $dom = $originBlog.Domain
    $da = $originBlog.Da
    $siteTitle = $originBlog.SiteName
    $url = $originBlog.Url
    $originGenreId = $originBlog.GenreId

    Write-Output "`n>>> [POTATO ROOT] Targeting Blog: $dom (DA: $da) Title: '$siteTitle'"
    $excludedDomains += $dom

    # Step 2: 個人ブログのGoogle 1〜10位獲得KW (Vol >= 1900) を一括抽出
    $siftRes = Get-PotatoBlogTopKeywords -Domain $dom -Gender $Gender -RegisteredKws $tracker.RegisteredKws -DryRun:$DryRun
    $totalApiCalls += $siftRes.ApiCallsMade
    if ($siftRes.IsExhausted) {
        $exhausted = $true
        $exhaustionError = $siftRes.ExhaustionError
        break
    }

    if ($DryRun -and $siftRes.ApiCallsMade -eq 0) {
        $totalApiCalls++
    }

    $candidateKws = $siftRes.FilteredKeywords
    if (-not $candidateKws -or $candidateKws.Count -eq 0) {
        Write-Output "    [No High-Vol Ranking KWs] '$dom' has no ranking keywords with Vol >= 1900. Marking analyzed."
        try {
            Invoke-SqliteNonQuery -SqlQuery "UPDATE discovered_sites SET status = 'harvested' WHERE domain = '$dom';" | Out-Null
        } catch {}
        continue
    }

    # Step 3 & 4: 各KWのSERP星数評価 ＆ 次世代個人ブログの自動収穫
    $winningKws = @()
    $kwBatchCount = 0

    foreach ($candItem in $candidateKws) {
        if ($kwBatchCount -ge $MaxKwsPerGenreBatch -or $totalApiCalls -ge $MaxTotalCalls) { break }

        $chainRes = Invoke-PotatoKeywordSerpChain -Keyword $candItem.Keyword -Volume $candItem.SearchVolume -Gender $Gender -OriginGenreId $originGenreId -Tracker $tracker -DryRun:$DryRun
        $totalApiCalls += $chainRes.ApiCallsMade
        $kwBatchCount++

        if ($chainRes.IsExhausted) {
            $exhausted = $true
            $exhaustionError = $chainRes.ExhaustionError
            break
        }

        if (-not [string]::IsNullOrWhiteSpace($chainRes.FormattedValue)) {
            $winningKws += $chainRes.FormattedValue
        }
    }

    # 当たりKWが存在する場合、星3先行コミットゲートへ
    if ($winningKws.Count -gt 0) {
        $harvestObj = [PSCustomObject]@{
            Success     = $true
            Domain      = $dom
            CleanUrl    = $url
            Da          = $da
            SiteTitle   = $siteTitle
            DomainKws   = $winningKws
        }

        # ジャンル情報の解決
        $targetGenre = [PSCustomObject]@{
            Id   = if ($originGenreId -gt 0) { $originGenreId } else { 1 }
            Name = "全般"
        }

        $gateRes = Invoke-Star3FirstCommitGate -HarvestResult $harvestObj -TargetGenre $targetGenre -Gender $Gender -Profile $profile -Tracker $tracker -DryRun:$DryRun
        if ($gateRes.Committed) {
            $sitesCommittedCount++
            Write-Output "    -> SUCCESS: Committed '$siteTitle' ($dom) with $($winningKws.Count) winning keywords!"
        }
    }

    # 起点ブログを解析完了として更新
    try {
        Invoke-SqliteNonQuery -SqlQuery "UPDATE discovered_sites SET status = 'harvested' WHERE domain = '$dom';" | Out-Null
    } catch {}
}

Write-Output "`n=========================================================="
Write-Output "POTATO-DIGGING HARVEST BATCH COMPLETED"
Write-Output "Total API Calls Made : $totalApiCalls"
Write-Output "Sites Committed      : $sitesCommittedCount"
Write-Output "Physical Exhausted   : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Reason    : $exhaustionError"
}
Write-Output "=========================================================="
