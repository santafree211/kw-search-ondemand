<#
.SYNOPSIS
    tools/store_query_cached_serp.ps1
    Responsibility: Standard CLI tool to query cached SERP entries by keyword and date without consuming API tokens.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Keyword,

    [Parameter(Mandatory=$false)]
    [string]$DateString = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\store_api_query.ps1"

$res = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $Keyword -DateString $DateString

if ($null -eq $res) {
    Write-Output "NOT_FOUND"
    exit 0
}

[PSCustomObject]@{
    Found = $true
    Date = $res.Date
    Keyword = $res.TargetKey
    FilePath = $res.FilePath
    Data = $res.Data
} | ConvertTo-Json -Depth 10
