<#
.SYNOPSIS
    tools/male/run_balanced_pipeline.ps1
    Male Dedicated Tool: Run 50-genre parallel water-leveling research pipeline.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 500,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 5
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
$balancedTool = Join-Path $toolsDir "research_balanced_genres.ps1"

& $balancedTool -Gender "male" -MaxTotalCalls $MaxTotalCalls -MaxKwsPerGenreBatch $MaxKwsPerGenreBatch
