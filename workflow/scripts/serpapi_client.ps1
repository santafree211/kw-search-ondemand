<#
.SYNOPSIS
    workflow/scripts/serpapi_client.ps1 - SerpApi Google Search クライアント

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SerpApi Google Search APIのリクエスト実行クライアント。
       当日窓内キャッシュ確認 ➔ クォータ上限確認 ➔ リモートHTTPリクエスト送信 ➔ SQLiteログ保存
       の一連の流れをオーケストレーションする。
    2. 準拠ルール:
       - GEMINI.md 第3条: 実測エビデンスに基づくリアルタイムGoogle SERPの取得。
       - SerpApi厳格クォータ管理: 日次上限（7回/日）、月間上限（240回/月）の完全遵守。
    3. 構成モジュール (Delegation Modules):
       - serpapi_config_resolver.ps1 : 設定ロード・APIキー解決
       - serpapi_usage_tracker.ps1   : 朝9時JST窓の利用状況集計・上限判定
       - serpapi_cache_store.ps1     : 0sキャッシュ照合・過去保管SERP取得・SQLite保存
    4. 入力・出力仕様:
       - Inputs : $Keyword (string), $ApiKey (string), $ForceRefresh (switch), $DryRun (switch)
       - Outputs: PSCustomObject @{ Keyword, IsExhausted, ExhaustionError, OrganicResults, FromCache, RawResponse }
    5. 修正時の注意点:
       - クォータ上限到達時（$usage.IsLimitReached=$true）は一切リモート通信を行わず、即座にIsExhausted=$trueを返すこと。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\serpapi_config_resolver.ps1"
. "$PSScriptRoot\serpapi_usage_tracker.ps1"
. "$PSScriptRoot\serpapi_cache_store.ps1"

function Invoke-SerpApiSearch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$false)]
        [string]$ApiKey = "",

        [Parameter(Mandatory=$false)]
        [switch]$ForceRefresh = $false,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $config = Get-SerpApiConfig
    $keyToUse = if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $ApiKey.Trim() } else { $config.api_key }
    $dailyLimit = $config.daily_limit

    # 1. Cache Check (same window) to save quota
    if (-not $ForceRefresh) {
        $windowCache = Find-SerpApiWindowCache -Keyword $Keyword
        if ($windowCache.Found) {
            Write-Output "  [0s SerpApi Cache Hit] Reusing today's SerpApi result for '$Keyword'."
            return [PSCustomObject]@{
                Keyword         = $Keyword
                IsExhausted     = $false
                ExhaustionError = ""
                OrganicResults  = $windowCache.OrganicResults
                FromCache       = $true
                RawResponse     = $windowCache.RawResponse
            }
        }
    }

    # 2. Quota Gate: Strict daily (7) and monthly (240) check
    $usage = Get-SerpApiDailyUsage -DailyLimit $dailyLimit -MonthlyLimit $config.monthly_limit
    if ($usage.IsLimitReached) {
        Write-Warning "SerpApi quota limit reached ($($usage.CallsToday)/$dailyLimit calls today). Halting remote search for '$Keyword'."
        return [PSCustomObject]@{
            Keyword         = $Keyword
            IsExhausted     = $true
            ExhaustionError = "Daily quota limit of $dailyLimit calls reached (Used today: $($usage.CallsToday))."
            OrganicResults  = @()
            FromCache       = $false
        }
    }

    if ($DryRun) {
        Write-Output "  [DryRun] Would query SerpApi for '$Keyword' (Current calls today: $($usage.CallsToday)/$dailyLimit)."
        return [PSCustomObject]@{
            Keyword         = $Keyword
            IsExhausted     = $false
            ExhaustionError = ""
            OrganicResults  = @()
            FromCache       = $false
            IsDryRun        = $true
        }
    }

    if ([string]::IsNullOrWhiteSpace($keyToUse)) {
        throw "SerpApi API key not found. Please set SERPAPI_API_KEY environment variable or configure workflow/config/serpapi_config.json."
    }

    # 3. Remote HTTP Request to SerpApi
    $encodedKw = [System.Uri]::EscapeDataString($Keyword)
    $uri = "https://serpapi.com/search.json?engine=$($config.engine)&q=$encodedKw&gl=$($config.gl)&hl=$($config.hl)&num=$($config.num)&api_key=$keyToUse"

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $responseJson = $null
    $httpStatus = 200
    try {
        $res = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $config.timeout_seconds
        $sw.Stop()
        $responseJson = $res | ConvertTo-Json -Depth 10 -Compress
    } catch {
        $sw.Stop()
        $errText = $_.Exception.Message
        Write-Warning "SerpApi HTTP request failed for '$Keyword': $errText"
        if ($errText -match "429|403|quota|Monthly limit|Daily limit") {
            return [PSCustomObject]@{
                Keyword         = $Keyword
                IsExhausted     = $true
                ExhaustionError = $errText
                OrganicResults  = @()
                FromCache       = $false
            }
        }
        throw "SerpApi error: $errText"
    }

    $parsed = $null
    try {
        $parsed = $responseJson | ConvertFrom-Json
    } catch {}

    $organics = @()
    if ($parsed -and $parsed.organic_results) {
        $organics = @($parsed.organic_results)
    }

    # 4. Save to SQLite database
    Save-SerpApiResponse -Keyword $Keyword -Engine $config.engine -Gl $config.gl -Hl $config.hl -HttpStatus $httpStatus -OrganicCount $organics.Count -ResponseJson $responseJson

    Write-Output "  [SerpApi Request Success] '$Keyword' -> $($organics.Count) organic results ($($sw.ElapsedMilliseconds) ms, Calls Today: $($usage.CallsToday + 1)/$dailyLimit)."

    return [PSCustomObject]@{
        Keyword         = $Keyword
        IsExhausted     = $false
        ExhaustionError = ""
        OrganicResults  = $organics
        FromCache       = $false
        RawResponse     = $parsed
    }
}
