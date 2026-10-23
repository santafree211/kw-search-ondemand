<#
.SYNOPSIS
    eval_star_calculator.ps1
    Responsibility: Calculate exact star rating based on DA 1-9 count in SERP top 10.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\eval_weak_competitor_rule.ps1"

function Get-StrictStarEvaluation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,
        
        [Parameter(Mandatory=$true)]
        [int]$SearchVolume,
        
        [Parameter(Mandatory=$true)]
        $SerpEntries
    )

    # 1. Filter organic entries within rank 1 to 10
    $top10Organic = $SerpEntries | Where-Object { 
        $_.position -ge 1 -and $_.position -le 10 -and $_.type -eq "organic" 
    }

    $pureLowDaSites = @()
    $weakUgcSites = @()
    $winningSeats = @()

    foreach ($entry in $top10Organic) {
        $domain = [string]$entry.domain
        $url = [string]$entry.url
        $da = [int]$entry.domainAuthority

        # A. Check if the site is a weak UGC competitor (virtually DA 1-9)
        $ugcRes = Test-WeakCompetitor -Domain $domain -Url $url
        if ($ugcRes.IsWeakCompetitor) {
            $seatObj = [PSCustomObject]@{
                position = $entry.position
                domain = $domain
                url = $url
                domainAuthority = $da
                type = "weak_ugc"
                category = $ugcRes.Category
                reason = $ugcRes.Reason
            }
            $weakUgcSites += $seatObj
            $winningSeats += $seatObj
            continue
        }

        # B. Check if the site is a genuine independent low DA blog (DA 1-9)
        if ($da -ge 1 -and $da -le 9) {
            $seatObj = [PSCustomObject]@{
                position = $entry.position
                domain = $domain
                url = $url
                domainAuthority = $da
                type = "pure_low_da"
                category = "individual_blog"
                reason = "Independent personal blog with measured DA 1-9"
            }
            $pureLowDaSites += $seatObj
            $winningSeats += $seatObj
        }
    }

    $starCount = $winningSeats.Count

    # 3. Hit evaluation (Volume >= 1900 and Star >= 1)
    $isHit = ($SearchVolume -ge 1900) -and ($starCount -ge 1)
    $starChar = [char]0x2606 # Star character
    $starPrefix = [string]::new($starChar, $starCount)
    $lParen = [char]0xFF08   # Fullwidth left paren
    $rParen = [char]0xFF09   # Fullwidth right paren

    $formattedValue = if ($starCount -gt 0) {
        "$starPrefix$Keyword$lParen$SearchVolume$rParen"
    } else {
        ""
    }

    return [PSCustomObject]@{
        Keyword = $Keyword
        SearchVolume = $SearchVolume
        StarCount = $starCount
        WeakUgcCount = $weakUgcSites.Count
        PureLowDaCount = $pureLowDaSites.Count
        FormattedValue = $formattedValue
        IsHit = $isHit
        LowDaSites = $winningSeats
        PureLowDaSites = $pureLowDaSites
        WeakUgcSites = $weakUgcSites
    }
}


