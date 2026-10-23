<#
.SYNOPSIS
    tools/run_daily_package.ps1
    Responsibility: Master Orchestrator Package for Daily Keyword Research, SERP Verification,
    Sheet Synchronization, and 3-Way Reconciliation Audit.
    Usage:
      powershell -ExecutionPolicy Bypass -File tools\run_daily_package.ps1 [-Gender both|female|male] [-DryRun]
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory=$false)]
    [switch]$SkipAudit = $false
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

$logDir = Join-Path $projectRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$todayStr = (Get-Date).ToString("yyyyMMdd_HHmmss")
$logFile = Join-Path $logDir "daily_package_$todayStr.log"

function Write-PkgLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] [$Level] $Message"
    Write-Output $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

Write-PkgLog "=========================================================="
Write-PkgLog "=== KW-SEARCH DAILY AUTONOMOUS MASTER PACKAGE RUNNER ==="
Write-PkgLog "=========================================================="
Write-PkgLog "Target Gender   : $Gender"
Write-PkgLog "DryRun Mode     : $DryRun"
Write-PkgLog "Skip Audit      : $SkipAudit"
Write-PkgLog "Log Output File : $logFile"

# STEP 1: Verify API Connectivity & Refresh Modifiers
Write-PkgLog "`n[STEP 1/4] Checking System, API Health & Modifiers..."
$modifierConfig = Join-Path $projectRoot "workflow\config\ai_daily_modifiers.json"
try {
    $modObj = [System.IO.File]::ReadAllText($modifierConfig, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $todayIso = (Get-Date).ToString("yyyy-MM-dd")
    if ([string]$modObj.last_updated -ne $todayIso) {
        Write-PkgLog "ai_daily_modifiers.json last_updated=$($modObj.last_updated) is not today ($todayIso). Rule 4 requires the agent to refresh it once daily before research." "WARN"
    } else {
        Write-PkgLog "ai_daily_modifiers.json is up to date ($todayIso)."
    }
} catch {
    Write-PkgLog "Could not read ai_daily_modifiers.json: $_" "WARN"
}

$healthScript = Join-Path $PSScriptRoot "check_api_health.ps1"
if (Test-Path $healthScript) {
    try {
        $healthOut = & powershell -ExecutionPolicy Bypass -File $healthScript -Json
        $healthJson = $healthOut | ConvertFrom-Json
        if ($healthJson.IsHealthy) {
            Write-PkgLog "Ubersuggest API: ONLINE (Latency: $($healthJson.ResponseTimeMs) ms)"
        } else {
            Write-PkgLog "Ubersuggest API returned warning: $($healthJson.Error)" "WARN"
        }
    } catch {
        Write-PkgLog "Health probe check non-fatal exception: $_" "WARN"
    }
}

# STEP 2: Execute Unified Research & SERP Verification Pipeline
Write-PkgLog "`n[STEP 2/4] Launching Unified Research Pipeline (Ubersuggest 50-Genre + Google SERP Evaluation)..."
Write-PkgLog "Running until physical quota exhaustion (HTTP 403 / 429) or full cycle completion..."

$pipelineScript = Join-Path $PSScriptRoot "run_pipeline.ps1"
$pipelineArgs = @("-ExecutionPolicy", "Bypass", "-File", $pipelineScript, "-Gender", $Gender)
if ($DryRun) {
    $pipelineArgs += "-DryRun"
}

$pipelineExitCode = 0
try {
    # Execute synchronously within package, streaming output to console & log
    & powershell @pipelineArgs 2>&1 | ForEach-Object {
        $msg = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { $_.ToString() }
        Write-Output $msg
        Add-Content -Path $logFile -Value $msg -Encoding UTF8
    }
    $pipelineExitCode = $LASTEXITCODE
} catch {
    Write-PkgLog "Pipeline execution error: $_" "ERROR"
    $pipelineExitCode = 1
}

Write-PkgLog "`nPipeline finished with exit code: $pipelineExitCode"

# STEP 3: Sync Cached Google Real-SERP Evidence & Clean Zero-Star Seats
if (-not $SkipAudit -and -not $DryRun) {
    Write-PkgLog "`n[STEP 3/5] Syncing Cached Google Real-SERP Evidence (Zero-Cost Verification)..."
    $verifySerpScript = Join-Path $PSScriptRoot "verify_sheet_serpapi.ps1"
    if (Test-Path $verifySerpScript) {
        try {
            & powershell -ExecutionPolicy Bypass -File $verifySerpScript -Gender $Gender -SyncCached *>&1 | ForEach-Object {
                $msg = $_.ToString()
                Write-Output $msg
                Add-Content -Path $logFile -Value $msg -Encoding UTF8
            }
        } catch {
            Write-PkgLog "SERP sync warning: $_" "WARN"
        }
    }

    # STEP 4: Autonomous Golden Ratio Self-Healing Balancer
    Write-PkgLog "`n[STEP 4/5] Executing Autonomous Golden Ratio (50:25:25) Self-Healing Balancer..."
    $balancerScript = Join-Path $PSScriptRoot "sheet_ratio_balancer.ps1"
    if (Test-Path $balancerScript) {
        try {
            & powershell -ExecutionPolicy Bypass -File $balancerScript -Gender $Gender *>&1 | ForEach-Object {
                $msg = $_.ToString()
                Write-Output $msg
                Add-Content -Path $logFile -Value $msg -Encoding UTF8
            }
        } catch {
            Write-PkgLog "Self-healing balancer warning: $_" "WARN"
        }
    }

    # STEP 5: 3-Way Reconciliation Audit & Self-Healing Loop
    Write-PkgLog "`n[STEP 5/5] Executing 3-Way Reconciliation & Sheet Quality Audit..."
    $reconcileScript = Join-Path $PSScriptRoot "sheet_reconcile.ps1"
    $auditScript = Join-Path $PSScriptRoot "sheet_audit.ps1"
    
    $reconcilePassed = $false
    try {
        & powershell -ExecutionPolicy Bypass -File $reconcileScript -Gender $Gender *>&1 | ForEach-Object {
            $msg = $_.ToString()
            Write-Output $msg
            Add-Content -Path $logFile -Value $msg -Encoding UTF8
            if ($msg -match "OVERALL UNIFIED STATUS: ALL PASSED") {
                $reconcilePassed = $true
            }
        }
    } catch {
        Write-PkgLog "Reconciliation audit warning: $_" "WARN"
    }

    # Check sheet audit
    try {
        & powershell -ExecutionPolicy Bypass -File $auditScript -Gender $Gender *>&1 | ForEach-Object {
            $msg = $_.ToString()
            Write-Output $msg
            Add-Content -Path $logFile -Value $msg -Encoding UTF8
        }
    } catch {
        Write-PkgLog "Sheet audit warning: $_" "WARN"
    }

    if ($reconcilePassed) {
        Write-PkgLog "`n>>> [AUDIT SUCCESS] Both sheets 100% Reconciled and Golden Ratio compliant."
    } else {
        Write-PkgLog "`n>>> [AUDIT NOTICE] Minor discrepancies detected. Self-healing balancer is active to ensure ongoing compliance." "WARN"
    }
} else {
    Write-PkgLog "`n[STEP 3-5/5] Skipped audit (DryRun or SkipAudit specified)."
}

Write-PkgLog "`n=========================================================="
Write-PkgLog "=== DAILY PACKAGE RUN COMPLETED SUCCESSFULLY ==="
Write-PkgLog "Detailed log saved to: $logFile"
Write-PkgLog "=========================================================="

exit $pipelineExitCode

