<#
.SYNOPSIS
    tools/ensure_pipeline_running.ps1
    Responsibility: Auto-Recovery & Resilient Watchdog Entrypoint for New Agent Harness.
    Checks if pipeline is currently active. If terminated unexpectedly (e.g. server restart),
    automatically restarts pipeline seamlessly from persistent checkpoint.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [switch]$ForceRestart = $false,

    [Parameter(Mandatory=$false)]
    [switch]$CheckOnly = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\pipeline_state_manager.ps1"
. "$projectRoot\workflow\scripts\guard_quota_archive.ps1"

$state = Get-PipelineState
$quota = Get-DailyApiQuotaUsage

$isActive = Test-PipelineProcessActive -ProcessId $state.Pid

Write-Output "=========================================================="
Write-Output "=== PIPELINE RESILIENCE & HEALTH WATCHDOG ==="
Write-Output "=========================================================="
Write-Output "Recorded State   : $($state.Status) (PID: $($state.Pid))"
Write-Output "Last Heartbeat   : $($state.LastHeartbeat)"
Write-Output "Process Active   : $isActive"
Write-Output "Today Calls Log  : $($quota.TotalRealCallsToday) / $($quota.DailyQuotaLimit) calls"
Write-Output "Remaining Quota  : $($quota.RemainingEstimated) calls (Estimated)"

# Check if quota genuinely exhausted
$isQuotaExhausted = ($state.Exhausted -or $quota.RemainingEstimated -le 0)

if ($isQuotaExhausted) {
    Write-Output "`n[STATUS] Daily API quota has been reached or exhausted."
    Write-Output "Exhaustion Evidence: $($state.ExhaustionError)"
    Set-PipelineState -Status "EXHAUSTED" -Exhausted $true | Out-Null
    exit 0
}

if ($isActive -and -not $ForceRestart) {
    Write-Output "`n[STATUS] Pipeline is ALIVE and actively running (PID: $($state.Pid)). No action needed."
    exit 0
}

if ($CheckOnly) {
    Write-Output "`n[STATUS] Pipeline is NOT running (CheckOnly mode)."
    exit 0
}

# Auto-recovery: Pipeline is stopped unexpectedly or restart forced
Write-Output "`n[ACTION] Detected inactive or interrupted pipeline. Initiating automatic recovery..."

$runScript = Join-Path $PSScriptRoot "run_pipeline.ps1"
$logDir = Join-Path $projectRoot "workflow\data\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "pipeline_auto_run_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Launch in background via PowerShell ProcessStartInfo
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$runScript`" -Gender $Gender"
$psi.WorkingDirectory = $projectRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)

if ($proc -and $proc.Id -gt 0) {
    Write-Output "Successfully revived autonomous pipeline! New PID: $($proc.Id)"
    Set-PipelineState -Status "RUNNING" -Pid $proc.Id -StartTime (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -TargetMode $Gender -Exhausted $false | Out-Null
} else {
    Write-Warning "Failed to launch pipeline process."
}

Write-Output "=========================================================="
