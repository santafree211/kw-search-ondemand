<#
.SYNOPSIS
    workflow/scripts/genre_seed_expander.ps1
    Responsibility: Autonomously derive high-volume (>=1900) long-tail keywords WITHIN a specific genre
    when catalog seeds are exhausted, preventing drift into entertainment or generic keywords.
    Architecture: Lean Orchestrator delegating to single-responsibility modules:
      - seed_modifier_combiner.ps1 (Head terms extraction, modifier combination, and Google autocomplete)
      - seed_database_sifter.ps1 (Database candidate retrieval and YMYL/Entertainment/Gender safety guards)
      - research_bulk_expand.ps1 (Ubersuggest match_keywords bulk expansion)
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\research_bulk_expand.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\guard_check_gender_kw.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\seed_modifier_combiner.ps1"
. "$PSScriptRoot\seed_database_sifter.ps1"

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
    $configDir = Join-Path $projectRoot "workflow\config"

    Write-Output "  [Genre Expander] Deriving long-tail keywords for [$genreId] $genreName..."

    $derivedKws = @()
    $seenKws = @{}

    # 1. Synthesize candidate seeds using AI modifiers and live Google autocomplete
    $synthesized = Get-GenreSynthesizedSeeds -GenreObj $GenreObj -ConfigDir $configDir
    $candidateSeeds = $synthesized.CandidateSeeds
    $coreTokens = $synthesized.CoreTokens

    if ($candidateSeeds.Count -eq 0) {
        Write-Warning "  [Genre Expander] No valid candidate seeds found for genre '$genreName'."
        return @()
    }

    # 2. Check SQLite DB for existing verified keywords containing core tokens but NOT yet in serp_cache
    $dbCandidates = Get-UnsearchedGenreDbKeywords -CoreTokens $coreTokens -Gender $Gender -MinVolume $MinVolume -Limit $Limit -ExcludeKeywords $ExcludeKeywords -ExcludeSerpKeywords $ExcludeSerpKeywords -SeenKeywords $seenKws
    if ($dbCandidates) {
        $derivedKws += $dbCandidates
    }

    # 3. Filter candidateSeeds against match_keywords query history to find truly UNQUERIED seeds
    $queriedSet = @{}
    try {
        $qSql = "SELECT target_key FROM api_call_logs WHERE endpoint = 'match_keywords' UNION SELECT target_key FROM raw_api_archive WHERE endpoint = 'match_keywords';"
        $qRows = @(Invoke-SqliteQuery -SqlQuery $qSql)
        foreach ($qr in $qRows) {
            $tk = [string]$qr.target_key
            if (-not [string]::IsNullOrWhiteSpace($tk)) {
                $queriedSet[$tk] = $true
                foreach ($subTok in ($tk -split "_")) {
                    $st = ([string]$subTok).Trim()
                    if ($st.Length -gt 0) { $queriedSet[$st] = $true }
                }
            }
        }
    } catch {
        Write-Verbose "Error fetching queried set: $_"
    }

    $unqueriedSeeds = @()
    foreach ($cs in $candidateSeeds) {
        $csNorm = ([string]$cs).Trim()
        if (-not $queriedSet.ContainsKey($csNorm)) {
            $unqueriedSeeds += $csNorm
        }
    }

    $actualApiCalls = 0
    $isExpExhausted = $false
    $expExhaustError = ""

    # 4. If unqueried seeds exist, query Ubersuggest to inject fresh keywords
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

                        # Safety guard checks
                        $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
                        if ($eCheck.IsEntertainment) { continue }
                        $yCheck = Test-KeywordYmylEligibility -Keyword $kw
                        if ($yCheck.IsYmyl) { continue }
                        $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kw
                        if (-not $gCheck.IsAllowed) { continue }

                        $seenKws[$kw] = $true
                        $derivedKws += @{
                            Keyword = $kw
                            Volume  = $vol
                            Source  = "Remote_MatchKeywords"
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
