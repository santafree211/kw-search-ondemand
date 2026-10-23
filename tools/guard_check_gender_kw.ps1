<#
.SYNOPSIS
    tools/guard_check_gender_kw.ps1
    Responsibility: Standard CLI tool to check whether a keyword is eligible for a specific gender sheet.
    Usage:
        powershell -ExecutionPolicy Bypass -File tools/guard_check_gender_kw.ps1 -Gender male -Keyword "アヌア レチノール効果"
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("male", "female", "m", "f", "men", "women")]
    [string]$Gender,

    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\workflow\scripts\guard_check_gender_kw.ps1"

$res = Test-KeywordGenderEligibility -Gender $Gender -Keyword $Keyword

if ($Json) {
    $res | ConvertTo-Json -Depth 3
} else {
    Write-Output "=========================================================="
    Write-Output "=== GENDER KEYWORD ELIGIBILITY CHECK ==="
    Write-Output "=========================================================="
    Write-Output "Target Gender     : $($res.TargetGender)"
    Write-Output "Keyword           : $($res.Keyword)"
    Write-Output "Is Allowed        : $($res.IsAllowed)"
    if (-not $res.IsAllowed) {
        Write-Output "Forbidden Pattern : $($res.ForbiddenPattern)"
        Write-Output "Violation Reason  : $($res.Reason)"
    } else {
        Write-Output "Status            : PASSED (Eligible for $($res.TargetGender) sheet)"
    }
    Write-Output "=========================================================="
}
