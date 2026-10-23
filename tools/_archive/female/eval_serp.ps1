<#
.SYNOPSIS
    tools/female/eval_serp.ps1
    Female Dedicated CLI Tool: Evaluate SERP top 10 results for Female keyword.
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
    [string]$SerpJson = ""
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
$evalScript = Join-Path $toolsDir "eval_evaluate_serp.ps1"

& $evalScript `
    -Keyword $Keyword `
    -SearchVolume $SearchVolume `
    -SerpJsonPath $SerpJsonPath `
    -SerpJson $SerpJson
