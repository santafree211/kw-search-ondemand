<#
.SYNOPSIS
    research_bulk_expand.ps1
    Responsibility: Expand seed keywords in chunked batches via Ubersuggest match_keywords.
    Token-Saving: Splits large seed lists into small batches (2-3 seeds), fetching up to 50 keywords per batch.
    Resilience: If quota exhaustion occurs mid-batch, preserves all retrieved data and saves to cache safely.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\store_api_archive.ps1"
. "$PSScriptRoot\store_api_query.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"

function Expand-BulkKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$SeedKeywords,

        [Parameter(Mandatory=$false)]
        [int]$BatchSize = 2,

        [Parameter(Mandatory=$false)]
        [int]$MaxBatches = 0,

        [Parameter(Mandatory=$false)]
        [int]$DelayMs = 500,

        [Parameter(Mandatory=$false)]
        [int]$MinVolume = 1900,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 100,

        [Parameter(Mandatory=$false)]
        [int]$LocId = 2392,

        [Parameter(Mandatory=$false)]
        [string]$Language = "ja",

        [Parameter(Mandatory=$false)]
        [string[]]$Excludes = @(),

        [Parameter(Mandatory=$false)]
        [string]$CachePath = "",

        [Parameter(Mandatory=$false)]
        [string]$MockJsonPath = "",

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $PSScriptRoot "..\data\verified_volume_cache.json"
    }

    # 1. Load existing cache
    $cacheObj = @{}
    if (Test-Path $CachePath) {
        try {
            $cRaw = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
            $parsed = $cRaw | ConvertFrom-Json
            if ($parsed -is [array]) {
                foreach ($item in $parsed) {
                    if ($item.Keyword -and $null -ne $item.Volume) {
                        $cacheObj[[string]$item.Keyword] = [int]$item.Volume
                    }
                }
            } elseif ($parsed.verified_volumes) {
                foreach ($prop in $parsed.verified_volumes.PSObject.Properties) {
                    $cacheObj[$prop.Name] = [int]$prop.Value
                }
            }
        } catch {}
    }

    # 2. Build exclude set
    $excludeSet = @{}
    foreach ($ex in $Excludes) {
        $t = $ex.Trim()
        if (-not [string]::IsNullOrWhiteSpace($t)) {
            $excludeSet[$t] = $true
        }
    }

    # 3. Chunk seed keywords into batches
    $cleanSeeds = @()
    foreach ($s in $SeedKeywords) {
        $st = $s.Trim()
        if (-not [string]::IsNullOrWhiteSpace($st)) {
            $cleanSeeds += $st
        }
    }

    if ($cleanSeeds.Count -eq 0) {
        return [PSCustomObject]@{
            Status = "EmptySeeds"
            TotalBatches = 0
            TotalFetched = 0
            PassedVolumeThreshold = 0
            EligibleCandidates = @()
            NewCacheEntries = 0
            TotalCachedNow = $cacheObj.Count
        }
    }

    if ($BatchSize -lt 1) { $BatchSize = 2 }

    $chunks = @()
    for ($i = 0; $i -lt $cleanSeeds.Count; $i += $BatchSize) {
        $end = [Math]::Min($i + $BatchSize, $cleanSeeds.Count)
        $chunk = @($cleanSeeds[$i..($end - 1)])
        $chunks += ,$chunk
    }

    $rawItems = @()
    $processedBatches = 0
    $isExhausted = $false
    $exhaustionError = ""

    # 4. Offline / Mock mode handling
    if (-not [string]::IsNullOrWhiteSpace($MockJsonPath) -and (Test-Path $MockJsonPath)) {
        $mockText = [System.IO.File]::ReadAllText($MockJsonPath, [System.Text.Encoding]::UTF8)
        $mJson = $mockText | ConvertFrom-Json
        if ($mJson -is [array]) {
            $rawItems = $mJson
        } elseif ($mJson.results) {
            $rawItems = $mJson.results
        } elseif ($mJson.keywords) {
            $rawItems = $mJson.keywords
        }
        $processedBatches = 1
    } elseif ($DryRun) {
        Write-Host "DryRun enabled: splitting $($cleanSeeds.Count) seeds into $($chunks.Count) batches (BatchSize: $BatchSize). Skipping API calls."
        return [PSCustomObject]@{
            Status = "DryRun"
            TotalBatches = $chunks.Count
            TotalFetched = 0
            PassedVolumeThreshold = 0
            EligibleCandidates = @()
            NewCacheEntries = 0
            TotalCachedNow = $cacheObj.Count
        }
    } else {
        # Remote execution setup
        $mcpConfig = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_config.ps1"
        $mcpAuth   = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_auth.ps1"
        $mcpApi    = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_api.ps1"

        if (-not ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi))) {
            throw "Ubersuggest MCP scripts not found."
        }

        . $mcpConfig
        . $mcpAuth
        . $mcpApi

        foreach ($chunk in $chunks) {
            $chunkKey = ($chunk -join "_")

            # 1. Check DB Cache first (0s instant reuse)
            $cachedArchive = Find-ApiArchive -Endpoint "match_keywords" -TargetKey $chunkKey
            if ($cachedArchive -and $cachedArchive.Data) {
                $inner = $cachedArchive.Data
                if ($inner -is [array]) { $rawItems += $inner }
                elseif ($inner.suggestions) { $rawItems += $inner.suggestions }
                elseif ($inner.results) { $rawItems += $inner.results }
                elseif ($inner.keywords) { $rawItems += $inner.keywords }
                if ($inner.searched_keywords) { $rawItems += $inner.searched_keywords }
                Write-Host "  [0s DB-Cache Hit] Match keywords for '$chunkKey' restored from SQLite archive."
                continue
            }

            # 2. Check if already queried in all-time history (duplicate prevention)
            $safeChunkKey = $chunkKey.Replace("'", "''")
            $dupMatchQuery = "SELECT 1 FROM api_call_logs WHERE endpoint = 'match_keywords' AND target_key = '$safeChunkKey' LIMIT 1;"
            $isMatchQueried = $false
            try {
                $mqRes = @(Invoke-SqliteQuery -SqlQuery $dupMatchQuery)
                if ($mqRes.Count -gt 0) { $isMatchQueried = $true }
            } catch {}

            if ($isMatchQueried) {
                Write-Host "  [Duplicate Prevented] Match keywords for '$chunkKey' already queried previously. Skipping API call."
                continue
            }

            $processedBatches++
            if ($MaxBatches -gt 0 -and $processedBatches -gt $MaxBatches) {
                Write-Host "Reached MaxBatches limit ($MaxBatches). Halting further batches."
                break
            }

            Write-Host "Executing Batch $processedBatches/$($chunks.Count): ($($chunk -join ', '))"

            $reqId = "bulk-" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
            $kwJsonArray = ($chunk | ConvertTo-Json -Compress)
            $reqPayload = '{"jsonrpc":"2.0","id":"' + $reqId + '","method":"tools/call","params":{"name":"match_keywords","arguments":{"keywords":' + $kwJsonArray + ',"limit":' + $Limit + ',"locId":' + $LocId + ',"language":"' + $Language + '","sortby":"-search_volume"}}}'

            $resJson = $null
            try {
                $resJson = Forward-RemoteMcp $reqPayload
            } catch {
                $resJson = $_.Exception.Message
            }

            if ([string]::IsNullOrWhiteSpace($resJson)) {
                Write-Warning "Batch $processedBatches returned empty response."
                continue
            }

            $parsedRes = $null
            try {
                $parsedRes = $resJson | ConvertFrom-Json
            } catch {}

            if ($null -ne $parsedRes -and $parsedRes.error) {
                Write-Warning "Batch $processedBatches RPC error: $($parsedRes.error.message)"
                if ($parsedRes.error.message -match "(?i)daily report.*limit|timed out|\b429\b|\b403\b") {
                    $isExhausted = $true
                    $exhaustionError = $parsedRes.error.message
                    break
                }
            } elseif ($null -eq $parsedRes -or -not $parsedRes.result) {
                if ($resJson -match "(?i)daily report.*limit|request timed out|temporarily unavailable|\b429\b|\b403\b") {
                    Write-Warning "API Quota Exhaustion or Timeout encountered on Batch $($processedBatches) - $resJson"
                    $isExhausted = $true
                    $exhaustionError = $resJson
                    break
                }
            }
            
            if ($null -ne $parsedRes -and $parsedRes.result -and $parsedRes.result.content) {
                foreach ($c in $parsedRes.result.content) {
                    if ($c.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($c.text)) {
                        if ($c.text -match "(?i)daily report.*limit|quota is exhausted|HTTP 429|HTTP 403") {
                            Write-Warning "API Quota Exhaustion encountered in response text: $($c.text)"
                            $isExhausted = $true
                            $exhaustionError = $c.text
                            break
                        }
                        $inner = $null
                        try {
                            $inner = $c.text | ConvertFrom-Json
                        } catch {}
                        if ($null -ne $inner) {
                            try {
                                Save-ApiArchive -Endpoint "match_keywords" -TargetKey ($chunk -join "_") -ResponseData $inner | Out-Null
                            } catch {}
                        }
                        if ($inner -is [array]) {
                            $rawItems += $inner
                        } elseif ($inner.suggestions) {
                            $rawItems += $inner.suggestions
                        } elseif ($inner.results) {
                            $rawItems += $inner.results
                        } elseif ($inner.keywords) {
                            $rawItems += $inner.keywords
                        }
                        if ($inner.searched_keywords) {
                            $rawItems += $inner.searched_keywords
                        }
                    }
                }
            }

            if ($isExhausted) { break }

            # Wait between batches to respect rate limits
            if ($DelayMs -gt 0 -and $processedBatches -lt $chunks.Count) {
                Start-Sleep -Milliseconds $DelayMs
            }
        }
    }

    # 5. Filter, separate Tier 1 & Tier 2, and update cache atomically
    $passedCandidates = @()
    $newCacheCount = 0
    $tier1Count = 0
    $longtailCount = 0
    $seenKws = @{}
    $sqlBatch = New-Object System.Collections.Generic.List[string]
    $sqlBatch.Add("BEGIN TRANSACTION;")

    foreach ($item in $rawItems) {
        $kw = $null
        $vol = 0
        $sd = 0
        $cpc = 0

        if ($item.keyword) { $kw = [string]$item.keyword }
        if ($null -ne $item.search_volume) { $vol = [int]$item.search_volume }
        elseif ($null -ne $item.volume) { $vol = [int]$item.volume }
        if ($null -ne $item.sd) { $sd = [int]$item.sd }
        if ($null -ne $item.cpc) { $cpc = [double]$item.cpc }

        if ([string]::IsNullOrWhiteSpace($kw)) { continue }
        $cleanKw = $kw.Trim()
        $escKw = $cleanKw.Replace("'", "''")

        # Deduplicate within current raw batch items
        if ($seenKws.ContainsKey($cleanKw)) { continue }
        $seenKws[$cleanKw] = $true

        # Automatically separate into Tier 1 (>= 1900) and Tier 2 (< 1900)
        if ($vol -ge $MinVolume) {
            $tier1Count++
            $sqlBatch.Add("INSERT OR REPLACE INTO verified_keywords (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'ubersuggest_bulk'); DELETE FROM longtail_keyword_pool WHERE keyword = '$escKw';")
            if (-not $cacheObj.ContainsKey($cleanKw) -or $cacheObj[$cleanKw] -ne $vol) {
                $cacheObj[$cleanKw] = $vol
                $newCacheCount++
            }
        } elseif ($vol -gt 0) {
            $longtailCount++
            $sqlBatch.Add("INSERT OR REPLACE INTO longtail_keyword_pool (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'ubersuggest_bulk');")
        }

        # Blacklist filtering (事前足切り: EC/物販/場所系はSERP調査前に即座に破棄)
        $isBlacklisted = $false
        $blacklistWords = @("売り場", "コーナー", "販売店", "どこで売ってる", "店舗", "サイズ", "カバー", "ケース", "通販", "楽天", "Amazon")
        foreach ($bw in $blacklistWords) {
            if ($cleanKw.IndexOf($bw, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $isBlacklisted = $true
                break
            }
        }
        if ($isBlacklisted) { continue }

        # Check volume threshold
        if ($vol -ge $MinVolume) {
            $isExcluded = $excludeSet.ContainsKey($cleanKw)
            $candObj = [PSCustomObject]@{
                Keyword = $cleanKw
                SearchVolume = $vol
                Sd = $sd
                IsExcluded = $isExcluded
            }

            if (-not $isExcluded) {
                $passedCandidates += $candObj
            }
        }
    }

    # Execute SQLite batch transaction
    $sqlBatch.Add("COMMIT;")
    try {
        $combinedSql = [string]::Join("`n", $sqlBatch)
        Invoke-SqliteNonQuery -SqlScript $combinedSql | Out-Null
    } catch {
        Write-Warning "SQLite batch insert error: $_"
    }

    # 6. Persist updated Tier 1 cache to disk (only volume >= 1900)
    if ($newCacheCount -gt 0) {
        $outList = @()
        foreach ($k in ($cacheObj.Keys | Sort-Object)) {
            if ($cacheObj[$k] -ge $MinVolume) {
                $outList += [PSCustomObject]@{
                    Keyword = $k
                    Volume = $cacheObj[$k]
                }
            }
        }
        $cacheOut = $outList | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($CachePath, $cacheOut, [System.Text.Encoding]::UTF8)
    }

    $finalStatus = if ($isExhausted) { "PartialExhausted" } else { "Success" }

    return [PSCustomObject]@{
        Status = $finalStatus
        IsExhausted = $isExhausted
        ExhaustionError = $exhaustionError
        TotalBatches = $chunks.Count
        BatchesProcessed = $processedBatches
        TotalFetched = $seenKws.Count
        FirstTierCount = $tier1Count
        LongtailCount = $longtailCount
        PassedVolumeThreshold = ($rawItems | Where-Object { 
            $v = if ($null -ne $_.search_volume) { [int]$_.search_volume } else { [int]$_.volume }
            $v -ge $MinVolume 
        }).Count
        EligibleCandidates = $passedCandidates
        NewCacheEntries = $newCacheCount
        TotalCachedNow = $cacheObj.Count
        ExhaustionEvidence = $exhaustionError
    }
}
