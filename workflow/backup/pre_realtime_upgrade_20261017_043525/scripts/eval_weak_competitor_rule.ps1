<#
.SYNOPSIS
    eval_weak_competitor_rule.ps1
    Responsibility: Identify whether a given domain/URL is a weak UGC/CGM competitor
                    (virtually DA 1-9 equivalent seats in top 10 SERP).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$script:WeakCompetitorPatternCache = $null

function Get-WeakCompetitorPatterns {
    if ($null -ne $script:WeakCompetitorPatternCache) {
        return $script:WeakCompetitorPatternCache
    }

    $jsonPath = Join-Path $PSScriptRoot "..\data\weak_competitor_patterns.json"
    if (Test-Path $jsonPath) {
        try {
            $jsonContent = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
            $parsed = $jsonContent | ConvertFrom-Json
            $script:WeakCompetitorPatternCache = $parsed
            return $script:WeakCompetitorPatternCache
        } catch {
            Write-Warning "Failed to load weak_competitor_patterns.json: $_. Using fallback."
        }
    }

    # Fallback definition if JSON file is missing
    $script:WeakCompetitorPatternCache = [PSCustomObject]@{
        version = "1.0.0-fallback"
        categories = [PSCustomObject]@{
            qa_community = [PSCustomObject]@{
                name = "Q&A and Question Services"
                reason = "Amateur short answers, opinions, lack of structured SEO"
                patterns = @(
                    "chiebukuro\.yahoo\.co\.jp",
                    "oshiete\.goo\.ne\.jp",
                    "okwave\.jp",
                    "komachi\.yomiuri\.co\.jp",
                    "jp\.quora\.com",
                    "q\.hatena\.ne\.jp"
                )
            }
            women_community = [PSCustomObject]@{
                name = "Women Community and BBS"
                reason = "Anonymous forum comments, emotional chat, lack of comprehensive solution"
                patterns = @(
                    "girlschannel\.net",
                    "mamastar\.jp",
                    "select\.mamastar\.jp",
                    "mamari\.jp"
                )
            }
            free_blog_diary = [PSCustomObject]@{
                name = "Free Blog and Diary Platforms"
                reason = "Casual personal journal, daily thoughts, zero keyword optimization"
                patterns = @(
                    "note\.com",
                    "ameblo\.jp",
                    "hatenablog\.(com|jp)",
                    "hateblo\.jp",
                    "hatenadiary\.(jp|com)",
                    "(blog|livedoor)\.livedoor\.(jp|blog)",
                    "ldblog\.jp",
                    "blog\.fc2\.com",
                    "plaza\.rakuten\.co\.jp",
                    "seesaa\.net",
                    "blog\.goo\.ne\.jp",
                    "exblog\.jp"
                )
            }
            review_culture = [PSCustomObject]@{
                name = "Culture, Book and Entertainment Reviews"
                reason = "Short impressions and snippets under 250 chars"
                patterns = @(
                    "bookmeter\.com",
                    "booklog\.jp",
                    "filmarks\.com"
                )
            }
            curation_sns_bbs = [PSCustomObject]@{
                name = "Curation, SNS snippets and Forum threads"
                reason = "Raw user tweets or chat thread dumps"
                patterns = @(
                    "togetter\.com",
                    "min\.togetter\.com",
                    "5ch\.net"
                )
            }
        }
    }
    return $script:WeakCompetitorPatternCache
}

function Test-WeakCompetitor {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Domain = "",

        [Parameter(Mandatory=$false)]
        [string]$Url = ""
    )

    $targetDomain = $Domain.Trim().ToLower()
    $targetUrl = $Url.Trim().ToLower()

    # If domain is empty but URL is provided, extract host
    if ([string]::IsNullOrWhiteSpace($targetDomain) -and -not [string]::IsNullOrWhiteSpace($targetUrl)) {
        try {
            $uri = [System.Uri]$targetUrl
            $targetDomain = $uri.Host.ToLower()
        } catch {
            $targetDomain = $targetUrl
        }
    }

    $patternsData = Get-WeakCompetitorPatterns
    $categories = $patternsData.categories

    foreach ($catProp in $categories.PSObject.Properties) {
        $catKey = $catProp.Name
        $catObj = $catProp.Value
        $catName = [string]$catObj.name
        $reason = [string]$catObj.reason
        $patterns = @($catObj.patterns)

        foreach ($p in $patterns) {
            # Check domain match
            $matched = $false
            if (-not [string]::IsNullOrWhiteSpace($targetDomain) -and ($targetDomain -match $p)) {
                $matched = $true
            }
            # Check full URL match if path pattern is involved
            if (-not $matched -and -not [string]::IsNullOrWhiteSpace($targetUrl) -and ($targetUrl -match $p)) {
                $matched = $true
            }

            if ($matched) {
                return [PSCustomObject]@{
                    IsWeakCompetitor = $true
                    Category = $catKey
                    CategoryName = $catName
                    MatchedPattern = $p
                    Reason = $reason
                    Domain = $targetDomain
                    Url = $targetUrl
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsWeakCompetitor = $false
        Category = ""
        CategoryName = ""
        MatchedPattern = ""
        Reason = ""
        Domain = $targetDomain
        Url = $targetUrl
    }
}
