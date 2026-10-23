<#
.SYNOPSIS
    db_sync_from_json.ps1
    Responsibility: Complete migration and synchronization of keyword pools (Tier 1 Useful & Tier 2 Longtail).
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\db_sqlite_manager.ps1"

function Escape-SqlStr([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return $s.Replace("'", "''")
}

function Sync-JsonDataToDatabase {
    param([string]$DbPath = "")

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Initialize-ResearchDatabase
    } else {
        Initialize-ResearchDatabase -DbPath $DbPath | Out-Null
    }

    Write-Output "--- Starting Two-Tier Pool Migration & DB Sync ($DbPath) ---"

    # Step 1: Move existing sub-1900 volume keywords in SQLite from verified_keywords to longtail_keyword_pool
    $moveSql = @"
BEGIN TRANSACTION;
INSERT OR REPLACE INTO longtail_keyword_pool (keyword, volume, cpc, seo_difficulty, source, genre_id)
SELECT keyword, volume, cpc, seo_difficulty, source, genre_id FROM verified_keywords WHERE volume < 1900;
DELETE FROM verified_keywords WHERE volume < 1900;
COMMIT;
"@
    try {
        Invoke-SqliteNonQuery -SqlScript $moveSql -DbPath $DbPath | Out-Null
        Write-Output "Moved existing sub-1900 keywords from verified_keywords to longtail_keyword_pool."
    } catch {
        Write-Warning "Initial table migration error: $_"
    }

    # Step 2: Migrate and sanitize verified_volume_cache.json (Keeping only Vol >= 1900 in JSON)
    $volCachePath = Join-Path $PSScriptRoot "..\data\verified_volume_cache.json"
    $cleanTier1Cache = [ordered]@{}
    $tier1Count = 0
    $tier2Count = 0

    if (Test-Path $volCachePath) {
        $rawText = [System.IO.File]::ReadAllText($volCachePath, [System.Text.Encoding]::UTF8)
        $volList = $rawText | ConvertFrom-Json
        $sqlList = New-Object System.Collections.Generic.List[string]
        $sqlList.Add("BEGIN TRANSACTION;")
        $ignoredKeywords = @("Count", "Length", "LongLength", "Rank", "SyncRoot", "IsReadOnly", "IsFixedSize", "IsSynchronized")
        
        foreach ($item in $volList) {
            $kw = [string]$item.Keyword
            if ([string]::IsNullOrWhiteSpace($kw) -or $ignoredKeywords -contains $kw) { continue }
            if ($kw.StartsWith("sample-") -or $kw.Contains("?")) { continue }

            $vol = [int]$item.Volume
            if ($vol -le 0) { continue }

            $escKw = Escape-SqlStr $kw
            if ($vol -ge 1900) {
                $sqlList.Add("INSERT OR REPLACE INTO verified_keywords (keyword, volume) VALUES ('$escKw', $vol); DELETE FROM longtail_keyword_pool WHERE keyword = '$escKw';")
                $cleanTier1Cache[$kw] = $vol
                $tier1Count++
            } else {
                $sqlList.Add("INSERT OR REPLACE INTO longtail_keyword_pool (keyword, volume) VALUES ('$escKw', $vol);")
                $tier2Count++
            }
        }
        $sqlList.Add("COMMIT;")
        $combinedSql = [string]::Join("`n", $sqlList)
        Invoke-SqliteNonQuery -SqlScript $combinedSql -DbPath $DbPath | Out-Null
        Write-Output "Processed JSON cache: $tier1Count Tier-1 keywords, $tier2Count Tier-2 longtails."

        # Rewrite verified_volume_cache.json strictly with Tier 1
        $outList = @()
        foreach ($k in ($cleanTier1Cache.Keys | Sort-Object)) {
            $outList += [PSCustomObject]@{
                Keyword = $k
                Volume = $cleanTier1Cache[$k]
            }
        }
        $cacheOut = $outList | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($volCachePath, $cacheOut, [System.Text.Encoding]::UTF8)
        Write-Output "Sanitized verified_volume_cache.json: $($outList.Count) pure qualified (>=1900) entries."
    }

    # Step 3: Scan all historical raw API logs to harvest any uncollected longtails or top keywords
    $archiveDir = Join-Path $PSScriptRoot "..\data\raw_api_archive"
    $rawFilesCount = 0
    $harvestedRawKw = 0
    if (Test-Path $archiveDir) {
        $jsonFiles = Get-ChildItem -Path $archiveDir -Recurse -Filter "*.json" -File
        $rawFilesCount = $jsonFiles.Count
        Write-Output "Scanning $rawFilesCount raw API response archives for historical keywords..."
        
        $sqlBatch = New-Object System.Collections.Generic.List[string]
        $sqlBatch.Add("BEGIN TRANSACTION;")
        $batchItems = 0

        foreach ($file in $jsonFiles) {
            try {
                $fText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                $parsed = $fText | ConvertFrom-Json
                $items = @()
                if ($parsed -is [array]) { $items = $parsed }
                elseif ($parsed.keywords) { $items = $parsed.keywords }
                elseif ($parsed.suggestions) { $items = $parsed.suggestions }
                elseif ($parsed.results) { $items = $parsed.results }

                foreach ($it in $items) {
                    $k = [string]$it.keyword
                    if ([string]::IsNullOrWhiteSpace($k)) { continue }
                    $kClean = $k.Trim()
                    $v = 0
                    if ($null -ne $it.volume) { $v = [int]$it.volume }
                    elseif ($null -ne $it.search_volume) { $v = [int]$it.search_volume }

                    if ($v -gt 0) {
                        $escK = Escape-SqlStr $kClean
                        $sd = if ($null -ne $it.sd) { [int]$it.sd } else { 0 }
                        $cpc = if ($null -ne $it.cpc) { [double]$it.cpc } else { 0 }

                        if ($v -ge 1900) {
                            $sqlBatch.Add("INSERT OR IGNORE INTO verified_keywords (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escK', $v, $cpc, $sd, 'archive_sync');")
                        } else {
                            $sqlBatch.Add("INSERT OR IGNORE INTO longtail_keyword_pool (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escK', $v, $cpc, $sd, 'archive_sync');")
                        }
                        $batchItems++
                        $harvestedRawKw++

                        if ($batchItems -ge 1000) {
                            $sqlBatch.Add("COMMIT;")
                            Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $sqlBatch)) -DbPath $DbPath | Out-Null
                            $sqlBatch.Clear()
                            $sqlBatch.Add("BEGIN TRANSACTION;")
                            $batchItems = 0
                        }
                    }
                }
            } catch {}
        }
        if ($batchItems -gt 0) {
            $sqlBatch.Add("COMMIT;")
            Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $sqlBatch)) -DbPath $DbPath | Out-Null
        }
        Write-Output "Harvested and synchronized $harvestedRawKw keywords from $rawFilesCount historical JSON logs."
    }

    # Step 4: Migrate raw_api_archive/index.jsonl into api_call_logs
    $indexFile = Join-Path $PSScriptRoot "..\data\raw_api_archive\index.jsonl"
    $logCount = 0
    if (Test-Path $indexFile) {
        $lines = [System.IO.File]::ReadAllLines($indexFile, [System.Text.Encoding]::UTF8)
        $sqlList = New-Object System.Collections.Generic.List[string]
        $sqlList.Add("BEGIN TRANSACTION;")
        foreach ($line in $lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $entry = $line | ConvertFrom-Json
            $ts = [string]$entry.Timestamp
            $date = [string]$entry.Date
            $ep = [string]$entry.Endpoint
            $tk = Escape-SqlStr ([string]$entry.TargetKey)
            $rp = Escape-SqlStr ([string]$entry.RelativePath)
            $sqlList.Add("INSERT OR IGNORE INTO api_call_logs (timestamp, window_date, endpoint, target_key, raw_json_path) VALUES ('$ts', '$date', '$ep', '$tk', '$rp');")
            $logCount++
        }
        $sqlList.Add("COMMIT;")
        $combinedSql = [string]::Join("`n", $sqlList)
        Invoke-SqliteNonQuery -SqlScript $combinedSql -DbPath $DbPath | Out-Null
        Write-Output "Migrated $logCount API call entries into api_call_logs table."
    }

    # Step 5: Export all Tier 1 keywords from SQLite directly to verified_volume_cache.json
    $allTier1 = Invoke-SqliteQuery -SqlQuery "SELECT keyword, volume FROM verified_keywords ORDER BY keyword ASC;" -DbPath $DbPath
    $t1List = @()
    foreach ($row in $allTier1) {
        $t1List += [PSCustomObject]@{
            Keyword = $row.keyword
            Volume = [int]$row.volume
        }
    }
    $cacheOut = $t1List | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($volCachePath, $cacheOut, [System.Text.Encoding]::UTF8)
    Write-Output "Synchronized verified_volume_cache.json directly from SQLite: $($t1List.Count) pure qualified (>=1900) entries."

    # Step 6: Final Summary
    $tier1Final = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM verified_keywords;" -DbPath $DbPath)[0].cnt
    $tier2Final = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM longtail_keyword_pool;" -DbPath $DbPath)[0].cnt
    $apiFinal   = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM api_call_logs;" -DbPath $DbPath)[0].cnt

    Write-Output "`n================ MIGRATION COMPLETE SUMMARY ================"
    Write-Output "Tier 1 Qualified Keywords (Vol >= 1900): $tier1Final"
    Write-Output "Tier 2 Longtail Keyword Pool (Vol < 1900): $tier2Final"
    Write-Output "Cleaned JSON Cache (Vol >= 1900 only):    $($t1List.Count)"
    Write-Output "API Call Audit Log Entries:               $apiFinal"
    Write-Output "============================================================"

    return [PSCustomObject]@{
        Tier1Count = $tier1Final
        Tier2Count = $tier2Final
        JsonCacheCount = $cleanTier1Cache.Count
        ApiLogsCount = $apiFinal
    }
}

Sync-JsonDataToDatabase