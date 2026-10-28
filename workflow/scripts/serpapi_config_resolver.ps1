<#
.SYNOPSIS
    serpapi_config_resolver.ps1
    Single Responsibility: Resolve SerpApi configuration and API key from file and environment variables.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-SerpApiConfig {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = ""
    )

    $configFile = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath
    } else {
        Join-Path $PSScriptRoot "..\config\serpapi_config.json"
    }

    $config = [PSCustomObject]@{
        api_key         = ""
        daily_limit     = 7
        monthly_limit   = 240
        engine          = "google"
        gl              = "jp"
        hl              = "ja"
        num             = 10
        timeout_seconds = 30
    }

    if (Test-Path $configFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.api_key) { $config.api_key = [string]$parsed.api_key }
            if ($null -ne $parsed.daily_limit) { $config.daily_limit = [int]$parsed.daily_limit }
            if ($null -ne $parsed.monthly_limit) { $config.monthly_limit = [int]$parsed.monthly_limit }
            if ($parsed.engine) { $config.engine = [string]$parsed.engine }
            if ($parsed.gl) { $config.gl = [string]$parsed.gl }
            if ($parsed.hl) { $config.hl = [string]$parsed.hl }
            if ($null -ne $parsed.num) { $config.num = [int]$parsed.num }
            if ($null -ne $parsed.timeout_seconds) { $config.timeout_seconds = [int]$parsed.timeout_seconds }
        } catch {}
    }

    # Check environment variables across scopes (Process, User, Machine)
    $keyFromEnv = if (-not [string]::IsNullOrWhiteSpace($env:SERPAPI_API_KEY)) { $env:SERPAPI_API_KEY.Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($keyFromEnv)) {
        try {
            $userKey = [System.Environment]::GetEnvironmentVariable("SERPAPI_API_KEY", "User")
            if (-not [string]::IsNullOrWhiteSpace($userKey)) {
                $keyFromEnv = $userKey.Trim()
                $env:SERPAPI_API_KEY = $keyFromEnv
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($keyFromEnv)) {
        try {
            $machKey = [System.Environment]::GetEnvironmentVariable("SERPAPI_API_KEY", "Machine")
            if (-not [string]::IsNullOrWhiteSpace($machKey)) {
                $keyFromEnv = $machKey.Trim()
                $env:SERPAPI_API_KEY = $keyFromEnv
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($keyFromEnv)) {
        $config.api_key = $keyFromEnv
    }

    return $config
}
