<#
.SYNOPSIS
    tools/research_balanced_genres.ps1
    Responsibility: Execute 50-genre parallel water-leveling research.
    Prioritizes underrepresented genres (deficit-first) in round-robin to raise the water level uniformly.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Gender = "female",

    [Parameter(Mandatory=$false)]
    [int]$MaxTotalCalls = 500,

    [Parameter(Mandatory=$false)]
    [int]$MaxKwsPerGenreBatch = 5
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot

. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\genre_tracker.ps1"
. "$projectRoot\workflow\scripts\research_bulk_expand.ps1"
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"
. "$projectRoot\workflow\scripts\eval_star_calculator.ps1"
. "$projectRoot\workflow\scripts\eval_weak_competitor_rule.ps1"
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
Write-Output "=== 50-GENRE PARALLEL WATER-LEVELING RESEARCH RUNNER ==="
Write-Output "=========================================================="
Write-Output "Target Profile: $Gender ($($profile.SheetTitle))"
Write-Output "Max Total Calls: $MaxTotalCalls"
Write-Output "Max KWs Per Genre Batch: $MaxKwsPerGenreBatch"

$catalog = Get-GenreCatalog -Gender $Gender -CatalogPath $profile.GenreCatalogPath
$volCachePath = "$projectRoot\workflow\data\verified_volume_cache.json"

$totalApiCalls = 0
$exhausted = $false
$exhaustionError = ""
$sitesCommittedCount = 0
$visitedGenres = @{}
$consecutiveTimeouts = 0

# Initialize registered sites and keywords from current sheet to prevent duplicate registrations
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
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

# Helper function to save volume cache safely (PS 5.1 compatible)
function Save-VolumeCacheEntry {
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
        # Advance milestone if all genres reached current milestone
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
    
    # 2. Find keywords for this genre (seeds or expand)
    $seeds = @($targetGenre.Seeds)
    Write-Output "Genre Seeds: $($seeds -join ', ')"
    
    # Collect candidate keywords with Vol >= 1900 from DB or expand
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
    
    # --- DOMAIN KEYWORDS HARVEST (TARGET-GENRE AWARE CANNON) ---
    # Only harvest from discovered sites that match the target genre (or whose harvested keywords match the target genre)
    if ($genreKws.Count -lt 5 -and $totalApiCalls -lt $MaxTotalCalls) {
        try {
            $domQuery = "SELECT domain, site_name FROM discovered_sites WHERE (gender = '$Gender' OR gender = 'common') AND status IN ('candidate', 'active') ORDER BY da ASC, discovered_at DESC LIMIT 5;"
            $availDoms = @(Invoke-SqliteQuery -SqlQuery $domQuery)
            foreach ($domRow in $availDoms) {
                if ($genreKws.Count -ge 5 -or $totalApiCalls -ge $MaxTotalCalls) { break }
                $targetHarvestDom = [string]$domRow.domain
                $targetSiteName = [string]$domRow.site_name
                if ([string]::IsNullOrWhiteSpace($targetHarvestDom) -or $registeredUrls.ContainsKey($targetHarvestDom)) { continue }

                # Pre-check domain and site name for entertainment patterns
                $domCheck = Test-KeywordEntertainmentEligibility -Keyword "$targetHarvestDom $targetSiteName"
                if ($domCheck.IsEntertainment) {
                    Invoke-SqliteNonQuery -SqlQuery "UPDATE discovered_sites SET status = 'excluded_entertainment' WHERE domain = '$targetHarvestDom';" | Out-Null
                    continue
                }

                Write-Output "  >>> [DOMAIN CANNON] Harvesting top keywords from discovered site '$targetHarvestDom' via domain_keywords..."
                $dkRes = Extract-DomainKeywords -Domain $targetHarvestDom -MinVolume 1900 -MaxPosition 10 -Limit 50
                if ($dkRes -and $dkRes.Status -ne "AlreadyQueried" -and $dkRes.Status -ne "DryRun") {
                    # Only increment real call count if not from cache
                    $totalApiCalls++
                }

                if ($dkRes -and $dkRes.WinningKeywords) {
                    foreach ($wk in $dkRes.WinningKeywords) {
                        $kText = [string]$wk.Keyword
                        # Guard: Check Entertainment
                        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kText
                        if ($eCheck.IsEntertainment) { continue }
                        # Guard: Check YMYL
                        $yCheck = Test-KeywordYmylEligibility -Keyword $kText
                        if ($yCheck.IsYmyl) { continue }
                        # Guard: Check Gender
                        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kText
                        if (-not $gCheck.IsAllowed) { continue }

                        # Guard: Check Target Genre Semantic Relevance
                        $isGenreMatch = $false
                        foreach ($sd in $seeds) {
                            $sdToken = ($sd -split "\s+")[0].ToLower().Trim()
                            if (-not [string]::IsNullOrWhiteSpace($sdToken) -and $kText.ToLower().Contains($sdToken)) {
                                $isGenreMatch = $true
                                break
                            }
                        }
                        if (-not $isGenreMatch) {
                            $gTokens = ([string]$targetGenre.Name) -split "[・\s\/\(\)]+"
                            foreach ($gt in $gTokens) {
                                $gtLower = $gt.ToLower().Trim()
                                if ($gtLower.Length -ge 2 -and $kText.ToLower().Contains($gtLower)) {
                                    $isGenreMatch = $true
                                    break
                                }
                            }
                        }

                        if ($isGenreMatch) {
                            $genreKws += @{ Keyword = $kText; Volume = [int]$wk.SearchVolume }
                        }
                    }
                }
                # Always update status to harvested so it never loops on empty domains
                $safeTargetDom = $targetHarvestDom.Replace("'", "''")
                Invoke-SqliteNonQuery -SqlScript "UPDATE discovered_sites SET status = 'harvested' WHERE domain = '$safeTargetDom';" | Out-Null
            }
        } catch {
            Write-Verbose "Domain cannon fail-safe: $_"
        }
    }

    # If not enough keywords in DB, expand seeds via API
    if ($genreKws.Count -lt 5 -and $totalApiCalls -lt $MaxTotalCalls) {
        # Extract concise core head terms (1-2 words) from seeds to ensure match_keywords finds high-volume candidates
        $expandSeeds = @()
        foreach ($s in $seeds) {
            $expandSeeds += $s
            $toks = $s -split "\s+"
            if ($toks.Count -ge 2) {
                $expandSeeds += "$($toks[0]) $($toks[1])"
            }
            if ($toks.Count -ge 1 -and $toks[0].Length -ge 2) {
                $expandSeeds += $toks[0]
            }
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
        if (-not $gCheck.IsAllowed) {
            Write-Output "  [Skip Cross-Gender KW] '$kText' ($($gCheck.Reason))"
            continue
        }
        $yCheck = Test-KeywordYmylEligibility -Keyword $kText
        if ($yCheck.IsYmyl) {
            Write-Output "  [Skip YMYL KW] '$kText' ($($yCheck.Reason))"
            continue
        }
        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kText
        if ($eCheck.IsEntertainment) {
            Write-Output "  [Skip Entertainment KW] '$kText' ($($eCheck.Reason))"
            continue
        }
        if (-not $uniqueKws.ContainsKey($kText)) {
            $uniqueKws[$kText] = $true
            $filteredKws += $item
        }
    }
    
    Write-Output "Available Qualified Keywords (Vol >= 1900) for Genre: $($filteredKws.Count)"
    
    if ($filteredKws.Count -eq 0) {
        Write-Output "  -> No unsearched seeds for genre '$($targetGenre.Name)'. Checking DB pool for matching keywords..."
        # Only pull keywords from DB pool that match target genre seeds or tokens
        $genreSeedTokens = @()
        foreach ($sd in $seeds) {
            $t = ($sd -split "\s+")[0].Trim()
            if ($t.Length -ge 2) { $genreSeedTokens += $t }
        }
        if ($genreSeedTokens.Count -gt 0) {
            $likeClauses = @()
            foreach ($st in $genreSeedTokens) {
                $safeSt = $st.Replace("'", "''")
                $likeClauses += "vk.keyword LIKE '%$safeSt%'"
            }
            $whereLike = ($likeClauses -join " OR ")
            $fallbackQuery = "SELECT vk.keyword, vk.volume FROM verified_keywords vk LEFT JOIN serp_cache sc ON vk.keyword = sc.keyword WHERE vk.volume >= 1900 AND (vk.gender = '$Gender' OR vk.gender = 'common') AND ($whereLike) AND sc.keyword IS NULL ORDER BY vk.volume DESC LIMIT 5;"
            try {
                $fRes = Invoke-SqliteQuery -SqlQuery $fallbackQuery
                if ($fRes) {
                    foreach ($row in $fRes) {
                        $fKw = [string]$row.keyword
                        $fgCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $fKw
                        $fyCheck = Test-KeywordYmylEligibility -Keyword $fKw
                        $feCheck = Test-KeywordEntertainmentEligibility -Keyword $fKw
                        if ($fgCheck.IsAllowed -and -not $fyCheck.IsYmyl -and -not $feCheck.IsEntertainment -and -not $uniqueKws.ContainsKey($fKw)) {
                            $uniqueKws[$fKw] = $true
                            $filteredKws += @{ Keyword = $fKw; Volume = [int]$row.volume }
                        }
                    }
                }
            } catch {}
            Write-Output "  -> Loaded from matching DB pool: $($filteredKws.Count) keywords"
        }
    }

    if ($filteredKws.Count -eq 0) {
        Write-Warning "No qualified high-volume keywords found for genre '$($targetGenre.Name)'. Moving to next genre."
        continue
    }
    
    # 3. Read existing sheet state to prevent duplicates and check ratios
    $sheetData = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $targetSheetName
    $registeredUrls = @{}
    $existingKws = @()
    $kwStartCol = $profile.KwStartCol
    $starChar = [char]0x2606
    
    foreach ($row in $sheetData.Rows) {
        if ($row.Count -gt 2 -and -not [string]::IsNullOrWhiteSpace($row[2])) {
            $u = ($row[2].Trim() -replace "^https?://", "" -replace "/.*$", "").ToLower()
            $registeredUrls[$u] = $true
        }
        for ($c = $kwStartCol; $c -lt $row.Count; $c++) {
            $cell = [string]$row[$c]
            if (-not [string]::IsNullOrWhiteSpace($cell)) {
                foreach ($l in ($cell -split "`r?`n")) {
                    $trimmed = $l.Trim()
                    if ($trimmed.StartsWith($starChar)) {
                        $existingKws += $trimmed
                    }
                }
            }
        }
    }
    
    # 4. Perform SERP analysis for this genre up to MaxKwsPerGenreBatch
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
        if (-not $gCheck.IsAllowed) {
            Write-Output "  [Skip Cross-Gender KW] '$kw' ($($gCheck.Reason))"
            continue
        }
        
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
                Write-Output "  [0s DB-Cache Hit] ($vol) SERP: '$kw' (cached: $consecutiveCacheHits)..."
                if ($consecutiveCacheHits -ge 5) {
                    Write-Output "  -> Fast-forwarding: Genre already well-covered in cache. Moving to unsearched candidate..."
                }
            }
        } else {
            $consecutiveCacheHits = 0
        }

        # 2. If not in DB cache, check if EVER queried (all-time duplicate API prevention)
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

            # Check if total API calls reached limit
            if ($totalApiCalls -ge $MaxTotalCalls) {
                break
            }

            $genreBatchCount++
            $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
            if ($null -ne $serp) {
                if ($serp.IsDuplicate) {
                    Write-Output "  -> Duplicate keyword skipped without API call."
                    continue
                }
                if (-not $serp.IsCached) {
                    $totalApiCalls++
                    Write-Output "  [$totalApiCalls] ($vol) Remote SERP: '$kw'..."
                }
                if ($serp.IsExhausted) {
                    # 1. Immediate stop on hard quota exhaustion
                    if ($serp.Error -match "(?i)429|403|Daily report.*limit") {
                        $exhausted = $true
                        $exhaustionError = $serp.Error
                        Write-Warning "PHYSICAL API EXHAUSTION DETECTED: $($serp.Error)"
                        break
                    }
                    # 2. Consecutive timeout circuit breaker for transient timeouts (NO DOUBLE RETRY: MCP already retried 3 times)
                    $consecutiveTimeouts++
                    Write-Warning "Keyword '$kw' timed out ($consecutiveTimeouts consecutive timeout(s))."
                    if ($consecutiveTimeouts -ge 5) {
                        $exhausted = $true
                        $exhaustionError = $serp.Error
                        Write-Warning "PHYSICAL API EXHAUSTION DETECTED: CONSECUTIVE TIMEOUT THRESHOLD REACHED (5 consecutive failures): $($serp.Error)"
                        break
                    } else {
                        Write-Output "  -> Cooling down 5s and skipping slow keyword '$kw', continuing to next candidate..."
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
                # --- AUTO-HARVEST DISCOVERED PERSONAL BLOGS (ZERO-MISS TRIGGER) ---
                # Scan top 10 results and automatically store all DA 1-9 independent personal blogs into SQLite
                try {
                    $allTop10 = @($entries | Where-Object { $_.position -ge 1 -and $_.position -le 10 })
                    foreach ($ent in $allTop10) {
                        $eDa = [int]$ent.domainAuthority
                        $eDom = ([string]$ent.domain).ToLower().Trim()
                        if ([string]::IsNullOrWhiteSpace($eDom) -or $eDom -eq "nodomain") { continue }
                        $eUgc = if ($Gender -eq "male") { Test-WeakCompetitorMale -Domain $eDom } else { Test-WeakCompetitor -Domain $eDom }
                        if ($eDa -ge 1 -and $eDa -le 9 -and -not $eUgc.IsWeakCompetitor) {
                            $entBlogCheck = Test-KeywordEntertainmentEligibility -Keyword "$eDom $eTitle"
                            if ($entBlogCheck.IsEntertainment) { continue }
                            $eUrl = [string]$ent.url
                            $eTitle = if (-not [string]::IsNullOrWhiteSpace($ent.title)) { $ent.title.Trim().Replace("'", "''") } else { $eDom }
                            $safeDom = $eDom.Replace("'", "''")
                            $safeUrl = $eUrl.Replace("'", "''")
                            $safeKw = $kw.Replace("'", "''")
                            $gid = if ($targetGenre -and $targetGenre.Id) { [int]$targetGenre.Id } else { "NULL" }
                            $insSql = "INSERT OR IGNORE INTO discovered_sites (domain, site_name, url, da, site_type, gender, status, discovered_from_kw, discovered_at, genre_id) VALUES ('$safeDom', '$eTitle', '$safeUrl', $eDa, 'personal_blog', '$Gender', 'candidate', '$safeKw', datetime('now','localtime'), $gid);"
                            Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null
                        }
                    }
                } catch {
                    Write-Verbose "Auto-harvest discovered sites fail-safe: $_"
                }

                $eval = Get-StrictStarEvaluation -Keyword $kw -SearchVolume $vol -SerpEntries $entries
                if ($eval.IsHit) {
                    Write-Output "    -> HIT: $($eval.FormattedValue) (Stars: $($eval.StarCount))"
                    Save-VolumeCacheEntry -Keyword $kw -Volume $vol
                    
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
                        # Pick the single best blog with lowest DA
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

                                # Real-time potato-digging: Harvest top keywords and verify SERP in real-time
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

                                             # Check cached SERP first (0 seconds instant reuse)
                                             $cachedEntries = $null
                                             $archH = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $wText
                                             if ($archH -and $archH.Data) {
                                                 $archHData = $archH.Data
                                                 if ($archHData.serpEntries) { $cachedEntries = $archHData.serpEntries }
                                                 elseif ($archHData.serp_table) { $cachedEntries = $archHData.serp_table }
                                                 elseif ($archHData.result -and $archHData.result.serp_table) { $cachedEntries = $archHData.result.serp_table }
                                                 if ($cachedEntries) {
                                                     Write-Output "    [0s DB-Cache Hit] Harvested SERP: '$wText' (Vol: $wVol)..."
                                                 }
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
                                                $hEval = Get-StrictStarEvaluation -Keyword $wText -SearchVolume $wVol -SerpEntries $targetEntries
                                                if ($hEval.IsHit) {
                                                    Save-VolumeCacheEntry -Keyword $wText -Volume $wVol
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

                                 # Check portfolio ratio (Soft guidance, never shelving qualified discoveries)
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
                                              -GenreName $targetGenre.Name
                                         
                                         Write-Output "    Commit Result: $commitOut"
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
                                         Write-Output "    [REAL-TIME SUCCESS] Site '$siteTitle' successfully committed to $Gender spreadsheet! (Total new sites: $sitesCommittedCount)"
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
Write-Output "50-GENRE WATER-LEVELING BATCH COMPLETED"
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