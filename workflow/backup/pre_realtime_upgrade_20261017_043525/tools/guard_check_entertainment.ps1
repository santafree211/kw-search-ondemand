<#
.SYNOPSIS
    tools/guard_check_entertainment.ps1
    CLI entry point to check if a keyword violates Entertainment & Fiction exclusion rules.
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$workspaceRoot = Split-Path -Parent $PSScriptRoot
. "$PSScriptRoot\..\workflow\scripts\guard_check_entertainment_kw.ps1"

$res = Test-KeywordEntertainmentEligibility -Keyword $Keyword

if ($Json) {
    $res | ConvertTo-Json -Compress
} else {
    Write-Host "========================================="
    Write-Host " ENTERTAINMENT GUARD ELIGIBILITY CHECK"
    Write-Host "========================================="
    Write-Host "Keyword: $($res.Keyword)"
    Write-Host "IsAllowed: $($res.IsAllowed)"
    Write-Host "IsEntertainment: $($res.IsEntertainment)"
    if ($res.IsEntertainment) {
        Write-Host "Category: $($res.CategoryName) ($($res.Category))"
        Write-Host "Matched: $($res.MatchedPattern)"
        Write-Host "Reason: $($res.Reason)" -ForegroundColor Red
    } else {
        Write-Host "Reason: $($res.Reason)" -ForegroundColor Green
    }
    Write-Host "========================================="
}

if (-not $res.IsAllowed) {
    exit 1
} else {
    exit 0
}
