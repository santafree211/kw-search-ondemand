<#
.SYNOPSIS
    workflow/scripts/guard_quota_archive.ps1
    Responsibility: Calculate actual daily API call counts and breakdown based on raw_api_archive index since 09:00 JST.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-DailyApiQuotaUsage {
    param(
        [Parameter(Mandatory=$false)]
        [string]$IndexFile = "",

        [Parameter(Mandatory=$false)]
        [int]$DailyQuotaLimit = 100
    )

    if ([string]::IsNullOrWhiteSpace($IndexFile)) {
        $IndexFile = Join-Path $PSScriptRoot "..\data\raw_api_archive\index.jsonl"
    }

    $now = Get-Date
    # 09:00 JST boundary calculation
    $windowStart = if ($now.Hour -lt 9) {
        (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0).AddDays(-1)
    } else {
        Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0
    }

    $breakdown = @{
        "serp_analysis" = 0
        "match_keywords" = 0
        "domain_keywords" = 0
        "keyword_overview" = 0
        "other" = 0
    }
    $totalCalls = 0
    $recentCalls = @()
    # Try SQLite query first
    $dbPath = Join-Path $PSScriptRoot "..\data\research.db"
    if (Test-Path $dbPath) {
        try {
            . "$PSScriptRoot\db_sqlite_manager.ps1"
            $isoStart = $windowStart.ToString("yyyy-MM-ddTHH:mm:ss")
            $sql = "SELECT endpoint, COUNT(*) as cnt FROM api_call_logs WHERE timestamp >= '$isoStart' GROUP BY endpoint;"
            $rows = @(Invoke-SqliteQuery -SqlQuery $sql)
            if ($rows.Count -gt 0) {
                foreach ($r in $rows) {
                    $ep = [string]$r.endpoint
                    $cnt = [int]$r.cnt
                    $breakdown[$ep] = $cnt
                    $totalCalls += $cnt
                }
                $remaining = [Math]::Max(0, ($DailyQuotaLimit - $totalCalls))
                return [PSCustomObject]@{
                    WindowStartTimeJst = $windowStart.ToString("yyyy-MM-dd HH:mm:ss")
                    CurrentTimeJst = $now.ToString("yyyy-MM-dd HH:mm:ss")
                    TotalRealCallsToday = $totalCalls
                    DailyQuotaLimit = $DailyQuotaLimit
                    RemainingEstimated = $remaining
                    CallBreakdown = $breakdown
                    Source = "sqlite_research_db"
                }
            }
        } catch {}
    }

    if (Test-Path $IndexFile) {
        $lines = [System.IO.File]::ReadAllLines($IndexFile, [System.Text.Encoding]::UTF8)
        foreach ($line in $lines) {
            $t = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($t)) { continue }

            try {
                $obj = $t | ConvertFrom-Json
                $ts = [DateTime]::MinValue
                if ($obj.Timestamp -and [DateTime]::TryParse($obj.Timestamp, [ref]$ts)) {
                    if ($ts -ge $windowStart) {
                        $ep = if ($obj.Endpoint) { [string]$obj.Endpoint } else { "other" }
                        if (-not $breakdown.ContainsKey($ep)) {
                            $breakdown[$ep] = 0
                        }
                        $breakdown[$ep]++
                        $totalCalls++

                        $recentCalls += [PSCustomObject]@{
                            Timestamp = $obj.Timestamp
                            Endpoint = $ep
                            TargetKey = $obj.TargetKey
                        }
                    }
                }
            } catch {}
        }
    }

    $remaining = [Math]::Max(0, ($DailyQuotaLimit - $totalCalls))

    return [PSCustomObject]@{
        WindowStartTimeJst = $windowStart.ToString("yyyy-MM-dd HH:mm:ss")
        CurrentTimeJst = $now.ToString("yyyy-MM-dd HH:mm:ss")
        TotalRealCallsToday = $totalCalls
        DailyQuotaLimit = $DailyQuotaLimit
        RemainingEstimated = $remaining
        CallBreakdown = $breakdown
        RecentCallsCount = $recentCalls.Count
    }
}
