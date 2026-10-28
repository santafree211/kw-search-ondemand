<#
.SYNOPSIS
    commit_policy_guard.ps1
    Single Responsibility: Enforce site eligibility (DA 1-9, non-UGC) and keyword policy guards (Gender, YMYL, Entertainment).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\guard_check_gender_kw.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"

function Assert-CommitSiteAndKeywordPolicy {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SiteName,

        [Parameter(Mandatory=$false)]
        [string]$Url = "",

        [Parameter(Mandatory=$true)]
        [int]$Da,

        [Parameter(Mandatory=$false)]
        [string]$OriginKw = "",

        [Parameter(Mandatory=$true)]
        [string[]]$WinningKws,

        [Parameter(Mandatory=$true)]
        [string]$Gender
    )

    if ([string]::IsNullOrWhiteSpace($SiteName) -or $WinningKws.Count -eq 0) {
        throw "SiteName and at least 1 WinningKw are required."
    }

    # 1. DA Range Gate (Rule 3: Personal blogs DA 1-9 only)
    if ($Da -lt 1 -or $Da -gt 9) {
        throw "DA Range Violation: Only personal blogs with DA 1-9 are eligible (Received DA: $Da). Aborting commit."
    }

    # 2. UGC/CGM Exclusion Gate (Rule 3: Cannot register UGC platform as a row subject)
    $checkDomain = ""
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $uUri = [System.Uri]$Url
            $checkDomain = $uUri.Host.ToLower().Trim()
            if ($checkDomain.StartsWith("www.")) { $checkDomain = $checkDomain.Substring(4) }
        } catch {
            $checkDomain = $Url.ToLower().Trim()
        }
    }
    $isUgc = if ($Gender -eq "male") {
        Test-WeakCompetitorMale -Domain $checkDomain -Url $Url
    } else {
        Test-WeakCompetitor -Domain $checkDomain -Url $Url
    }
    if ($isUgc.IsWeakCompetitor) {
        throw "UGC Platform Row Subject Violation: Cannot register weak UGC/CGM competitor ('$Url', Category: $($isUgc.CategoryName)) as a site row subject. Only pure personal blogs (DA 1-9) are eligible. Aborting commit."
    }

    # 3. Gender Guard Gate
    foreach ($wKw in $WinningKws) {
        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $wKw
        if (-not $gCheck.IsAllowed) {
            throw "Gender Guard Violation: $($gCheck.Reason). Aborting commit."
        }
    }

    # 4. YMYL Guard Gate (Physical Block)
    if (-not [string]::IsNullOrWhiteSpace($OriginKw)) {
        $yCheckOrigin = Test-KeywordYmylEligibility -Keyword $OriginKw
        if ($yCheckOrigin.IsYmyl) {
            throw "YMYL Guard Violation (OriginKw): $($yCheckOrigin.Reason). Aborting commit."
        }
    }
    foreach ($wKw in $WinningKws) {
        $yCheck = Test-KeywordYmylEligibility -Keyword $wKw
        if ($yCheck.IsYmyl) {
            throw "YMYL Guard Violation (WinningKw): $($yCheck.Reason). Aborting commit."
        }
    }

    # 5. Entertainment & Fiction Guard Gate (Physical Block)
    if (-not [string]::IsNullOrWhiteSpace($OriginKw)) {
        $entCheckOrigin = Test-KeywordEntertainmentEligibility -Keyword $OriginKw
        if ($entCheckOrigin.IsEntertainment) {
            throw "Entertainment Guard Violation (OriginKw): $($entCheckOrigin.Reason). Aborting commit."
        }
    }
    foreach ($wKw in $WinningKws) {
        $entCheck = Test-KeywordEntertainmentEligibility -Keyword $wKw
        if ($entCheck.IsEntertainment) {
            throw "Entertainment Guard Violation (WinningKw): $($entCheck.Reason). Aborting commit."
        }
    }
}
