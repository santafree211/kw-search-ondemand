<#
.SYNOPSIS
    workflow/scripts/db_migrate_raw_archive.ps1
    Responsibility: Fully migrate all historical and today's raw API responses from filesystem (.json)
                    into SQLite research.db (raw_api_archive, serp_cache, serp_entries, discovered_sites, verified_keywords, longtail_keyword_pool).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"

function Escape-Sql([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return $s.Replace("'", "''")
}

function Invoke-RawArchiveMigration {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ArchiveBaseDir = "",

        [Parameter(Mandatory=$false)]
        [string]$DbPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        $DbPath = Initialize-ResearchDatabase
    } else {
        Initialize-ResearchDatabase -DbPath $DbPath | Out-Null
    }

    if ([string]::IsNullOrWhiteSpace($ArchiveBaseDir)) {
        $ArchiveBaseDir = Join-Path $PSScriptRoot "..\data\raw_api_archive"
    }

    if (-not (Test-Path $ArchiveBaseDir)) {
        throw "Archive directory not found: $ArchiveBaseDir"
    }

    Write-Host "=== Starting Full Raw API Archive Migration to SQLite DB ==="
    Write-Host "Database Path : $DbPath"
    Write-Host "Source Archive: $ArchiveBaseDir"

    $dateDirs = @(Get-ChildItem -Path $ArchiveBaseDir -Directory | Sort-Object Name)
    $totalFiles = 0
    $migratedResponses = 0
    $serpEntriesCount = 0
    $discoveredSitesCount = 0
    $keywordsHarvested = 0

    foreach ($d in $dateDirs) {
        $dateStr = $d.Name
        $jsonFiles = @(Get-ChildItem -Path $d.FullName -Filter "*.json" -File | Sort-Object Name)
        Write-Host "`nProcessing date: $dateStr ($($jsonFiles.Count) files)..."
        $totalFiles += $jsonFiles.Count

        $batchSql = New-Object System.Collections.Generic.List[string]
        $batchSql.Add("BEGIN TRANSACTION;")
        $batchCount = 0

        foreach ($file in $jsonFiles) {
            try {
                $rawText = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
                if ([string]::IsNullOrWhiteSpace($rawText)) { continue }

                $parsed = $rawText | ConvertFrom-Json
                $fName = $file.Name

                # Determine endpoint and target key
                $endpoint = ""
                $targetKey = ""

                if ($fName.StartsWith("serp_analysis_")) {
                    $endpoint = "serp_analysis"
                    $targetKey = $fName.Substring("serp_analysis_".Length)
                    $targetKey = $targetKey.Substring(0, $targetKey.Length - ".json".Length)
                    if ($parsed.keyword) { $targetKey = [string]$parsed.keyword }
                    elseif ($parsed.result -and $parsed.result.keyword) { $targetKey = [string]$parsed.result.keyword }
                } elseif ($fName.StartsWith("match_keywords_")) {
                    $endpoint = "match_keywords"
                    $targetKey = $fName.Substring("match_keywords_".Length)
                    $targetKey = $targetKey.Substring(0, $targetKey.Length - ".json".Length)
                } elseif ($fName.StartsWith("domain_keywords_")) {
                    $endpoint = "domain_keywords"
                    $targetKey = $fName.Substring("domain_keywords_".Length)
                    $targetKey = $targetKey.Substring(0, $targetKey.Length - ".json".Length)
                } elseif ($fName.StartsWith("keyword_overview_")) {
                    $endpoint = "keyword_overview"
                    $targetKey = $fName.Substring("keyword_overview_".Length)
                    $targetKey = $targetKey.Substring(0, $targetKey.Length - ".json".Length)
                    if ($parsed.keyword) { $targetKey = [string]$parsed.keyword }
                } else {
                    $endpoint = "other"
                    $targetKey = $file.BaseName
                }

                $targetKey = $targetKey.Trim()
                $escEp = Escape-Sql $endpoint
                $escKey = Escape-Sql $targetKey
                $escJson = Escape-Sql $rawText
                $fileTs = $file.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:sszzz")

                # 1. Insert into raw_api_archive
                $batchSql.Add("INSERT OR REPLACE INTO raw_api_archive (endpoint, target_key, date_string, response_json, created_at) VALUES ('$escEp', '$escKey', '$dateStr', '$escJson', '$fileTs');")
                $migratedResponses++
                $batchCount++

                # 2. Insert into api_call_logs
                $batchSql.Add("INSERT OR IGNORE INTO api_call_logs (timestamp, window_date, endpoint, target_key, raw_json_path) VALUES ('$fileTs', '$dateStr', '$escEp', '$escKey', 'sqlite:raw_api_archive');")
                $batchCount++

                # 3. If serp_analysis, update serp_cache
                if ($endpoint -eq "serp_analysis") {
                    $batchSql.Add("INSERT OR REPLACE INTO serp_cache (keyword, search_date, raw_json_path) VALUES ('$escKey', '$dateStr', 'sqlite:raw_api_archive');")
                    $batchCount++
                }

                # Flush batch periodically
                if ($batchCount -ge 200) {
                    $batchSql.Add("COMMIT;")
                    Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $batchSql)) -DbPath $DbPath | Out-Null
                    $batchSql.Clear()
                    $batchSql.Add("BEGIN TRANSACTION;")
                    $batchCount = 0
                }
            } catch {
                Write-Warning "Error processing file $($file.FullName): $_"
            }
        }

        if ($batchCount -gt 0) {
            $batchSql.Add("COMMIT;")
            Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $batchSql)) -DbPath $DbPath | Out-Null
        }
    }

    Write-Host "`nRaw responses inserted into raw_api_archive: $migratedResponses"

    # Step 2: Populate serp_entries and discovered_sites from all serp_analysis in raw_api_archive
    Write-Host "`nPopulating serp_entries and discovered_sites from SERP raw responses..."
    $serpArchives = Invoke-SqliteQuery -SqlQuery "SELECT id, target_key, date_string, response_json FROM raw_api_archive WHERE endpoint = 'serp_analysis';" -DbPath $DbPath
    
    $serpBatch = New-Object System.Collections.Generic.List[string]
    $serpBatch.Add("BEGIN TRANSACTION;")
    $sBatchCount = 0

    foreach ($sa in $serpArchives) {
        try {
            $kw = [string]$sa.target_key
            $dStr = [string]$sa.date_string
            $escK = Escape-Sql $kw

            # Lookup serp_id
            $scRows = Invoke-SqliteQuery -SqlQuery "SELECT id FROM serp_cache WHERE keyword = '$escK' AND search_date = '$dStr' LIMIT 1;" -DbPath $DbPath
            if (-not $scRows -or $scRows.Count -eq 0) { continue }
            $serpId = [int]$scRows[0].id

            $pObj = $sa.response_json | ConvertFrom-Json
            $entries = $pObj.serpEntries
            if (-not $entries -and $pObj.result -and $pObj.result.serp_table) {
                $entries = $pObj.result.serp_table
            }

            if ($entries -and $entries.Count -gt 0) {
                $serpBatch.Add("DELETE FROM serp_entries WHERE serp_id = $serpId;")
                $pos = 1
                foreach ($e in $entries) {
                    $pNum = if ($null -ne $e.position) { [int]$e.position } else { $pos }
                    $dom = [string]$e.domain
                    $u = [string]$e.url
                    if ([string]::IsNullOrWhiteSpace($dom) -and -not [string]::IsNullOrWhiteSpace($u)) {
                        try { $dom = ([System.Uri]$u).Host.ToLower() } catch {}
                    }
                    $da = 0
                    if ($null -ne $e.domainAuthority) { $da = [int]$e.domainAuthority }
                    elseif ($null -ne $e.domain_authority) { $da = [int]$e.domain_authority }

                    $clicks = 0
                    if ($null -ne $e.clicks) { $clicks = [int]$e.clicks }

                    $isUgc = 0
                    $isPureLow = 0
                    if (-not [string]::IsNullOrWhiteSpace($dom)) {
                        $ugcTest = Test-WeakCompetitorMale -Domain $dom -Url $u
                        if ($ugcTest.IsWeakCompetitor) {
                            $isUgc = 1
                        } elseif ($da -ge 1 -and $da -le 9) {
                            $isPureLow = 1
                        }
                    }

                    $escDom = Escape-Sql $dom
                    $escU = Escape-Sql $u

                    $serpBatch.Add("INSERT INTO serp_entries (serp_id, keyword, position, domain, url, domain_authority, is_weak_ugc, is_pure_low_da, clicks) VALUES ($serpId, '$escK', $pNum, '$escDom', '$escU', $da, $isUgc, $isPureLow, $clicks);")
                    $serpEntriesCount++
                    $sBatchCount++

                    if ($isPureLow -eq 1 -and -not [string]::IsNullOrWhiteSpace($dom)) {
                        $serpBatch.Add("INSERT OR IGNORE INTO discovered_sites (domain, url, da, site_type, status, discovered_from_kw) VALUES ('$escDom', '$escU', $da, 'personal_blog', 'candidate', '$escK');")
                        $discoveredSitesCount++
                        $sBatchCount++
                    }
                    $pos++
                }

                if ($sBatchCount -ge 500) {
                    $serpBatch.Add("COMMIT;")
                    Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $serpBatch)) -DbPath $DbPath | Out-Null
                    $serpBatch.Clear()
                    $serpBatch.Add("BEGIN TRANSACTION;")
                    $sBatchCount = 0
                }
            }
        } catch {}
    }

    if ($sBatchCount -gt 0) {
        $serpBatch.Add("COMMIT;")
        Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $serpBatch)) -DbPath $DbPath | Out-Null
    }

    # Step 3: Harvest and synchronize all keywords from match_keywords and domain_keywords into keyword pools
    Write-Host "`nHarvesting keywords and volumes from match_keywords and domain_keywords..."
    $kwArchives = Invoke-SqliteQuery -SqlQuery "SELECT endpoint, response_json FROM raw_api_archive WHERE endpoint IN ('match_keywords', 'domain_keywords');" -DbPath $DbPath

    $kwBatch = New-Object System.Collections.Generic.List[string]
    $kwBatch.Add("BEGIN TRANSACTION;")
    $kBatchCount = 0

    foreach ($ka in $kwArchives) {
        try {
            $pObj = $ka.response_json | ConvertFrom-Json
            $items = @()
            if ($pObj -is [array]) { $items = $pObj }
            elseif ($pObj.keywords) { $items = $pObj.keywords }
            elseif ($pObj.suggestions) { $items = $pObj.suggestions }
            elseif ($pObj.results) { $items = $pObj.results }
            elseif ($pObj.result -and $pObj.result.keywords) { $items = $pObj.result.keywords }

            foreach ($it in $items) {
                $kwName = [string]$it.keyword
                if ([string]::IsNullOrWhiteSpace($kwName)) { continue }
                $kwClean = $kwName.Trim()

                $vol = 0
                if ($null -ne $it.volume) { $vol = [int]$it.volume }
                elseif ($null -ne $it.search_volume) { $vol = [int]$it.search_volume }

                if ($vol -gt 0) {
                    $escKw = Escape-Sql $kwClean
                    $cpc = if ($null -ne $it.cpc) { [double]$it.cpc } else { 0 }
                    $sd = if ($null -ne $it.sd) { [int]$it.sd } else { 0 }

                    if ($vol -ge 1900) {
                        $kwBatch.Add("INSERT OR IGNORE INTO verified_keywords (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'archive_sync');")
                    } else {
                        $kwBatch.Add("INSERT OR IGNORE INTO longtail_keyword_pool (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'archive_sync');")
                    }
                    $keywordsHarvested++
                    $kBatchCount++

                    if ($kBatchCount -ge 500) {
                        $kwBatch.Add("COMMIT;")
                        Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $kwBatch)) -DbPath $DbPath | Out-Null
                        $kwBatch.Clear()
                        $kwBatch.Add("BEGIN TRANSACTION;")
                        $kBatchCount = 0
                    }
                }
            }
        } catch {}
    }

    if ($kBatchCount -gt 0) {
        $kwBatch.Add("COMMIT;")
        Invoke-SqliteNonQuery -SqlScript ([string]::Join("`n", $kwBatch)) -DbPath $DbPath | Out-Null
    }

    # Step 4: Final verification and summary
    $finalRaw = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM raw_api_archive;" -DbPath $DbPath)[0].cnt
    $finalSerpCache = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM serp_cache;" -DbPath $DbPath)[0].cnt
    $finalSerpEntries = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM serp_entries;" -DbPath $DbPath)[0].cnt
    $finalDiscovered = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM discovered_sites;" -DbPath $DbPath)[0].cnt
    $finalTier1 = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM verified_keywords;" -DbPath $DbPath)[0].cnt
    $finalTier2 = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM longtail_keyword_pool;" -DbPath $DbPath)[0].cnt
    $finalLogs = (Invoke-SqliteQuery -SqlQuery "SELECT COUNT(*) as cnt FROM api_call_logs;" -DbPath $DbPath)[0].cnt

    Write-Host "`n============================================================"
    Write-Host "=== RAW API ARCHIVE TO SQLITE MIGRATION COMPLETED ==="
    Write-Host "============================================================"
    Write-Host "Files Processed           : $totalFiles"
    Write-Host "Raw API Archive Rows      : $finalRaw"
    Write-Host "SERP Cache Rows           : $finalSerpCache"
    Write-Host "SERP Entries Rows (Top 10): $finalSerpEntries"
    Write-Host "Discovered Sites (DA 1-9) : $finalDiscovered"
    Write-Host "Tier 1 Keywords (>= 1900) : $finalTier1"
    Write-Host "Tier 2 Longtails (< 1900) : $finalTier2"
    Write-Host "API Call Audit Logs       : $finalLogs"
    Write-Host "============================================================"

    return [PSCustomObject]@{
        Success = $true
        FilesProcessed = $totalFiles
        RawArchiveCount = $finalRaw
        SerpCacheCount = $finalSerpCache
        SerpEntriesCount = $finalSerpEntries
        DiscoveredSitesCount = $finalDiscovered
        Tier1KeywordsCount = $finalTier1
        Tier2LongtailCount = $finalTier2
        ApiLogsCount = $finalLogs
    }
}

if ($MyInvocation.InvocationName -ne '.' -and $MyInvocation.Line -notmatch '\. ') {
    Invoke-RawArchiveMigration
}
