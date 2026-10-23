<#
.SYNOPSIS
    research_serp_fetcher.ps1
    Responsibility: Parse and structure SERP top 10 organic entries from Ubersuggest serp_analysis output.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-Top10OrganicEntries {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetKeyword = "",

        [Parameter(Mandatory=$false)]
        $ResponseObj = $null,

        [Parameter(Mandatory=$false)]
        [string]$InputPath = ""
    )

    $rawEntries = @()

    if (-not [string]::IsNullOrWhiteSpace($InputPath) -and (Test-Path $InputPath)) {
        $jsonText = [System.IO.File]::ReadAllText($InputPath, [System.Text.Encoding]::UTF8)
        $parsed = $jsonText | ConvertFrom-Json
        if ($parsed.keyword -and [string]::IsNullOrWhiteSpace($TargetKeyword)) { $TargetKeyword = $parsed.keyword }
        if ($parsed.serpEntries) { $rawEntries = $parsed.serpEntries }
        elseif ($parsed -is [array]) { $rawEntries = $parsed }
    } elseif ($null -ne $ResponseObj) {
        if ($ResponseObj -is [string]) {
            $parsed = $ResponseObj | ConvertFrom-Json
            if ($parsed.serpEntries) { $rawEntries = $parsed.serpEntries }
            elseif ($parsed -is [array]) { $rawEntries = $parsed }
        } elseif ($ResponseObj.serpEntries) {
            $rawEntries = $ResponseObj.serpEntries
        } elseif ($ResponseObj -is [array]) {
            $rawEntries = $ResponseObj
        }
    }

    $top10 = @($rawEntries | Where-Object {
        $_.position -ge 1 -and $_.position -le 10 -and $_.type -eq "organic"
    } | ForEach-Object {
        [PSCustomObject]@{
            position = [int]$_.position
            type = [string]$_.type
            domain = ([string]$_.domain).ToLower()
            domainAuthority = [int]$_.domainAuthority
            url = [string]$_.url
            title = [string]$_.title
        }
    })

    return [PSCustomObject]@{
        Keyword = $TargetKeyword
        TotalEntries = $top10.Count
        Top10Organic = $top10
    }
}

. "$PSScriptRoot\store_api_archive.ps1"
. "$PSScriptRoot\store_api_query.ps1"

function Invoke-SerpAnalysisRemote {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TargetKeyword,

        [Parameter(Mandatory=$false)]
        [int]$LocId = 2392,

        [Parameter(Mandatory=$false)]
        [string]$Language = "ja",

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false,

        [Parameter(Mandatory=$false)]
        [switch]$ForceRefresh = $false
    )

    if ($DryRun) {
        Write-Output "DryRun enabled: skipping remote serp_analysis API call for '$TargetKeyword'."
        return $null
    }

    . "$PSScriptRoot\db_sqlite_manager.ps1"

    # 1. DB Cache Check (0 seconds instant reuse, 0 API calls)
    if (-not $ForceRefresh) {
        $cachedArch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $TargetKeyword
        if ($cachedArch -and $cachedArch.Data) {
            Write-Output "  [0s DB-Cache Hit] Reusing cached SERP for '$TargetKeyword' from SQLite archive."
            $cData = $cachedArch.Data
            $rawEntries = $null
            if ($cData.serpEntries) { $rawEntries = $cData.serpEntries }
            elseif ($cData.serp_table) { $rawEntries = $cData.serp_table }
            elseif ($cData.result -and $cData.result.serp_table) { $rawEntries = $cData.result.serp_table }
            elseif ($cData -is [array]) { $rawEntries = $cData }

            return [PSCustomObject]@{
                keyword = $TargetKeyword
                serpEntries = $rawEntries
                result = [PSCustomObject]@{
                    serp_table = $rawEntries
                }
                IsCached = $true
                IsExhausted = $false
            }
        }

        # 2. All-time duplicate check against api_call_logs
        $safeKw = $TargetKeyword.Replace("'", "''")
        $dupQuery = "SELECT 1 FROM api_call_logs WHERE endpoint = 'serp_analysis' AND target_key = '$safeKw' LIMIT 1;"
        $alreadyQueried = $false
        try {
            $dqRes = @(Invoke-SqliteQuery -SqlQuery $dupQuery)
            if ($dqRes.Count -gt 0) { $alreadyQueried = $true }
        } catch {}

        if ($alreadyQueried) {
            Write-Output "  [Duplicate Prevented] Target keyword '$TargetKeyword' was already queried previously. Skipping API call."
            return [PSCustomObject]@{
                keyword = $TargetKeyword
                serpEntries = $null
                IsDuplicate = $true
                IsExhausted = $false
            }
        }
    }

    $userProf = $env:USERPROFILE
    $mcpDir = Join-Path $userProf ".gemini\antigravity\mcp"
    $mcpConfig = Join-Path $mcpDir "ubersuggest_mcp_config.ps1"
    $mcpAuth   = Join-Path $mcpDir "ubersuggest_mcp_auth.ps1"
    $mcpApi    = Join-Path $mcpDir "ubersuggest_mcp_api.ps1"

    if (-not ((Test-Path $mcpConfig) -and (Test-Path $mcpAuth) -and (Test-Path $mcpApi))) {
        throw "Ubersuggest MCP scripts not found in $mcpDir."
    }

    . $mcpConfig
    . $mcpAuth
    . $mcpApi

    $reqId = "serp-" + [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $reqPayload = @{
        jsonrpc = "2.0"
        id = $reqId
        method = "tools/call"
        params = @{
            name = "serp_analysis"
            arguments = @{
                keyword = $TargetKeyword
                locId = $LocId
                language = $Language
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
        Write-Warning "serp_analysis returned empty response for '$TargetKeyword'."
        return $null
    }

    $parsedRes = $null
    try {
        $parsedRes = $resJson | ConvertFrom-Json
    } catch {}

    if ($null -ne $parsedRes -and $parsedRes.error) {
        Write-Warning "RPC Error for '$TargetKeyword': $($parsedRes.error.message)"
        return [PSCustomObject]@{
            Error = $parsedRes.error.message
            IsExhausted = ($parsedRes.error.message -match "(?i)daily report.*limit|timed out|\b429\b|\b403\b|\b401\b|unauthorized|oauth|token invalid")
        }
    }

    if (($null -eq $parsedRes -or -not $parsedRes.result) -and ($resJson -match "(?i)daily report.*limit|request timed out|temporarily unavailable|\b429\b|\b403\b|\b401\b|unauthorized|oauth")) {
        Write-Warning "API Quota Exhaustion, Auth Error, or Timeout encountered on '$TargetKeyword': $resJson"
        return [PSCustomObject]@{
            Error = $resJson
            IsExhausted = $true
        }
    }

    if ($parsedRes.result -and $parsedRes.result.isError) {
        $errText = ""
        if ($parsedRes.result.content) {
            $errText = ($parsedRes.result.content | ForEach-Object { $_.text }) -join " "
        }
        if ([string]::IsNullOrWhiteSpace($errText)) { $errText = $resJson }
        Write-Warning "Tool Execution Error for '$TargetKeyword': $errText"
        return [PSCustomObject]@{
            Error = $errText
            IsExhausted = ($errText -match "(?i)daily report.*limit|timed out|\b429\b|\b403\b|rate limited|temporarily unavailable")
        }
    }

    try {
        if ($parsedRes.result -and $parsedRes.result.content) {
            foreach ($c in $parsedRes.result.content) {
                if ($c.type -eq "text" -and -not [string]::IsNullOrWhiteSpace($c.text)) {
                    # Try parsing as valid SERP JSON first
                    $inner = $null
                    try {
                        $inner = $c.text | ConvertFrom-Json
                    } catch {}

                    if ($null -ne $inner) {
                        # If it contains serpEntries or organic results, it is a 100% valid response!
                        if ($inner.serpEntries -or ($inner.result -and $inner.result.serp_table) -or ($inner -is [array])) {
                            try {
                                Save-ApiArchive -Endpoint "serp_analysis" -TargetKey $TargetKeyword -ResponseData $inner | Out-Null
                            } catch {}
                            return $inner
                        }
                        # If inner object is an error message
                        if ($inner.error -or $inner.message) {
                            $msg = if ($inner.message) { $inner.message } else { $inner.error }
                            if ($msg -match "(?i)daily report.*limit|timed out|\b429\b|\b403\b|rate limited|temporarily unavailable") {
                                Write-Warning "API Exhaustion detected in JSON error for '$TargetKeyword': $msg"
                                return [PSCustomObject]@{
                                    Error = $msg
                                    IsExhausted = $true
                                }
                            }
                        }
                    }

                    # If not a valid SERP structure, check raw text for true exhaustion errors
                    if ($c.text -match "(?i)daily report.*limit|timed out|HTTP 429|HTTP 403|rate limited|temporarily unavailable") {
                        Write-Warning "API Exhaustion detected in content for '$TargetKeyword': $($c.text)"
                        return [PSCustomObject]@{
                            Error = $c.text
                            IsExhausted = $true
                        }
                    }

                    if ($null -ne $inner) {
                        return $inner
                    }
                }
            }
        }
    } catch {
        Write-Warning "Failed to parse serp_analysis response for '$TargetKeyword': $_"
        if ($resJson -match "(?i)daily report.*limit|timed out|HTTP 429|HTTP 403|rate limited|temporarily unavailable") {
            return [PSCustomObject]@{
                Error = $resJson
                IsExhausted = $true
            }
        }
    }

    return $null
}


