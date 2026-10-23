<#
.SYNOPSIS
    tools\research_bulk_expand.ps1
    Agent Dedicated CLI Tool: Chunked bulk keyword expansion with auto-volume validation.
    Usage:
        powershell -ExecutionPolicy Bypass -File tools\research_bulk_expand.ps1 -SeedKeywords @('DIY', 'Craft', 'Recipe') -BatchSize 2
        powershell -ExecutionPolicy Bypass -File tools\research_bulk_expand.ps1 -SeedKeywords @('DIY', 'Craft') -DryRun
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
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
    [int]$Limit = 50,

    [Parameter(Mandatory=$false)]
    [string[]]$Excludes = @(),

    [Parameter(Mandatory=$false)]
    [string]$MockJsonPath = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libPath = Join-Path $scriptDir "..\workflow\scripts\research_bulk_expand.ps1"

if (-not (Test-Path $libPath)) {
    Write-Error "Required module not found: $libPath"
    exit 1
}

. $libPath

$cleanSeeds = @()
foreach ($s in $SeedKeywords) {
    if ($s.Contains(",")) {
        $cleanSeeds += ($s -split ",")
    } else {
        $cleanSeeds += $s
    }
}
$SeedKeywords = @($cleanSeeds | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

try {
    $res = Expand-BulkKeywords -SeedKeywords $SeedKeywords -BatchSize $BatchSize -MaxBatches $MaxBatches -DelayMs $DelayMs -MinVolume $MinVolume -Limit $Limit -Excludes $Excludes -MockJsonPath $MockJsonPath -DryRun:$DryRun
    
    Write-Output "================ CHUNKED BULK EXPANSION SUMMARY ================"
    Write-Output "Status:                   $($res.Status)"
    Write-Output "Total Seed Batches:       $($res.TotalBatches) (BatchSize: $BatchSize)"
    Write-Output "Batches Processed:        $($res.BatchesProcessed)"
    Write-Output "Total Keywords Fetched:   $($res.TotalFetched)"
    Write-Output "Passed Volume (>= $MinVolume): $($res.PassedVolumeThreshold)"
    Write-Output "Eligible (Unregistered):  $($res.EligibleCandidates.Count)"
    Write-Output "New Cache Entries:        $($res.NewCacheEntries)"
    Write-Output "Total Cache Size:         $($res.TotalCachedNow)"
    if ($res.Status -eq "PartialExhausted") {
        Write-Output "Exhaustion Evidence:      $($res.ExhaustionEvidence)"
    }
    Write-Output "================================================================="
    
    if ($res.EligibleCandidates.Count -gt 0) {
        Write-Output "`n--- Top Eligible Winning KW Candidates ---"
        foreach ($c in $res.EligibleCandidates) {
            Write-Output "  * $($c.Keyword) [Vol: $($c.SearchVolume), SD: $($c.Sd)]"
        }
    }
} catch {
    Write-Error "Chunked bulk expansion failed: $_"
    exit 1
}
