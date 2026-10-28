<#
.SYNOPSIS
    serpapi_usage_tracker.ps1 - SerpApi 09:00JST窓日次・月次クォータ集計＆ログ管理

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SerpApiの実行ログテーブル（serpapi_call_logs）の初期化と、09:00 JSTリセット窓に基づく本日利用回数、
       月間利用回数のリアルタイム集計、およびKW別最終検証日の取得を行う。
    2. 準拠ルール:
       - GEMINI.md 第5条: 09:00 JSTリセットに同期したクォータ枠管理。
       - 日次7枠 / 月間240枠の物理リミット保護。
    3. 入力・出力仕様:
       - Get-SerpApiDailyUsage:
           - Inputs : $DailyLimit (int), $MonthlyLimit (int)
           - Outputs: PSCustomObject @{ CallsToday, DailyLimit, RemainingCalls, CallsThisMonth, MonthlyLimit, IsLimitReached, ... }
       - Get-SerpApiKeywordLastVerifiedDate:
           - Inputs : $Keyword (string)
           - Outputs: PSCustomObject @{ IsVerified, LastVerifiedDate, DaysAgo }
    4. 修正時の注意点:
       - 日次集計の開始境界は 00:00 ではなく毎朝 09:00 JST であることに留意すること。
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
