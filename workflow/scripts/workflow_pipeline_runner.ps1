<#
.SYNOPSIS
    workflow/scripts/workflow_pipeline_runner.ps1
    Responsibility: Master autonomous pipeline runner orchestrating the 3-stage rocket discovery lifecycle.
    100x-Yield Architecture:
      - Phase 1: Bulk Keyword Expansion (match_keywords, Limit=100, up to 100 KWs/call)
      - Phase 2: Verified SERP Inspection & By-Product Personal Blog Harvester (serp_analysis, DA 1-9 collection)
      - Phase 3: Harvested Domain Bulk Infiltration (domain_keywords, Limit=100, winning KW cluster extraction)
      - Phase 4: Portfolio Golden Ratio Balancing & Safe Atomic Sheet Commit (50:25:25 protection)
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

# Load modules (1 file 1 responsibility)
. "$PSScriptRoot\sheet_auth_provider.ps1"
. "$PSScriptRoot\sheet_data_reader.ps1"
. "$PSScriptRoot\research_seed_suggest.ps1"
. "$PSScriptRoot\research_bulk_expand.ps1"
. "$PSScriptRoot\research_domain_extract.ps1"
. "$PSScriptRoot\research_volume_verifier.ps1"
. "$PSScriptRoot\research_serp_fetcher.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"
. "$PSScriptRoot\eval_star_calculator_male.ps1"
. "$PSScriptRoot\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\eval_star_calculator.ps1"
. "$PSScriptRoot\sheet_profile_resolver.ps1"
. "$PSScriptRoot\research_domain_harvester.ps1"
. "$PSScriptRoot\research_diff_keywords.ps1"
. "$PSScriptRoot\research_diff_domains.ps1"
. "$PSScriptRoot\guard_serp_gate.ps1"
. "$PSScriptRoot\store_api_archive.ps1"
. "$PSScriptRoot\store_api_query.ps1"
. "$PSScriptRoot\portfolio_ratio_balancer.ps1"
. "$PSScriptRoot\guard_normal_state.ps1"
. "$PSScriptRoot\guard_quota_monitor.ps1"
. "$PSScriptRoot\sheet_atomic_writer.ps1"
. "$PSScriptRoot\sheet_date_tracker.ps1"
. "$PSScriptRoot\guard_sheet_reconcile.ps1"

function Invoke-KeywordSearchPipeline {
    param(
        [string[]]$Seeds = @(),
        [int]$BatchSize = 2,
        [int]$MaxBatches = 5,
        [switch]$IsDryRun = $false,
        [int]$Limit = 1000,
        [string]$CandFile = "",
        [bool]$EnableBulk = $true,
        [string]$MockFile = "",
        [int]$MaxSerpCalls = 15,
        [int]$MaxDomainCalls = 10,
        [string]$SpreadsheetId = "",
        [string]$Gender = "",
        [string]$SurveyDate = ""
    )

    $profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
    $SpreadsheetId = $profile.SpreadsheetId

    if ([string]::IsNullOrWhiteSpace($SurveyDate)) {
        $SurveyDate = (Get-Date).ToString("yyyy-MM-dd")
    }

    Write-Output "=========================================================="
    Write-Output "=== 3-STAGE ROCKET DISCOVERY PIPELINE ($($profile.Title)) ==="
    Write-Output "=========================================================="
    Write-Output "Date: $SurveyDate | DryRun: $IsDryRun | Limit: $Limit | Gender: $($profile.Gender)"

    $isExhaustedStop = $false
    $exhaustionReason = ""

    # ---------------------------------------------------------
    # 0. Read Current Spreadsheet State & Golden Ratio
    # ---------------------------------------------------------
    Write-Output "`n[Stage 0] Auditing Current Spreadsheet State..."
    $sheetState = Read-SheetData -SheetId $SpreadsheetId
    Write-Output "  Existing Registered Sites: $($sheetState.SiteCount)"

    $existingKeywords = @()
    $header = $sheetState.Header
    $kwStartCol = 6
    for ($i = 0; $i -lt $header.Count; $i++) {
        if ([string]$header[$i] -match "KW1") {
            $kwStartCol = $i
            break
        }
    }

    foreach ($row in $sheetState.Rows) {
        $maxCol = [Math]::Min($row.Count, ($header.Count - 1))
        for ($c = $kwStartCol; $c -lt $maxCol; $c++) {
            $cell = [string]$row[$c]
            if (-not [string]::IsNullOrWhiteSpace($cell)) {
                $lines = $cell -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($t)) {
                        $existingKeywords += $t
                    }
                }
            }
        }
    }
    Write-Output "  Existing Winning Keywords: $($existingKeywords.Count)"

    $auditRes = Test-NormalStateStandard -SheetRows $sheetState.RawValues
    $pAlloc = Get-PortfolioAllocation -CurrentKws $existingKeywords -NewKws @()
    Write-Output "  Portfolio Ratio: S3+=$($pAlloc.ResultingRatio.Star3Percent)%, S2=$($pAlloc.ResultingRatio.Star2Percent)%, S1=$($pAlloc.ResultingRatio.Star1Percent)% (Passed: $($auditRes.Passed))"

    # ---------------------------------------------------------
    # 1. Stage 1: Bulk Keyword Expansion (1 call = 100 entries)
    # ---------------------------------------------------------
    Write-Output "`n[Stage 1] Executing Bulk Keyword Expansion (match_keywords, Limit=$Limit)..."
    $eligibleCandidates = @()
    $stage1Calls = 0

    if ($EnableBulk -and $Seeds.Count -gt 0) {
        $bulkRes = Expand-BulkKeywords -SeedKeywords $Seeds -BatchSize $BatchSize -MaxBatches $MaxBatches -Limit $Limit -Excludes $existingKeywords -MockJsonPath $MockFile -DryRun:$IsDryRun
        $stage1Calls = $bulkRes.BatchesProcessed
        Write-Output "  Bulk Batches Processed: $stage1Calls (Total Fetched: $($bulkRes.TotalFetched))"
        Write-Output "  Keywords Qualified (Vol >= 1900): $($bulkRes.PassedVolumeThreshold)"
        $eligibleCandidates = @($bulkRes.EligibleCandidates)
    } elseif (-not [string]::IsNullOrWhiteSpace($CandFile) -and (Test-Path $CandFile)) {
        $cText = [System.IO.File]::ReadAllText($CandFile, [System.Text.Encoding]::UTF8)
        $rawList = @()
        if ($CandFile.EndsWith(".json")) {
            $p = $cText | ConvertFrom-Json
            if ($p -is [array]) { $rawList = $p }
            elseif ($p.keywords) { $rawList = $p.keywords }
        } else {
            $rawList = ($cText -split "`r?`n")
        }
        $eligibleCandidates = @($rawList)
    }

    Write-Output "  Stage 1 Candidates for SERP Verification: $($eligibleCandidates.Count)"

    # ---------------------------------------------------------
    # 2. Stage 2: Diff Gate & Verified SERP Inspection + Domain Harvester
    # ---------------------------------------------------------
    Write-Output "`n[Stage 2] SERP Verification & By-Product Personal Blog Harvester..."
    
    $eligibleKwStrings = @()
    foreach ($cand in $eligibleCandidates) {
        if ($cand -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($cand)) { $eligibleKwStrings += $cand.Trim() }
        } elseif ($null -ne $cand -and $cand.Keyword) {
            $eligibleKwStrings += ([string]$cand.Keyword).Trim()
        }
    }

    # Check diffs against local archive to avoid duplicate API calls
    $kwDiff = Get-KeywordDiff -Keywords $eligibleKwStrings -Endpoint "serp_analysis"
    Write-Output "  Local Archive Cache Hits: $($kwDiff.CachedCount) (API Calls Saved: $($kwDiff.SavedApiCalls))"
    Write-Output "  Uninvestigated Diff Keywords: $($kwDiff.DiffCount)"

    $serpQueue = @($kwDiff.DiffKeywords)
    if ($serpQueue.Count -gt $MaxSerpCalls) {
        $serpQueue = @($serpQueue | Get-Random -Count $MaxSerpCalls)
    }
    Write-Output "  Selected for SERP API Execution (Capped at $MaxSerpCalls, Fairly Sampled): $($serpQueue.Count)"

    $harvestedDomains = @()
    $seenHarvDomains = @{}
    $verifiedWinningKws = @()
    $stage2Calls = 0

    # Helper scriptblock to evaluate SERP and harvest personal blogs
    $processSerp = {
        param($targetKw, $serpObj, [bool]$fromCache)
        if ($null -eq $serpObj) { return }

        $serpEntries = @()
        if ($serpObj.serpEntries) { $serpEntries = $serpObj.serpEntries }
        elseif ($serpObj.Top10Organic) { $serpEntries = $serpObj.Top10Organic }
        elseif ($serpObj -is [array]) { $serpEntries = $serpObj }

        if ($serpEntries.Count -eq 0) { return }

        $kwVol = 0
        $volCheck = Test-KeywordVolume -TargetKeyword $targetKw
        if ($null -ne $volCheck) {
            if ($null -ne $volCheck.SearchVolume -and $volCheck.SearchVolume -ge 1900) {
                $kwVol = [int]$volCheck.SearchVolume
            } elseif ($null -ne $volCheck.Volume -and $volCheck.Volume -ge 1900) {
                $kwVol = [int]$volCheck.Volume
            }
        }

        # Male / Female UGC star calculation
        $starCalc = $null
        if ($profile.IsFemale) {
            $starCalc = Get-StrictStarEvaluation -Keyword $targetKw -SearchVolume $kwVol -SerpEntries $serpEntries
        } else {
            $starCalc = Get-StrictStarEvaluationMale -Keyword $targetKw -SearchVolume $kwVol -SerpEntries $serpEntries
        }

        if ($null -ne $starCalc -and $starCalc.IsHit) {
            $verifiedWinningKws += $starCalc
            $srcTag = if ($fromCache) { "[CacheHit]" } else { "[RemoteHit]" }
            Write-Output "    -> Winning KW Discovered ${srcTag}: $($starCalc.FormattedValue) [Stars: $($starCalc.StarCount)]"
        }

        # Harvest personal blogs (DA 1-9)
        $harv = Get-HarvestedDomainsFromSerp -SerpEntries $serpEntries -Gender $profile.Gender
        foreach ($hd in $harv.Domains) {
            if (-not $seenHarvDomains.ContainsKey($hd.Domain)) {
                $seenHarvDomains[$hd.Domain] = $true
                $harvestedDomains += $hd
                Write-Output "    -> Personal Blog Harvested: $($hd.Domain) (DA: $($hd.DA)) from '$targetKw'"
            }
        }
    }

    # 2-A. Process cached SERP entries first (0 API calls consumed!)
    if ($kwDiff.CachedEntries.Count -gt 0) {
        Write-Output "  Processing $($kwDiff.CachedEntries.Count) local cached SERP entries (Zero API Cost)..."
        foreach ($cEntry in $kwDiff.CachedEntries) {
            $cKw = $cEntry.Keyword
            $cachedArchive = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cKw
            if ($null -ne $cachedArchive -and $null -ne $cachedArchive.Data) {
                . $processSerp $cKw $cachedArchive.Data $true
            }
        }
    }

    # 2-B. Process uninvestigated diff keywords via remote API
    foreach ($kw in $serpQueue) {
        $gate = Test-SerpEligibility -Keyword $kw -DateString $SurveyDate
        if (-not $gate.Eligible -and $gate.Action -eq "Block") {
            Write-Output "    [Gate Blocked] '$kw' - Reason: $($gate.Reason), Volume: $($gate.Volume)"
            continue
        }

        if ($IsDryRun) {
            Write-Output "    [DryRun] Skipping remote serp_analysis for: '$kw'"
            continue
        }

        Write-Output "    -> Fetching SERP analysis for: '$kw'..."

        $remoteSerp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
        if ($null -ne $remoteSerp) {
            if ($remoteSerp.IsExhausted) {
                Write-Warning "API Exhausted during Stage 2 on '$kw': $($remoteSerp.Error)"
                $isExhaustedStop = $true
                $exhaustionReason = "Stage 2 SERP Exhausted: $($remoteSerp.Error)"
                break
            }
            $stage2Calls++
            . $processSerp $kw $remoteSerp $false
        }
    }
    Write-Output "  Total Harvested Personal Blogs from SERP: $($harvestedDomains.Count)"

    # ---------------------------------------------------------
    # 3. Stage 3: Harvested Domain Bulk Infiltration (Limit=100)
    # ---------------------------------------------------------
    Write-Output "`n[Stage 3] Infiltrating Harvested Personal Blogs (domain_keywords, Limit=$Limit)..."
    
    $domDiff = Get-DomainDiff -Domains @($harvestedDomains | ForEach-Object { $_.Domain })
    Write-Output "  Already Investigated Domains: $($domDiff.CachedCount) (API Calls Saved: $($domDiff.SavedApiCalls))"
    Write-Output "  Uninvestigated Diff Domains: $($domDiff.DiffCount)"

    $domainQueue = @($domDiff.DiffDomains)
    if ($domainQueue.Count -gt $MaxDomainCalls) {
        $domainQueue = @($domainQueue[0..($MaxDomainCalls - 1)])
    }
    Write-Output "  Selected for Domain Extraction (Capped at $MaxDomainCalls): $($domainQueue.Count)"

    $stage3Calls = 0
    $newDiscoveredKws = @()
    $domainHarvestedWinningKws = @{}

    foreach ($dom in $domainQueue) {
        if ($IsDryRun) {
            Write-Output "    [DryRun] Skipping remote domain_keywords for: '$dom'"
            continue
        }
        Write-Output "    -> Infiltrating personal blog: '$dom' (Limit=$Limit)..."
        try {
            $domRes = Extract-DomainKeywords -Domain $dom -Limit $Limit -Excludes $existingKeywords
            $stage3Calls++
            if ($null -ne $domRes -and $domRes.WinningKeywords.Count -gt 0) {
                Write-Output "       Found $($domRes.WinningKeywords.Count) winning keywords from '$dom'!"
                if (-not $domainHarvestedWinningKws.ContainsKey($dom)) {
                    $domainHarvestedWinningKws[$dom] = @()
                }
                foreach ($wk in $domRes.WinningKeywords) {
                    $domainHarvestedWinningKws[$dom] += $wk
                    $newDiscoveredKws += $wk
                }
            }
        } catch {
            Write-Warning "Failed domain extraction for '$dom': $_"
            if ($_ -match "403|429|daily reports limit|timed out") {
                Write-Warning "API Quota Exhausted during Stage 3."
                $isExhaustedStop = $true
                $exhaustionReason = "Stage 3 Domain Extraction Exhausted: $_"
                break
            }
        }
    }

    # ---------------------------------------------------------
    # 4. Stage 4: Automated Ratio-Protected Allocation & Commit
    # ---------------------------------------------------------
    Write-Output "`n[Stage 4] Compiling 3-Stage Discovery Results & Balancing Portfolio..."
    $totalApiEstimated = $stage1Calls + $stage2Calls + $stage3Calls
    $totalSavedCalls = $kwDiff.SavedApiCalls + $domDiff.SavedApiCalls

    $committedSites = @()
    $shelvedKws = @()
    $stockPath = $profile.StockPath

    # Map discovered winning keywords to harvested personal blogs
    $siteCandidates = @{}

    # 4-A. Map from Stage 2 SERP verified hits
    foreach ($wk in $verifiedWinningKws) {
        $kwStr = $wk.FormattedValue
        foreach ($site in $wk.PureLowDaSites) {
            $domKey = ([string]$site.domain).ToLower().Trim()
            if (-not $siteCandidates.ContainsKey($domKey)) {
                $siteCandidates[$domKey] = [PSCustomObject]@{
                    Domain = $domKey
                    SiteName = if (-not [string]::IsNullOrWhiteSpace($site.title)) { $site.title } else { $domKey }
                    Url = $site.url
                    DA = [int]$site.domainAuthority
                    OriginKw = $wk.Keyword
                    WinningKws = @()
                }
            }
            if (-not ($siteCandidates[$domKey].WinningKws -contains $kwStr)) {
                $siteCandidates[$domKey].WinningKws += $kwStr
            }
        }
    }

    # 4-B. Map from Stage 3 personal blog domain extraction
    foreach ($domKey in $domainHarvestedWinningKws.Keys) {
        $harvestedSite = $harvestedDomains | Where-Object { $_.Domain -eq $domKey } | Select-Object -First 1
        $siteDa = if ($null -ne $harvestedSite) { [int]$harvestedSite.DA } else { 5 }
        $siteUrl = if ($null -ne $harvestedSite) { [string]$harvestedSite.Url } else { "https://$domKey/" }
        $siteTitle = if ($null -ne $harvestedSite -and -not [string]::IsNullOrWhiteSpace($harvestedSite.Title)) { [string]$harvestedSite.Title } else { $domKey }

        if (-not $siteCandidates.ContainsKey($domKey)) {
            $siteCandidates[$domKey] = [PSCustomObject]@{
                Domain = $domKey
                SiteName = $siteTitle
                Url = $siteUrl
                DA = $siteDa
                OriginKw = "domain_extraction"
                WinningKws = @()
            }
        }

        $starChar = [char]0x2606
        $openParen = [char]0xff08
        $closeParen = [char]0xff09
        foreach ($wkItem in $domainHarvestedWinningKws[$domKey]) {
            $formattedWk = "$starChar$($wkItem.Keyword)$openParen$($wkItem.SearchVolume)$closeParen"
            if (-not ($siteCandidates[$domKey].WinningKws -contains $formattedWk)) {
                $siteCandidates[$domKey].WinningKws += $formattedWk
            }
        }
    }

    # Attempt to commit sites that have winning keywords
    foreach ($domKey in $siteCandidates.Keys) {
        $cand = $siteCandidates[$domKey]
        if ($cand.WinningKws.Count -eq 0) { continue }

        Write-Output "  Evaluating Site Candidate: $($cand.SiteName) ($($cand.Domain), DA: $($cand.DA)) with $($cand.WinningKws.Count) KW(s)..."
        
        $alloc = Get-PortfolioAllocation -CurrentKws $existingKeywords -NewKws $cand.WinningKws -StockPath $stockPath
        if ($alloc.CanCommit -and $alloc.CommitKeywords.Count -gt 0) {
            if ($IsDryRun) {
                Write-Output "    [DryRun] Would commit site '$($cand.SiteName)' with KWs: $($alloc.CommitKeywords -join ', ')"
                $committedSites += $cand
                $existingKeywords += $alloc.CommitKeywords
            } else {
                # Live commit via standard sheet_commit_site.ps1
                $commitTool = Join-Path $PSScriptRoot "..\..\tools\sheet_commit_site.ps1"
                try {
                    $cRes = & $commitTool `
                        -SiteName $cand.SiteName `
                        -Url $cand.Url `
                        -SiteKey $cand.Domain `
                        -Da $cand.DA `
                        -OriginKw $cand.OriginKw `
                        -WinningKws $alloc.CommitKeywords `
                        -SpreadsheetId $SpreadsheetId `
                        -Gender $profile.Gender `
                        -SurveyDate $SurveyDate
                    Write-Output "    -> Site Successfully Committed to Spreadsheet: '$($cand.SiteName)'!"
                    $committedSites += $cand
                    $existingKeywords += $alloc.CommitKeywords
                } catch {
                    Write-Warning "Commit failed for '$($cand.SiteName)': $_"
                }
            }
            if ($alloc.ShelvedKeywords.Count -gt 0) {
                $shelvedKws += $alloc.ShelvedKeywords
            }
        } else {
            Write-Output "    -> Shelving keywords for '$($cand.SiteName)' to preserve 50:25:25 golden ratio."
            $shelvedKws += $cand.WinningKws
        }
    }

    # ---------------------------------------------------------
    # 5. Exit Routine: Automatic Sheet Health & 3-Way Reconciliation Audit
    # ---------------------------------------------------------
    Write-Output "`n[Exit Routine] Executing Automatic Sheet Health & 3-Way Reconciliation Audit..."
    $exitAudit = [PSCustomObject]@{
        HealthAudit = $null
        ReconciliationAudit = $null
        AuditPassed = $false
    }

    try {
        # 1. Health Audit (Normal State Standard: 50:25:25, format, no garbage)
        $sheetDataAfter = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $profile.TargetSheetName
        $healthRes = Test-NormalStateStandard -SheetRows $sheetDataAfter.RawValues
        $exitAudit.HealthAudit = [PSCustomObject]@{
            Passed = $healthRes.Passed
            SiteCount = $healthRes.SiteCount
            TotalKeywords = $healthRes.TotalKeywords
            Star3Percent = $healthRes.Star3Percent
            Star2Percent = $healthRes.Star2Percent
            Star1Percent = $healthRes.Star1Percent
            Errors = $healthRes.Errors
        }

        # 2. 3-Way Reconciliation Audit on Latest Row
        $reconcileRes = Invoke-Sheet3WayReconciliation -ProfileName $profile.Gender -Silent:$true
        $exitAudit.ReconciliationAudit = [PSCustomObject]@{
            OverallPassed = $reconcileRes.OverallPassed
            TotalViolations = $reconcileRes.TotalViolations
            RowAudited = if ($reconcileRes.RowResults.Count -gt 0) { $reconcileRes.RowResults[0].Row } else { $null }
            SiteName = if ($reconcileRes.RowResults.Count -gt 0) { $reconcileRes.RowResults[0].SiteName } else { "" }
            Violations = if ($reconcileRes.RowResults.Count -gt 0) { $reconcileRes.RowResults[0].Violations } else { @() }
        }

        $exitAudit.AuditPassed = ($healthRes.Passed -and $reconcileRes.OverallPassed)

        Write-Output "  Sheet Health Audit   : $(if ($healthRes.Passed) { 'PASSED' } else { 'FAILED' }) (Star3+: $($healthRes.Star3Percent)%, Star2: $($healthRes.Star2Percent)%, Star1: $($healthRes.Star1Percent)%)"
        Write-Output "  3-Way Reconciliation : $(if ($reconcileRes.OverallPassed) { 'PASSED (100% Reconciled)' } else { 'FAILED (Violations: ' + $reconcileRes.TotalViolations + ')' })"
    } catch {
        Write-Warning "Automatic exit audit encountered an issue: $_"
    }

    $summary = [PSCustomObject]@{
        SurveyDate = $SurveyDate
        IsDryRun = $IsDryRun
        LimitPerCall = $Limit
        Stage1_BulkFetched = if ($bulkRes) { $bulkRes.TotalFetched } else { 0 }
        Stage1_Candidates = $eligibleCandidates.Count
        Stage2_SerpCalls = $stage2Calls
        Stage2_HarvestedDomains = $harvestedDomains.Count
        Stage2_WinningKws = $verifiedWinningKws.Count
        Stage3_DomainCalls = $stage3Calls
        Stage3_DiscoveredKws = $newDiscoveredKws.Count
        Stage4_CommittedSites = $committedSites.Count
        Stage4_ShelvedKws = $shelvedKws.Count
        TotalApiCallsConsumed = $totalApiEstimated
        TotalApiCallsSavedByDiff = $totalSavedCalls
        Status = if ($isExhaustedStop) { "Exhausted" } else { "Completed" }
        ExhaustionReason = $exhaustionReason
        ExitAudit = $exitAudit
    }

    $statePath = $profile.PipelineStatePath
    $stateJson = $summary | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($statePath, $stateJson, [System.Text.UTF8Encoding]::new($false))

    Write-Output "=== Pipeline Summary ==="
    Write-Output "  Status: $($summary.Status) $(if ($isExhaustedStop) { 'Reason: ' + $exhaustionReason })"
    Write-Output "  API Calls Consumed: $totalApiEstimated (Diff Saved: $totalSavedCalls)"
    Write-Output "  Harvested Personal Blogs: $($harvestedDomains.Count)"
    Write-Output "  Discovered Winning Keywords: $($verifiedWinningKws.Count)"
    Write-Output "  Sites Committed: $($committedSites.Count)"
    Write-Output "  Keywords Shelved: $($shelvedKws.Count)"
    Write-Output "  Exit Audit Passed: $($exitAudit.AuditPassed) (Health: $(if ($exitAudit.HealthAudit) { $exitAudit.HealthAudit.Passed } else { 'N/A' }) | Reconcile: $(if ($exitAudit.ReconciliationAudit) { $exitAudit.ReconciliationAudit.OverallPassed } else { 'N/A' }))"
    Write-Output "=========================================================="

    return $summary
}
