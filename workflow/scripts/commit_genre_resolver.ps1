<#
.SYNOPSIS
    commit_genre_resolver.ps1
    Single Responsibility: Resolve Genre ID and Genre Name semantically against catalog seeds without arbitrary fallback.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-GenreSemanticMatch {
    param(
        $GenreObj,
        [string]$TargetText
    )

    if (-not $GenreObj) { return $false }
    $gSeeds = @($GenreObj.seeds)
    foreach ($sd in $gSeeds) {
        $sdLower = ([string]$sd).ToLower().Trim()
        if (-not [string]::IsNullOrWhiteSpace($sdLower) -and $TargetText.Contains($sdLower)) {
            return $true
        }
    }
    $nakaguro = [char]0x30FB
    $splitPattern = "[" + $nakaguro + "\s\/\(\)]+"
    $gTokens = ([string]$GenreObj.name) -split $splitPattern
    foreach ($gt in $gTokens) {
        $gtLower = $gt.ToLower().Trim()
        if ($gtLower.Length -ge 2 -and $TargetText.Contains($gtLower)) {
            return $true
        }
    }
    return $false
}

function Resolve-CommitGenre {
    param(
        [Parameter(Mandatory=$false)]
        [string]$GenreNumber = "",

        [Parameter(Mandatory=$false)]
        [string]$GenreName = "",

        [Parameter(Mandatory=$true)]
        [string]$SiteName,

        [Parameter(Mandatory=$true)]
        [string[]]$CommitKws,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        [string]$ConfigDir
    )

    $catalogPath = Join-Path $ConfigDir "genre_catalog_$Gender.json"
    $catalogGenres = @()
    if (Test-Path $catalogPath) {
        try {
            $catJson = [System.IO.File]::ReadAllText($catalogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $catalogGenres = @($catJson.genres)
        } catch {}
    }

    $searchTarget = ("$SiteName " + ($CommitKws -join " ")).ToLower()
    $matchedGenre = $null

    # 1. Match specified GenreNumber if provided
    if (-not [string]::IsNullOrWhiteSpace($GenreNumber)) {
        $cleanNum = $GenreNumber.Trim()
        $prefix = $Gender.Substring(0,1).ToUpper()
        $specifiedGenre = $catalogGenres | Where-Object { 
            $_.id -eq $cleanNum -or 
            $_.id -eq "$prefix-$cleanNum" -or 
            $_.id -eq "$prefix-0$cleanNum" -or
            $_.name -eq $GenreName
        } | Select-Object -First 1
        if ($specifiedGenre) {
            $matchedGenre = $specifiedGenre
        }
    }

    # 2. Match semantically across catalog
    if (-not $matchedGenre) {
        foreach ($g in $catalogGenres) {
            if (Test-GenreSemanticMatch -GenreObj $g -TargetText $searchTarget) {
                $matchedGenre = $g
                break
            }
        }
    }

    if ($matchedGenre) {
        Write-Output "Genre Resolved: [$($matchedGenre.id)] $($matchedGenre.name)"
        return [PSCustomObject]@{
            Id   = $matchedGenre.id
            Name = $matchedGenre.name
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($GenreName)) {
        Write-Output "Genre Preserved: [$GenreNumber] $GenreName"
        return [PSCustomObject]@{
            Id   = $GenreNumber
            Name = $GenreName
        }
    } else {
        throw "Genre Resolution Failed: Keywords '$($CommitKws -join ', ')' did not match any of the 50 genres in catalog. Refusing to blindly assign fallback genre. Aborting commit."
    }
}
