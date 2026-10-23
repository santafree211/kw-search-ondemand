<#
.SYNOPSIS
    research_seed_suggest.ps1
    Responsibility: Clean, normalize and deduplicate candidate keywords from seeds or suggests.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"

function Get-NormalizedCandidates {
    param(
        [string[]]$Keywords,
        [string[]]$Excludes = @()
    )

    $starBlack = [char]0x2605
    $starWhite = [char]0x2606
    $fullwidthSpace = [char]0x3000
    $lParen = [char]0xFF08
    $rParen = [char]0xFF09

    $cleanExcludes = @{}
    foreach ($ex in $Excludes) {
        $trimmed = $ex.Trim()
        if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
            $cleanEx = $trimmed -replace "^\s*[\u2605\u2606]+", ""
            $cleanEx = ($cleanEx -replace "[\(\uFF08][0-9]+[\)\uFF09]", "").Trim()
            $cleanExcludes[$cleanEx] = $true
        }
    }

    $candidates = @()
    $seen = @{}

    foreach ($kw in $Keywords) {
        if ([string]::IsNullOrWhiteSpace($kw)) { continue }
        
        # Normalize whitespace and strip stars/parentheses
        $clean = $kw.Replace($fullwidthSpace, ' ')
        $clean = $clean -replace "^\s*[\u2605\u2606]+", ""
        $clean = ($clean -replace "[\(\uFF08][0-9]+[\)\uFF09]", "").Trim()
        $clean = ($clean -replace "\s+", " ").Trim()

        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($cleanExcludes.ContainsKey($clean)) { continue }
        if ($seen.ContainsKey($clean)) { continue }

        # YMYL check: filter out high-risk YMYL keywords
        $ymylCheck = Test-KeywordYmylEligibility -Keyword $clean
        if ($ymylCheck.IsYmyl) { continue }

        # Entertainment check: filter out fiction, novels, manga, anime, spoilers, games
        $entCheck = Test-KeywordEntertainmentEligibility -Keyword $clean
        if ($entCheck.IsEntertainment) { continue }

        $seen[$clean] = $true
        $candidates += $clean
    }

    return [PSCustomObject]@{
        CandidateKeywords = $candidates
        TotalCandidates = $candidates.Count
    }
}


