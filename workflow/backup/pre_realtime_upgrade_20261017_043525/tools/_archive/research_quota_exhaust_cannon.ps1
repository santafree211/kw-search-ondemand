# PowerShell Cannon Runner to exhaust API quota directly using unsearched keywords with real-time commit
param(
    [Parameter(Mandatory=$false)]
    [int]$MaxCalls = 2500
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator_male.ps1"
. "$projectRoot\workflow\scripts\guard_check_ymyl_kw.ps1"
. "$projectRoot\workflow\scripts\guard_check_entertainment_kw.ps1"
. "$projectRoot\workflow\scripts\guard_check_gender_kw.ps1"
. "$projectRoot\workflow\scripts\guard_quota_archive.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\research_domain_extract.ps1"
. "$projectRoot\workflow\scripts\research_bulk_expand.ps1"

Write-Output "=========================================================="
Write-Output "=== UBERSUGGEST API QUOTA EXHAUSTION CANNON RUNNER ==="
Write-Output "=========================================================="
Write-Output "Max Calls Target: $MaxCalls"

# 1. Inspect current usage
$initialUsage = Get-DailyApiQuotaUsage
Write-Output "Current Real Calls Today: $($initialUsage.TotalRealCallsToday)"

# 2. Track registered domains from sheets
$regDomains = @{}
try {
    $mData = Read-SheetData -SheetId "1ZFYMVVc10cZISofcB71x6ICt9ejZyGLzmVgpKbXvR40" -TargetSheetName "当たりKW"
    $fData = Read-SheetData -SheetId "1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw" -TargetSheetName "当たりKW"
    foreach ($r in $mData.Rows) {
        if ($r.Count -gt 4 -and $r[4]) {
            try { $h = ([System.Uri]$r[4]).Host.ToLower(); $regDomains[$h] = $true } catch {}
        }
    }
    foreach ($r in $fData.Rows) {
        if ($r.Count -gt 4 -and $r[4]) {
            try { $h = ([System.Uri]$r[4]).Host.ToLower(); $regDomains[$h] = $true } catch {}
        }
    }
} catch {
    Write-Warning "Could not read sheets registered domains: $_"
}
Write-Output "Tracked Registered Domains in Sheets: $($regDomains.Count)"

$callCount = 0
$exhausted = $false
$exhaustionError = ""
$newStar3Count = 0
$committedCount = 0
$skippedKws = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

while (-not $exhausted -and $callCount -lt $MaxCalls) {
    # 3. Fetch all unqueried verified keywords (Vol >= 1900)
    $query = @"
SELECT vk.keyword, vk.volume, vk.gender 
FROM verified_keywords vk 
WHERE vk.volume >= 1900 
  AND REPLACE(REPLACE(REPLACE(vk.keyword, ' ', ''), '`"', ''), char(12288), '') NOT IN (
      SELECT REPLACE(REPLACE(REPLACE(target_key, ' ', ''), '`"', ''), char(12288), '') 
      FROM raw_api_archive 
      WHERE endpoint = 'serp_analysis'
  ) 
ORDER BY vk.volume DESC;
"@

    $rawList = @(Invoke-SqliteQuery -SqlQuery $query)
    $unqueriedList = @($rawList | Where-Object { -not $skippedKws.Contains([string]$_.keyword) })
    Write-Output "Unqueried Eligible Keywords Remaining: $($unqueriedList.Count) (Skipped in-memory: $($skippedKws.Count))"

    if ($unqueriedList.Count -eq 0) {
        # Tier 2: Check Discovered Sites
        Write-Output "No more unqueried eligible keywords with Vol >= 1900. Checking discovered blogs (Tier 2)..."
        $blogQuery = @"
SELECT DISTINCT ds.domain 
FROM discovered_sites ds
WHERE ds.da BETWEEN 1 AND 9 
  AND ds.domain NOT IN (
      SELECT target_key FROM raw_api_archive WHERE endpoint = 'domain_keywords'
  )
LIMIT 10;
"@
        $unqueriedBlogs = @(Invoke-SqliteQuery -SqlQuery $blogQuery)
        if ($unqueriedBlogs.Count -gt 0) {
            $expandedAny = $false
            foreach ($b in $unqueriedBlogs) {
                if ($callCount -ge $MaxCalls -or $exhausted) { break }
                $dom = [string]$b.domain
                Write-Output "Extracting domain keywords for '$dom'..."
                try {
                    $extRes = Extract-DomainKeywords -Domain $dom -MinVolume 1900 -MaxPosition 10 -Limit 50
                    if ($extRes.Status -ne "AlreadyQueried" -and $extRes.Status -ne "DryRun") {
                        $callCount++
                    }
                    $expandedAny = $true
                } catch {
                    if ($_ -match "(?i)429|403|Daily report.*limit") {
                        $exhausted = $true
                        $exhaustionError = $_.ToString()
                        break
                    }
                }
            }
            if ($expandedAny) {
                continue
            }
        }

        # Tier 3: Expand via Full Catalog Genre Seeds (500 seeds across 100 genres)
        Write-Output "Expanding via Catalog Genre Seeds (Tier 3)..."
        $maleCat = Get-Content "$projectRoot\workflow\config\genre_catalog_male.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        $femaleCat = Get-Content "$projectRoot\workflow\config\genre_catalog_female.json" -Raw -Encoding UTF8 | ConvertFrom-Json
        
        $allSeeds = @()
        foreach ($g in $maleCat.genres) {
            foreach ($s in $g.seeds) { $allSeeds += [string]$s }
        }
        foreach ($g in $femaleCat.genres) {
            foreach ($s in $g.seeds) { $allSeeds += [string]$s }
        }

        # Find unqueried seeds
        $unqueriedSeeds = @()
        foreach ($s in $allSeeds) {
            if ($skippedKws.Contains($s)) { continue }
            $safeS = $s.Replace("'", "''")
            $chkQ = "SELECT 1 FROM raw_api_archive WHERE endpoint = 'match_keywords' AND target_key LIKE '%$safeS%' LIMIT 1;"
            $alreadyQ = @(Invoke-SqliteQuery -SqlQuery $chkQ)
            if ($alreadyQ.Count -eq 0) {
                $unqueriedSeeds += $s
            } else {
                $skippedKws.Add($s) | Out-Null
            }
        }

        Write-Output "Total Unqueried Catalog Seeds Available: $($unqueriedSeeds.Count)"
        if ($unqueriedSeeds.Count -gt 0) {
            $batchSeeds = @($unqueriedSeeds | Select-Object -First 4)
            foreach ($s in $batchSeeds) { $skippedKws.Add($s) | Out-Null }
            
            Write-Output "Expanding $($batchSeeds.Count) catalog seeds via match_keywords in-process..."
            try {
                $bRes = Expand-BulkKeywords -SeedKeywords $batchSeeds -BatchSize 2
                if ($bRes.IsExhausted) {
                    $exhausted = $true
                    $exhaustionError = $bRes.ExhaustionEvidence
                    break
                }
                $callCount += $bRes.BatchesProcessed
            } catch {
                if ($_ -match "(?i)429|403|Daily report.*limit") {
                    $exhausted = $true
                    $exhaustionError = $_.ToString()
                    break
                }
            }
            continue
        }

        # Tier 4: Expand via Longtail Keyword Pool (Vol 1000 - 1800, ~3500 keywords)
        Write-Output "Checking Longtail Keyword Pool (Vol 1000-1800) for fresh seeds (Tier 4)..."
        $longtailQuery = @"
SELECT lkp.keyword, lkp.volume 
FROM longtail_keyword_pool lkp 
WHERE lkp.volume BETWEEN 1000 AND 1800 
  AND NOT EXISTS (
      SELECT 1 FROM raw_api_archive r 
      WHERE r.endpoint = 'match_keywords' 
        AND r.target_key LIKE '%' || lkp.keyword || '%'
  )
ORDER BY lkp.volume DESC 
LIMIT 20;
"@
        $unqueriedLongtails = @(Invoke-SqliteQuery -SqlQuery $longtailQuery)
        $freshLongtails = @($unqueriedLongtails | Where-Object { -not $skippedKws.Contains([string]$_.keyword) })

        if ($freshLongtails.Count -gt 0) {
            $batchSeeds = @($freshLongtails | Select-Object -First 4 | ForEach-Object { [string]$_.keyword })
            foreach ($s in $batchSeeds) { $skippedKws.Add($s) | Out-Null }
            
            Write-Output "Expanding $($batchSeeds.Count) longtail seeds ($($batchSeeds -join ', ')) via match_keywords in-process..."
            try {
                $bRes = Expand-BulkKeywords -SeedKeywords $batchSeeds -BatchSize 2
                if ($bRes.IsExhausted) {
                    $exhausted = $true
                    $exhaustionError = $bRes.ExhaustionEvidence
                    break
                }
                $callCount += $bRes.BatchesProcessed
            } catch {
                if ($_ -match "(?i)429|403|Daily report.*limit") {
                    $exhausted = $true
                    $exhaustionError = $_.ToString()
                    break
                }
            }
            continue
        }

        # Tier 5: Fallback to Lower Longtail Keyword Pool (Vol 500 - 999, ~5600 keywords)
        Write-Output "Checking Longtail Keyword Pool (Vol 500-999) for fresh seeds (Tier 5)..."
        $longtailLowQuery = @"
SELECT lkp.keyword, lkp.volume 
FROM longtail_keyword_pool lkp 
WHERE lkp.volume BETWEEN 500 AND 999 
  AND NOT EXISTS (
      SELECT 1 FROM raw_api_archive r 
      WHERE r.endpoint = 'match_keywords' 
        AND r.target_key LIKE '%' || lkp.keyword || '%'
  )
ORDER BY lkp.volume DESC 
LIMIT 20;
"@
        $unqueriedLow = @(Invoke-SqliteQuery -SqlQuery $longtailLowQuery)
        $freshLow = @($unqueriedLow | Where-Object { -not $skippedKws.Contains([string]$_.keyword) })

        if ($freshLow.Count -gt 0) {
            $batchSeeds = @($freshLow | Select-Object -First 4 | ForEach-Object { [string]$_.keyword })
            foreach ($s in $batchSeeds) { $skippedKws.Add($s) | Out-Null }
            
            Write-Output "Expanding $($batchSeeds.Count) low longtail seeds ($($batchSeeds -join ', ')) via match_keywords in-process..."
            try {
                $bRes = Expand-BulkKeywords -SeedKeywords $batchSeeds -BatchSize 2
                if ($bRes.IsExhausted) {
                    $exhausted = $true
                    $exhaustionError = $bRes.ExhaustionEvidence
                    break
                }
                $callCount += $bRes.BatchesProcessed
            } catch {
                if ($_ -match "(?i)429|403|Daily report.*limit") {
                    $exhausted = $true
                    $exhaustionError = $_.ToString()
                    break
                }
            }
            continue
        }

        Write-Output "No fresh seeds available in longtail pool."
        break
    }

    $processedInBatch = 0
    foreach ($item in $unqueriedList) {
        if ($callCount -ge $MaxCalls -or $exhausted) { break }

        $kw = [string]$item.keyword
        $vol = [int]$item.volume
        $gender = [string]$item.gender
        if ([string]::IsNullOrWhiteSpace($gender)) { $gender = "common" }

        # Guard checks
        $ymylCheck = Test-KeywordYmylEligibility -Keyword $kw
        if ($ymylCheck.IsYmyl) { 
            $skippedKws.Add($kw) | Out-Null
            continue 
        }

        $entCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
        if ($entCheck.IsEntertainment) { 
            $skippedKws.Add($kw) | Out-Null
            continue 
        }

        $processedInBatch++

        # Execute Remote SERP Analysis with self-healing retry
        $serp = $null
        $retryAttempts = 0
        while ($retryAttempts -lt 3 -and $null -eq $serp -and -not $exhausted) {
            try {
                $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
            } catch {
                $errMsg = $_.ToString()
                if ($errMsg -match "(?i)429|403|Daily report.*limit") {
                    $exhausted = $true
                    $exhaustionError = $errMsg
                    break
                }
                $retryAttempts++
                Write-Warning "Temporary communication error on '$kw' (attempt $retryAttempts/3): $errMsg. Waiting 10s..."
                Start-Sleep -Seconds 10
            }
        }

        if ($exhausted) {
            Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $exhaustionError"
            break
        }

        if ($null -eq $serp) { 
            $skippedKws.Add($kw) | Out-Null
            continue 
        }

        if ($serp.IsDuplicate) {
            $skippedKws.Add($kw) | Out-Null
            continue
        }

        if (-not $serp.IsCached) {
            $callCount++
            $currentTotal = $initialUsage.TotalRealCallsToday + $callCount
            Write-Output "[$callCount] (Total: $currentTotal) Remote SERP: '$kw' (Vol: $vol)..."
        }

        if ($serp.IsExhausted) {
            if ($serp.Error -match "(?i)429|403|Daily report.*limit") {
                $exhausted = $true
                $exhaustionError = $serp.Error
                Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($serp.Error)"
                break
            }
        }

        # Evaluate SERP for Star 3+
        $entries = $serp.serpEntries
        if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }

        if ($entries) {
            $mEval = Get-StrictStarEvaluationMale -Keyword $kw -SearchVolume $vol -SerpEntries $entries
            $fEval = Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries

            $isMaleHit = ($mEval.StarCount -ge 3 -and $mEval.PureLowDaCount -ge 1)
            $isFemaleHit = ($fEval.StarCount -ge 3 -and $fEval.PureLowDaCount -ge 1)

            if ($isMaleHit -or $isFemaleHit) {
                $newStar3Count++
                Write-Output "  >>> [STAR 3+ HIT!] '$kw' (Male Stars: $($mEval.StarCount), Female Stars: $($fEval.StarCount))"

                # Check gender eligibility
                $fAllowed = (Test-KeywordGenderEligibility -Gender "female" -Keyword $kw).IsAllowed
                $mAllowed = (Test-KeywordGenderEligibility -Gender "male" -Keyword $kw).IsAllowed

                # Prioritize female sheet to heal ratio to >= 50%
                $targets = @()
                if ($isFemaleHit -and $fAllowed) {
                    $targets += [PSCustomObject]@{ Gender = "female"; Eval = $fEval }
                }
                if ($isMaleHit -and $mAllowed) {
                    $targets += [PSCustomObject]@{ Gender = "male"; Eval = $mEval }
                }

                foreach ($tgt in $targets) {
                    $bestGender = $tgt.Gender
                    $bestEval = $tgt.Eval
                    foreach ($blog in $bestEval.PureLowDaSites) {
                        $bDom = ([string]$blog.domain).ToLower()
                        if ($regDomains.ContainsKey($bDom)) { continue }

                        $starChar = [char]0x2606
                        $starPrefix = [string]::new($starChar, $bestEval.StarCount)
                        $formattedKw = "$starPrefix$kw（$vol）"

                        Write-Output "  >>> [REAL-TIME COMMIT] Attempting to add $($blog.domain) (DA: $($blog.domainAuthority)) to $bestGender sheet..."
                        try {
                            $commitScript = "$projectRoot\tools\$bestGender\sheet_commit.ps1"
                            & $commitScript `
                                -SiteName "$($blog.domain) ブログ" `
                                -Url $blog.url `
                                -Da $blog.domainAuthority `
                                -OriginKw $formattedKw `
                                -WinningKws @($formattedKw)
                            $committedCount++
                            $regDomains[$bDom] = $true
                            Write-Output "  >>> [COMMITTED SUCCESS] Successfully added to $bestGender sheet!"
                            break
                        } catch {
                            Write-Output "  -> Commit held in stock / ratio guard for $($bestGender): $_"
                        }
                    }
                }
            }
        }

        # Gentle rate limit throttle
        Start-Sleep -Milliseconds 200
    }

    if ($processedInBatch -eq 0 -and $unqueriedList.Count -gt 0) {
        Write-Output "All remaining unqueried keywords were filtered by guards. Proceeding to expansion tiers."
        continue
    }
}

Write-Output "`n=========================================================="
Write-Output "CANNON RUN FINISHED"
Write-Output "Calls Made in This Run : $callCount"
$finalUsage = Get-DailyApiQuotaUsage
Write-Output "Total Real Calls Today : $($finalUsage.TotalRealCallsToday)"
Write-Output "New Star 3+ Hits Found : $newStar3Count"
Write-Output "Sites Committed Today  : $committedCount"
Write-Output "Physical Exhausted     : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Evidence    : $exhaustionError"
    Write-Output "`nExecuting Unified Exit Audit..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\guard_check_exhaustion.ps1" -ErrorText $exhaustionError
} else {
    Write-Output "Execution completed without physical exhaustion."
    Write-Output "Executing Unified Sheet Reconciliation..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\sheet_reconcile.ps1"
}
Write-Output "=========================================================="
