<#
.SYNOPSIS
    tools/check_api_health.ps1
    Responsibility: Fast, lightweight single-call probe to verify Ubersuggest API connectivity.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ProbeKeyword = "健康 美容",

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"
if ($Json) { $WarningPreference = "SilentlyContinue" }

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$res = Invoke-SerpAnalysisRemote -TargetKeyword $ProbeKeyword
$sw.Stop()

$isHealthy = $false
$status = "DOWN"
$errorMsg = ""
$topCount = 0

if ($null -eq $res) {
    $errorMsg = "Empty response returned from API wrapper."
} elseif ($res.IsExhausted) {
    $errorMsg = $res.Error
    if ($errorMsg -match "401|Unauthorized|invalid_grant|OAuth authentication error|Token invalid") {
        $status = "AUTH_EXPIRED"
    }
} else {
    $parsed = Get-Top10OrganicEntries -TargetKeyword $ProbeKeyword -ResponseObj $res
    if ($parsed -and $parsed.Top10Organic -and $parsed.Top10Organic.Count -gt 0) {
        $isHealthy = $true
        $status = "ONLINE"
        $topCount = $parsed.Top10Organic.Count
    } else {
        $errorMsg = "API returned 200 OK but SERP entries were empty."
    }
}

$outputObj = [PSCustomObject]@{
    IsHealthy      = $isHealthy
    Status         = $status
    ResponseTimeMs = $sw.ElapsedMilliseconds
    ProbeKeyword   = $ProbeKeyword
    EntriesCount   = $topCount
    Error          = $errorMsg
    CheckedAtJst   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

if ($Json) {
    $outputObj | ConvertTo-Json
} else {
    Write-Output "=========================================================="
    Write-Output "=== UBERSUGGEST API HEALTH CHECK PROBE ==="
    Write-Output "=========================================================="
    Write-Output "Checked At     : $($outputObj.CheckedAtJst)"
    Write-Output "Status         : $($outputObj.Status)"
    Write-Output "Is Healthy     : $($outputObj.IsHealthy)"
    Write-Output "Response Time  : $($outputObj.ResponseTimeMs) ms"
    if ($isHealthy) {
        Write-Output "Entries Found  : $topCount organic results"
        Write-Output ">> API SERVER IS FULLY OPERATIONAL (ONLINE) <<"
    } elseif ($status -eq "AUTH_EXPIRED") {
        Write-Output "Failure Detail : $($outputObj.Error)"
        Write-Output ">> OAUTH TOKEN EXPIRED OR REVOKED (PLEASE UPDATE TOKEN) <<"
    } else {
        Write-Output "Failure Detail : $($outputObj.Error)"
        Write-Output ">> API SERVER IS CURRENTLY DOWN OR TIMING OUT <<"
    }
    Write-Output "=========================================================="
}
