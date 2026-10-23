<#
.SYNOPSIS
    workflow/scripts/serpapi_client.ps1
    Responsibility: Client wrapper for SerpApi Google Search engine with strict daily quota limit (90 calls/day).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"

function Initialize-SerpApiDatabase {
    param(
        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )
    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Initialize-ResearchDatabase
    }

    $createSql = @"
CREATE TABLE IF NOT EXISTS serpapi_call_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    window_date TEXT NOT NULL,
    keyword TEXT NOT NULL,
    engine TEXT NOT NULL DEFAULT 'google',
    gl TEXT NOT NULL DEFAULT 'jp',
    hl TEXT NOT NULL DEFAULT 'ja',
    http_status INTEGER NOT NULL DEFAULT 200,
    organic_count INTEGER NOT NULL DEFAULT 0,
    star_count INTEGER NOT NULL DEFAULT 0,
    response_json TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
CREATE INDEX IF NOT EXISTS idx_serpapi_logs_time ON serpapi_call_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_serpapi_logs_kw ON serpapi_call_logs(keyword);
"@
    try {
        Invoke-SqliteNonQuery -SqlScript $createSql -DbPath $DbPath | Out-Null
    } catch {
        Write-Verbose "Error initializing serpapi_call_logs table: $_"
    }
    return $DbPath
}

function Get-SerpApiConfig {
    $configFile = Join-Path $PSScriptRoot "..\config\serpapi_config.json"
    $config = [PSCustomObject]@{
        api_key         = ""
        daily_limit     = 7
        monthly_limit   = 240
        engine          = "google"
        gl              = "jp"
        hl              = "ja"
        num             = 10
        timeout_seconds = 30
    }

    if (Test-Path $configFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.api_key) { $config.api_key = [string]$parsed.api_key }
            if ($null -ne $parsed.daily_limit) { $config.daily_limit = [int]$parsed.daily_limit }
            if ($null -ne $parsed.monthly_limit) { $config.monthly_limit = [int]$parsed.monthly_limit }
            if ($parsed.engine) { $config.engine = [string]$parsed.engine }
            if ($parsed.gl) { $config.gl = [string]$parsed.gl }
            if ($parsed.hl) { $config.hl = [string]$parsed.hl }
            if ($null -ne $parsed.num) { $config.num = [int]$parsed.num }
            if ($null -ne $parsed.timeout_seconds) { $config.timeout_seconds = [int]$parsed.timeout_seconds }
        } catch {}
    }

    # Check environment variables (Process, User, Machine)
    $keyFromEnv = if (-not [string]::IsNullOrWhiteSpace($env:SERPAPI_API_KEY)) { $env:SERPAPI_API_KEY.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($keyFromEnv)) {
        try {
            $userKey = [System.Environment]::GetEnvironmentVariable("SERPAPI_API_KEY", "User")
            if (-not [string]::IsNullOrWhiteSpace($userKey)) {
                $keyFromEnv = $userKey.Trim()
                $env:SERPAPI_API_KEY = $keyFromEnv
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($keyFromEnv)) {
        try {
            $machKey = [System.Environment]::GetEnvironmentVariable("SERPAPI_API_KEY", "Machine")
            if (-not [string]::IsNullOrWhiteSpace($machKey)) {
                $keyFromEnv = $machKey.Trim()
                $env:SERPAPI_API_KEY = $keyFromEnv
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($keyFromEnv)) {
        $config.api_key = $keyFromEnv
    }

    return $config
}

function Get-SerpApiDailyUsage {
    param(
        [Parameter(Mandatory=$false)]
        [int]$DailyLimit = 7,

        [Parameter(Mandatory=$false)]
        [int]$MonthlyLimit = 240
    )

    $dbPath = Initialize-SerpApiDatabase
    $now = Get-Date

    # 09:00 JST window boundary (matching Ubersuggest quota window standard)
    $windowStart = if ($now.Hour -lt 9) {
        (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0).AddDays(-1)
    } else {
        Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0
    }
    $isoStart = $windowStart.ToString("yyyy-MM-ddTHH:mm:ss")

    # Monthly tracking (calendar month starting from 1st 00:00:00)
    $monthStart = Get-Date -Year $now.Year -Month $now.Month -Day 1 -Hour 0 -Minute 0 -Second 0
    $isoMonthStart = $monthStart.ToString("yyyy-MM-ddTHH:mm:ss")

    $countSql = "SELECT COUNT(*) as cnt FROM serpapi_call_logs WHERE timestamp >= '$isoStart';"
    $monthCountSql = "SELECT COUNT(*) as cnt FROM serpapi_call_logs WHERE timestamp >= '$isoMonthStart';"

    $callsToday = 0
    $callsThisMonth = 0
    try {
        $rows = @(Invoke-SqliteQuery -SqlQuery $countSql -DbPath $dbPath)
        if ($rows.Count -gt 0 -and $rows[0].cnt) {
            $callsToday = [int]$rows[0].cnt
        }
        $mRows = @(Invoke-SqliteQuery -SqlQuery $monthCountSql -DbPath $dbPath)
        if ($mRows.Count -gt 0 -and $mRows[0].cnt) {
            $callsThisMonth = [int]$mRows[0].cnt
        }
    } catch {
        Write-Verbose "Error checking serpapi usage: $_"
    }

    $isDailyLimitReached = ($callsToday -ge $DailyLimit)
    $isMonthlyLimitReached = ($callsThisMonth -ge $MonthlyLimit)
    $isLimitReached = ($isDailyLimitReached -or $isMonthlyLimitReached)

    $remainingDaily = [Math]::Max(0, ($DailyLimit - $callsToday))
    $remainingMonthly = [Math]::Max(0, ($MonthlyLimit - $callsThisMonth))
    $effectiveRemaining = [Math]::Min($remainingDaily, $remainingMonthly)

    return [PSCustomObject]@{
        CallsToday            = $callsToday
        DailyLimit            = $DailyLimit
        RemainingCalls        = $effectiveRemaining
        CallsThisMonth        = $callsThisMonth
        MonthlyLimit          = $MonthlyLimit
        IsDailyLimitReached   = $isDailyLimitReached
        IsMonthlyLimitReached = $isMonthlyLimitReached
        IsLimitReached        = $isLimitReached
        WindowStartJst        = $windowStart.ToString("yyyy-MM-dd HH:mm:ss")
        MonthStartJst         = $monthStart.ToString("yyyy-MM-dd HH:mm:ss")
        CheckedAtJst          = $now.ToString("yyyy-MM-dd HH:mm:ss")
    }
}

function Get-SerpApiKeywordLastVerifiedDate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword
    )

    $dbPath = Initialize-SerpApiDatabase
    $safeKw = $Keyword.Trim().Replace("'", "''")
    $sql = "SELECT timestamp FROM serpapi_call_logs WHERE keyword = '$safeKw' ORDER BY id DESC LIMIT 1;"
    try {
        $rows = @(Invoke-SqliteQuery -SqlQuery $sql -DbPath $dbPath)
        if ($rows.Count -gt 0 -and $rows[0].timestamp) {
            $tsStr = [string]$rows[0].timestamp
            $datePart = if ($tsStr.Length -ge 10) { $tsStr.Substring(0, 10) } else { "" }
            $dt = [DateTime]::MinValue
            $daysAgo = 999.0
            if ([DateTime]::TryParse($tsStr, [ref]$dt)) {
                $daysAgo = ([DateTime]::Now - $dt).TotalDays
            }
            return [PSCustomObject]@{
                IsVerified       = $true
                LastVerifiedDate = $datePart
                Timestamp        = $tsStr
                DaysAgo          = [Math]::Round($daysAgo, 1)
            }
        }
    } catch {
        Write-Verbose "Error fetching keyword verification date: $_"
    }

    return [PSCustomObject]@{
        IsVerified       = $false
        LastVerifiedDate = ""
        Timestamp        = ""
        DaysAgo          = 9999.0
    }
}

function Get-SerpApiStoredResult {
    <#
    .SYNOPSIS
        Returns the latest stored Google SERP (SerpApi) for a keyword regardless of date. Zero API cost.
        Found=$false when no stored evidence exists.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword
    )
    $dbPathStored = Initialize-SerpApiDatabase
    $safeKwStored = $Keyword.Replace("'", "''")
    $normKwStored = ($Keyword -replace "[\s\u3000]+", " ").Trim().Replace("'", "''")
    $normKwNoSpace = ($Keyword -replace "[\s\u3000]+", "").Trim().Replace("'", "''")
    $sqlStored = "SELECT response_json, timestamp FROM serpapi_call_logs WHERE (keyword = '$safeKwStored' OR keyword = '$normKwStored' OR REPLACE(REPLACE(keyword, ' ', ''), '　', '') = '$normKwNoSpace') AND http_status = 200 AND response_json IS NOT NULL ORDER BY id DESC LIMIT 1;"
    try {
        $rowsStored = @(Invoke-SqliteQuery -SqlQuery $sqlStored -DbPath $dbPathStored)
        if ($rowsStored.Count -gt 0 -and $rowsStored[0].response_json) {
            $parsedStored = [string]$rowsStored[0].response_json | ConvertFrom-Json
            if ($parsedStored.organic_results) {
                return [PSCustomObject]@{
                    Keyword         = $Keyword
                    Found           = $true
                    IsExhausted     = $false
                    ExhaustionError = ""
                    OrganicResults  = @($parsedStored.organic_results)
                    FromCache       = $true
                    FetchedAt       = [string]$rowsStored[0].timestamp
                }
            }
        }
    } catch {}
    return [PSCustomObject]@{ Keyword = $Keyword; Found = $false; IsExhausted = $false; ExhaustionError = ""; OrganicResults = @(); FromCache = $true; FetchedAt = "" }
}

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
    $dbPath = Initialize-SerpApiDatabase
    $safeKw = $Keyword.Replace("'", "''")
    if (-not $ForceRefresh) {
        $now = Get-Date
        $windowStart = if ($now.Hour -lt 9) {
            (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0).AddDays(-1)
        } else {
            Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0
        }
        $isoStart = $windowStart.ToString("yyyy-MM-ddTHH:mm:ss")
        $cacheSql = "SELECT response_json, organic_count, star_count FROM serpapi_call_logs WHERE keyword = '$safeKw' AND timestamp >= '$isoStart' ORDER BY id DESC LIMIT 1;"
        try {
            $cRows = @(Invoke-SqliteQuery -SqlQuery $cacheSql -DbPath $dbPath)
            if ($cRows.Count -gt 0 -and $cRows[0].response_json) {
                $cachedJson = [string]$cRows[0].response_json
                $parsedCache = $cachedJson | ConvertFrom-Json
                Write-Output "  [0s SerpApi Cache Hit] Reusing today's SerpApi result for '$Keyword'."
                return [PSCustomObject]@{
                    Keyword         = $Keyword
                    IsExhausted     = $false
                    ExhaustionError = ""
                    OrganicResults  = if ($parsedCache.organic_results) { @($parsedCache.organic_results) } else { @() }
                    FromCache       = $true
                    RawResponse     = $parsedCache
                }
            }
        } catch {}
    }

    # 2. Quota Gate: Strict daily (7) and monthly (240) check
    $usage = Get-SerpApiDailyUsage -DailyLimit $dailyLimit
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
    $nowStr = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $escJson = $responseJson.Replace("'", "''")
    $orgCount = $organics.Count

    $insSql = "INSERT INTO serpapi_call_logs (timestamp, window_date, keyword, engine, gl, hl, http_status, organic_count, star_count, response_json) VALUES ('$nowStr', '$todayStr', '$safeKw', '$($config.engine)', '$($config.gl)', '$($config.hl)', $httpStatus, $orgCount, 0, '$escJson');"
    try {
        Invoke-SqliteNonQuery -SqlScript $insSql -DbPath $dbPath | Out-Null
    } catch {
        Write-Verbose "Error saving serpapi log: $_"
    }

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
