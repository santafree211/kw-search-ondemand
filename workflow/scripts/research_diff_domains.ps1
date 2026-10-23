<#
.SYNOPSIS
    workflow/scripts/research_diff_domains.ps1
    Responsibility: Compare input domains against local domain_keywords archive to isolate uninvestigated domains.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\store_api_query.ps1"

function Get-DomainDiff {
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$Domains = @(),

        [Parameter(Mandatory=$false)]
        [int]$MaxAgeDays = 30,

        [Parameter(Mandatory=$false)]
        [string]$ArchiveBaseDir = ""
    )

    if ($null -eq $Domains -or $Domains.Count -eq 0) {
        return [PSCustomObject]@{
            TotalInput = 0
            DiffCount = 0
            CachedCount = 0
            SavedApiCalls = 0
            DiffDomains = @()
            CachedDomains = @()
        }
    }

    $diffDomains = @()
    $cachedDomains = @()
    $seen = @{}

    $cutoffDate = (Get-Date).AddDays(-$MaxAgeDays)

    foreach ($dom in $Domains) {
        $cleanDom = $dom.ToLower().Trim()
        if ([string]::IsNullOrWhiteSpace($cleanDom) -or $seen.ContainsKey($cleanDom)) {
            continue
        }
        $seen[$cleanDom] = $true

        $found = Find-ApiArchive -Endpoint "domain_keywords" -TargetKey $cleanDom -ArchiveBaseDir $ArchiveBaseDir
        $isFresh = $false

        if ($null -ne $found -and $found.Found) {
            $parsedDate = [DateTime]::MinValue
            if ([DateTime]::TryParse($found.Date, [ref]$parsedDate)) {
                if ($parsedDate -ge $cutoffDate) {
                    $isFresh = $true
                }
            } else {
                $isFresh = $true
            }
        }

        if ($isFresh) {
            $cachedDomains += [PSCustomObject]@{
                Domain = $cleanDom
                Date = $found.Date
                FilePath = $found.FilePath
            }
        } else {
            $diffDomains += $cleanDom
        }
    }

    return [PSCustomObject]@{
        TotalInput = $seen.Count
        DiffCount = $diffDomains.Count
        CachedCount = $cachedDomains.Count
        SavedApiCalls = $cachedDomains.Count
        DiffDomains = $diffDomains
        CachedDomains = $cachedDomains
    }
}
