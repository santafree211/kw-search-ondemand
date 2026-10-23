<#
.SYNOPSIS
    tools/eval_check_weak_competitor.ps1
    Responsibility: Standardized CLI tool to check whether a domain or URL is a weak UGC competitor.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Domain = "",

    [Parameter(Mandatory=$false)]
    [string]$Url = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\eval_weak_competitor_rule.ps1"

if ([string]::IsNullOrWhiteSpace($Domain) -and [string]::IsNullOrWhiteSpace($Url)) {
    throw "Specify -Domain or -Url."
}

$res = Test-WeakCompetitor -Domain $Domain -Url $Url
$res | ConvertTo-Json -Depth 3
