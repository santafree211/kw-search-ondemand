<#
.SYNOPSIS
    tools/research_diff_keywords.ps1
    Responsibility: Standard CLI tool to extract unknown keyword diffs against local archive to eliminate duplicate API calls.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string[]]$Keywords,

    [Parameter(Mandatory=$false)]
    [string]$Endpoint = "serp_analysis",

    [Parameter(Mandatory=$false)]
    [int]$MaxAgeDays = 30
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\research_diff_keywords.ps1"

$cleanKws = @()
foreach ($k in $Keywords) {
    if ($k.Contains(",")) {
        $cleanKws += ($k -split ",")
    } else {
        $cleanKws += $k
    }
}

$res = Get-KeywordDiff -Keywords $cleanKws -Endpoint $Endpoint -MaxAgeDays $MaxAgeDays

$res | ConvertTo-Json -Depth 5
