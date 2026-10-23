<#
.SYNOPSIS
    workflow/scripts/pipeline_state_manager.ps1
    Responsibility: Unified Pipeline Execution State & Heartbeat Manager for Resilient Agent Harness.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($scriptRoot)) { $scriptRoot = Split-Path -Parent (Get-Variable MyInvocation -Scope 1).Value.MyCommand.Path }

function Get-PipelineStatePath {
    $baseDir = if ($scriptRoot) { $scriptRoot } else { $PSScriptRoot }
    if (-not $baseDir) { $baseDir = Join-Path $PWD "workflow\scripts" }
    $dataPath = Join-Path $baseDir "..\data"
    if (-not (Test-Path $dataPath)) {
        New-Item -ItemType Directory -Path $dataPath -Force | Out-Null
    }
    return (Join-Path $dataPath "pipeline_run_state.json")
}

function Get-PipelineState {
    $path = Get-PipelineStatePath
    if (Test-Path $path) {
        try {
            $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            $obj = $raw | ConvertFrom-Json
            if ($obj) { return $obj }
        } catch {}
    }

    return [PSCustomObject]@{
        Status          = "STOPPED"
        Pid             = 0
        StartTime       = ""
        LastHeartbeat   = ""
        CurrentGender   = ""
        TargetMode      = ""
        TotalCallsDone  = 0
        Exhausted       = $false
        ExhaustionError = ""
    }
}

function Set-PipelineState {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Status,

        [Parameter(Mandatory=$false)]
        [int]$ProcessId = 0,

        [Parameter(Mandatory=$false)]
        [string]$StartTime,

        [Parameter(Mandatory=$false)]
        [string]$LastHeartbeat,

        [Parameter(Mandatory=$false)]
        [string]$CurrentGender,

        [Parameter(Mandatory=$false)]
        [string]$TargetMode,

        [Parameter(Mandatory=$false)]
        [int]$TotalCallsDone = -1,

        [Parameter(Mandatory=$false)]
        $Exhausted = $null,

        [Parameter(Mandatory=$false)]
        [string]$ExhaustionError
    )

    $curr = Get-PipelineState
    $nowStr = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $newPid = if ($ProcessId -gt 0) { $ProcessId } else { $curr.Pid }
    $newStatus = if (-not [string]::IsNullOrWhiteSpace($Status)) { $Status } else { $curr.Status }
    $newStart = if (-not [string]::IsNullOrWhiteSpace($StartTime)) { $StartTime } elseif ($curr.StartTime) { $curr.StartTime } else { $nowStr }
    $newHeartbeat = if (-not [string]::IsNullOrWhiteSpace($LastHeartbeat)) { $LastHeartbeat } else { $nowStr }
    $newGender = if (-not [string]::IsNullOrWhiteSpace($CurrentGender)) { $CurrentGender } else { $curr.CurrentGender }
    $newMode = if (-not [string]::IsNullOrWhiteSpace($TargetMode)) { $TargetMode } else { $curr.TargetMode }
    $newCalls = if ($TotalCallsDone -ge 0) { $TotalCallsDone } else { $curr.TotalCallsDone }
    $newExh = if ($null -ne $Exhausted) { [bool]$Exhausted } else { [bool]$curr.Exhausted }
    $newErr = if ($null -ne $ExhaustionError) { $ExhaustionError } else { $curr.ExhaustionError }

    $stateObj = [PSCustomObject]@{
        Status          = $newStatus
        Pid             = $newPid
        StartTime       = $newStart
        LastHeartbeat   = $newHeartbeat
        CurrentGender   = $newGender
        TargetMode      = $newMode
        TotalCallsDone  = $newCalls
        Exhausted       = $newExh
        ExhaustionError = $newErr
        UpdatedTime     = $nowStr
    }

    $json = $stateObj | ConvertTo-Json -Depth 5
    $path = Get-PipelineStatePath
    [System.IO.File]::WriteAllText($path, $json, [System.Text.Encoding]::UTF8)
    return $stateObj
}

function Test-PipelineProcessActive {
    param([int]$ProcessId)

    if ($ProcessId -le 0) { return $false }
    try {
        $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($p -and (-not $p.HasExited)) {
            return $true
        }
    } catch {}
    return $false
}
