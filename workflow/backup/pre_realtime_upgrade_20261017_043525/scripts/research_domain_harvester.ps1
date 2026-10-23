<#
.SYNOPSIS
    workflow/scripts/research_domain_harvester.ps1
    Responsibility: Harvest all independent personal blog domains (measured DA 1-9) from a SERP analysis response.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"

function Get-HarvestedDomainsFromSerp {
    param(
        [Parameter(Mandatory=$true)]
        $SerpEntries,

        [Parameter(Mandatory=$false)]
        [int]$MaxDa = 9,

        [Parameter(Mandatory=$false)]
        [int]$MinDa = 1,

        [Parameter(Mandatory=$false)]
        [string]$Gender = "female"
    )

    $rawList = @()
    if ($SerpEntries -is [string]) {
        $parsed = $SerpEntries | ConvertFrom-Json
        if ($parsed.serpEntries) { $rawList = $parsed.serpEntries }
        elseif ($parsed.Top10Organic) { $rawList = $parsed.Top10Organic }
        elseif ($parsed -is [array]) { $rawList = $parsed }
    } elseif ($SerpEntries.serpEntries) {
        $rawList = $SerpEntries.serpEntries
    } elseif ($SerpEntries.Top10Organic) {
        $rawList = $SerpEntries.Top10Organic
    } elseif ($SerpEntries -is [array]) {
        $rawList = $SerpEntries
    }

    $harvested = @()
    $seenDomains = @{}

    foreach ($entry in $rawList) {
        $url = [string]$entry.url
        $domain = ([string]$entry.domain).ToLower().Trim()
        $da = [int]$entry.domainAuthority
        $title = [string]$entry.title
        $pos = [int]$entry.position

        if ([string]::IsNullOrWhiteSpace($domain) -or $seenDomains.ContainsKey($domain)) {
            continue
        }

        # Must satisfy DA 1-9
        if ($da -lt $MinDa -or $da -gt $MaxDa) {
            continue
        }

        # Must NOT be a weak UGC platform (e.g. note, chiebukuro) - we only want independent personal blog candidates
        $isWeakUgc = $false
        if ($Gender -eq "male") {
            $ugcCheck = Test-WeakCompetitorMale -Domain $domain -Url $url
            if ($null -ne $ugcCheck -and $ugcCheck.IsWeakCompetitor) { $isWeakUgc = $true }
        } else {
            $ugcCheck = Test-WeakCompetitor -Domain $domain -Url $url
            if ($null -ne $ugcCheck -and $ugcCheck.IsWeakCompetitor) { $isWeakUgc = $true }
        }

        if ($isWeakUgc) {
            continue
        }

        $seenDomains[$domain] = $true
        $harvested += [PSCustomObject]@{
            Domain = $domain
            Url = $url
            DA = $da
            Position = $pos
            Title = $title
        }
    }

    return [PSCustomObject]@{
        TotalHarvested = $harvested.Count
        Domains = $harvested
    }
}
