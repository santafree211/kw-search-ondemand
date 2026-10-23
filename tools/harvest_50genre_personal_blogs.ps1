<#
.SYNOPSIS
    tools/harvest_50genre_personal_blogs.ps1
    Responsibility: Harvest 100 independent personal blogs (measured DA 1-9) for each of the 50 genres into SQLite DB.
    Target: 50 genres x 100 sites = 5,000 personal blogs.
    Pure Ubersuggest SERP analysis with zero hallucination.
    Usage:
      powershell -ExecutionPolicy Bypass -File tools\harvest_50genre_personal_blogs.ps1 [-Gender both|female|male] [-MaxCalls 1500] [-SitesPerGenreTarget 100]
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$MaxCalls = 1500,

    [Parameter(Mandatory=$false)]
    [int]$SitesPerGenreTarget = 100,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

. "$projectRoot\workflow\scripts\db_sqlite_manager.ps1"
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\genre_tracker.ps1"
. "$projectRoot\workflow\scripts\research_serp_fetcher.ps1"
. "$projectRoot\workflow\scripts\research_domain_harvester.ps1"
. "$projectRoot\workflow\scripts\guard_check_entertainment_kw.ps1"
. "$projectRoot\workflow\scripts\guard_check_ymyl_kw.ps1"

Write-Output "=========================================================="
Write-Output "=== 50-GENRE x 100 PERSONAL BLOGS OILFIELD HARVESTER ==="
Write-Output "=========================================================="
Write-Output "Target Mode           : $Gender"
Write-Output "Sites Per Genre Target: $SitesPerGenreTarget (Total: $($SitesPerGenreTarget * 50))"
Write-Output "Max API Calls Allowed : $MaxCalls"
Write-Output "DryRun Mode           : $DryRun"

$gendersToRun = if ($Gender -eq "both") { @("female", "male") } else { @($Gender) }
$totalCalls = 0
$totalDiscoveredSites = 0

foreach ($g in $gendersToRun) {
    if ($totalCalls -ge $MaxCalls) { break }
    
    $profile = Resolve-SheetProfile -Gender $g
    $catalog = Get-GenreCatalog -Gender $g -CatalogPath $profile.GenreCatalogPath
    
    Write-Output "`n>>> Scanning Profile: $g ($($catalog.Genres.Count) genres)..."
    
    foreach ($genre in $catalog.Genres) {
        if ($totalCalls -ge $MaxCalls) { break }
        
        $gidNum = [int]($genre.Id -replace '\D', '')
        
        # Check current personal blog count in DB for this genre
        $countSql = "SELECT count(DISTINCT domain) FROM discovered_sites WHERE da BETWEEN 1 AND 9 AND site_type = 'personal_blog' AND (gender = '$g' OR gender IS NULL) AND genre_id = $gidNum;"
        $currentCount = 0
        try {
            $cRes = Invoke-SqliteQuery -SqlQuery $countSql
            if ($cRes -and $cRes.Count -gt 0) {
                $prop = ($cRes[0].PSObject.Properties | Select-Object -First 1).Name
                $currentCount = [int]$cRes[0].$prop
            }
        } catch {}
        
        if ($currentCount -ge $SitesPerGenreTarget) {
            Write-Output "  [Target Reached] [$($genre.Id)] $($genre.Name): $currentCount / $SitesPerGenreTarget sites. Skipping."
            continue
        }
        
        Write-Output "`n----------------------------------------------------------"
        Write-Output "Harvesting Blogs for [$($genre.Id)] $($genre.Name) (Current: $currentCount / $SitesPerGenreTarget)"
        Write-Output "----------------------------------------------------------"
        
        $seeds = @($genre.Seeds)
        foreach ($seed in $seeds) {
            if ($totalCalls -ge $MaxCalls -or $currentCount -ge $SitesPerGenreTarget) { break }
            
            $kw = [string]$seed
            if ([string]::IsNullOrWhiteSpace($kw)) { continue }
            
            # Check YMYL / Entertainment
            $yCheck = Test-KeywordYmylEligibility -Keyword $kw
            if ($yCheck.IsYmyl) { continue }
            $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
            if ($eCheck.IsEntertainment) { continue }
            
            # Query SERP (cache first, then remote)
            $serp = Invoke-SerpAnalysisRemote -TargetKeyword $kw
            if ($null -ne $serp) {
                if (-not $serp.IsCached) {
                    $totalCalls++
                    Write-Output "  [$totalCalls / $MaxCalls] Remote SERP: '$kw'..."
                } else {
                    Write-Output "  [0s Cache] SERP: '$kw'..."
                }
                
                if ($serp.IsExhausted) {
                    Write-Warning "API Exhaustion detected: $($serp.Error)"
                    $totalCalls = $MaxCalls
                    break
                }
                
                $entries = $serp.serpEntries
                if (-not $entries -and $serp.result -and $serp.result.serp_table) { $entries = $serp.result.serp_table }
                
                if ($entries) {
                    $harvestRes = Get-HarvestedDomainsFromSerp -SerpEntries $entries -Gender $g -MinDa 1 -MaxDa 9
                    if ($harvestRes -and $harvestRes.Domains.Count -gt 0) {
                        foreach ($domObj in $harvestRes.Domains) {
                            $dom = $domObj.Domain
                            $url = $domObj.Url
                            $da = $domObj.DA
                            $title = $domObj.Title
                            
                            $entCheck = Test-KeywordEntertainmentEligibility -Keyword "$dom $title"
                            if ($entCheck.IsEntertainment) { continue }
                            
                            $safeDom = $dom.Replace("'", "''")
                            $safeUrl = $url.Replace("'", "''")
                            $safeTitle = $title.Replace("'", "''")
                            $safeKw = $kw.Replace("'", "''")
                            
                            if (-not $DryRun) {
                                $insSql = "INSERT OR IGNORE INTO discovered_sites (domain, site_name, url, da, site_type, gender, status, discovered_from_kw, discovered_at, genre_id) VALUES ('$safeDom', '$safeTitle', '$safeUrl', $da, 'personal_blog', '$g', 'candidate', '$safeKw', datetime('now','localtime'), $gidNum);"
                                Invoke-SqliteNonQuery -SqlQuery $insSql | Out-Null
                            }
                            
                            $currentCount++
                            $totalDiscoveredSites++
                            Write-Output "     [+1 Blog Discovered] DA=$da | $dom ($title)"
                            if ($currentCount -ge $SitesPerGenreTarget) { break }
                        }
                    }
                }
            }
        }
    }
}

Write-Output "`n=========================================================="
Write-Output "=== HARVESTING RUN FINISHED ==="
Write-Output "Total API Calls Used       : $totalCalls"
Write-Output "Total Personal Blogs Added : $totalDiscoveredSites"
Write-Output "=========================================================="
