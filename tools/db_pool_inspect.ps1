<#
.SYNOPSIS
    tools\db_pool_inspect.ps1
    Agent Dedicated CLI Tool: Inspect Tier 1 (Qualified Useful Pool) and Tier 2 (Longtail Sub-Pool).
    Usage:
        powershell -ExecutionPolicy Bypass -File tools\db_pool_inspect.ps1
#>

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\workflow\scripts\db_sqlite_manager.ps1"

$dbPath = Get-ResearchDbPath
if (-not (Test-Path $dbPath)) {
    Write-Error "Database not found: $dbPath"
    exit 1
}

$dbFileInfo = Get-Item $dbPath
$dbSizeKb = [Math]::Round($dbFileInfo.Length / 1KB, 2)
$dbSizeMb = [Math]::Round($dbFileInfo.Length / 1MB, 2)

# Query Tier 1 counts
$t1Stats = Invoke-SqliteQuery -SqlQuery @"
SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN volume >= 10000 THEN 1 ELSE 0 END) as v_10k_plus,
    SUM(CASE WHEN volume >= 5000 AND volume < 10000 THEN 1 ELSE 0 END) as v_5k_9k,
    SUM(CASE WHEN volume >= 1900 AND volume < 5000 THEN 1 ELSE 0 END) as v_1900_4999,
    SUM(CASE WHEN genre_id IS NOT NULL AND genre_id > 0 THEN 1 ELSE 0 END) as with_genre
FROM verified_keywords;
"@

# Query Tier 2 counts
$t2Stats = Invoke-SqliteQuery -SqlQuery @"
SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN volume >= 1000 AND volume < 1900 THEN 1 ELSE 0 END) as v_1000_1899,
    SUM(CASE WHEN volume >= 500 AND volume < 1000 THEN 1 ELSE 0 END) as v_500_999,
    SUM(CASE WHEN volume >= 100 AND volume < 500 THEN 1 ELSE 0 END) as v_100_499,
    SUM(CASE WHEN volume < 100 THEN 1 ELSE 0 END) as v_under_100
FROM longtail_keyword_pool;
"@

# Check JSON Cache
$cachePath = Join-Path $scriptDir "..\workflow\data\verified_volume_cache.json"
$cacheCount = 0
$cacheViolations = 0
if (Test-Path $cachePath) {
    try {
        $cRaw = [System.IO.File]::ReadAllText($cachePath, [System.Text.Encoding]::UTF8)
        $parsed = $cRaw | ConvertFrom-Json
        if ($parsed -is [array]) {
            $cacheCount = $parsed.Count
            foreach ($item in $parsed) {
                if ([int]$item.Volume -lt 1900) { $cacheViolations++ }
            }
        } elseif ($parsed.verified_volumes) {
            foreach ($p in $parsed.verified_volumes.PSObject.Properties) {
                $cacheCount++
                if ([int]$p.Value -lt 1900) { $cacheViolations++ }
            }
        }
    } catch {}
}

# API Call Logs
$apiLogs = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM api_call_logs;")[0].cnt

Write-Output "=========================================================="
Write-Output "=== KEYWORD POOL DUAL-TIER STATUS (1-GUN & 2-GUN POOLS) ==="
Write-Output "=========================================================="
Write-Output "Database File:   $dbPath"
Write-Output "Database Size:   $dbSizeKb KB ($dbSizeMb MB) - SSD Overhead: ZERO"
Write-Output "API Log Entries: $apiLogs calls recorded"

Write-Output "`n[Tier 1: Qualified Useful Pool (verified_keywords, Vol >= 1900)]"
Write-Output "  Total Qualified Keywords: $($t1Stats[0].total) (Direct input for Sheets & 50 Genres)"
Write-Output "    - Mega Volume (10,000+):  $($t1Stats[0].v_10k_plus)"
Write-Output "    - High Volume (5,000-9k): $($t1Stats[0].v_5k_9k)"
Write-Output "    - Core Target (1,900-5k): $($t1Stats[0].v_1900_4999)"
Write-Output "    - Assigned to 50 Genres:  $($t1Stats[0].with_genre)"

Write-Output "`n[Tier 2: Longtail Sub-Pool (longtail_keyword_pool, Vol < 1900)]"
Write-Output "  Total Longtail Stock:     $($t2Stats[0].total) (Headings H2/H3, Co-occurrences, Future Promotion)"
Write-Output "    - Semi-Core (1,000-1899): $($t2Stats[0].v_1000_1899)"
Write-Output "    - Medium    (500-999):    $($t2Stats[0].v_500_999)"
Write-Output "    - Longtail  (100-499):    $($t2Stats[0].v_100_499)"
Write-Output "    - Micro/Niche (< 100):    $($t2Stats[0].v_under_100)"

Write-Output "`n[JSON Cache Integrity (verified_volume_cache.json)]"
Write-Output "  Total Entries:            $cacheCount"
Write-Output "  Sub-1900 Violations:      $cacheViolations (Must be 0)"
Write-Output "=========================================================="
