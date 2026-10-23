<#
.SYNOPSIS
    guard_sheet_reconcile.ps1
    Responsibility: 3-Way Reconciliation Audit between Spreadsheet, Research Rules (Rule 3/4),
                    and Ubersuggest Raw Data (Raw API Archive JSON, Cache, DB).
                    Supports Female, Male, and Unified All (Both) execution.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$scriptsDir = $PSScriptRoot
. "$scriptsDir\sheet_profile_resolver.ps1"
. "$scriptsDir\sheet_data_reader.ps1"
. "$scriptsDir\guard_normal_state.ps1"
. "$scriptsDir\eval_star_calculator.ps1"
. "$scriptsDir\eval_weak_competitor_rule.ps1"
. "$scriptsDir\eval_star_calculator_male.ps1"
. "$scriptsDir\guard_check_ymyl_kw.ps1"
. "$scriptsDir\guard_check_entertainment_kw.ps1"
. "$scriptsDir\guard_check_gender_kw.ps1"
. "$scriptsDir\serpapi_evaluator.ps1"

function Normalize-KwForMatch {
    param([string]$kw)
    if ([string]::IsNullOrWhiteSpace($kw)) { return "" }
    return ($kw -replace "[\s\u3000]+", "").ToLower()
}

function Invoke-SingleProfileReconciliation {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,

        [Parameter(Mandatory=$false)]
        [int]$RowNumber = 0,

        [Parameter(Mandatory=$false)]
        [switch]$CheckAllRows = $false,

        [Parameter(Mandatory=$false)]
        [string]$RawArchiveDir = "",

        [Parameter(Mandatory=$false)]
        [string]$CachePath = "",

        [Parameter(Mandatory=$false)]
        [hashtable]$VolumeMap = $null,

        [Parameter(Mandatory=$false)]
        [hashtable]$SerpIndex = $null,

        [Parameter(Mandatory=$false)]
        [hashtable]$DomainDaMap = $null,

        [Parameter(Mandatory=$false)]
        [hashtable]$GoogleSerpIndex = $null,

        [Parameter(Mandatory=$false)]
        [hashtable]$KnownBlogMap = $null
    )

    $profile = Resolve-SheetProfile -ProfileName $ProfileName
    $sheetId = $profile.SpreadsheetId
    $sheetTitle = $profile.Title
    $isFemale = ($profile.Gender -eq "female")

    # 1. Read Spreadsheet Data
    $sheetData = Read-SheetData -SheetId $sheetId -TargetSheetName $profile.TargetSheetName
    $rows = $sheetData.RawValues
    if (-not $rows -or $rows.Count -le 1) {
        throw "Spreadsheet ($ProfileName) has no data rows."
    }

    # 2. Resolve Column Indices dynamically from Header Row
    $headerRow = $rows[0]
    $siteCol = 1
    $urlCol = 3
    $daCol = 4
    $kwStartCol = 8

    $foundKw = $false
    for ($i = 0; $i -lt $headerRow.Count; $i++) {
        $hText = [string]$headerRow[$i]
        if ($hText -match "^(サイト名|SiteName|Site)$" -or $hText.EndsWith([char]0x30b5 + [char]0x30a4 + [char]0x30c8 + [char]0x540d)) { 
            $siteCol = $i 
        }
        elseif ($hText -match "^URL$" -or $hText -match "^Url$") { 
            $urlCol = $i 
        }
        elseif ($hText -match "^DA$" -or $hText -match "^DomainAuthority$") { 
            $daCol = $i 
        }
        elseif (-not $foundKw -and ($hText -match "WinningKw1\b" -or $hText -match "KW1\b" -or $hText.EndsWith("KW1"))) { 
            $kwStartCol = $i 
            $foundKw = $true
        }
    }

    $targetIndices = @()
    if ($RowNumber -gt 0) {
        $rIdx = $RowNumber - 1
        if ($rIdx -ge 1 -and $rIdx -lt $rows.Count) {
            $targetIndices += $rIdx
        } else {
            throw "RowNumber $RowNumber is out of range (Sheet has $($rows.Count) rows)."
        }
    } elseif ($CheckAllRows) {
        for ($r = 1; $r -lt $rows.Count; $r++) {
            $targetIndices += $r
        }
    } else {
        # Default: audit EVERY row. (Previously only the last row was audited, which let
        # violations in all other rows pass unnoticed.)
        for ($r = 1; $r -lt $rows.Count; $r++) {
            $targetIndices += $r
        }
    }

    # 3. Execute 3-Way Audit for Target Rows
    $auditResults = @()
    $totalViolations = 0
    $reconcileSeenKws = @{}
    $reconcileSeenDomains = @{}
    $unverifiedStarKws = 0

    $starChar = [char]0x2606
    $starBlack = [char]0x2605
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

    foreach ($idx in $targetIndices) {
        $row = $rows[$idx]
        $rowNum = $idx + 1

        $siteName = if ($row.Count -gt $siteCol) { [string]$row[$siteCol] } else { "" }
        $url = if ($row.Count -gt $urlCol) { [string]$row[$urlCol] } else { "" }
        $daStr = if ($row.Count -gt $daCol) { [string]$row[$daCol] } else { "" }
        $sheetDa = 0
        [int]::TryParse($daStr, [ref]$sheetDa) | Out-Null

        if ([string]::IsNullOrWhiteSpace($siteName) -and [string]::IsNullOrWhiteSpace($url)) {
            continue
        }

        # Extract domain
        $domain = ""
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            try { $domain = ([System.Uri]$url).Host.ToLower() } catch { $domain = $url.ToLower() }
        }

        $rowViolations = @()

        # [Site Domain Uniqueness Check]
        $cleanDom = if ($domain.StartsWith("www.")) { $domain.Substring(4) } else { $domain }
        if (-not [string]::IsNullOrWhiteSpace($cleanDom)) {
            if ($reconcileSeenDomains.ContainsKey($cleanDom)) {
                if ($reconcileSeenDomains[$cleanDom] -ne ($rowNum - 1)) {
                    $rowViolations += "Duplicate Site Domain Violation: Domain '$cleanDom' is already registered at Row $($reconcileSeenDomains[$cleanDom])."
                } else {
                    $reconcileSeenDomains[$cleanDom] = $rowNum
                }
            } else {
                $reconcileSeenDomains[$cleanDom] = $rowNum
            }
        }

        # [Rule 3 Check 1] Personal Blog Subject Guard (Gender-Specific UGC check)
        $ugcCheck = if ($isFemale) {
            Test-WeakCompetitor -Domain $domain -Url $url
        } else {
            Test-WeakCompetitorMale -Domain $domain -Url $url
        }
        $isPurePersonal = -not $ugcCheck.IsWeakCompetitor
        if (-not $isPurePersonal) {
            $rowViolations += "Rule 3 Subject Violation: Row registered as UGC platform ($($ugcCheck.CategoryName): $domain)."
        }

        # [Rule 3 Check 2] Measured DA range 1-9
        $isDaInRange = ($sheetDa -ge 1 -and $sheetDa -le 9)
        if (-not $isDaInRange) {
            $rowViolations += "Rule 3 DA Range Violation: Sheet DA is $sheetDa (Must be 1-9)."
        }

        # [Uber Raw Check 1] Domain DA 1-to-1 Match
        $rawDaInfo = $null
        $rawDaMatch = $false
        $rawDaVal = $null
        if ($DomainDaMap.ContainsKey($domain)) {
            $rawDaInfo = $DomainDaMap[$domain]
            $rawDaVal = $rawDaInfo.DomainAuthority
            $rawDaMatch = ($rawDaVal -eq $sheetDa)
            if (-not $rawDaMatch) {
                $rowViolations += "Raw DA Mismatch: Sheet DA is $sheetDa, but Raw Uber DA is $rawDaVal (Source: $($rawDaInfo.Source))."
            }
        } else {
            $rawDaMatch = $null
        }

        # [Keyword Reconciliation]
        $kwAudits = @()
        for ($c = $kwStartCol; $c -lt [Math]::Min($row.Count, ($kwStartCol + 15)); $c++) {
            $cellVal = [string]$row[$c]
            if ([string]::IsNullOrWhiteSpace($cellVal)) { continue }

            $lines = $cellVal -split "`r?`n"
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

                # A. Black star garbage check
                if ($trimmed.StartsWith($starBlack)) {
                    $rowViolations += "Rule 3 Garbage: Black star detected: '$trimmed'."
                }

                # B. Extract Stars
                $sheetStars = 0
                while ($sheetStars -lt $trimmed.Length -and $trimmed[$sheetStars] -eq $starChar) {
                    $sheetStars++
                }

                # C. Extract Volume & Keyword
                $cleanKw = $trimmed.Substring($sheetStars).Trim()
                $sheetVol = 0
                if ($cleanKw -match $parenPattern) {
                    $sheetVol = [int]$matches[1]
                    $cleanKw = ($cleanKw -replace $parenPattern, "").Trim()
                } else {
                    $rowViolations += "Format Error: No volume pattern found in '$trimmed'."
                }

                $normKw = Normalize-KwForMatch -kw $cleanKw

                # D. Keyword Uniqueness Check (Token-Permutation Match)
                $tokens = $cleanKw -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                $sortedNormKw = (($tokens | Sort-Object) -join " ").ToLower()
                if ($reconcileSeenKws.ContainsKey($sortedNormKw)) {
                    $prevItem = $reconcileSeenKws[$sortedNormKw]
                    $rowViolations += "Duplicate Keyword Violation: '$cleanKw' is already registered at Row $($prevItem.Row) Col $($prevItem.Col)."
                } else {
                    $reconcileSeenKws[$sortedNormKw] = @{ Row = $rowNum; Col = [char](65 + $c) }
                }

                # E. Rule 4: Search Volume Threshold (Vol >= 1900)
                $volRulePass = ($sheetVol -ge 1900)
                if (-not $volRulePass) {
                    $rowViolations += "Rule 4 Violation for '$cleanKw': Sheet volume is $sheetVol (Must be >= 1900)."
                }

                # E.2 YMYL / Pharmaceutical Law Audit
                $ymylAudit = Test-KeywordYmylEligibility -Keyword $cleanKw
                if ($ymylAudit.IsYmyl) {
                    $rowViolations += "YMYL Violation for '$cleanKw': matched forbidden pattern '$($ymylAudit.MatchedPattern)' in category '$($ymylAudit.CategoryName)'."
                }

                # E.3 Entertainment / Fiction Audit
                $entAudit = Test-KeywordEntertainmentEligibility -Keyword $cleanKw
                if ($entAudit.IsEntertainment) {
                    $rowViolations += "Entertainment Violation for '$cleanKw': matched forbidden pattern '$($entAudit.MatchedPattern)' in category '$($entAudit.CategoryName)'."
                }

                # E.4 Gender Audit
                $genderAudit = Test-KeywordGenderEligibility -Gender $profile.Gender -Keyword $cleanKw
                if (-not $genderAudit.IsAllowed) {
                    $rowViolations += "Gender Violation for '$cleanKw': $($genderAudit.Reason)."
                }

                # E. Raw Volume Match
                $rawVol = $null
                $rawVolMatch = $false
                if ($VolumeMap.ContainsKey($normKw)) {
                    $rawVol = $VolumeMap[$normKw]
                    $rawVolMatch = ($rawVol -eq $sheetVol)
                    if (-not $rawVolMatch) {
                        $rowViolations += "Raw Volume Mismatch for '$cleanKw': Sheet has $sheetVol, but Raw Cache has $rawVol."
                    }
                } else {
                    $rawVolMatch = $null
                }

                # F. Raw SERP & Star Calculation Match (Gender-Specific Star Calculator)
                $serpRawObj = $null
                $calcStars = $null
                $starMatch = $false
                $serpFile = ""
                $weakPersonalCount = 0
                $weakUgcCount = 0
                $lowDaDetails = @()

                $exactK = $cleanKw.ToLower().Trim()
                if ($SerpIndex.ContainsKey($exactK)) {
                    $serpRawObj = $SerpIndex[$exactK]
                } elseif ($SerpIndex.ContainsKey($normKw)) {
                    $serpRawObj = $SerpIndex[$normKw]
                }

                $googleOrganic = $null
                if ($null -ne $GoogleSerpIndex) {
                    if ($GoogleSerpIndex.ContainsKey($exactK)) { $googleOrganic = $GoogleSerpIndex[$exactK] }
                    elseif ($GoogleSerpIndex.ContainsKey($normKw)) { $googleOrganic = $GoogleSerpIndex[$normKw] }
                }

                if ($null -ne $googleOrganic) {
                    # Google real SERP (SerpApi) is the latest actual result -> source of truth for stars.
                    $gEval = Evaluate-SerpApiResults -Keyword $cleanKw -OrganicResults $googleOrganic -Gender $profile.Gender -KnownPersonalBlogMap $KnownBlogMap
                    $calcStars = $gEval.StarCount
                    $weakPersonalCount = $gEval.PersonalBlogSeats
                    $weakUgcCount = $gEval.WeakUgcSeats
                    $serpFile = "serpapi_call_logs:google"
                    $starMatch = ($calcStars -eq $sheetStars)
                    if (-not $starMatch) {
                        $rowViolations += "Google SERP Star Mismatch for '$cleanKw': Sheet has $sheetStars stars, but latest Google SERP yields $calcStars ($weakPersonalCount measured-DA personal + $weakUgcCount UGC)."
                    }
                } elseif ($null -ne $serpRawObj) {
                    $serpFile = $serpRawObj.FileName

                    $starEval = if ($isFemale) {
                        Get-StrictStarEvaluation -Keyword $cleanKw -SearchVolume $sheetVol -SerpEntries $serpRawObj.SerpEntries
                    } else {
                        Get-StrictStarEvaluationMale -Keyword $cleanKw -SearchVolume $sheetVol -SerpEntries $serpRawObj.SerpEntries
                    }

                    $calcStars = $starEval.StarCount
                    $weakPersonalCount = $starEval.PureLowDaCount
                    $weakUgcCount = $starEval.WeakUgcCount
                    # Rule 3 standard: 3 or more weak seats qualify for the Star 3+ (☆☆☆) tier
                    $starMatch = ($calcStars -eq $sheetStars) -or ($sheetStars -ge 3 -and $calcStars -ge 3)

                    if (-not $starMatch) {
                        $rowViolations += "Raw Star Mismatch for '$cleanKw': Sheet has $sheetStars stars, but Raw SERP top 10 yields $calcStars weak seats ($weakPersonalCount personal + $weakUgcCount UGC)."
                    }
                } else {
                    # No evidence at all: surface it instead of silently passing.
                    $starMatch = $null
                    $unverifiedStarKws++
                }

                $kwAudits += [PSCustomObject]@{
                    RawText = $trimmed
                    Keyword = $cleanKw
                    SheetStars = $sheetStars
                    CalculatedStars = $calcStars
                    StarMatch = $starMatch
                    SheetVolume = $sheetVol
                    RawVolume = $rawVol
                    VolumeMatch = $rawVolMatch
                    VolumeEligible = $volRulePass
                    IsYmyl = $ymylAudit.IsYmyl
                    YmylMatchedPattern = $ymylAudit.MatchedPattern
                    WeakPersonalCount = $weakPersonalCount
                    WeakUgcCount = $weakUgcCount
                    SerpRawFile = $serpFile
                    LowDaDetails = $lowDaDetails
                }
            }
        }

        $totalViolations += $rowViolations.Count

        $auditResults += [PSCustomObject]@{
            Row = $rowNum
            SiteName = $siteName
            Url = $url
            Domain = $domain
            SheetDa = $sheetDa
            RawDa = $rawDaVal
            DaMatch = $rawDaMatch
            IsPurePersonal = $isPurePersonal
            Keywords = $kwAudits
            Violations = $rowViolations
            Passed = ($rowViolations.Count -eq 0)
        }
    }

    # 4. Overall Sheet Golden Ratio Audit (STRICT: no healing bypass - a ratio below 50% must FAIL the audit)
    $goldenRatioEval = Test-NormalStateStandard -SheetRows $rows

    $overallPassed = ($totalViolations -eq 0 -and $goldenRatioEval.Passed)

    return [PSCustomObject]@{
        Profile = $ProfileName
        SpreadsheetId = $sheetId
        Title = $sheetTitle
        OverallPassed = $overallPassed
        TotalViolations = $totalViolations
        UnverifiedStarKeywords = $unverifiedStarKws
        GoldenRatioPassed = $goldenRatioEval.Passed
        GoldenRatio = [PSCustomObject]@{
            Star3Percent = $goldenRatioEval.Star3Percent
            Star2Percent = $goldenRatioEval.Star2Percent
            Star1Percent = $goldenRatioEval.Star1Percent
            Errors = $goldenRatioEval.Errors
        }
        RowResults = $auditResults
    }
}

function Invoke-Sheet3WayReconciliation {
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet("female", "male", "all", "both")]
        [string]$ProfileName = "all",

        [Parameter(Mandatory=$false)]
        [int]$RowNumber = 0,

        [Parameter(Mandatory=$false)]
        [switch]$CheckAllRows = $false,

        [Parameter(Mandatory=$false)]
        [string]$RawArchiveDir = "",

        [Parameter(Mandatory=$false)]
        [string]$CachePath = "",

        [Parameter(Mandatory=$false)]
        [switch]$Silent = $false
    )

    $projectRoot = Split-Path -Parent (Split-Path -Parent $scriptsDir)
    if ([string]::IsNullOrWhiteSpace($RawArchiveDir)) {
        $RawArchiveDir = Join-Path $projectRoot "workflow\data\raw_api_archive"
    }
    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $projectRoot "workflow\data\verified_volume_cache.json"
    }

    # Build Raw Indexes once for all profiles
    $volumeMap = @{}
    if (Test-Path $CachePath) {
        try {
            $cacheText = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
            $parsed = $cacheText | ConvertFrom-Json
            if ($parsed -is [array]) {
                foreach ($item in $parsed) {
                    if ($item.Keyword -and $null -ne $item.Volume) {
                        $normK = Normalize-KwForMatch -kw ([string]$item.Keyword)
                        $vol = [int]$item.Volume
                        if (-not $volumeMap.ContainsKey($normK) -or $vol -gt $volumeMap[$normK]) {
                            $volumeMap[$normK] = $vol
                        }
                    }
                }
            } elseif ($parsed.verified_volumes) {
                foreach ($prop in $parsed.verified_volumes.PSObject.Properties) {
                    if ($prop.Name -and $null -ne $prop.Value) {
                        $normK = Normalize-KwForMatch -kw ([string]$prop.Name)
                        $vol = [int]$prop.Value
                        if (-not $volumeMap.ContainsKey($normK) -or $vol -gt $volumeMap[$normK]) {
                            $volumeMap[$normK] = $vol
                        }
                    }
                }
            }
        } catch {
            Write-Warning "Failed to read volume cache: $_"
        }
    }

    $serpIndex = @{}
    $domainDaMap = @{}

    $dbPath = Join-Path $projectRoot "workflow\data\research.db"
    $loadedFromDb = $false
    if (Test-Path $dbPath) {
        try {
            . "$scriptsDir\db_sqlite_manager.ps1"
            $archiveRows = Invoke-SqliteQuery -SqlQuery "SELECT endpoint, target_key, response_json FROM raw_api_archive WHERE endpoint IN ('serp_analysis', 'domain_keywords');" -DbPath $dbPath
            if ($archiveRows -and $archiveRows.Count -gt 0) {
                foreach ($row in $archiveRows) {
                    try {
                        $p = $row.response_json | ConvertFrom-Json
                        if ($row.endpoint -eq "serp_analysis") {
                            $kw = [string]$row.target_key
                            if ([string]::IsNullOrWhiteSpace($kw) -and $p.keyword) { $kw = [string]$p.keyword }
                            if ([string]::IsNullOrWhiteSpace($kw) -and $p.result -and $p.result.keyword) { $kw = [string]$p.result.keyword }
                            $entries = $p.serpEntries
                            if (-not $entries -and $p.result -and $p.result.serp_table) { $entries = $p.result.serp_table }

                            if (-not [string]::IsNullOrWhiteSpace($kw) -and $entries) {
                                $exactK = $kw.ToLower().Trim()
                                $normK = Normalize-KwForMatch -kw $kw
                                $serpObj = [PSCustomObject]@{
                                    Keyword = $kw
                                    FilePath = "sqlite:raw_api_archive"
                                    FileName = "sqlite:serp_analysis_$kw"
                                    SerpEntries = $entries
                                }
                                $serpIndex[$exactK] = $serpObj
                                if (-not $serpIndex.ContainsKey($normK)) {
                                    $serpIndex[$normK] = $serpObj
                                }

                                foreach ($e in $entries) {
                                    $dom = [string]$e.domain
                                    if ([string]::IsNullOrWhiteSpace($dom) -and $e.url) {
                                        try { $dom = ([System.Uri][string]$e.url).Host.ToLower() } catch {}
                                    }
                                    if (-not [string]::IsNullOrWhiteSpace($dom) -and $null -ne $e.domainAuthority) {
                                        $domLow = $dom.ToLower().Trim()
                                        if (-not $domainDaMap.ContainsKey($domLow)) {
                                            $domainDaMap[$domLow] = [PSCustomObject]@{
                                                DomainAuthority = [int]$e.domainAuthority
                                                Source = "sqlite:raw_api_archive"
                                            }
                                        }
                                    }
                                }
                            }
                        } elseif ($row.endpoint -eq "domain_keywords") {
                            $domName = [string]$row.target_key
                            if ($p.result -and $p.result.domain_overview -and $null -ne $p.result.domain_overview.domain_authority) {
                                $domainDaMap[$domName.ToLower()] = [PSCustomObject]@{
                                    DomainAuthority = [int]$p.result.domain_overview.domain_authority
                                    Source = "sqlite:raw_api_archive"
                                }
                            }
                        }
                    } catch {}
                }
                $loadedFromDb = ($serpIndex.Count -gt 0)
            }
        } catch {}
    }

    if (-not $loadedFromDb -and (Test-Path $RawArchiveDir)) {
        $serpFiles = Get-ChildItem -Path $RawArchiveDir -Recurse -Filter "serp_analysis_*.json" -ErrorAction SilentlyContinue
        foreach ($sf in $serpFiles) {
            try {
                $rawTxt = [System.IO.File]::ReadAllText($sf.FullName, [System.Text.Encoding]::UTF8)
                $p = $rawTxt | ConvertFrom-Json
                $kw = [string]$p.keyword
                if ([string]::IsNullOrWhiteSpace($kw) -and $p.result -and $p.result.keyword) {
                    $kw = [string]$p.result.keyword
                }
                $entries = $p.serpEntries
                if (-not $entries -and $p.result -and $p.result.serp_table) {
                    $entries = $p.result.serp_table
                }

                if (-not [string]::IsNullOrWhiteSpace($kw) -and $entries) {
                    $exactK = $kw.ToLower().Trim()
                    $normK = Normalize-KwForMatch -kw $kw
                    $serpObj = [PSCustomObject]@{
                        Keyword = $kw
                        FilePath = $sf.FullName
                        FileName = $sf.Name
                        SerpEntries = $entries
                    }
                    $serpIndex[$exactK] = $serpObj
                    if (-not $serpIndex.ContainsKey($normK)) {
                        $serpIndex[$normK] = $serpObj
                    }

                    foreach ($e in $entries) {
                        $dom = [string]$e.domain
                        if ([string]::IsNullOrWhiteSpace($dom) -and $e.url) {
                            try { $dom = ([System.Uri][string]$e.url).Host.ToLower() } catch {}
                        }
                        if (-not [string]::IsNullOrWhiteSpace($dom) -and $null -ne $e.domainAuthority) {
                            $domLow = $dom.ToLower().Trim()
                            if (-not $domainDaMap.ContainsKey($domLow)) {
                                $domainDaMap[$domLow] = [PSCustomObject]@{
                                    DomainAuthority = [int]$e.domainAuthority
                                    Source = $sf.Name
                                }
                            }
                        }
                    }
                }
            } catch {}
        }

        $domFiles = Get-ChildItem -Path $RawArchiveDir -Recurse -Filter "domain_keywords_*.json" -ErrorAction SilentlyContinue
        foreach ($df in $domFiles) {
            try {
                $rawTxt = [System.IO.File]::ReadAllText($df.FullName, [System.Text.Encoding]::UTF8)
                $p = $rawTxt | ConvertFrom-Json
                $domName = $df.Name -replace "^domain_keywords_", "" -replace "\.json$", ""
                if ($p.result -and $p.result.domain_overview -and $null -ne $p.result.domain_overview.domain_authority) {
                    $domainDaMap[$domName.ToLower()] = [PSCustomObject]@{
                        DomainAuthority = [int]$p.result.domain_overview.domain_authority
                        Source = $df.Name
                    }
                }
            } catch {}
        }
    }

    $profilesToRun = if ($ProfileName -in @("all", "both")) { @("female", "male") } else { @($ProfileName) }
    $results = @()
    $allPassed = $true

    # Google real-SERP evidence (SerpApi): latest stored result per keyword
    $googleSerpIndex = @{}
    $knownBlogMap = $null
    try {
        if (Test-Path $dbPath) {
            $gRows = @(Invoke-SqliteQuery -SqlQuery "SELECT keyword, response_json FROM serpapi_call_logs WHERE http_status = 200 AND response_json IS NOT NULL ORDER BY id ASC;" -DbPath $dbPath)
            foreach ($gr in $gRows) {
                try {
                    $gp = [string]$gr.response_json | ConvertFrom-Json
                    if ($gp.organic_results) {
                        $gk = ([string]$gr.keyword).ToLower().Trim()
                        $googleSerpIndex[$gk] = @($gp.organic_results)
                        $googleSerpIndex[(Normalize-KwForMatch -kw $gk)] = @($gp.organic_results)
                    }
                } catch {}
            }
        }
        if ($googleSerpIndex.Count -gt 0) {
            $knownBlogMap = Get-KnownPersonalBlogDomainMap
        }
    } catch {
        Write-Warning "Failed to load Google SERP evidence: $_"
    }

    foreach ($pName in $profilesToRun) {
        $pRes = Invoke-SingleProfileReconciliation `
            -ProfileName $pName `
            -RowNumber $RowNumber `
            -CheckAllRows:$CheckAllRows `
            -RawArchiveDir $RawArchiveDir `
            -CachePath $CachePath `
            -VolumeMap $volumeMap `
            -SerpIndex $serpIndex `
            -DomainDaMap $domainDaMap `
            -GoogleSerpIndex $googleSerpIndex `
            -KnownBlogMap $knownBlogMap
        
        $results += $pRes
        if (-not $pRes.OverallPassed) {
            $allPassed = $false
        }
    }

    if ($ProfileName -in @("all", "both")) {
        return [PSCustomObject]@{
            Mode = "Unified_All"
            OverallPassed = $allPassed
            Female = ($results | Where-Object { $_.Profile -eq "female" } | Select-Object -First 1)
            Male = ($results | Where-Object { $_.Profile -eq "male" } | Select-Object -First 1)
            Profiles = $results
        }
    } else {
        return $results[0]
    }
}
