<#
.SYNOPSIS
    tools/eval_evaluate_serp.ps1
    Responsibility: Standardized tool to evaluate SERP top 10 results for DA 1-9 count and stars.
    Replaces: All temporary eval_batch*.ps1 scripts.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Keyword = "",

    [Parameter(Mandatory=$false)]
    [int]$SearchVolume = 0,

    [Parameter(Mandatory=$false)]
    [string]$SerpJsonPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SerpJson = "",

    [Parameter(Mandatory=$false)]
    $SerpEntries = $null
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\eval_star_calculator.ps1"

$entries = @()

if (-not [string]::IsNullOrWhiteSpace($SerpJsonPath) -and (Test-Path $SerpJsonPath)) {
    $jsonText = [System.IO.File]::ReadAllText($SerpJsonPath, [System.Text.Encoding]::UTF8)
    $parsed = $jsonText | ConvertFrom-Json
    if ($parsed.keyword -and [string]::IsNullOrWhiteSpace($Keyword)) { $Keyword = $parsed.keyword }
    if ($parsed.searchVolume -and $SearchVolume -le 0) { $SearchVolume = [int]$parsed.searchVolume }
    elseif ($parsed.search_volume -and $SearchVolume -le 0) { $SearchVolume = [int]$parsed.search_volume }

    if ($parsed.serpEntries) { $entries = $parsed.serpEntries }
    elseif ($parsed -is [array]) { $entries = $parsed }
} elseif (-not [string]::IsNullOrWhiteSpace($SerpJson)) {
    $parsed = $SerpJson | ConvertFrom-Json
    if ($parsed.keyword -and [string]::IsNullOrWhiteSpace($Keyword)) { $Keyword = $parsed.keyword }
    if ($parsed.searchVolume -and $SearchVolume -le 0) { $SearchVolume = [int]$parsed.searchVolume }
    elseif ($parsed.search_volume -and $SearchVolume -le 0) { $SearchVolume = [int]$parsed.search_volume }

    if ($parsed.serpEntries) { $entries = $parsed.serpEntries }
    elseif ($parsed -is [array]) { $entries = $parsed }
} elseif ($null -ne $SerpEntries) {
    $entries = $SerpEntries
}

if ([string]::IsNullOrWhiteSpace($Keyword)) {
    throw "Keyword is required. Pass via -Keyword or inside the SERP JSON file."
}
if ($SearchVolume -le 0) {
    throw "SearchVolume must be > 0. Pass via -SearchVolume or inside the SERP JSON file."
}
if ($entries.Count -eq 0) {
    throw "No serpEntries found."
}

$eval = Get-StrictStarEvaluation -Keyword $Keyword -SearchVolume $SearchVolume -SerpEntries $entries

[PSCustomObject]@{
    Keyword = $eval.Keyword
    SearchVolume = $eval.SearchVolume
    StarCount = $eval.StarCount
    WeakUgcCount = $eval.WeakUgcCount
    PureLowDaCount = $eval.PureLowDaCount
    FormattedValue = $eval.FormattedValue
    IsHit = $eval.IsHit
    WinningSeatsCount = $eval.LowDaSites.Count
    WinningSeats = ($eval.LowDaSites | ForEach-Object { "[$($_.type)] DA$($_.domainAuthority): $($_.domain)" }) -join ", "
} | ConvertTo-Json
