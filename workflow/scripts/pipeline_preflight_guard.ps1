<#
.SYNOPSIS
    pipeline_preflight_guard.ps1
    Single Responsibility: Perform pre-flight connectivity and quota health checks prior to pipeline loop execution.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\research_serp_fetcher.ps1"

function Test-PipelinePreflightHealth {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TestKeyword = "健康 美容"
    )

    Write-Output "`n[Pre-flight Health Check] Testing Ubersuggest API connectivity..."
    $healthCheckRes = Invoke-SerpAnalysisRemote -TargetKeyword $TestKeyword

    if ($null -ne $healthCheckRes -and $healthCheckRes.IsExhausted) {
        Write-Warning "PRE-FLIGHT CHECK FAILED: Ubersuggest API is currently unavailable or exhausted."
        Write-Warning "Error Detail: $($healthCheckRes.Error)"
        return [PSCustomObject]@{
            Passed          = $false
            IsExhausted     = $true
            ExhaustionError = $healthCheckRes.Error
        }
    }

    Write-Output "Pre-flight Health Check Passed: Ubersuggest API is responsive."
    return [PSCustomObject]@{
        Passed          = $true
        IsExhausted     = $false
        ExhaustionError = ""
    }
}
