<#
.SYNOPSIS
    potato_origin_fetcher.ps1 - Origin Personal Blog Extraction Module (Pure ASCII)
.DESCRIPTION
    Extracts candidate personal blogs with measured DA 1-9 strictly complying with SKILL.md.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\eval_weak_competitor_male_rule.ps1"

function Get-NextPotatoOriginBlog {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Gender = "both",

        [Parameter(Mandatory=$false)]
        [string[]]$ExcludeDomains = @()
    )

    $genderClause = ""
    if ($Gender -eq "female") {
        $genderClause = "AND (gender = 'female' OR gender = 'common' OR gender IS NULL)"
    } elseif ($Gender -eq "male") {
        $genderClause = "AND (gender = 'male' OR gender = 'common' OR gender IS NULL)"
    }

    $q1 = "SELECT domain, url, site_name, da, gender, genre_id FROM discovered_sites WHERE da >= 1 AND da <= 9 AND (status = 'candidate' OR status IS NULL) " + $genderClause + " ORDER BY da ASC, rowid ASC LIMIT 30;"
    $rows = @(Invoke-SqliteQuery -SqlQuery $q1)

    if (-not $rows -or $rows.Count -eq 0) {
        $q2 = "SELECT DISTINCT s.domain, s.url, s.domain_authority as da FROM serp_entries s LEFT JOIN api_call_logs l ON l.endpoint = 'domain_keywords' AND l.target_key = s.domain WHERE s.domain_authority >= 1 AND s.domain_authority <= 9 AND s.is_weak_ugc = 0 AND l.target_key IS NULL LIMIT 30;"
        $rows = @(Invoke-SqliteQuery -SqlQuery $q2)
    }

    foreach ($r in $rows) {
        if (-not $r -or [string]::IsNullOrWhiteSpace($r.domain)) { continue }
        $dom = ([string]$r.domain).ToLower().Trim()
        
        if ($ExcludeDomains -contains $dom) { continue }

        $isMale = ($Gender -eq "male")
        $ugcCheck = if ($isMale) { Test-WeakCompetitorMale -Domain $dom } else { Test-WeakCompetitor -Domain $dom }
        if ($ugcCheck.IsWeakCompetitor) { continue }

        $daVal = [int]$r.da
        if ($daVal -lt 1 -or $daVal -gt 9) { continue }

        $url = if (-not [string]::IsNullOrWhiteSpace($r.url)) { [string]$r.url } else { "https://" + $dom + "/" }
        $name = if (-not [string]::IsNullOrWhiteSpace($r.site_name)) { [string]$r.site_name } else { $dom }
        $gen = if (-not [string]::IsNullOrWhiteSpace($r.gender)) { [string]$r.gender } else { "common" }
        $gid = if ($r.genre_id) { [int]$r.genre_id } else { 0 }

        return [PSCustomObject]@{
            Domain   = $dom
            Url      = $url
            SiteName = $name
            Da       = $daVal
            Gender   = $gen
            GenreId  = $gid
        }
    }

    return $null
}
