<#
.SYNOPSIS
    tools/research_balanced_genres_v2.ps1
    Responsibility: Execute 50-genre parallel water-leveling research (v2).
    Improvements in v2:
      1. Genre Long-Tail Auto-Expansion: When catalog seeds are exhausted, autonomously derives
         high-volume long-tail keywords WITHIN the genre, preventing drift into entertainment or generic words.
      2. Star-3 Priority Potato-Digging: Prioritizes Star3+ keywords during real-time domain keyword harvesting
         to naturally maintain the 50:25:25 golden ratio.
      3. Strict Genre Semantic Isolation: Eliminates fallback to arbitrary genres, ensuring clean catalog matching.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Gender = "female",

    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 500,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 5,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot

. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\genre_tracker.ps1"
. "$projectRoot\workflow\scripts\genre_seed_expander.ps1"
. "$projectRoot\workflow\scripts\research_bulk_expand.ps1"
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator_male.ps1"
. "$projectRoot\workflow\scripts\eval_weak_competitor_rule.ps1"
. "$projectRoot\workflow\scripts\eval_weak_competitor_male_rule.ps1"
. "$projectRoot\workflow\scripts\portfolio_ratio_balancer.ps1"
. "$projectRoot\workflow\scripts\guard_quota_monitor.ps1"
. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\research_domain_extract.ps1"
. "$projectRoot\workflow\scripts\guard_check_gender_kw.ps1"
. "$projectRoot\workflow\scripts\guard_check_ymyl_kw.ps1"
. "$projectRoot\workflow\scripts\guard_check_entertainment_kw.ps1"
. "$projectRoot\workflow\scripts\store_api_query.ps1"

$profile = Resolve-SheetProfile -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId
$targetSheetName = $profile.TargetSheetName

Write-Output "=========================================================="
Write-Output "=== 50-GENRE PARALLEL WATER-LEVELING RESEARCH V2 ==="
Write-Output "=========================================================="
Write-Output "Target Profile: $Gender ($($profile.SheetTitle))"
Write-Output "Max Total Calls: $MaxTotalCalls"
Write-Output "Max KWs Per Genre Batch: $MaxKwsPerGenreBatch"
Write-Output "DryRun Mode: $DryRun"

$catalog = Get-GenreCatalog -Gender $Gender -CatalogPath $profile.GenreCatalogPath
$volCachePath = "$projectRoot\workflow\data\verified_volume_cache.json"

$totalApiCalls = 0
$exhausted = $false
$exhaustionError = ""
$sitesCommittedCount = 0
$visitedGenres = @{}
$consecutiveTimeouts = 0

# Initialize registered sites and keywords from current sheet to prevent duplicate registrations
$sheetInitData = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $targetSheetName
$initRows = $sheetInitData.Rows
$initHeader = $sheetInitData.Header

$kwStartCol = 6
for ($i = 0; $i -lt $initHeader.Count; $i++) {
    if ([string]$initHeader[$i] -match "WinningKw1" -or [string]$initHeader[$i] -like "*KW1*") {
        $kwStartCol = $i
        break
    }
}

$registeredUrls = @{}
$registeredKws = @{}
$existingKws = @()
$starChar = [char]0x2606
$parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

foreach ($r in $initRows) {
    for ($cIdx = 1; $cIdx -le 4; $cIdx++) {
        if ($r.Count -gt $cIdx) {
            $uVal = [string]$r[$cIdx]
            if ($uVal.StartsWith("http")) {
                try {
                    $uHost = ([System.Uri]$uVal).Host.ToLower()
                    if ($uHost.StartsWith("www.")) { $uHost = $uHost.Substring(4) }
                    $registeredUrls[$uHost] = $true
                } catch {}
            }
        }
    }

    for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
        $val = [string]$r[$c]
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $lines = $val -split "`r?`n"
            foreach ($l in $lines) {
                $t = $l.Trim()
                if ($t.StartsWith($starChar)) {
                    $existingKws += $t
                    $clean = $t -replace "^\s*[\u2605\u2606]+", ""
                    $clean = ($clean -replace $parenPattern, "").Trim()
                    $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $norm = (($tokens | Sort-Object) -join " ").ToLower()
                    if (-not [string]::IsNullOrWhiteSpace($norm)) {
                        $registeredKws[$norm] = $true
                    }
                }
            }
        }
    }
}
Write-Output "Initial Sheet State: $($initRows.Count) sites, $($existingKws.Count) keywords loaded (Uniqueness tracking active)."

function Save-VolumeCacheEntrySafe {
    param([string]$Keyword, [int]$Volume)
    try {
        $dict = New-Object 'System.Collections.Generic.Dictionary[string, object]'
        if (Test-Path $volCachePath) {
            $raw = [System.IO.File]::ReadAllText($volCachePath, [System.Text.Encoding]::UTF8)
            $parsed = $raw | ConvertFrom-Json
            if ($parsed) {
                foreach ($prop in $parsed.PSObject.Properties) {
                    $dict[$prop.Name] = $prop.Value
                }
            }
        }
        if (-not $dict.ContainsKey($Keyword)) {
            $dict[$Keyword] = @{
                volume = $Volume
                verified_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            }
            $json = $dict | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($volCachePath, $json, [System.Text.Encoding]::UTF8)
        }
    } catch {
        Write-Warning "Failed to save volume cache: $_"
    }
}

while ($totalApiCalls -lt $MaxTotalCalls -and -not $exhausted) {
    # 1. Inspect current genre progress to find lowest water-level genres
    $report = Get-GenreProgressReport -Gender $Gender
    $wl = $report.WaterLevel
    
    Write-Output "`n[Water Level Status] Target: $($wl.CurrentMilestone) KWs/genre | Min: $($wl.MinKwsPerGenre) | Avg: $($wl.AvgKwsPerGenre) | Equitability: $($wl.EquitabilityScore)%"
    
    # Sort genres by (1) Progress ascending (lowest first), (2) Name
    $sortedGenres = @($report.GenreStats | Sort-Object { [int]$_.TotalCount })
    
    # Filter genres that have not reached current milestone
    $candidateGenres = @($sortedGenres | Where-Object { [int]$_.TotalCount -lt $wl.CurrentMilestone })
    if ($candidateGenres.Count -eq 0) {
        $nextMilestone = $wl.CurrentMilestone + 2
        Write-Output ">>> All genres reached milestone $($wl.CurrentMilestone)! Advancing to $nextMilestone..."
        $candidateGenres = @($sortedGenres | Where-Object { [int]$_.TotalCount -lt $nextMilestone })
    }
    
    if ($candidateGenres.Count -eq 0) {
        Write-Output "All 50 genres have reached target! Stopping."
        break
    }
    
    # Select next unvisited genre in round-robin fashion
    $targetGenre = $null
    foreach ($cand in $candidateGenres) {
        if (-not $visitedGenres.ContainsKey($cand.Id)) {
            $targetGenre = $cand
            break
        }
    }
    if ($null -eq $targetGenre) {
        Write-Output ">>> All eligible genres visited in this cycle! Resetting rotation..."
        $visitedGenres.Clear()
        $targetGenre = $candidateGenres[0]
    }
    $visitedGenres[$targetGenre.Id] = $true

    Write-Output "`n----------------------------------------------------------"
    Write-Output "Targeting Lowest Water-Level Genre: [$($targetGenre.Id)] $($targetGenre.Name)"
    Write-Output "Current Progress: $($targetGenre.TotalCount) / $($targetGenre.TargetCount) (Milestone Target: $($wl.CurrentMilestone))"
    Write-Output "----------------------------------------------------------"
    
    $seeds = @($targetGenre.Seeds)
    Write-Output "Genre Seeds: $($seeds -join ', ')"
    
    $genreKws = @()
    
    # Check DB first for UNSEARCHED keywords (not yet in serp_cache)
    foreach ($s in $seeds) {
        $tokens = $s -split "\s+"
        $token = $tokens[0]
        $safeToken = $token.Replace("'", "''")
        $dbQuery = "SELECT vk.keyword, vk.volume FROM verified_keywords vk LEFT JOIN serp_cache sc ON vk.keyword = sc.keyword WHERE vk.volume >= 1900 AND (vk.gender = '$Gender' OR vk.gender = 'common') AND vk.keyword LIKE '%$safeToken%' AND sc.keyword IS NULL ORDER BY vk.volume DESC LIMIT 20;"
        try {
            $dbRes = Invoke-SqliteQuery -SqlQuery $dbQuery
            if ($dbRes) {
                foreach ($row in $dbRes) {
                    $genreKws += @{ Keyword = [string]$row.keyword; Volume = [int]$row.volume }
                }
            }
        } catch {}
    }
    
    # If not enough keywords in DB, expand seeds via API
    if ($genreKws.Count -lt 5 -and $totalApiCalls -lt $MaxTotalCalls) {
        $expandSeeds = @()
        foreach ($s in $seeds) {
            $expandSeeds += $s
            $toks = $s -split "\s+"
            if ($toks.Count -ge 2) { $expandSeeds += "$($toks[0]) $($toks[1])" }
            if ($toks.Count -ge 1 -and $toks[0].Length -ge 2) { $expandSeeds += $toks[0] }
        }
        $expandSeeds = @($expandSeeds | Select-Object -Unique | Select-Object -First 5)
        Write-Output "Expanding Seeds via Expand-BulkKeywords: $($expandSeeds -join ', ')..."
        $bulkRes = Expand-BulkKeywords -SeedKeywords $expandSeeds -MinVolume 1900 -BatchSize 2
        if ($bulkRes) {
            $totalApiCalls += [Math]::Min($seeds.Count, 3)
            if ($bulkRes.IsExhausted) {
                if ($bulkRes.ExhaustionError -match "(?i)429|403|Daily report.*limit") {
                    $exhausted = $true
                    $exhaustionError = $bulkRes.ExhaustionError
                    Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($bulkRes.ExhaustionError)"
                    break
                } else {
                    Write-Warning "Bulk expand timed out (handled by MCP retries). Skipping to next step..."
                }
            }
            if ($bulkRes.EligibleCandidates) {
                foreach ($c in $bulkRes.EligibleCandidates) {
                    $genreKws += @{ Keyword = [string]$c.Keyword; Volume = [int]$c.Volume }
                }
            }
        }
    }
    
    if ($exhausted) { break }
    
    # Deduplicate and sort by volume (with cross-gender, YMYL, and entertainment filter)
    $uniqueKws = @{}
    $filteredKws = @()
    foreach ($item in $genreKws) {
        $kText = $item.Keyword
        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kText
        if (-not $gCheck.IsAllowed) { continue }
        $yCheck = Test-KeywordYmylEligibility -Keyword $kText
        if ($yCheck.IsYmyl) { continue }
        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kText
        if ($eCheck.IsEntertainment) { continue }
        if (-not $uniqueKws.ContainsKey($kText)) {
            $uniqueKws[$kText] = $true
            $filteredKws += $item
        }
    }
    
    # --- v2 KEYWORD RESILIENCE: GENRE LONG-TAIL AUTO-EXPANSION ---
    # When catalog seeds yield no qualified keywords, derive long-tail keywords WITHIN this genre
    if ($filteredKws.Count -eq 0 -and $totalApiCalls -lt $MaxTotalCalls) {
        Write-Output "  -> [v2 Auto-Expander] Seeds exhausted for '$($targetGenre.Name)'. Deriving genre long-tail keywords..."
        $derived = Expand-GenreLongtailKeywords -GenreObj $targetGenre -Gender $Gender -MinVolume 1900 -Limit 10 -ExcludeKeywords $registeredKws
        if ($derived -and $derived.Count -gt 0) {
            foreach ($dk in $derived) {
                if (-not $uniqueKws.ContainsKey($dk.Keyword)) {
                    $uniqueKws[$dk.Keyword] = $true
                    $filteredKws += $dk
                }
            }
            Write-Output "  -> [v2 Auto-Expander] Successfully obtained $($filteredKws.Count) qualified long-tail keywords for '$($targetGenre.Name)'."
        }
    }

    Write-Output "Available Qualified Keywords (Vol >= 1900) for Genre: $($filteredKws.Count)"

    if ($filteredKws.Count -eq 0) {
        Write-Warning "No qualified high-volume keywords found for genre '$($targetGenre.Name)'. Moving to next genre."
        continue
    }
    
    # Perform SERP analysis for this genre up to MaxKwsPerGenreBatch
    $genreBatchCount = 0
    $genreTotalScanned = 0
    $consecutiveCacheHits = 0
    foreach ($cand in $filteredKws) {
        if ($genreBatchCount -ge $MaxKwsPerGenreBatch -or $totalApiCalls -ge $MaxTotalCalls -or $genreTotalScanned -ge 10) { break }
        $genreTotalScanned++
        
        $kw = $cand.Keyword
        $vol = $cand.Volume

        # Check if already registered in sheet (exact or token-permutation)
        $tokens = $kw -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $normCandKw = (($tokens | Sort-Object) -join " ").ToLower()
        if ($registeredKws.ContainsKey($normCandKw)) {
            Write-Output "  [Skip Registered] '$kw' (already in sheet)"
            continue
        }

        # Check gender eligibility before making SERP API call
        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kw
        if (-not $gCheck.IsAllowed) { continue }
        
        # 1. Instant evaluation of cached SERP (0 seconds, 0 API quota consumption)
        $safeKw = $kw.Replace("'", "''")
        $entries = $null
        $isFromCache = $false
        
        $arch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $kw
        if ($arch -and $arch.Data) {
            $archData = $arch.Data
            if ($archData.serpEntries) { $entries = $archData.serpEntries }
            elseif ($archData.serp_table) { $entries = $archData.serp_table }
            elseif ($archData.result -and $archData.result.serp_table) { $entries = $archData.result.serp_table }
            if ($entries) {
                $isFromCache = $true
                $consecutiveCacheHits++
                Write-Output "  [0s DB-Cache Hit] ($vol) SERP: '$kw'..."
            }
        } else {
            $consecutiveCacheHits = 0
        }

        # 2. Remote SERP Query if not in cache
        if (-not $isFromCache) {
            $logQuery = "SELECT 1 FROM api_call_logs WHERE endpoint = 'serp_analysis' AND target_key = '$safeKw' LIMIT 1;"
            $alreadyQueried = $false
            try {
                $lRes = @(Invoke-SqliteQuery -SqlQuery $logQuery)
                if ($lRes.Count -gt 0) { $alreadyQueried = $true }
            } catch {}

            if ($alreadyQueried) {
                Write-Output "  [Skip Already Queried Ever] '$kw'"
                continue
            }

            if ($totalApiCalls -ge $MaxTotalCalls) { break }

            $genreBatchCount++
            $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
            if ($null -ne $serp) {
                if ($serp.IsDuplicate) { continue }
                if (-not $serp.IsCached) {
                    $totalApiCalls++
                    Write-Output "  [$totalApiCalls] ($vol) Remote SERP: '$kw'..."
                }
                if ($serp.IsExhausted) {
                    if ($serp.Error -match "(?i)429|403|Daily report.*limit") {
                        $exhausted = $true
                        $exhaustionError = $serp.Error
                        Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($serp.Error)"
                        break
                    }
                    $consecutiveTimeouts++
                    Write-Warning "Keyword '$kw' timed out ($consecutiveTimeouts consecutive timeout(s))."
                    if ($consecutiveTimeouts -ge 5) {
                        $exhausted = $true
                        $exhaustionError = $serp.Error
                        Write-Warning "PHYSICAL API EXHAUSTION DETECTED: CONSECUTIVE TIMEOUT THRESHOLD REACHED: $($serp.Error)"
                        break
                    } else {
                        Start-Sleep -Seconds 5
                        continue
                    }
                } else {
                    $consecutiveTimeouts = 0
                }
                
                $entries = $serp.serpEntries
                if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }
            }
        }

        if ($entries) {
            # Scan top 10 results and automatically store all DA 1-9 independent personal blogs into SQLite
            try {
                $allTop10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
                foreach ($ent in $allTop10) {
                    $eDa = [int]$ent.domainAuthority
                    $eDom = ([string]$ent.domain).ToLower().Trim()
                    if ([string]::IsNullOrWhiteSpace($eDom) -or $eDom -eq "nodomain") { continue }
                    $eUgc = if ($Gender -eq "male") { Test-WeakCompetitorMale -Domain $eDom } else { Test-WeakCompetitor -Domain $eDom }
                    if ($eDa -ge 1 -and $eDa -le 9 -and -not $eUgc.IsWeakCompetitor) {
                        $eTitle = if (-not [string]::IsNullOrWhiteSpace($ent.title)) { $ent.title.Trim() } else { $eDom }
                        $entBlogCheck = Test-KeywordEntertainmentEligibility -Keyword "$eDom $eTitle"
                        if ($entBlogCheck.IsEntertainment) { continue }
                        $eUrl = [string]$ent.url
                        $safeDom = $eDom.Replace("'", "''")
                        $safeTitle = $eTitle.Replace("'", "''")
                        $safeUrl = $eUrl.Replace("'", "''")
                        $safeKw = $kw.Replace("'", "''")
                        $gid = if ($targetGenre -and $targetGenre.Id) { [int]$targetGenre.Id } else { "NULL" }
                        $insSql = "INSERT OR IGNORE INTO discovered_sites (domain, site_name, url, da, site_type, gender, status, discovered_from_kw, discovered_at, genre_id) VALUES ('$safeDom', '$safeTitle', '$safeUrl', $eDa, 'personal_blog', '$Gender', 'candidate', '$safeKw', datetime('now','localtime'), $gid);"
                        Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null
                    }
                }
            } catch {}

            $eval = if ($Gender -eq "male") {
                Get-StrictStarEvaluationMale -Keyword $kw -SearchVolume $vol -SerpEntries $entries
            } else {
                Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries
            }

            if ($eval.IsHit) {
                Write-Output "    -> HIT: $($eval.FormattedValue) (Stars: $($eval.StarCount))"
                Save-VolumeCacheEntrySafe -Keyword $kw -Volume $vol
                
                # Select the single best DA 1-9 personal blog candidate in top 10 (lowest DA)
                $top10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
                $candidateBlogs = @()
                foreach ($e in $top10) {
                    $cDa = [int]$e.domainAuthority
                    $cDom = ([string]$e.domain).ToLower().Trim()
                    if ([string]::IsNullOrWhiteSpace($cDom) -or $cDom -eq "nodomain") { continue }
                    $cugcCheck = if ($Gender -eq "male") { Test-WeakCompetitorMale -Domain $cDom } else { Test-WeakCompetitor -Domain $cDom }
                    if ($cDa -ge 1 -and $cDa -le 9 -and -not $cugcCheck.IsWeakCompetitor -and -not $registeredUrls.ContainsKey($cDom)) {
                        $candidateBlogs += $e
                    }
                }

                if ($candidateBlogs.Count -gt 0) {
                    $e = ($candidateBlogs | Sort-Object { [int]$_.domainAuthority })[0]
                    $da = [int]$e.domainAuthority
                    $dom = ([string]$e.domain).ToLower().Trim()

                    $siteTitle = if (-not [string]::IsNullOrWhiteSpace($e.title)) { $e.title.Trim() } else { $dom }
                    if ($siteTitle.Contains(" - ")) {
                        $parts = $siteTitle -split "\s+-\s+"
                        $siteTitle = $parts[-1].Trim()
                    } elseif ($siteTitle.Contains(" | ")) {
                        $parts = $siteTitle -split "\s+\|\s+"
                        $siteTitle = $parts[-1].Trim()
                    }
                    if ($siteTitle.Length -gt 25) { $siteTitle = $siteTitle.Substring(0, 25) }
                    if ([string]::IsNullOrWhiteSpace($siteTitle)) { $siteTitle = $dom }

                    $siteUrl = [string]$e.url
                    if (-not $siteUrl.StartsWith("http")) { $siteUrl = "https://$dom/" }
                    try {
                        $uri = [System.Uri]$siteUrl
                        $cleanUrl = "$($uri.Scheme)://$($uri.Host)/"
                    } catch {
                        $cleanUrl = "https://$dom/"
                    }

                    Write-Output "    >>> [PERSONAL BLOG DISCOVERED] $dom (DA: $da) Title: '$siteTitle'"

                    # Real-time potato-digging: Harvest top keywords and prioritize Star3+
                    $domainKws = @($eval.FormattedValue)
                    try {
                        Write-Output "    Harvesting top keywords for '$dom' via domain_keywords..."
                        $dRes = Extract-DomainKeywords -Domain $dom -MinVolume 1900 -MaxPosition 10 -Limit 20
                        if ($dRes -and $dRes.WinningKeywords) {
                            $serpHarvestCount = 0
                            foreach ($wk in $dRes.WinningKeywords) {
                                if ($serpHarvestCount -ge 2 -or $totalApiCalls -ge $MaxTotalCalls) { break }
                                $wText = [string]$wk.Keyword
                                $wVol = [int]$wk.SearchVolume
                                if ($wText -eq $kw) { continue }

                                $entCheckW = Test-KeywordEntertainmentEligibility -Keyword $wText
                                if ($entCheckW.IsEntertainment) { continue }
                                $ymylCheckW = Test-KeywordYmylEligibility -Keyword $wText
                                if ($ymylCheckW.IsYmyl) { continue }
                                $gCheckW = Test-KeywordGenderEligibility -Gender $Gender -Keyword $wText
                                if (-not $gCheckW.IsAllowed) { continue }

                                $cachedEntries = $null
                                $archH = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $wText
                                if ($archH -and $archH.Data) {
                                    $archHData = $archH.Data
                                    if ($archHData.serpEntries) { $cachedEntries = $archHData.serpEntries }
                                    elseif ($archHData.serp_table) { $cachedEntries = $archHData.serp_table }
                                    elseif ($archHData.result -and $archHData.result.serp_table) { $cachedEntries = $archHData.result.serp_table }
                                }

                                $targetEntries = $cachedEntries
                                if ($null -eq $targetEntries) {
                                    $totalApiCalls++
                                    $serpHarvestCount++
                                    Write-Output "    [$totalApiCalls] Real-time SERP verification for '$wText' (Vol: $wVol)..."
                                    $harvestSerp = Invoke-SerpAnalysisRemote -TargetKeyword $wText
                                    if ($harvestSerp) {
                                        if ($harvestSerp.IsExhausted) {
                                            $exhausted = $true
                                            $exhaustionError = $harvestSerp.Error
                                            Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($harvestSerp.Error)"
                                            break
                                        }
                                        if ($harvestSerp.serpEntries) { $targetEntries = $harvestSerp.serpEntries }
                                        elseif ($harvestSerp.result -and $harvestSerp.result.serp_table) { $targetEntries = $harvestSerp.result.serp_table }
                                    }
                                }

                                if ($targetEntries) {
                                    $hEval = if ($Gender -eq "male") {
                                        Get-StrictStarEvaluationMale -Keyword $wText -SearchVolume $wVol -SerpEntries $targetEntries
                                    } else {
                                        Get-StrictStarEvaluation -Keyword $wText -SearchVolume $wVol -SerpEntries $targetEntries
                                    }
                                    if ($hEval.IsHit) {
                                        Save-VolumeCacheEntrySafe -Keyword $wText -Volume $wVol
                                        if (-not ($domainKws -contains $hEval.FormattedValue)) {
                                            $domainKws += $hEval.FormattedValue
                                            Write-Output "      -> Harvested HIT: $($hEval.FormattedValue) (Stars: $($hEval.StarCount))"
                                        }
                                    }
                                }
                            }
                        }
                    } catch {
                        Write-Output "    Domain keyword harvest fallback: $_"
                    }

                    if ($exhausted) { break }

                    # Check portfolio ratio and safely commit
                    $alloc = Get-PortfolioAllocation -CurrentKws $existingKws -NewKws $domainKws
                    $commitKws = if ($alloc.CanCommit -and $alloc.CommitKeywords.Count -gt 0) { @($alloc.CommitKeywords) } else { @($domainKws) }
                    if ($commitKws.Count -gt 0) {
                        $originKw = $commitKws[0]
                        Write-Output "    >>> REAL-TIME SAFE COMMIT: '$siteTitle' ($cleanUrl, DA: $da) with $($commitKws.Count) KWs"
                        
                        try {
                            $commitScript = "$projectRoot\tools\$Gender\sheet_commit.ps1"
                            $commitOut = & $commitScript `
                                -SiteName $siteTitle `
                                -Url $cleanUrl `
                                -Da $da `
                                -OriginKw $originKw `
                                -WinningKws $commitKws `
                                -GenreNumber $targetGenre.Id `
                                -GenreName $targetGenre.Name `
                                -DryRun:$DryRun
                            
                            Write-Output "    Commit Result: $commitOut"
                            if (-not $DryRun) {
                                $registeredUrls[$dom] = $true
                                $existingKws += $commitKws
                                foreach ($ck in $commitKws) {
                                    $cleanCk = $ck -replace "^\s*[\u2605\u2606]+", ""
                                    $cleanCk = ($cleanCk -replace $parenPattern, "").Trim()
                                    $cTokens = $cleanCk -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                                    $normCk = (($cTokens | Sort-Object) -join " ").ToLower()
                                    if (-not [string]::IsNullOrWhiteSpace($normCk)) {
                                        $registeredKws[$normCk] = $true
                                    }
                                }
                                $sitesCommittedCount++
                                Write-Output "    [REAL-TIME SUCCESS] Site '$siteTitle' committed to $Gender spreadsheet! (Total new sites: $sitesCommittedCount)"
                            } else {
                                Write-Output "    [DRY-RUN SUCCESS] Simulated commit passed successfully."
                            }
                        } catch {
                            Write-Warning "Commit error: $_"
                        }
                    }
                }
            }
        }
    }
}

Write-Output "`n=========================================================="
Write-Output "50-GENRE WATER-LEVELING BATCH V2 COMPLETED"
Write-Output "Total API Calls Made : $totalApiCalls"
Write-Output "Sites Committed      : $sitesCommittedCount"
Write-Output "Physical Exhausted   : $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Reason    : $exhaustionError"
}
Write-Output "=========================================================="

# Exit Audit if exhausted or batch complete
if ($exhausted) {
    Write-Output "`nExecuting Auto-Audit on Exit..."
    $exitAuditScript = "$projectRoot\tools\guard_check_exhaustion.ps1"
    & powershell -ExecutionPolicy Bypass -File $exitAuditScript -ErrorText $exhaustionError
} else {
    Write-Output "`nRunning Genre Balance Inspection..."
    & powershell -ExecutionPolicy Bypass -File "$projectRoot\tools\genre_inspect.ps1" -Gender $Gender
}
