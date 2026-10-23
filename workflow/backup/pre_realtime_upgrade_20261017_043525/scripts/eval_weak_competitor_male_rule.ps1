<#
.SYNOPSIS
    eval_weak_competitor_male_rule.ps1
    Responsibility: Identify whether a given domain/URL is a weak UGC competitor
                    specifically for Male-intent keywords (virtually DA 1-9 equivalent seats).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$script:WeakCompetitorMalePatternCache = $null

function Get-WeakCompetitorMalePatterns {
    if ($null -ne $script:WeakCompetitorMalePatternCache) {
        return $script:WeakCompetitorMalePatternCache
    }

    $jsonPath = Join-Path $PSScriptRoot "..\data\weak_competitor_male_patterns.json"
    if (Test-Path $jsonPath) {
        try {
            $jsonContent = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
            $parsed = $jsonContent | ConvertFrom-Json
            $script:WeakCompetitorMalePatternCache = $parsed
            return $script:WeakCompetitorMalePatternCache
        } catch {
            Write-Warning "Failed to load weak_competitor_male_patterns.json: $_. Using fallback."
        }
    }

    # Fallback definition if JSON file is missing
    $script:WeakCompetitorMalePatternCache = [PSCustomObject]@{
        version = "1.0.0-male-fallback"
        categories = [PSCustomObject]@{
            qa_community = [PSCustomObject]@{
                name = "Q&A and Question Services (Male/General)"
                reason = "Amateur short answers, opinions, lack of structured SEO, easily beaten by dedicated guide"
                patterns = @(
                    "chiebukuro\.yahoo\.co\.jp",
                    "oshiete\.goo\.ne\.jp",
                    "okwave\.jp",
                    "jp\.quora\.com",
                    "q\.hatena\.ne\.jp",
                    "peing\.net",
                    "marshmallow-qa\.com",
                    "mond\.how",
                    "ask\.fm"
                )
            }
            curation_sns_bbs = [PSCustomObject]@{
                name = "Anonymous Forums and SNS Curations"
                reason = "Raw user thread dumps, emotional debates, fragment discussions"
                patterns = @(
                    "5ch\.net",
                    "2ch\.sc",
                    "open2ch\.net",
                    "togetter\.com",
                    "min\.togetter\.com",
                    "twilog\.togetter\.com",
                    "b\.hatena\.ne\.jp"
                )
            }
            knowledge_experience_ugc = [PSCustomObject]@{
                name = "Experience Notes and Technical Scratchpads"
                reason = "Casual personal journal, daily thoughts, short problem-solving snippets without comprehensive SEO"
                patterns = @(
                    "note\.com",
                    "qiita\.com",
                    "zenn\.dev",
                    "teratail\.com"
                )
            }
            subculture_review_wiki = [PSCustomObject]@{
                name = "Subculture, Book, Film Reviews and Volunteer Wikis"
                reason = "Short user impressions under 250 characters or basic volunteer wiki tables"
                patterns = @(
                    "bookmeter\.com",
                    "booklog\.jp",
                    "filmarks\.com",
                    "w\.atwiki\.jp",
                    "wikiwiki\.jp",
                    "seesaawiki\.jp",
                    "syosetu\.com",
                    "ncode\.syosetu\.com",
                    "kakuyomu\.jp"
                )
            }
            free_blog_diary = [PSCustomObject]@{
                name = "Free Blog and Diary Platforms (Male-frequent)"
                reason = "Casual personal diary, daily lifestyle thoughts, zero SEO heading optimization"
                patterns = @(
                    "hatenablog\.(com|jp)",
                    "hateblo\.jp",
                    "hatenadiary\.(jp|com)",
                    "(blog|livedoor)\\.livedoor\\.(jp|blog)",
                    "ldblog\.jp",
                    "doorblog\.jp",
                    "blog\.jp",
                    "blog\.fc2\.com",
                    "fc2\.com",
                    "ameblo\.jp",
                    "amebaownd\.com",
                    "seesaa\.net",
                    "sblo\.jp",
                    "blog\.goo\.ne\.jp",
                    "plaza\.rakuten\.co\.jp",
                    "exblog\.jp",
                    "cocolog-nifty\.com"
                )
            }
        }
    }
    return $script:WeakCompetitorMalePatternCache
}

function Test-WeakCompetitorMale {
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

    $patternsData = Get-WeakCompetitorMalePatterns
    $categories = $patternsData.categories

    foreach ($catProp in $categories.PSObject.Properties) {
        $catKey = $catProp.Name
        $catObj = $catProp.Value
        $catName = [string]$catObj.name
        $reason = [string]$catObj.reason
        $patterns = @($catObj.patterns)

        foreach ($p in $patterns) {
            $matched = $false
            if (-not [string]::IsNullOrWhiteSpace($targetDomain) -and ($targetDomain -match $p)) {
                $matched = $true
            }
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
