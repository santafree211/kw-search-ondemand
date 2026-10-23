<#
.SYNOPSIS
    tools/watch_and_run_pipeline.ps1
    Responsibility: Poll Ubersuggest API health every 30 minutes (low load).
    As soon as API comes ONLINE, immediately launch the unified balanced pipeline to research up to daily quota limit.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$IntervalSeconds = 1800,

    [Parameter(Mandatory=$false)]
    [int]$MaxChecks = 26
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$healthProbeScript = Join-Path $PSScriptRoot "check_api_health.ps1"
$pipelineScript = Join-Path $PSScriptRoot "run_unified_balanced_pipeline.ps1"

Write-Output "=========================================================="
Write-Output "=== UBERSUGGEST API WATCHER & AUTO-PIPELINE LAUNCHER ==="
Write-Output "=========================================================="
Write-Output "Poll Interval: $IntervalSeconds seconds (30 mins)"
Write-Output "Max Checks   : $MaxChecks checks (~13 hours)"

$checkCount = 0
$isOnline = $false

while ($checkCount -lt $MaxChecks -and -not $isOnline) {
    $checkCount++
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Output "`n[$nowStr] [Probe #$checkCount/$MaxChecks] Checking Ubersuggest API status..."

    try {
        $rawJson = & powershell -ExecutionPolicy Bypass -File $healthProbeScript -Json
        $probeRes = $rawJson | ConvertFrom-Json
        if ($probeRes.IsHealthy) {
            Write-Output ">>> API IS ONLINE! Latency: $($probeRes.ResponseTimeMs) ms, Entries: $($probeRes.EntriesCount) <<<"
            $isOnline = $true
            break
        } else {
            Write-Output "API is still DOWN: $($probeRes.Error)"
            Write-Output "Sleeping for $IntervalSeconds seconds until next check..."
        }
    } catch {
        Write-Warning "Health probe execution failed: $_"
    }

    if ($checkCount -lt $MaxChecks) {
        Start-Sleep -Seconds $IntervalSeconds
    }
}

if ($isOnline) {
    Write-Output "`n=========================================================="
    Write-Output ">>> LAUNCHING UNIFIED BALANCED RESEARCH PIPELINE NOW <<<"
    Write-Output "=========================================================="
    & powershell -ExecutionPolicy Bypass -File $pipelineScript
} else {
    Write-Output "`nWatcher reached max checks without API coming online. Daily refresh approaching."
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\guard_check_exhaustion.ps1" -ErrorText "API remained unavailable until watcher timeout"
}
