<#
.SYNOPSIS
    tools/guard_check_serp_eligibility.ps1
    Responsibility: Standard CLI tool to check whether a keyword is eligible for a serp_analysis API call.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [int]$MinVolume = 1900,

    [Parameter(Mandatory=$false)]
    [string]$DateString = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\guard_serp_gate.ps1"

$res = Test-SerpEligibility -Keyword $Keyword -MinVolume $MinVolume -DateString $DateString

$res | ConvertTo-Json -Compress
