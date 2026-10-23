<#
.SYNOPSIS
    tools/watchdog_heartbeat.ps1
    Responsibility: Health check and auto-recovery watchdog for autonomous goal research under new agent harness.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\pipeline_state_manager.ps1"
. "$projectRoot\workflow\scripts\guard_quota_archive.ps1"
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

$state = Get-PipelineState
$quota = Get-DailyApiQuotaUsage
$isActive = Test-PipelineProcessActive -ProcessId $state.Pid

$fProf = Resolve-SheetProfile -Gender female
$mProf = Resolve-SheetProfile -Gender male
$fData = Read-SheetData -SheetId $fProf.SpreadsheetId -TargetSheetName $fProf.TargetSheetName
$mData = Read-SheetData -SheetId $mProf.SpreadsheetId -TargetSheetName $mProf.TargetSheetName

$recovered = $false
$isExhausted = ($state.Exhausted -or $quota.RemainingEstimated -le 0)

if (-not $isActive -and -not $isExhausted) {
    # Pipeline stopped unexpectedly (e.g. server restart) - Revive immediately!
    Write-Output "Watchdog: Inactive pipeline detected with $($quota.RemainingEstimated) remaining quota. Auto-reviving..."
    & powershell -ExecutionPolicy Bypass -File "$PSScriptRoot\ensure_pipeline_running.ps1" -Gender "both" | Out-Null
    $recovered = $true
    $state = Get-PipelineState
    $isActive = Test-PipelineProcessActive -ProcessId $state.Pid
}

$report = [PSCustomObject]@{
    WatchdogTime        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    PipelineStatus      = $state.Status
    ProcessActive       = $isActive
    AutoRecovered       = $recovered
    CallsToday          = $quota.TotalRealCallsToday
    QuotaLimit          = $quota.DailyQuotaLimit
    RemainingEstimated  = $quota.RemainingEstimated
    IsExhausted         = $isExhausted
    FemaleKeywords      = $fData.ValidKeywordCount
    MaleKeywords        = $mData.ValidKeywordCount
    TotalKeywords       = ($fData.ValidKeywordCount + $mData.ValidKeywordCount)
}

$report | ConvertTo-Json -Depth 5
