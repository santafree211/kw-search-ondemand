<#
.SYNOPSIS
    tools/male/run_pipeline.ps1
    Male Dedicated CLI Tool: Master autonomous pipeline runner for Male keyword exploration.
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
    [string]$SurveyDate = ""
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
$pipelineScript = Join-Path $toolsDir "workflow_run_pipeline.ps1"

& $pipelineScript `
    -SeedKeywords $SeedKeywords `
    -BatchSize $BatchSize `
    -MaxBatches $MaxBatches `
    -CandidateFilePath $CandidateFilePath `
    -DryRun:$DryRun `
    -Limit $Limit `
    -UseBulk $UseBulk `
    -MockJsonPath $MockJsonPath `
    -MaxSerpCalls $MaxSerpCalls `
    -MaxDomainCalls $MaxDomainCalls `
    -Gender "male" `
    -SurveyDate $SurveyDate
