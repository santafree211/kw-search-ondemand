<#
.SYNOPSIS
    tools/research_harvest_domains_from_serp.ps1
    Responsibility: Standard CLI tool to harvest independent personal blog domains (DA 1-9) from SERP results.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Keyword = "",

    [Parameter(Mandatory=$false)]
    [string]$SerpJsonPath = "",

    [Parameter(Mandatory=$false)]
    [string]$DateString = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\research_domain_harvester.ps1"
. "$PSScriptRoot\..\workflow\scripts\store_api_query.ps1"

$serpData = $null

if (-not [string]::IsNullOrWhiteSpace($SerpJsonPath) -and (Test-Path $SerpJsonPath)) {
    $text = [System.IO.File]::ReadAllText($SerpJsonPath, [System.Text.Encoding]::UTF8)
    $serpData = $text | ConvertFrom-Json
} elseif (-not [string]::IsNullOrWhiteSpace($Keyword)) {
    $found = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $Keyword -DateString $DateString
    if ($null -ne $found -and $found.Found) {
        $serpData = $found.Data
    } else {
        Write-Output "NO_SERP_DATA_FOUND"
        exit 0
    }
} else {
    throw "Either -Keyword or -SerpJsonPath must be specified."
}

$res = Get-HarvestedDomainsFromSerp -SerpEntries $serpData

$res | ConvertTo-Json -Depth 5
