<#
.SYNOPSIS
    tools/eval_evaluate_serp_male.ps1
    Responsibility: Standardized CLI tool to evaluate SERP top 10 for Male keywords
                    combining measured DA 1-9 independent blogs and weak UGC seats.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$true)]
    [int]$SearchVolume,

    [Parameter(Mandatory=$false)]
    [string]$SerpJsonPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SerpJsonString = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\eval_star_calculator_male.ps1"

$serpData = $null
if (-not [string]::IsNullOrWhiteSpace($SerpJsonPath)) {
    if (-not (Test-Path $SerpJsonPath)) {
        throw "SerpJsonPath not found: $SerpJsonPath"
    }
    $raw = [System.IO.File]::ReadAllText($SerpJsonPath, [System.Text.Encoding]::UTF8)
    $serpData = $raw | ConvertFrom-Json
} elseif (-not [string]::IsNullOrWhiteSpace($SerpJsonString)) {
    $serpData = $SerpJsonString | ConvertFrom-Json
} else {
    throw "Specify -SerpJsonPath or -SerpJsonString."
}

$entries = if ($serpData.serpEntries) { $serpData.serpEntries } else { $serpData }

$eval = Get-StrictStarEvaluationMale -Keyword $Keyword -SearchVolume $SearchVolume -SerpEntries $entries
$eval | ConvertTo-Json -Depth 5
