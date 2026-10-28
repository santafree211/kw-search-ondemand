<#
.SYNOPSIS
    pipeline_serp_sync.ps1
    Single Responsibility: Invoke SerpApi verification and sync/purge Google Sheets real-time evidence.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\serpapi_client.ps1"

function Invoke-PipelineSerpSync {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetGender = "both",

        [Parameter(Mandatory=$false)]
        [switch]$IsDryRun = $false
    )

    Write-Output "`n----------------------------------------------------------"
    Write-Output ">>> [CYCLE 2-4: SERP & SHEET CLEANUP] Verifying & Purging via Google Real SERP..."
    Write-Output "----------------------------------------------------------"

    $serpConfig = Get-SerpApiConfig
    if (-not [string]::IsNullOrWhiteSpace($serpConfig.api_key)) {
        $serpUsage = Get-SerpApiDailyUsage -DailyLimit $serpConfig.daily_limit -MonthlyLimit $serpConfig.monthly_limit
        if (-not $serpUsage.IsLimitReached -and $serpUsage.RemainingCalls -gt 0) {
            Write-Output "SerpApi available quota: $($serpUsage.RemainingCalls) calls today (Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit))."
            Write-Output "Running Google real-time SERP verification: Deleting 0-stars, purging dead sites, confirming true stars..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$projectRoot\tools\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-Limit", $serpUsage.RemainingCalls
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {
                Write-Warning "SerpApi verification encountered an error: $_"
            }
        } else {
            Write-Output "SerpApi quota currently at limit (Today: $($serpUsage.CallsToday)/$($serpUsage.DailyLimit), Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit)). Syncing cached SERP evidence..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$projectRoot\tools\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-SyncCached"
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {}
        }
    } else {
        Write-Output "SerpApi key not detected in Windows environment. Skipping SERP verification phase."
    }
}
