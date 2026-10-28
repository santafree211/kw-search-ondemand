<#
.SYNOPSIS
    engine_potato_harvester.ps1 - 実測個人ブログ起点・芋づる式当たりKW発掘モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SERP上位10位内で捕捉された実測DA 1〜9の独立個人ブログからドメイン全体の上位流入KWを芋づる式に抽出し、
       弱競合席が担保された当たりKWリスト（DomainKws）を構成する。
    2. 準拠ルール:
       - GEMINI.md 第2条: 行登録の主語は実測DA 1〜9の個人ブログのみ（UGCは不可）。
       - 芋づる式数珠つなぎ（potato_digging_research スキル）の実装。
    3. 入力・出力仕様:
       - Inputs : $HitEntry, $OriginEval, $OriginKw, $Gender, $Tracker, $MaxTotalCalls, $CurrentApiCalls
       - Outputs: PSCustomObject @{
           Success, Domain, CleanUrl, Da, SiteTitle, DomainKws, ApiCallsMade, IsExhausted, ExhaustionError
         }
    4. 修正時の注意点:
       - 抽出された各KWは即座にSERP弱席照合を実施し、星数およびVol >= 1900の実測エビデンスを付与すること。
       - 既にスプシに登録済みのドメイン・URLはスキップすること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\research_domain_harvester.ps1"
. "$PSScriptRoot\research_serp_fetcher.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\store_api_query.ps1"

function Invoke-PotatoBlogHarvest {
    param(
        [Parameter(Mandatory=$true)]
        $HitEntry,

        [Parameter(Mandatory=$true)]
        $OriginEval,

        [Parameter(Mandatory=$true)]
        [string]$OriginKw,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        $Tracker,

        [Parameter(Mandatory=$false)]
        [int]$MaxTotalCalls = 500,

        [Parameter(Mandatory=$false)]
        [int]$CurrentApiCalls = 0
    )

    $dom = [string]$HitEntry.domain
    $da = [int]$HitEntry.domain_authority
    $siteTitle = if ($HitEntry.title) { [string]$HitEntry.title } else { $dom }

    $cleanUrl = "https://$dom/"
    try {
        if ($HitEntry.url) {
            $u = [System.Uri]$HitEntry.url
            $cleanUrl = "$($u.Scheme)://$($u.Host)/"
        }
    } catch {
        $cleanUrl = "https://$dom/"
    }

    Write-Output "    >>> [PERSONAL BLOG DISCOVERED] $dom (DA: $da) Title: '$siteTitle'"

    $domainKws = @($OriginEval.FormattedValue)
    $apiCallsMade = 0
    $isExhausted = $false
    $exhaustionError = ""

    try {
        Write-Output "    Harvesting top keywords for '$dom' via domain_keywords..."
        $dRes = Extract-DomainKeywords -Domain $dom -MinVolume 1900 -MaxPosition 10 -Limit 20
        if ($dRes -and $dRes.WinningKeywords) {
            $serpHarvestCount = 0
            foreach ($wk in $dRes.WinningKeywords) {
                if ($serpHarvestCount -ge 12 -or ($CurrentApiCalls + $apiCallsMade) -ge $MaxTotalCalls) { break }
                $wText = [string]$wk.Keyword
                $wVol = [int]$wk.SearchVolume
                if ($wText -eq $OriginKw) { continue }

                $entCheckW = Test-KeywordEntertainmentEligibility -Keyword $wText
                if ($entCheckW.IsEntertainment) { continue }
                $ymylCheckW = Test-KeywordYmylEligibility -Keyword $wText
                if ($ymylCheckW.IsYmyl) { continue }
                $gCheckW = Test-KeywordGenderEligibility -Gender $Gender -Keyword $wText
                if (-not $gCheckW.IsAllowed) { continue }

                $cachedEntries = $null
                $archH = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $wText
                if ($archH -and $archH.Data) {
                    $archHData = $archH.Data
                    if ($archHData.serpEntries) { $cachedEntries = $archHData.serpEntries }
                    elseif ($archHData.serp_table) { $cachedEntries = $archHData.serp_table }
                    elseif ($archHData.result -and $archHData.result.serp_table) { $cachedEntries = $archHData.result.serp_table }
                }

                $targetEntries = $cachedEntries
                if ($null -eq $targetEntries) {
                    $apiCallsMade++
                    $serpHarvestCount++
                    Write-Output "    [$($CurrentApiCalls + $apiCallsMade)] Real-time SERP verification for '$wText' (Vol: $wVol)..."
                    $harvestSerp = Invoke-SerpAnalysisRemote -TargetKeyword $wText
                    if ($harvestSerp) {
                        [void]$Tracker.SearchedSerpKeywords.Add($wText)
                        if ($harvestSerp.IsExhausted) {
                            $isExhausted = $true
                            $exhaustionError = $harvestSerp.Error
                            Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($harvestSerp.Error)"
                            break
                        }
                        if ($harvestSerp.serpEntries) { $targetEntries = $harvestSerp.serpEntries }
                        elseif ($harvestSerp.result -and $harvestSerp.result.serp_table) { $targetEntries = $harvestSerp.result.serp_table }
                    }
                }

                if ($targetEntries) {
                    $hEval = if ($Gender -eq "male") {
                        Get-StrictStarEvaluationMale -Keyword $wText -SearchVolume $wVol -SerpEntries $targetEntries
                    } else {
                        Get-StrictStarEvaluation -Keyword $wText -SearchVolume $wVol -SerpEntries $targetEntries
                    }
                    if ($hEval.IsHit) {
                        $hTokens = $wText -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        $hNorm = (($hTokens | Sort-Object) -join " ").ToLower()
                        if (-not $Tracker.RegisteredKws.ContainsKey($hNorm)) {
                            Save-VolumeCacheEntrySafe -Keyword $wText -Volume $wVol
                            if (-not ($domainKws -contains $hEval.FormattedValue)) {
                                $domainKws += $hEval.FormattedValue
                                Write-Output "      -> Harvested HIT: $($hEval.FormattedValue) (Stars: $($hEval.StarCount))"
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Output "    Domain keyword harvest fallback: $_"
    }

    return [PSCustomObject]@{
        Domain          = $dom
        CleanUrl        = $cleanUrl
        Da              = $da
        SiteTitle       = $siteTitle
        DomainKws       = $domainKws
        ApiCallsMade    = $apiCallsMade
        IsExhausted     = $isExhausted
        ExhaustionError = $exhaustionError
    }
}
