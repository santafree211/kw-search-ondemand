<#
.SYNOPSIS
    workflow/scripts/domain_da_measurer.ps1
    Responsibility: Real-time, on-demand measurement and verification of domain authority (DA)
                    using Ubersuggest domain_overview API.
                    Caches measured DAs in SQLite research.db (discovered_sites & raw_api_archive).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"

function Get-MeasuredDomainAuthority {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,

        [Parameter(Mandatory=$false)]
        [int]$MaxCacheAgeDays = 30,

        [Parameter(Mandatory=$false)]
        [switch]$ForceRefresh = $false
    )

    $cleanDomain = ($Domain -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', '').ToLower().Trim()
    if ([string]::IsNullOrWhiteSpace($cleanDomain)) {
        return $null
    }

    $dbPath = Initialize-ResearchDatabase

    # 1. Check local SQLite DB first (0s instant reuse if within MaxCacheAgeDays)
    if (-not $ForceRefresh) {
        try {
            $safeDom = $cleanDomain.Replace("'", "''")
            $sql = "SELECT da, discovered_at FROM discovered_sites WHERE domain = '$safeDom' AND da >= 1 LIMIT 1;"
            $rows = @(Invoke-SqliteQuery -SqlQuery $sql -DbPath $dbPath)
            if ($rows.Count -gt 0 -and $null -ne $rows[0].da) {
                $da = [int]$rows[0].da
                $updatedAtStr = [string]$rows[0].discovered_at
                $isFresh = $true
                if (-not [string]::IsNullOrWhiteSpace($updatedAtStr)) {
                    try {
                        $upDate = [DateTime]::Parse($updatedAtStr)
                        if ((Get-Date).Subtract($upDate).TotalDays -gt $MaxCacheAgeDays) {
                            $isFresh = $false
                        }
                    } catch {}
                }
                if ($isFresh) {
                    return [PSCustomObject]@{
                        Domain          = $cleanDomain
                        DomainAuthority = $da
                        Source          = "SQLite_Cache"
                        IsFresh         = $true
                        IsLowDa         = ($da -ge 1 -and $da -le 9)
                    }
                }
            }
        } catch {
            Write-Verbose "Error reading domain cache: $_"
        }
    }

    # 2. On-demand real-time measurement via Ubersuggest domain_overview API
    $userProf = $env:USERPROFILE
    $mcpDir = Join-Path $userProf ".gemini\antigravity\mcp"
    $mcpConfig = Join-Path $mcpDir "ubersuggest_mcp_config.ps1"
    $mcpAuth   = Join-Path $mcpDir "ubersuggest_mcp_auth.ps1"
    $mcpApi    = Join-Path $mcpDir "ubersuggest_mcp_api.ps1"

    if (-not ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi))) {
        Write-Warning "Ubersuggest MCP scripts not found in $mcpDir."
        return $null
    }

    . $mcpConfig
    . $mcpAuth
    . $mcpApi

    $reqId = "da-" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $reqPayload = @{
        jsonrpc = "2.0"
        id      = $reqId
        method  = "tools/call"
        params  = @{
            name      = "domain_overview"
            arguments = @{
                domain = $cleanDomain
            }
        }
    } | ConvertTo-Json -Compress

    $resJson = $null
    try {
        $resJson = Forward-RemoteMcp $reqPayload
    } catch {
        $resJson = $_.Exception.Message
    }

    if ([string]::IsNullOrWhiteSpace($resJson)) {
        return $null
    }

    $parsedRes = $null
    try {
        $parsedRes = $resJson | ConvertFrom-Json
    } catch {}

    $daValue = $null
    $rawText = ""

    if ($parsedRes) {
        if ($parsedRes.result -and $parsedRes.result.content) {
            foreach ($c in $parsedRes.result.content) {
                if ($c.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($c.text)) {
                    $rawText = $c.text
                    try {
                        $inner = $c.text | ConvertFrom-Json
                        if ($null -ne $inner.domainAuthority) {
                            $daValue = [int]$inner.domainAuthority
                            break
                        }
                    } catch {}
                }
            }
        }
        if ($null -eq $daValue -and $parsedRes.structuredContent) {
            if ($null -ne $parsedRes.structuredContent.domainAuthority) {
                $daValue = [int]$parsedRes.structuredContent.domainAuthority
            }
        }
        if ($null -eq $daValue -and $null -ne $parsedRes.domainAuthority) {
            $daValue = [int]$parsedRes.domainAuthority
        }
    }

    if ($null -ne $daValue) {
        # 3. Persist to SQLite discovered_sites
        try {
            $safeDom = $cleanDomain.Replace("'", "''")
            $nowIso = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $upsertSql = "INSERT INTO discovered_sites (domain, da, discovered_at) VALUES ('$safeDom', $daValue, '$nowIso') ON CONFLICT(domain) DO UPDATE SET da = excluded.da, discovered_at = excluded.discovered_at;"
            Invoke-SqliteNonQuery -SqlScript $upsertSql -DbPath $dbPath | Out-Null
        } catch {
            Write-Verbose "Error updating discovered_sites: $_"
        }

        return [PSCustomObject]@{
            Domain          = $cleanDomain
            DomainAuthority = $daValue
            Source          = "Ubersuggest_Live"
            IsFresh         = $true
            IsLowDa         = ($daValue -ge 1 -and $daValue -le 9)
        }
    }

    return $null
}

function Measure-SerpCandidateDomains {
    <#
    .SYNOPSIS
        Takes a list of candidate domains (from Google SERP Top 10) and measures unmeasured personal blogs in real time.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$CandidateDomains,

        [Parameter(Mandatory=$false)]
        [hashtable]$KnownPersonalBlogMap = $null
    )

    if ($null -eq $KnownPersonalBlogMap) {
        . "$PSScriptRoot\serpapi_evaluator.ps1"
        $KnownPersonalBlogMap = Get-KnownPersonalBlogDomainMap
    }

    $measuredResults = @{}

    foreach ($dom in $CandidateDomains) {
        $cDom = ($dom -replace '^https?://', '' -replace '/.*$', '' -replace '^www\.', '').ToLower().Trim()
        if ([string]::IsNullOrWhiteSpace($cDom)) { continue }

        if ($KnownPersonalBlogMap.ContainsKey($cDom)) {
            $measuredResults[$cDom] = [PSCustomObject]@{
                Domain          = $cDom
                DomainAuthority = [int]$KnownPersonalBlogMap[$cDom]
                Source          = "Known_Map"
                IsLowDa         = ($KnownPersonalBlogMap[$cDom] -ge 1 -and $KnownPersonalBlogMap[$cDom] -le 9)
            }
            continue
        }

        $liveRes = Get-MeasuredDomainAuthority -Domain $cDom
        if ($liveRes) {
            $measuredResults[$cDom] = $liveRes
            if ($liveRes.IsLowDa) {
                $KnownPersonalBlogMap[$cDom] = $liveRes.DomainAuthority
            }
        }
    }

    return [PSCustomObject]@{
        MeasuredMap = $measuredResults
        UpdatedKnownMap = $KnownPersonalBlogMap
    }
}
