<#
.SYNOPSIS
    tools\workflow_run_pipeline.ps1
    Responsibility: Master autonomous CLI runner for agent keyword exploration sessions.
    Token-Saving: Supports chunked bulk expansion to reduce API calls by up to 98%.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$SeedKeywords = @(),

    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 2,

    [Parameter(Mandatory=$false)]
    [int]$MaxBatches = 5,

    [Parameter(Mandatory=$false)]
    [string]$CandidateFilePath = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory=$false)]
    [int]$Limit = 1000,

    [Parameter(Mandatory=$false)]
    [bool]$UseBulk = $true,

    [Parameter(Mandatory=$false)]
    [string]$MockJsonPath = "",

    [Parameter(Mandatory=$false)]
    [int]$MaxSerpCalls = 15,

    [Parameter(Mandatory=$false)]
    [int]$MaxDomainCalls = 10,

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SurveyDate = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\workflow_pipeline_runner.ps1"
. "$PSScriptRoot\..\workflow\scripts\genre_tracker.ps1"

$cleanSeeds = @()
foreach ($s in $SeedKeywords) {
    if ($s.Contains(",")) {
        $cleanSeeds += ($s -split ",")
    } else {
        $cleanSeeds += $s
    }
}

if ($cleanSeeds.Count -eq 0 -and [string]::IsNullOrWhiteSpace($CandidateFilePath)) {
    $balanced = Get-NextBalancedGenreSeeds -Gender $Gender -MaxGenres 3
    $cleanSeeds = @($balanced.Seeds)
    Write-Output "[Auto-Balanced Parallel Discovery] Targeting Milestone: $($balanced.CurrentMilestone) KWs/genre"
    Write-Output "Selected $($cleanSeeds.Count) seeds from bottom-up deficit genres:"
    foreach ($tg in $balanced.TargetGenres) {
        Write-Output "  - $tg"
    }
}

$res = Invoke-KeywordSearchPipeline `
    -Seeds $cleanSeeds `
    -BatchSize $BatchSize `
    -MaxBatches $MaxBatches `
    -IsDryRun:$DryRun `
    -Limit $Limit `
    -CandFile $CandidateFilePath `
    -EnableBulk $UseBulk `
    -MockFile $MockJsonPath `
    -MaxSerpCalls $MaxSerpCalls `
    -MaxDomainCalls $MaxDomainCalls `
    -SpreadsheetId $SpreadsheetId `
    -Gender $Gender `
    -SurveyDate $SurveyDate

$res | ConvertTo-Json -Depth 5
