<#
.SYNOPSIS
    research_volume_verifier.ps1
    Responsibility: Verify keyword search volume strictly against Ubersuggest API response.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\store_api_archive.ps1"

function Test-KeywordVolume {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetKeyword,

        [Parameter(Mandatory=$false)]
        $ResponseObj = $null,

        [Parameter(Mandatory=$false)]
        [string]$CachePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $PSScriptRoot "..\data\verified_volume_cache.json"
    }

    $volume = -1

    # 1. Extract search_volume from response object if provided
    if ($null -ne $ResponseObj) {
        if ($ResponseObj -is [string]) {
            $parsed = $ResponseObj | ConvertFrom-Json
            if ($parsed.search_volume -ne $null) { $volume = [int]$parsed.search_volume }
            elseif ($parsed.searchVolume -ne $null) { $volume = [int]$parsed.searchVolume }
        } elseif ($ResponseObj.search_volume -ne $null) {
            $volume = [int]$ResponseObj.search_volume
        } elseif ($ResponseObj.searchVolume -ne $null) {
            $volume = [int]$ResponseObj.searchVolume
        }
    }

    # 2. Check SQLite research.db first (Tier 1 then Tier 2), then JSON cache
    if ($volume -lt 0) {
        try {
            . "$PSScriptRoot\db_sqlite_manager.ps1"
            $escKw = $TargetKeyword.Replace("'", "''")
            $dbRes = Invoke-SqliteQuery -SqlQuery "SELECT volume FROM verified_keywords WHERE keyword = '$escKw' LIMIT 1;"
            if ($dbRes -and $dbRes.Count -gt 0 -and [int]$dbRes[0].volume -gt 0) {
                $volume = [int]$dbRes[0].volume
            } else {
                $ltRes = Invoke-SqliteQuery -SqlQuery "SELECT volume FROM longtail_keyword_pool WHERE keyword = '$escKw' LIMIT 1;"
                if ($ltRes -and $ltRes.Count -gt 0 -and [int]$ltRes[0].volume -gt 0) {
                    $volume = [int]$ltRes[0].volume
                }
            }
        } catch {}
    }

    if ($volume -lt 0 -and (Test-Path $CachePath)) {
        try {
            $cacheText = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
            $parsed = $cacheText | ConvertFrom-Json
            $cItems = @()
            if ($parsed -is [array]) {
                $cItems = $parsed
            } elseif ($parsed.SyncRoot) {
                $cItems = $parsed.SyncRoot
            }
            if ($cItems.Count -gt 0) {
                foreach ($item in $cItems) {
                    if ($item.Keyword -eq $TargetKeyword -and [int]$item.Volume -gt 0) {
                        $volume = [int]$item.Volume
                        break
                    }
                }
            } elseif ($parsed.verified_volumes) {
                $p = $parsed.verified_volumes.PSObject.Properties[$TargetKeyword]
                if ($null -ne $p -and [int]$p.Value -gt 0) {
                    $volume = [int]$p.Value
                }
            }
        } catch {}
    }

    # 3. Fallback: Query remote API via Forward-RemoteMcp if not cached
    if ($volume -lt 0) {
        $mcpConfig = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_config.ps1"
        $mcpAuth   = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_auth.ps1"
        $mcpApi    = "C:\Users\santa\.gemini\antigravity\mcp\ubersuggest_mcp_api.ps1"

        if ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi)) {
            try {
                . $mcpConfig
                . $mcpAuth
                . $mcpApi

                $reqId = "vol-" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
                $reqPayload = @{
                    jsonrpc = "2.0"
                    id = $reqId
                    method = "tools/call"
                    params = @{
                        name = "keyword_overview"
                        arguments = @{
                            keyword = $TargetKeyword
                            locId = 2392
                            language = "ja"
                        }
                    }
                } | ConvertTo-Json -Compress

                $resJson = Forward-RemoteMcp $reqPayload
                if (-not [string]::IsNullOrWhiteSpace($resJson)) {
                    $parsedRes = $resJson | ConvertFrom-Json
                    if ($parsedRes.result -and $parsedRes.result.content) {
                        foreach ($c in $parsedRes.result.content) {
                            if ($c.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($c.text)) {
                                $inner = $c.text | ConvertFrom-Json
                                if ($inner.search_volume -ne $null) { $volume = [int]$inner.search_volume }
                                elseif ($inner.volume -ne $null) { $volume = [int]$inner.volume }
                                if ($volume -ge 0) {
                                    try {
                                        Save-ApiArchive -Endpoint "keyword_overview" -TargetKey $TargetKeyword -ResponseData $inner | Out-Null
                                    } catch {}
                                    break
                                }
                            }
                        }
                    }
                }
            } catch {}
        }
    }

    if ($volume -lt 0) {
        throw "No verified search_volume found for '$TargetKeyword'. Manual/assumed volume is strictly prohibited."
    }

    # 3. Qualification: Volume must be >= 1900
    $passed = ($volume -ge 1900)

    # 4. Update cache if newly verified (Separate Tier 1 and Tier 2)
    try {
        . "$PSScriptRoot\db_sqlite_manager.ps1"
        $escKw = $TargetKeyword.Replace("'", "''")
        if ($volume -ge 1900) {
            Invoke-SqliteNonQuery -SqlScript "INSERT OR REPLACE INTO verified_keywords (keyword, volume) VALUES ('$escKw', $volume); DELETE FROM longtail_keyword_pool WHERE keyword = '$escKw';" | Out-Null
        } else {
            Invoke-SqliteNonQuery -SqlScript "INSERT OR REPLACE INTO longtail_keyword_pool (keyword, volume) VALUES ('$escKw', $volume);" | Out-Null
        }
    } catch {}

    # Update JSON cache ONLY for Tier 1 (Volume >= 1900)
    if ($volume -ge 1900 -and (Test-Path $CachePath)) {
        try {
            $cacheText = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
            $parsed = $cacheText | ConvertFrom-Json
            $dict = @{}
            if ($parsed -is [array]) {
                foreach ($item in $parsed) {
                    if ($item.Keyword -and [int]$item.Volume -ge 1900) { $dict[[string]$item.Keyword] = [int]$item.Volume }
                }
            } elseif ($parsed.verified_volumes) {
                foreach ($prop in $parsed.verified_volumes.PSObject.Properties) {
                    if ([int]$prop.Value -ge 1900) {
                        $dict[$prop.Name] = [int]$prop.Value
                    }
                }
            }

            if (-not $dict.ContainsKey($TargetKeyword) -or $dict[$TargetKeyword] -ne $volume) {
                $dict[$TargetKeyword] = $volume
                $outList = @()
                foreach ($k in ($dict.Keys | Sort-Object)) {
                    $outList += [PSCustomObject]@{
                        Keyword = $k
                        Volume = $dict[$k]
                    }
                }
                $newJson = $outList | ConvertTo-Json -Depth 5
                [System.IO.File]::WriteAllText($CachePath, $newJson, [System.Text.Encoding]::UTF8)
            }
        } catch {}
    }

    return [PSCustomObject]@{
        Keyword = $TargetKeyword
        SearchVolume = $volume
        Passed = $passed
        Reason = if ($passed) { "Volume >= 1900 qualification met." } else { "Volume ($volume) is below 1900." }
    }
}


