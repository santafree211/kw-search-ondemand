<#
.SYNOPSIS
    tools/research_verify_volume.ps1
    Responsibility: Verify keyword search volume strictly (>= 1900) and register into verified cache.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Keyword = "",

    [Parameter(Mandatory=$false)]
    [int]$SearchVolume = -1,

    [Parameter(Mandatory=$false)]
    [string]$ApiJsonPath = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\research_volume_verifier.ps1"

$respObj = $null

if (-not [string]::IsNullOrWhiteSpace($ApiJsonPath) -and (Test-Path $ApiJsonPath)) {
    $jsonText = [System.IO.File]::ReadAllText($ApiJsonPath, [System.Text.Encoding]::UTF8)
    $respObj = $jsonText | ConvertFrom-Json
    if ($respObj.keyword -and [string]::IsNullOrWhiteSpace($Keyword)) { $Keyword = $respObj.keyword }
} elseif ($SearchVolume -ge 0) {
    $respObj = [PSCustomObject]@{ search_volume = $SearchVolume }
}

if ([string]::IsNullOrWhiteSpace($Keyword)) {
    throw "Keyword is required. Pass via -Keyword or inside the API JSON file."
}

$res = Test-KeywordVolume -TargetKeyword $Keyword -ResponseObj $respObj
$res | ConvertTo-Json
