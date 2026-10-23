<#
.SYNOPSIS
    tools/research_db_harvest_diff.ps1
    Responsibility: Efficiently scan ONLY newly added SERPs (delta/incremental) from SQLite DB since last scan.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [switch]$FullScan = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Commit = $false,

    [Parameter(Mandatory=$false)]
    [string]$TargetGender = "both"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator.ps1"
. "$projectRoot\workflow\scripts\eval_weak_competitor_rule.ps1"
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\guard_check_ymyl_kw.ps1"

Write-Output "=========================================================="
Write-Output "=== INCREMENTAL DELTA SCANNER (RESEARCH.DB) ==="
Write-Output "=========================================================="
Write-Output "FullScan Mode: $FullScan | Auto-Commit: $Commit | Gender: $TargetGender"

# 1. Initialize tracker table in DB if not exists
$initTrackerSql = @"
CREATE TABLE IF NOT EXISTS offline_scan_tracker (
    target_key TEXT PRIMARY KEY,
    scanned_at TEXT NOT NULL,
    is_hit INTEGER NOT NULL,
    personal_sites_found INTEGER NOT NULL
);
"@
Invoke-SqliteQuery -SqlQuery $initTrackerSql | Out-Null

# 2. Determine target records
$querySql = if ($FullScan) {
    "SELECT DISTINCT target_key, response_json FROM raw_api_archive WHERE endpoint = 'serp_analysis';"
} else {
    "SELECT DISTINCT target_key, response_json FROM raw_api_archive WHERE endpoint = 'serp_analysis' AND target_key NOT IN (SELECT target_key FROM offline_scan_tracker);"
}

$pendingRecords = @(Invoke-SqliteQuery -SqlQuery $querySql)
Write-Output "Delta SERP Records to analyze: $($pendingRecords.Count)"

if ($pendingRecords.Count -eq 0) {
    Write-Output "No new delta SERP records to process. Database is up to date."
    return
}

# 3. Load verified volumes for delta keys
$volMap = @{}
$vRows = @(Invoke-SqliteQuery -SqlQuery "SELECT DISTINCT keyword, volume FROM verified_keywords WHERE volume >= 1900;")
foreach ($vr in $vRows) {
    if ($vr.keyword -and $null -ne $vr.volume) {
        $volMap[[string]$vr.keyword] = [int]$vr.volume
    }
}

# 4. Analyze delta records
$discoveredSites = @{}
$trackerInserts = @()
$nowStr = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")

foreach ($rec in $pendingRecords) {
    $kw = [string]$rec.target_key
    $vol = if ($volMap.ContainsKey($kw)) { $volMap[$kw] } else { 0 }
    $isHit = 0
    $personalCount = 0

    # YMYL check: skip any YMYL keywords
    $ymylCheck = Test-KeywordYmylEligibility -Keyword $kw
    if ($ymylCheck.IsYmyl) {
        $escapedKw = $kw.Replace("'", "''")
        $trackerInserts += "INSERT OR REPLACE INTO offline_scan_tracker (target_key, scanned_at, is_hit, personal_sites_found) VALUES ('$escapedKw', '$nowStr', 0, 0);"
        continue
    }

    if ($vol -ge 1900) {
        try {
            $parsed = $rec.response_json | ConvertFrom-Json
            $entries = $parsed.serpEntries
            if (-not $entries -and $parsed.result -and $parsed.result.serp_table) { $entries = $parsed.result.serp_table }
            if ($entries) {
                $eval = Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries
                if ($eval.IsHit -and $eval.PureLowDaSites.Count -gt 0) {
                    $isHit = 1
                    foreach ($site in $eval.PureLowDaSites) {
                        $dom = ([string]$site.domain).ToLower().Trim()
                        $da = [int]$site.domainAuthority
                        if ($dom -eq "nodomain" -or [string]::IsNullOrWhiteSpace($dom)) { continue }

                        $ugc = Test-WeakCompetitor -Domain $dom
                        if ($da -ge 1 -and $da -le 9 -and -not $ugc.IsWeakCompetitor) {
                            $personalCount++
                            if (-not $discoveredSites.ContainsKey($dom)) {
                                $discoveredSites[$dom] = @{
                                    Domain = $dom
                                    DA = $da
                                    SiteName = if ($site.title) { $site.title.Trim() } else { $dom }
                                    Url = [string]$site.url
                                    WinningKws = @()
                                }
                            }
                            if (-not ($discoveredSites[$dom].WinningKws -contains $eval.FormattedValue)) {
                                $discoveredSites[$dom].WinningKws += $eval.FormattedValue
                            }
                        }
                    }
                }
            }
        } catch {}
    }

    # Record in tracker to avoid re-scanning
    $escapedKw = $kw.Replace("'", "''")
    $trackerInserts += "INSERT OR REPLACE INTO offline_scan_tracker (target_key, scanned_at, is_hit, personal_sites_found) VALUES ('$escapedKw', '$nowStr', $isHit, $personalCount);"
}

# Flush tracker records in batch
if ($trackerInserts.Count -gt 0) {
    $batchSql = "BEGIN TRANSACTION; " + ($trackerInserts -join " ") + " COMMIT;"
    Invoke-SqliteQuery -SqlQuery $batchSql | Out-Null
}

Write-Output "`n[DELTA SCAN FINISHED]"
Write-Output "Analyzed $($pendingRecords.Count) new SERPs."
Write-Output "Discovered $($discoveredSites.Count) candidate personal blogs."

foreach ($s in $discoveredSites.Values) {
    Write-Output "Found: $($s.SiteName) ($($s.Domain), DA $($s.DA)) - KWs: $($s.WinningKws.Count)"
}
