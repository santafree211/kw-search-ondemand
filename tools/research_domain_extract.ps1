<#
.SYNOPSIS
    tools\research_domain_extract.ps1
    Agent Dedicated CLI Tool: Single-call bulk domain keyword extraction.
    Usage:
        powershell -ExecutionPolicy Bypass -File tools\research_domain_extract.ps1 -Domain "example.com"
        powershell -ExecutionPolicy Bypass -File tools\research_domain_extract.ps1 -Domain "example.com" -DryRun
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Domain,

    [Parameter(Mandatory=$false)]
    [int]$MinVolume = 1900,

    [Parameter(Mandatory=$false)]
    [int]$MaxPosition = 10,

    [Parameter(Mandatory=$false)]
    [int]$Limit = 1000,

    [Parameter(Mandatory=$false)]
    [string[]]$Excludes = @(),

    [Parameter(Mandatory=$false)]
    [string]$MockJsonPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $scriptDir "..\workflow\scripts\research_domain_extract.ps1"

if (-not (Test-Path $libPath)) {
    Write-Error "Required module not found: $libPath"
    exit 1
}

. $libPath

try {
    $res = Extract-DomainKeywords -Domain $Domain -MinVolume $MinVolume -MaxPosition $MaxPosition -Limit $Limit -Excludes $Excludes -MockJsonPath $MockJsonPath -DryRun:$DryRun
    
    Write-Output "================ DOMAIN EXTRACTION SUMMARY ================"
    Write-Output "Status:                     $($res.Status)"
    Write-Output "Domain:                     $($res.Domain)"
    Write-Output "Total Keywords Fetched:     $($res.TotalFetched) (via 1 API call, Limit=$Limit)"
    Write-Output "Tier 1 Qualified (>= $MinVolume): $($res.FirstTierCount)"
    Write-Output "Tier 2 Longtail (< $MinVolume):   $($res.LongtailCount)"
    Write-Output "Passed Conditions (Top 10): $($res.PassedConditions)"
    Write-Output "Eligible (Unregistered):    $($res.WinningKeywords.Count)"
    Write-Output "New Cache Entries:          $($res.NewCacheEntries)"
    Write-Output "Total Cache Size:           $($res.TotalCachedNow)"
    Write-Output "==========================================================="
    
    if ($res.WinningKeywords.Count -gt 0) {
        Write-Output "`n--- Top Winning Keywords for Domain ---"
        foreach ($k in $res.WinningKeywords) {
            Write-Output "  * $($k.Keyword) [Vol: $($k.SearchVolume), Pos: $($k.Position), URL: $($k.Url)]"
        }
    }
} catch {
    Write-Error "Domain extraction failed: $_"
    exit 1
}
