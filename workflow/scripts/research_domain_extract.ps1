<#
.SYNOPSIS
    research_domain_extract.ps1
    Responsibility: Extract all winning keywords and volumes from a specific domain in bulk.
    Token-Saving: Extracts up to 50 keywords + search volumes for a domain in a single API call.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\store_api_archive.ps1"
. "$PSScriptRoot\store_api_query.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"

function Extract-DomainKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,

        [Parameter(Mandatory=$false)]
        [int]$MinVolume = 1900,

        [Parameter(Mandatory=$false)]
        [int]$MaxPosition = 10,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 1000,

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

    # 1. Load existing volume cache
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

    # 2.5 Check DB cache first (0s instant reuse, 0 API quota consumption)
    $cachedData = Find-ApiArchive -Endpoint "domain_keywords" -TargetKey $Domain
    if ($cachedData -and $cachedData.Data) {
        $cData = $cachedData.Data
        if ($cData -is [array]) {
            $rawItems = $cData
        } elseif ($cData.keywords) {
            $rawItems = $cData.keywords
        }
        if ($rawItems.Count -gt 0) {
            Write-Output "  [0s DB-Cache Hit] Domain keywords for '$Domain' restored from SQLite archive ($($rawItems.Count) items)."
        }
    }

    # 3. Obtain domain keyword data
    if ($rawItems.Count -gt 0) {
        # Already restored from cache
    } elseif (-not [string]::IsNullOrWhiteSpace($MockJsonPath) -and (Test-Path $MockJsonPath)) {
        # Offline / Test mode from mock file
        $mockText = [System.IO.File]::ReadAllText($MockJsonPath, [System.Text.Encoding]::UTF8)
        $mJson = $mockText | ConvertFrom-Json
        if ($mJson -is [array]) {
            $rawItems = $mJson
        } elseif ($mJson.keywords) {
            $rawItems = $mJson.keywords
        }
    } elseif ($DryRun) {
        Write-Output "DryRun enabled: skipping API call."
        return [PSCustomObject]@{
            Status = "DryRun"
            Domain = $Domain
            WinningKeywords = @()
            TotalFetched = 0
            PassedCount = 0
            NewCacheEntries = 0
        }
    } else {
        # Duplicate call prevention: check if domain was already queried in all-time history
        $safeDom = $Domain.Replace("'", "''")
        $dupQuery = "SELECT 1 FROM api_call_logs WHERE endpoint = 'domain_keywords' AND target_key = '$safeDom' LIMIT 1;"
        $isAlreadyQueried = $false
        try {
            $dqRes = @(Invoke-SqliteQuery -SqlQuery $dupQuery)
            if ($dqRes.Count -gt 0) { $isAlreadyQueried = $true }
        } catch {}

        if ($isAlreadyQueried) {
            Write-Output "  [Duplicate Prevented] Domain '$Domain' was already queried previously. Skipping API call."
            return [PSCustomObject]@{
                Status = "AlreadyQueried"
                Domain = $Domain
                WinningKeywords = @()
                TotalFetched = 0
                PassedCount = 0
                NewCacheEntries = 0
            }
        }

        # Call remote Ubersuggest API via Forward-RemoteMcp
        $mcpConfig = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_config.ps1"
        $mcpAuth   = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_auth.ps1"
        $mcpApi    = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_api.ps1"

        if ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi)) {
            . $mcpConfig
            . $mcpAuth
            . $mcpApi

            $reqId = "domain-" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
            $reqPayload = @{
                jsonrpc = "2.0"
                id = $reqId
                method = "tools/call"
                params = @{
                    name = "domain_keywords"
                    arguments = @{
                        domain = $Domain
                        limit = $Limit
                        locId = $LocId
                        language = $Language
                        searchType = "organic"
                    }
                }
            } | ConvertTo-Json -Compress

            $resJson = Forward-RemoteMcp $reqPayload

            if ([string]::IsNullOrWhiteSpace($resJson)) {
                throw "Remote Ubersuggest API returned empty response."
            }

            $parsedRes = $null
            try {
                $parsedRes = $resJson | ConvertFrom-Json
            } catch {}

            if ($null -ne $parsedRes -and $parsedRes.error) {
                throw "RPC Error: $($parsedRes.error.message)"
            }

            if (($null -eq $parsedRes -or -not $parsedRes.result) -and ($resJson -match "(?i)daily report.*limit|request timed out|temporarily unavailable|\b429\b|\b403\b")) {
                throw "API Error: $resJson"
            }

            if ($parsedRes.result -and $parsedRes.result.content) {
                foreach ($c in $parsedRes.result.content) {
                    if ($c.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($c.text)) {
                        $inner = $c.text | ConvertFrom-Json
                        if ($null -ne $inner) {
                            try {
                                Save-ApiArchive -Endpoint "domain_keywords" -TargetKey $Domain -ResponseData $inner | Out-Null
                            } catch {}
                        }
                        if ($inner -is [array]) {
                            $rawItems += $inner
                        } elseif ($inner.keywords) {
                            $rawItems += $inner.keywords
                        }
                    }
                }
            }
        } else {
            throw "Ubersuggest MCP scripts not found."
        }
    }

    # 4. Filter volume >= MinVolume and position <= MaxPosition, separate Tier 1 & Tier 2
    $winningKws = @()
    $newCacheCount = 0
    $tier1Count = 0
    $longtailCount = 0
    $sqlBatch = New-Object System.Collections.Generic.List[string]
    $sqlBatch.Add("BEGIN TRANSACTION;")

    foreach ($item in $rawItems) {
        $kw = $null
        $vol = 0
        $pos = 999
        $sd = 0
        $cpc = 0
        $url = ""

        if ($item.keyword) { $kw = [string]$item.keyword }
        if ($null -ne $item.volume) { $vol = [int]$item.volume }
        elseif ($null -ne $item.search_volume) { $vol = [int]$item.search_volume }
        if ($null -ne $item.position) { $pos = [int]$item.position }
        if ($null -ne $item.sd) { $sd = [int]$item.sd }
        if ($null -ne $item.cpc) { $cpc = [double]$item.cpc }
        if ($null -ne $item.url) { $url = [string]$item.url }

        if ([string]::IsNullOrWhiteSpace($kw)) { continue }
        $cleanKw = $kw.Trim()
        $escKw = $cleanKw.Replace("'", "''")

        # Automatically separate into Tier 1 (>= 1900) and Tier 2 (< 1900)
        if ($vol -ge $MinVolume) {
            $tier1Count++
            $sqlBatch.Add("INSERT OR REPLACE INTO verified_keywords (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'ubersuggest_domain'); DELETE FROM longtail_keyword_pool WHERE keyword = '$escKw';")
            if (-not $cacheObj.ContainsKey($cleanKw) -or $cacheObj[$cleanKw] -ne $vol) {
                $cacheObj[$cleanKw] = $vol
                $newCacheCount++
            }
        } elseif ($vol -gt 0) {
            $longtailCount++
            $sqlBatch.Add("INSERT OR REPLACE INTO longtail_keyword_pool (keyword, volume, cpc, seo_difficulty, source) VALUES ('$escKw', $vol, $cpc, $sd, 'ubersuggest_domain');")
        }

        # Check volume threshold and top 10 position for winning candidate
        if ($vol -ge $MinVolume -and $pos -le $MaxPosition) {
            $isExcluded = $excludeSet.ContainsKey($cleanKw)
            $kwObj = [PSCustomObject]@{
                Keyword = $cleanKw
                SearchVolume = $vol
                Position = $pos
                Sd = $sd
                Url = $url
                IsExcluded = $isExcluded
            }

            if (-not $isExcluded) {
                $winningKws += $kwObj
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

    # 5. Persist updated Tier 1 cache to disk (Standard array format, only volume >= 1900)
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

    return [PSCustomObject]@{
        Status = "Success"
        Domain = $Domain
        TotalFetched = $rawItems.Count
        FirstTierCount = $tier1Count
        LongtailCount = $longtailCount
        PassedConditions = ($rawItems | Where-Object {
            $v = if ($null -ne $_.volume) { [int]$_.volume } else { [int]$_.search_volume }
            $p = [int]$_.position
            ($v -ge $MinVolume) -and ($p -le $MaxPosition)
        }).Count
        WinningKeywords = $winningKws
        NewCacheEntries = $newCacheCount
        TotalCachedNow = $cacheObj.Count
    }
}
