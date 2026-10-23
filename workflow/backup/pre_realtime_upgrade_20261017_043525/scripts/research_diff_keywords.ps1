<#
.SYNOPSIS
    workflow/scripts/research_diff_keywords.ps1
    Responsibility: Compare input keywords against local archive to separate unknown diffs from cached entries.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\store_api_query.ps1"
. "$PSScriptRoot\research_volume_verifier.ps1"

function Get-KeywordDiff {
    param(
        [Parameter(Mandatory=$false)]
        $Keywords = @(),

        [Parameter(Mandatory=$false)]
        [string]$Endpoint = "serp_analysis",

        [Parameter(Mandatory=$false)]
        [int]$MaxAgeDays = 30,

        [Parameter(Mandatory=$false)]
        [string]$ArchiveBaseDir = ""
    )

    if ($null -eq $Keywords -or $Keywords.Count -eq 0) {
        return [PSCustomObject]@{
            TotalInput = 0
            DiffCount = 0
            CachedCount = 0
            SavedApiCalls = 0
            DiffKeywords = @()
            CachedEntries = @()
        }
    }

    $diffList = @()
    $cachedList = @()
    $seen = @{}

    $cutoffDate = (Get-Date).AddDays(-$MaxAgeDays)

    foreach ($item in $Keywords) {
        $kStr = if ($item -is [string]) { $item } elseif ($null -ne $item -and $item.Keyword) { [string]$item.Keyword } else { [string]$item }
        if ([string]::IsNullOrWhiteSpace($kStr)) { continue }
        $cleanKw = $kStr.Trim()
        if ($seen.ContainsKey($cleanKw)) {
            continue
        }
        $seen[$cleanKw] = $true

        if ($Endpoint -eq "volume") {
            # Check verified volume cache
            $volCheck = $null
            try {
                $volCheck = Test-KeywordVolume -TargetKeyword $cleanKw
            } catch {}

            $foundVol = -1
            if ($null -ne $volCheck) {
                if ($null -ne $volCheck.SearchVolume) { $foundVol = [int]$volCheck.SearchVolume }
                elseif ($null -ne $volCheck.Volume) { $foundVol = [int]$volCheck.Volume }
            }

            if ($foundVol -ge 0) {
                $cachedList += [PSCustomObject]@{
                    Keyword = $cleanKw
                    Volume = $foundVol
                    Source = "verified_volume_cache"
                }
            } else {
                $diffList += $cleanKw
            }
        } else {
            # Check SERP archive
            $found = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cleanKw -ArchiveBaseDir $ArchiveBaseDir
            $isFreshCache = $false

            if ($null -ne $found -and $found.Found) {
                # Check date freshness
                $parsedDate = [DateTime]::MinValue
                if ([DateTime]::TryParse($found.Date, [ref]$parsedDate)) {
                    if ($parsedDate -ge $cutoffDate) {
                        $isFreshCache = $true
                    }
                } else {
                    $isFreshCache = $true
                }
            }

            if ($isFreshCache) {
                $cachedList += [PSCustomObject]@{
                    Keyword = $cleanKw
                    Date = $found.Date
                    FilePath = $found.FilePath
                    Source = "raw_api_archive"
                }
            } else {
                $diffList += $cleanKw
            }
        }
    }

    return [PSCustomObject]@{
        TotalInput = $seen.Count
        DiffCount = $diffList.Count
        CachedCount = $cachedList.Count
        SavedApiCalls = $cachedList.Count
        DiffKeywords = $diffList
        CachedEntries = $cachedList
    }
}
