<#
.SYNOPSIS
    serpapi_cache_store.ps1
    Single Responsibility: Check SerpApi cache, retrieve zero-cost stored SERPs, and save API responses to SQLite.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$PSScriptRoot\serpapi_usage_tracker.ps1"

function Get-SerpApiStoredResult {
    <#
    .SYNOPSIS
        Returns the latest stored Google SERP (SerpApi) for a keyword regardless of date. Zero API cost.
        Found=$false when no stored evidence exists.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword
    )

    $dbPathStored = Initialize-SerpApiDatabase
    $safeKwStored = $Keyword.Replace("'", "''")
    $normKwStored = ($Keyword -replace "[\s\u3000]+", " ").Trim().Replace("'", "''")
    $normKwNoSpace = ($Keyword -replace "[\s\u3000]+", "").Trim().Replace("'", "''")
    $sqlStored = "SELECT response_json, timestamp FROM serpapi_call_logs WHERE (keyword = '$safeKwStored' OR keyword = '$normKwStored' OR REPLACE(REPLACE(keyword, ' ', ''), '　', '') = '$normKwNoSpace') AND http_status = 200 AND response_json IS NOT NULL ORDER BY id DESC LIMIT 1;"
    try {
        $rowsStored = @(Invoke-SqliteQuery -SqlQuery $sqlStored -DbPath $dbPathStored)
        if ($rowsStored.Count -gt 0 -and $rowsStored[0].response_json) {
            $parsedStored = [string]$rowsStored[0].response_json | ConvertFrom-Json
            if ($parsedStored.organic_results) {
                return [PSCustomObject]@{
                    Keyword         = $Keyword
                    Found           = $true
                    IsExhausted     = $false
                    ExhaustionError = ""
                    OrganicResults  = @($parsedStored.organic_results)
                    FromCache       = $true
                    FetchedAt       = [string]$rowsStored[0].timestamp
                }
            }
        }
    } catch {}
    return [PSCustomObject]@{ Keyword = $Keyword; Found = $false; IsExhausted = $false; ExhaustionError = ""; OrganicResults = @(); FromCache = $true; FetchedAt = "" }
}

function Find-SerpApiWindowCache {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword
    )

    $dbPath = Initialize-SerpApiDatabase
    $safeKw = $Keyword.Replace("'", "''")
    $now = Get-Date
    $windowStart = if ($now.Hour -lt 9) {
        (Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0).AddDays(-1)
    } else {
        Get-Date -Year $now.Year -Month $now.Month -Day $now.Day -Hour 9 -Minute 0 -Second 0
    }
    $isoStart = $windowStart.ToString("yyyy-MM-ddTHH:mm:ss")
    $cacheSql = "SELECT response_json, organic_count, star_count FROM serpapi_call_logs WHERE keyword = '$safeKw' AND timestamp >= '$isoStart' ORDER BY id DESC LIMIT 1;"
    try {
        $cRows = @(Invoke-SqliteQuery -SqlQuery $cacheSql -DbPath $dbPath)
        if ($cRows.Count -gt 0 -and $cRows[0].response_json) {
            $cachedJson = [string]$cRows[0].response_json
            $parsedCache = $cachedJson | ConvertFrom-Json
            return [PSCustomObject]@{
                Found          = $true
                RawResponse    = $parsedCache
                OrganicResults = if ($parsedCache.organic_results) { @($parsedCache.organic_results) } else { @() }
            }
        }
    } catch {}

    return [PSCustomObject]@{
        Found          = $false
        RawResponse    = $null
        OrganicResults = @()
    }
}

function Save-SerpApiResponse {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$true)]
        [string]$Engine,

        [Parameter(Mandatory=$true)]
        [string]$Gl,

        [Parameter(Mandatory=$true)]
        [string]$Hl,

        [Parameter(Mandatory=$true)]
        [int]$HttpStatus,

        [Parameter(Mandatory=$true)]
        [int]$OrganicCount,

        [Parameter(Mandatory=$true)]
        [string]$ResponseJson
    )

    $dbPath = Initialize-SerpApiDatabase
    $safeKw = $Keyword.Replace("'", "''")
    $nowStr = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    $todayStr = (Get-Date).ToString("yyyy-MM-dd")
    $escJson = $ResponseJson.Replace("'", "''")

    $insSql = "INSERT INTO serpapi_call_logs (timestamp, window_date, keyword, engine, gl, hl, http_status, organic_count, star_count, response_json) VALUES ('$nowStr', '$todayStr', '$safeKw', '$Engine', '$Gl', '$Hl', $HttpStatus, $OrganicCount, 0, '$escJson');"
    try {
        Invoke-SqliteNonQuery -SqlScript $insSql -DbPath $dbPath | Out-Null
    } catch {
        Write-Verbose "Error saving serpapi log: $_"
    }
}
