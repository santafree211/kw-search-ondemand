<#
.SYNOPSIS
    workflow/scripts/serpapi_evaluator.ps1
    Responsibility: Precisely determine star ratings from Google real-time SERP (SerpApi).
    4-Stage Precise Determination Algorithm:
      Stage 1: Weak UGC Competitor Identification (Yahoo! Chiebukuro, note, ameblo, oshiete-goo, free blog subdomains)
      Stage 2: Strict Corporate & Enterprise Domain Exclusion (.co.jp, major platforms, aggregators)
      Stage 3: Reconciliation against Known Measured DA 1-9 Personal Blogs (Spreadsheet active rows + SQLite DB)
      Stage 4: Structural Personal Blog Heuristic Verification for Unknown Independent Domains
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$projectRoot\workflow\scripts\eval_weak_competitor_male_rule.ps1"
. "$projectRoot\workflow\scripts\eval_weak_competitor_rule.ps1"
. "$projectRoot\workflow\scripts\eval_corporate_domain_rule.ps1"
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

function Get-KnownPersonalBlogDomainMap {
    param(
        [switch]$IncludeSheetRows = $true
    )

    $map = @{}
    $dbPath = Initialize-ResearchDatabase

    # 1. From discovered_sites (SQLite DA 1-9)
    try {
        $sql1 = "SELECT DISTINCT domain, da FROM discovered_sites WHERE da >= 1 AND da <= 9;"
        $rows1 = @(Invoke-SqliteQuery -SqlQuery $sql1 -DbPath $dbPath)
        foreach ($r in $rows1) {
            $d = ([string]$r.domain).ToLower().Trim()
            if ($d.StartsWith("www.")) { $d = $d.Substring(4) }
            if (-not [string]::IsNullOrWhiteSpace($d)) {
                $map[$d] = [int]$r.da
            }
        }
    } catch {}

    # 2. From historical serp_entries (SQLite DA 1-9 measured by Ubersuggest)
    try {
        $sql2 = "SELECT DISTINCT domain, domain_authority FROM serp_entries WHERE domain_authority >= 1 AND domain_authority <= 9;"
        $rows2 = @(Invoke-SqliteQuery -SqlQuery $sql2 -DbPath $dbPath)
        foreach ($r in $rows2) {
            $d = ([string]$r.domain).ToLower().Trim()
            if ($d.StartsWith("www.")) { $d = $d.Substring(4) }
            if (-not [string]::IsNullOrWhiteSpace($d) -and -not $map.ContainsKey($d)) {
                $map[$d] = [int]$r.domain_authority
            }
        }
    } catch {}

    # 3. From active spreadsheet rows (Directly extracts DA 1-9 registered personal blogs)
    if ($IncludeSheetRows) {
        foreach ($g in @("female", "male")) {
            try {
                $profile = Resolve-SheetProfile -Gender $g
                $sheet = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName -TargetRange "A:H"
                if ($sheet -and $sheet.RawValues -and $sheet.RawValues.Count -gt 1) {
                    $headerRow = $sheet.RawValues[0]
                    $urlCol = 3
                    $daCol = 4
                    $txtSiteName = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x82,0xB5,0xE3,0x82,0xA4,0xE3,0x83,0x88,0xE5,0x90,0x8D))
                    for ($ci = 0; $ci -lt $headerRow.Count; $ci++) {
                        $ht = [string]$headerRow[$ci]
                        if ($ht -match "\bURL\b" -or $ht.EndsWith("URL") -or $ht -eq "Url") { $urlCol = $ci }
                        elseif ($ht -match "^DA$" -or $ht -match "DomainAuthority") { $daCol = $ci }
                    }
                    for ($ri = 1; $ri -lt $sheet.RawValues.Count; $ri++) {
                        $r = $sheet.RawValues[$ri]
                        $uVal = if ($r.Count -gt $urlCol) { [string]$r[$urlCol] } else { "" }
                        $daVal = if ($r.Count -gt $daCol) { [string]$r[$daCol] } else { "0" }
                        if ($uVal.StartsWith("http")) {
                            try {
                                $uri = [System.Uri]$uVal
                                $hostName = $uri.Host.ToLower().Trim()
                                if ($hostName.StartsWith("www.")) { $hostName = $hostName.Substring(4) }
                                $daNum = 0
                                [int]::TryParse($daVal, [ref]$daNum) | Out-Null
                                if ($daNum -ge 1 -and $daNum -le 9) {
                                    $map[$hostName] = $daNum
                                }
                            } catch {}
                        }
                    }
                }
            } catch {}
        }
    }

    return $map
}

function Evaluate-SerpApiResults {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$true)]
        [array]$OrganicResults,

        [Parameter(Mandatory=$false)]
        [string]$Gender = "male",

        [Parameter(Mandatory=$false)]
        [hashtable]$KnownPersonalBlogMap = $null
    )

    if ($null -eq $KnownPersonalBlogMap) {
        $KnownPersonalBlogMap = Get-KnownPersonalBlogDomainMap
    }

    $top10 = @($OrganicResults | Select-Object -First 10)
    $weakUgcSeats = 0
    $personalBlogSeats = 0
    $qualifyingDetails = @()
    $unmeasuredCandidates = @()

    $starChar = [char]0x2606 # Empty star character ☆

    foreach ($item in $top10) {
        $link = if ($item.link) { [string]$item.link } else { "" }
        if ([string]::IsNullOrWhiteSpace($link)) { continue }

        $domain = ""
        $pathAndQuery = ""
        try {
            $uri = [System.Uri]$link
            $domain = $uri.Host.ToLower().Trim()
            if ($domain.StartsWith("www.")) { $domain = $domain.Substring(4) }
            $pathAndQuery = $uri.PathAndQuery.ToLower()
        } catch {
            continue
        }

        # ----------------------------------------------------
        # STAGE 1: Weak UGC Competitor Identification (100% Certainty)
        # ----------------------------------------------------
        $ugcCheck = if ($Gender -eq "male") {
            Test-WeakCompetitorMale -Domain $domain -Url $link
        } else {
            Test-WeakCompetitor -Domain $domain -Url $link
        }

        if ($ugcCheck.IsWeakCompetitor) {
            $weakUgcSeats++
            $qualifyingDetails += [PSCustomObject]@{
                Position = $item.position
                Domain   = $domain
                Type     = "WeakUGC"
                Detail   = $ugcCheck.MatchedPattern
            }
            continue
        }

        # Check free blog service subdomains (e.g. *.hatenablog.com, livedoor.blog)
        if ($domain -match "(?i)\.(?:hatenablog\.(?:com|jp)|hatenadiary\.jp|livedoor\.blog|blog\.jp|seesaa\.net|fc2\.com|ameblo\.jp|weblog\.to)$") {
            $weakUgcSeats++
            $qualifyingDetails += [PSCustomObject]@{
                Position = $item.position
                Domain   = $domain
                Type     = "FreeBlogUGC"
                Detail   = "SubdomainPersonalBlog"
            }
            continue
        }

        # ----------------------------------------------------
        # STAGE 2: Strict Corporate Domain Exclusion
        # ----------------------------------------------------
        $corpCheck = Test-IsCorporateDomain -Domain $domain -Url $link
        if ($corpCheck.IsCorporate) {
            # Completely excluded corporate site
            continue
        }

        # ----------------------------------------------------
        # STAGE 3: Reconciliation against Known Measured DA 1-9 Personal Blogs
        # ----------------------------------------------------
        if ($KnownPersonalBlogMap.ContainsKey($domain)) {
            $da = $KnownPersonalBlogMap[$domain]
            $personalBlogSeats++
            $qualifyingDetails += [PSCustomObject]@{
                Position = $item.position
                Domain   = $domain
                Type     = "PersonalBlog"
                Detail   = "Measured_DA=$da"
            }
            continue
        }

        # ----------------------------------------------------
        # STAGE 4: Structural Personal Blog Heuristic Verification for Unknown Independent Domains
        # ----------------------------------------------------
        $isBlogStructure = $false
        $blogReason = ""

        # Personal WordPress / CMS standard permalink structure
        if ($pathAndQuery -match "(?i)\/\?p=\d+|\/archives\/\d+|\/entry\/|\/\d{4}\/\d{2}\/|\/post-\d+|\/article-\d+") {
            $isBlogStructure = $true
            $blogReason = "PersonalPermalinkStructure"
        }
        # Title personal markers (Pure ASCII matching via byte sequences)
        $title = if ($item.title) { [string]$item.title } else { "" }
        if (-not $isBlogStructure -and -not [string]::IsNullOrWhiteSpace($title)) {
            # Check for blog, diary, review in title
            if ($title -match "(?i)blog|review" -or 
                $title -match "(?:\u30D6\u30ED\u30B0|\u65E5\u8A18|\u4F53\u9A13\u8AC7|\u30EC\u30D3\u30E5\u30FC|\u500B\u4EBA)") {
                $isBlogStructure = $true
                $blogReason = "PersonalTitleKeywords"
            }
        }

        # Rule 3: only MEASURED DA 1-9 personal blogs may occupy a star seat.
        # A structural/heuristic guess has no measured DA, so it must NOT add a seat
        # (it is recorded as an unmeasured candidate for DA measurement follow-up only).
        if ($isBlogStructure) {
            $unmeasuredCandidates += [PSCustomObject]@{
                Position = $item.position
                Domain   = $domain
                Type     = "UnmeasuredPersonalBlogCandidate"
                Detail   = "NeedsDaMeasurement ($blogReason)"
            }
            continue
        }
    }

    $totalSeats = $weakUgcSeats + $personalBlogSeats
    $starCount = $totalSeats
    $hasStars = ($starCount -ge 1)

    $starString = if ($starCount -gt 0) {
        [string]::new($starChar, $starCount)
    } else {
        ""
    }

    return [PSCustomObject]@{
        Keyword             = $Keyword
        TotalSeats          = $totalSeats
        StarCount           = $starCount
        StarString          = $starString
        HasStars            = $hasStars
        IsStarLost          = ($starCount -eq 0)
        WeakUgcSeats        = $weakUgcSeats
        PersonalBlogSeats   = $personalBlogSeats
        QualifyingDetails   = $qualifyingDetails
        Top10Count          = $top10.Count
    }
}
