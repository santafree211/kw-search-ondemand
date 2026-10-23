<#
.SYNOPSIS
    tools/guard_check_ymyl.ps1
    Responsibility: Standard CLI tool to test whether a keyword violates YMYL/Medical guidelines.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [string]$RulesPath = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\guard_check_ymyl_kw.ps1"

$res = Test-KeywordYmylEligibility -Keyword $Keyword -RulesPath $RulesPath
$res | ConvertTo-Json -Depth 3
