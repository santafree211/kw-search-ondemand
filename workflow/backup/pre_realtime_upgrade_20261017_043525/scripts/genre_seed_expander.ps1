<#
.SYNOPSIS
    workflow/scripts/genre_seed_expander.ps1
    Responsibility: Autonomously derive high-volume (>=1900) long-tail keywords WITHIN a specific genre
    when catalog seeds are exhausted, preventing drift into entertainment or generic keywords.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$PSScriptRoot\research_bulk_expand.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\guard_check_gender_kw.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\google_suggest_fetcher.ps1"

function Expand-GenreLongtailKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$GenreObj,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$false)]
        [int]$MinVolume = 1900,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 10,

        [Parameter(Mandatory=$false)]
        [hashtable]$ExcludeKeywords = @{},

        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$ExcludeSerpKeywords = $null,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $genreId = [string]$GenreObj.id
    $genreName = [string]$GenreObj.name
    $seeds = @($GenreObj.seeds)

    Write-Output "  [Genre Expander] Deriving long-tail keywords for [$genreId] $genreName..."

    $derivedKws = @()
    $seenKws = @{}

    # 1. Extract core head terms (1-2 tokens) from seeds
    $coreTokens = @()
    $rawSeedList = @()
    foreach ($s in $seeds) {
        $toks = ([string]$s) -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($toks.Count -ge 1 -and $toks[0].Length -ge 2) {
            $coreTokens += $toks[0].Trim()
        }
        if ($toks.Count -ge 2) {
            $coreTokens += "$($toks[0]) $($toks[1])".Trim()
            $rawSeedList += "$($toks[0]) $($toks[1])".Trim()
        }
        if ($toks.Count -ge 3) {
            $rawSeedList += "$($toks[0]) $($toks[1]) $($toks[2])".Trim()
        }
        if ($toks.Count -ge 1) {
            $rawSeedList += $toks[0].Trim()
        }
    }

    # Also extract tokens from genre name
    $nakaguro = [char]0x30FB
    $splitPattern = "[" + $nakaguro + "\s\/\(\)]+"
    $nameTokens = $genreName -split $splitPattern | Where-Object { $_.Length -ge 2 }
    foreach ($nt in $nameTokens) {
        $coreTokens += $nt.Trim()
        $rawSeedList += $nt.Trim()
    }

    # Generate genre-specific longtail modifier combinations (Pure ASCII) - TOP PRIORITY!
    $headTerms = @($coreTokens | Where-Object { $_.Length -ge 2 -and $_.Length -le 10 } | Select-Object -Unique | Select-Object -First 10)
    $modOsusume    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x81,0x8A,0xE3,0x81,0x99,0xE3,0x81,0x99,0xE3,0x82,0x81))
    $modErabikata  = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE9,0x81,0xB8,0xE3,0x81,0xB3,0xE6,0x96,0xB9))
    $modShoshin    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x88,0x9D,0xE5,0xBF,0x83,0xE8,0x80,0x85))
    $modYarikata   = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x82,0x84,0xE3,0x82,0x8A,0xE6,0x96,0xB9))
    $modKotsu      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x82,0xB3,0xE3,0x83,0x84))
    $modRanking    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xA9,0xE3,0x83,0xB3,0xE3,0x82,0xAD,0xE3,0x83,0xB3,0xE3,0x82,0xB0))
    $modNinki      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE4,0xBA,0xBA,0xE6,0xB0,0x97))
    $modTeire      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0x89,0x8B,0xE5,0x85,0xA5,0xE3,0x82,0x8C))
    $modHikaku     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0xAF,0x94,0xE8,0xBC,0x83))
    $modHajimekata = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0xA7,0x8B,0xE3,0x82,0x81,0xE6,0x96,0xB9))
    $modTsukaikata = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE4,0xBD,0xBF,0xE3,0x81,0x84,0xE6,0x96,0xB9))
    $modReview     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xAC,0xE3,0x83,0x93,0xE3,0x83,0xA5,0xE3,0x83,0xBC))
    $modHyoban     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE8,0xA9,0x95,0xE5,0x88,0xA4))
    $modKuchikomi  = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x8F,0xA3,0xE3,0x82,0xB3,0xE3,0x83,0x9F))
    $modHiyo       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE8,0xB2,0xBB,0xE7,0x94,0xA8))
    $modMerit      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xA1,0xE3,0x83,0xAA,0xE3,0x83,0x83,0xE3,0x83,0x88))
    $modKoka       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x8A,0xB9,0xE6,0x9E,0x9C))
    $modTejun      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0x89,0x8B,0xE9,0xA0,0x86))
    $modChuiten    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0xB3,0xA8,0xE6,0x84,0x8F,0xE7,0x82,0xB9))
    $modBlog       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0x96,0xE3,0x83,0xAD,0xE3,0x82,0xB0))
    $modifiers = @(
        $modOsusume, $modErabikata, $modShoshin, $modYarikata, $modKotsu, $modRanking,
        $modNinki, $modTeire, $modHikaku, $modHajimekata, $modTsukaikata, $modReview,
        $modHyoban, $modKuchikomi, $modHiyo, $modMerit, $modKoka, $modTejun, $modChuiten, $modBlog
    )

    # Dynamically load AI Daily Modifiers from external JSON (Zero token runtime cost)
    $aiConfigFile = Join-Path $PSScriptRoot "..\config\ai_daily_modifiers.json"
    $dynamicMods = @()
    if (Test-Path $aiConfigFile) {
        try {
            $aiConfigJson = [System.IO.File]::ReadAllText($aiConfigFile, [System.Text.Encoding]::UTF8)
            $aiConfigObj = $aiConfigJson | ConvertFrom-Json
            if ($aiConfigObj.universal_modifiers) {
                $dynamicMods += @($aiConfigObj.universal_modifiers)
            }
            if ($aiConfigObj.intent_categories) {
                foreach ($prop in $aiConfigObj.intent_categories.PSObject.Properties) {
                    $dynamicMods += @($prop.Value)
                }
            }
        } catch {}
    }

    $allModifiers = if ($dynamicMods.Count -gt 0) {
        @(@($dynamicMods) + @($modifiers)) | Select-Object -Unique
    } else {
        $modifiers
    }

    $longtailSeeds = @()
    foreach ($h in $headTerms) {
        foreach ($m in $allModifiers) {
            $longtailSeeds += "$h $m"
        }
    }

    # Fetch live, real-time Google Autocomplete suggestions directly from head terms (Zero API Cost)
    $liveSuggestions = @()
    foreach ($h in ($headTerms | Select-Object -First 3)) {
        try {
            $sugs = Get-LiveGoogleSuggestions -Keyword $h -Limit 10
            if ($sugs -and $sugs.Count -gt 0) {
                $liveSuggestions += $sugs
            }
        } catch {}
    }

    # Priority order: 1. Live Google Autocomplete Suggestions (Real search queries), 2. Longtail combinations ($h $m), 3. Raw seeds
    $candidateSeeds = @($liveSuggestions) + @($longtailSeeds) + @($rawSeedList)
    $candidateSeeds = @($candidateSeeds | Select-Object -Unique)
    $coreTokens = @($coreTokens | Select-Object -Unique)

    if ($candidateSeeds.Count -eq 0) {
        Write-Warning "  [Genre Expander] No valid candidate seeds found for genre '$genreName'."
        return @()
    }

    # 2. Check SQLite DB for existing verified keywords containing core tokens but NOT yet in serp_cache
    foreach ($token in ($coreTokens | Select-Object -First 8)) {
        if ($derivedKws.Count -ge $Limit) { break }
        $safeToken = $token.Replace("'", "''")
        $query = "SELECT vk.keyword, vk.volume FROM verified_keywords vk LEFT JOIN serp_cache sc ON vk.keyword = sc.keyword WHERE vk.volume >= $MinVolume AND (vk.gender = '$Gender' OR vk.gender = 'common') AND vk.keyword LIKE '%$safeToken%' AND sc.keyword IS NULL ORDER BY vk.volume DESC LIMIT 20;"
        try {
            $dbRows = @(Invoke-SqliteQuery -SqlQuery $query)
            foreach ($row in $dbRows) {
                if ($derivedKws.Count -ge $Limit) { break }
                $kw = [string]$row.keyword
                if ([string]::IsNullOrWhiteSpace($kw)) { continue }
                if ($seenKws.ContainsKey($kw) -or $ExcludeKeywords.ContainsKey($kw)) { continue }
                if ($null -ne $ExcludeSerpKeywords -and $ExcludeSerpKeywords.Contains($kw)) { continue }

                # Safety checks
                $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
                if ($eCheck.IsEntertainment) { continue }
                $yCheck = Test-KeywordYmylEligibility -Keyword $kw
                if ($yCheck.IsYmyl) { continue }
                $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kw
                if (-not $gCheck.IsAllowed) { continue }

                $seenKws[$kw] = $true
                $derivedKws += @{
                    Keyword = $kw
                    Volume = [int]$row.volume
                    Source = "DB_Verified"
                }
            }
        } catch {
            Write-Verbose "DB query error in Genre Expander: $_"
        }
    }

    # 3. Filter candidateSeeds against api_call_logs and api_archive to find UNQUERIED seeds for fresh Ubersuggest calls
    $queriedSet = @{}
    try {
        $qSql = "SELECT target_key FROM api_call_logs WHERE endpoint = 'match_keywords' UNION SELECT target_key FROM raw_api_archive WHERE endpoint = 'match_keywords';"
        $qRows = @(Invoke-SqliteQuery -SqlQuery $qSql)
        foreach ($qr in $qRows) {
            $tk = [string]$qr.target_key
            if (-not [string]::IsNullOrWhiteSpace($tk)) {
                $queriedSet[$tk] = $true
                foreach ($subTok in ($tk -split "_")) {
                    $st = $subTok.Trim()
                    if ($st.Length -gt 0) { $queriedSet[$st] = $true }
                }
            }
        }
    } catch {
        Write-Verbose "Error fetching queried set: $_"
    }

    $unqueriedSeeds = @()
    foreach ($cs in $candidateSeeds) {
        $csNorm = $cs.Trim()
        if (-not $queriedSet.ContainsKey($csNorm)) {
            $unqueriedSeeds += $csNorm
        }
    }

    $actualApiCalls = 0
    $isExpExhausted = $false
    $expExhaustError = ""

    # If unqueried seeds exist, query Ubersuggest to inject fresh keywords even if DB has some cached entries
    if ($unqueriedSeeds.Count -gt 0) {
        $apiSeeds = @($unqueriedSeeds | Select-Object -First 4)
        Write-Output "  [Genre Expander] Querying fresh unqueried seeds to discover new keywords: $($apiSeeds -join ', ')..."
        try {
            $bulkRes = Expand-BulkKeywords -SeedKeywords $apiSeeds -MinVolume $MinVolume -BatchSize 2 -DryRun:$DryRun
            if ($bulkRes) {
                if ($null -ne $bulkRes.BatchesProcessed) { $actualApiCalls += [int]$bulkRes.BatchesProcessed }
                if ($bulkRes.IsExhausted) {
                    $isExpExhausted = $true
                    $expExhaustError = $bulkRes.ExhaustionError
                }
                if ($bulkRes.EligibleCandidates) {
                    foreach ($cand in $bulkRes.EligibleCandidates) {
                        $kw = [string]$cand.Keyword
                        $vol = if ($null -ne $cand.Volume -and [int]$cand.Volume -gt 0) { [int]$cand.Volume } elseif ($null -ne $cand.SearchVolume) { [int]$cand.SearchVolume } else { 0 }
                        if ([string]::IsNullOrWhiteSpace($kw) -or $vol -lt $MinVolume) { continue }
                        if ($seenKws.ContainsKey($kw) -or $ExcludeKeywords.ContainsKey($kw)) { continue }
                        if ($null -ne $ExcludeSerpKeywords -and $ExcludeSerpKeywords.Contains($kw)) { continue }

                        # Guard checks
                        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
                        if ($eCheck.IsEntertainment) { continue }
                        $yCheck = Test-KeywordYmylEligibility -Keyword $kw
                        if ($yCheck.IsYmyl) { continue }
                        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kw
                        if (-not $gCheck.IsAllowed) { continue }

                        $seenKws[$kw] = $true
                        $derivedKws += @{
                            Keyword = $kw
                            Volume = $vol
                            Source = "Remote_MatchKeywords"
                        }

                        # Save to verified_keywords SQLite with genre_id tag
                        $safeKw = $kw.Replace("'", "''")
                        $numericGid = if ($genreId) { [int]($genreId -replace '\D', '') } else { "NULL" }
                        $insSql = "INSERT OR IGNORE INTO verified_keywords (keyword, volume, gender, genre_id, updated_at) VALUES ('$safeKw', $vol, '$Gender', $numericGid, datetime('now','localtime'));"
                        try { Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null } catch {}
                    }
                }
            }
        } catch {
            Write-Warning "  [Genre Expander] Error expanding bulk keywords: $_"
        }
    }

    if ($derivedKws.Count -eq 0 -and $unqueriedSeeds.Count -eq 0) {
        Write-Output "  [Genre Expander] All candidate seeds already queried in match_keywords for [$genreId] $genreName."
    } else {
        Write-Output "  [Genre Expander] Successfully derived $($derivedKws.Count) long-tail keywords for [$genreId] $genreName (Remote Calls: $actualApiCalls)."
    }

    return [PSCustomObject]@{
        Keywords        = @($derivedKws)
        ApiCalls        = $actualApiCalls
        IsExhausted     = $isExpExhausted
        ExhaustionError = $expExhaustError
    }
}
