<#
.SYNOPSIS
    tools/research_diff_domains.ps1
    Responsibility: Standard CLI tool to extract uninvestigated domain diffs to eliminate duplicate domain_keywords calls.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string[]]$Domains = @(),

    [Parameter(Mandatory=$false)]
    [int]$MaxAgeDays = 30
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\research_diff_domains.ps1"

$cleanDoms = @()
foreach ($d in $Domains) {
    if ($d.Contains(",")) {
        $cleanDoms += ($d -split ",")
    } else {
        $cleanDoms += $d
    }
}

$res = Get-DomainDiff -Domains $cleanDoms -MaxAgeDays $MaxAgeDays

$res | ConvertTo-Json -Depth 5
