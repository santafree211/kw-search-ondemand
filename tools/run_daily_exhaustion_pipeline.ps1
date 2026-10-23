# PowerShell Complete Autonomous Daily Exhaustion Pipeline
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
. "$projectRoot\workflow\scripts\research_bulk_expand.ps1"

Write-Output "=========================================================="
Write-Output "=== AUTONOMOUS DAILY API EXHAUSTION & REAL-TIME COMMIT ==="
Write-Output "=========================================================="
Write-Output "Max Calls Target: $MaxCalls"

# 1. Inspect current usage
$initialUsage = Get-DailyApiQuotaUsage
Write-Output "Initial Real Calls Today: $($initialUsage.TotalRealCallsToday)"

$callCount = 0
$exhausted = $false
$exhaustionError = ""
$committedCount = 0
$star3HitsCount = 0
$seenInRun = @{}

# Track registered domains and keywords from sheets
function Get-SheetRegisteredState {
    $maleData = Read-SheetData -SheetId "1ZFYMVVc10cZISofcB71x6ICt9ejZyGLzmVgpKbXvR40" -TargetSheetName "当たりKW"
    $femaleData = Read-SheetData -SheetId "1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw" -TargetSheetName "当たりKW"
    $doms = @{}
    $kws = @{}
    foreach ($r in $maleData.Rows) {
        if ($r.Count -gt 4 -and $r[4]) {
            try { $h = ([System.Uri]$r[4]).Host.ToLower(); $doms[$h] = $true } catch {}
        }
    }
    foreach ($r in $femaleData.Rows) {
        if ($r.Count -gt 4 -and $r[4]) {
            try { $h = ([System.Uri]$r[4]).Host.ToLower(); $doms[$h] = $true } catch {}
        }
    }
    return @{ Domains = $doms; Keywords = $kws }
}

. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
$regState = Get-SheetRegisteredState
Write-Output "Current registered domains in sheets: $($regState.Domains.Count)"

while ($callCount -lt $MaxCalls -and -not $exhausted) {
    # Fetch TRUE unqueried verified keywords (not in raw_api_archive)
    $query = @"
SELECT vk.keyword, vk.volume, vk.gender 
FROM verified_keywords vk
LEFT JOIN raw_api_archive raa 
    ON raa.endpoint = 'serp_analysis' AND raa.target_key = vk.keyword
WHERE vk.volume >= 1900 AND raa.target_key IS NULL
ORDER BY vk.volume DESC
LIMIT 200;
"@

    $batchList = @(Invoke-SqliteQuery -SqlQuery $query)
    # Filter out already seen in this run
    $freshList = @()
    foreach ($b in $batchList) {
        $kText = ([string]$b.keyword).Trim()
        if (-not $seenInRun.ContainsKey($kText)) {
            $freshList += $b
        }
    }

    if ($freshList.Count -eq 0) {
        Write-Output "No unqueried keywords remaining in DB. Expanding new seeds from 50 genres..."
        # Expand new seeds using match_keywords
        . "$projectRoot\workflow\scripts\genre_catalog_provider.ps1"
        $mCat = Get-GenreCatalog -Gender "male"
        $fCat = Get-GenreCatalog -Gender "female"
        $allSeeds = @()
        foreach ($g in $mCat) { if ($g.seeds) { $allSeeds += $g.seeds } }
        foreach ($g in $fCat) { if ($g.seeds) { $allSeeds += $g.seeds } }

        $pickSeeds = @($allSeeds | Get-Random -Count 5)
        Write-Output "Expanding 5 random genre seeds: $($pickSeeds -join ', ')"
        $expRes = Expand-BulkKeywords -Keywords $pickSeeds -MinVolume 1900
        $callCount += [Math]::Min($pickSeeds.Count, 3)
        if ($expRes -and $expRes.IsExhausted) {
            $exhausted = $true
            $exhaustionError = $expRes.ExhaustionError
            break
        }
        continue
    }

    foreach ($item in $freshList) {
        if ($callCount -ge $MaxCalls -or $exhausted) { break }

        $kw = [string]$item.keyword
        $vol = [int]$item.volume
        $gender = [string]$item.gender
        if ([string]::IsNullOrWhiteSpace($gender)) { $gender = "common" }

        $seenInRun[$kw] = $true

        # Eligibility guards
        $ymyl = Test-KeywordYmylEligibility -Keyword $kw
        if ($ymyl.IsYmyl) { continue }

        $ent = Test-KeywordEntertainmentEligibility -Keyword $kw
        if ($ent.IsEntertainment) { continue }

        # Remote SERP Call
        $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
        if ($null -eq $serp) { continue }
        if ($serp.IsDuplicate) { continue }

        if (-not $serp.IsCached) {
            $callCount++
            $todayTotal = $initialUsage.TotalRealCallsToday + $callCount
            Write-Output "[$callCount] (Total: $todayTotal) Remote SERP: '$kw' (Vol: $vol)..."
        }

        if ($serp.IsExhausted) {
            if ($serp.Error -match "(?i)429|403|Daily report.*limit") {
                $exhausted = $true
                $exhaustionError = $serp.Error
                Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($serp.Error)"
                break
            }
        }

        # SERP Evaluation & Real-Time Hit Handling
        $entries = $serp.serpEntries
        if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }

        if ($entries) {
            # Evaluate male and female star ratings
            $mEval = Get-StrictStarEvaluationMale -Keyword $kw -SearchVolume $vol -SerpEntries $entries
            $fEval = Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries

            $isMaleHit = ($mEval.StarCount -ge 3 -and $mEval.PureLowDaCount -ge 1)
            $isFemaleHit = ($fEval.StarCount -ge 3 -and $fEval.PureLowDaCount -ge 1)

            if ($isMaleHit -or $isFemaleHit) {
                $star3HitsCount++
                $bestEval = if ($isMaleHit) { $mEval } else { $fEval }
                $bestGender = if ($isMaleHit) { "male" } else { "female" }
                Write-Output "  >>> [STAR 3+ HIT!] '$kw' (Stars: $($bestEval.StarCount), Blogs: $($bestEval.PureLowDaCount), UGC: $($bestEval.WeakUgcCount)) -> Gender: $bestGender"

                # Check if we can commit the discovered personal blog immediately
                foreach ($blog in $bestEval.PureLowDaSites) {
                    $bDom = ([string]$blog.domain).ToLower()
                    if ($regState.Domains.ContainsKey($bDom)) { continue }

                    # Form winning keyword string
                    $starChar = [char]0x2606
                    $starPrefix = [string]::new($starChar, $bestEval.StarCount)
                    $formattedKw = "$starPrefix$kw（$vol）"

                    Write-Output "  >>> [REAL-TIME COMMIT ATTEMPT] Site: $($blog.domain) (DA: $($blog.domainAuthority)) -> KW: $formattedKw"
                    try {
                        $commitRes = & "$projectRoot\tools\$bestGender\sheet_commit.ps1" `
                            -SiteName "$($blog.domain) ブログ" `
                            -Url $blog.url `
                            -Da $blog.domainAuthority `
                            -OriginKw $formattedKw `
                            -WinningKws @($formattedKw)

                        Write-Output "  >>> [COMMITTED SUCCESS] Added to $bestGender sheet!"
                        $committedCount++
                        $regState.Domains[$bDom] = $true
                        break # Successfully committed one blog for this KW
                    } catch {
                        Write-Output "  -> Commit held in stock or ratio guard: $_"
                    }
                }
            }
        }

        Start-Sleep -Milliseconds 200
    }
}

Write-Output "`n=========================================================="
Write-Output "PIPELINE COMPLETED"
Write-Output "Calls Made in This Run : $callCount"
$finalUsage = Get-DailyApiQuotaUsage
Write-Output "Total Real Calls Today : $($finalUsage.TotalRealCallsToday)"
Write-Output "New Star 3+ Hits Found : $star3HitsCount"
Write-Output "Sites Committed Today  : $committedCount"
Write-Output "Physical Exhausted     : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Evidence    : $exhaustionError"
    Write-Output "`nExecuting Unified Exit Audit..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\guard_check_exhaustion.ps1" -ErrorText $exhaustionError
} else {
    Write-Output "API Quota not exhausted yet."
}
Write-Output "=========================================================="
