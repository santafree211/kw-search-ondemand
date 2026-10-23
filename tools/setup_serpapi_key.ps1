<#
.SYNOPSIS
    tools/setup_serpapi_key.ps1
    Responsibility: Securely manage and store SerpApi API key in Windows User Environment Variables.
    Benefits:
      - Key is stored persistently in Windows (Registry: HKCU\Environment) across reboots.
      - Zero plaintext API keys in git repository or project files.
      - Automatically accessible by all scripts via $env:SERPAPI_API_KEY.
    Usage:
      # Direct CLI argument:
      powershell -ExecutionPolicy Bypass -File tools\setup_serpapi_key.ps1 -ApiKey "your_key_here"

      # Interactive input:
      powershell -ExecutionPolicy Bypass -File tools\setup_serpapi_key.ps1

      # Check current status:
      powershell -ExecutionPolicy Bypass -File tools\setup_serpapi_key.ps1 -Status

      # Remove key from Windows:
      powershell -ExecutionPolicy Bypass -File tools\setup_serpapi_key.ps1 -Remove
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$ApiKey = "",

    [Parameter(Mandatory=$false)]
    [switch]$Status = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Remove = $false
)

$ErrorActionPreference = "Stop"

function Mask-ApiKey([string]$key) {
    if ([string]::IsNullOrWhiteSpace($key)) { return "(None)" }
    $trimmed = $key.Trim()
    if ($trimmed.Length -le 8) { return "********" }
    $prefix = $trimmed.Substring(0, 4)
    $suffix = $trimmed.Substring($trimmed.Length - 4, 4)
    return "$prefix" + ("*" * ($trimmed.Length - 8)) + "$suffix (Length: $($trimmed.Length))"
}

Write-Output "=========================================================="
Write-Output "=== SERPAPI KEY WINDOWS STORAGE MANAGER ==="
Write-Output "=========================================================="

if ($Remove) {
    Write-Output "Removing SERPAPI_API_KEY from Windows User environment..."
    [System.Environment]::SetEnvironmentVariable("SERPAPI_API_KEY", $null, "User")
    $env:SERPAPI_API_KEY = $null
    Write-Output ">> SERPAPI_API_KEY successfully removed from Windows."
    Write-Output "=========================================================="
    return
}

if ($Status) {
    $userVal = [System.Environment]::GetEnvironmentVariable("SERPAPI_API_KEY", "User")
    $procVal = $env:SERPAPI_API_KEY
    $configVal = ""
    $configFile = Join-Path $PSScriptRoot "..\workflow\config\serpapi_config.json"
    if (Test-Path $configFile) {
        try {
            $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
            $parsed = $raw | ConvertFrom-Json
            if ($parsed.api_key) { $configVal = [string]$parsed.api_key }
        } catch {}
    }

    Write-Output "Current Configuration Status:"
    Write-Output "  Windows User Env (HKCU) : $(Mask-ApiKey $userVal)"
    Write-Output "  Current Process Session : $(Mask-ApiKey $procVal)"
    Write-Output "  File (serpapi_config)   : $(Mask-ApiKey $configVal)"
    if (-not [string]::IsNullOrWhiteSpace($userVal) -or -not [string]::IsNullOrWhiteSpace($procVal)) {
        Write-Output "`n>> STATUS: READY (SerpApi key is configured in Windows environment)"
    } else {
        Write-Output "`n>> STATUS: NOT CONFIGURED (No SerpApi key found in Windows environment)"
    }
    Write-Output "=========================================================="
    return
}

# If no key passed via parameter, prompt interactively
$targetKey = $ApiKey
if ([string]::IsNullOrWhiteSpace($targetKey)) {
    Write-Output "Enter your SerpApi API Key (input will be trimmed):"
    $targetKey = Read-Host "SerpApi Key"
}

if ([string]::IsNullOrWhiteSpace($targetKey)) {
    Write-Warning "No API key provided. Operation aborted."
    Write-Output "=========================================================="
    return
}

$cleanKey = $targetKey.Trim()

# Save permanently to Windows User Environment (HKCU\Environment)
try {
    [System.Environment]::SetEnvironmentVariable("SERPAPI_API_KEY", $cleanKey, "User")
    # Also sync to current running process immediately
    $env:SERPAPI_API_KEY = $cleanKey

    Write-Output "`n>> SUCCESS: SERPAPI_API_KEY saved permanently to Windows User environment!"
    Write-Output "  Storage Location : Windows Registry (HKCU\Environment)"
    Write-Output "  Stored Key       : $(Mask-ApiKey $cleanKey)"
    Write-Output "`nAll search and verification scripts will now automatically recognize this key"
    Write-Output "without needing any keys written to project files."
} catch {
    Write-Warning "Failed to save environment variable to Windows: $_"
}

Write-Output "=========================================================="
