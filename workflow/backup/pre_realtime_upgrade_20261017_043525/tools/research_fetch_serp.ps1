<#
.SYNOPSIS
    tools/research_fetch_serp.ps1
    Responsibility: Fetch top 10 organic SERP entries for a keyword via Ubersuggest serp_analysis.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\research_serp_fetcher.ps1"

$cleanKw = $Keyword.Trim()

$res = Invoke-SerpAnalysisRemote -TargetKeyword $cleanKw -DryRun:$DryRun

if ($null -eq $res) {
    [PSCustomObject]@{
        Keyword = $cleanKw
        Success = $false
        Message = "No response or dry-run"
    } | ConvertTo-Json
} elseif ($res.IsExhausted) {
    [PSCustomObject]@{
        Keyword = $cleanKw
        Success = $false
        IsExhausted = $true
        Error = $res.Error
    } | ConvertTo-Json
} else {
    $parsed = Get-Top10OrganicEntries -TargetKeyword $cleanKw -ResponseObj $res
    [PSCustomObject]@{
        Keyword = $cleanKw
        Success = $true
        TotalOrganic = $parsed.TotalEntries
        Top10Organic = $parsed.Top10Organic
    } | ConvertTo-Json -Depth 5
}
