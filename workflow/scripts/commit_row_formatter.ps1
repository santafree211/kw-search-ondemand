<#
.SYNOPSIS
    commit_row_formatter.ps1
    Single Responsibility: Format a single standard 25-column site row and generate star summary display string.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-CommitStarDisplayString {
    param([string[]]$Keywords)

    $starVals = @()
    $starChar = [char]0x2606
    foreach ($k in $Keywords) {
        $str = ([string]$k).Trim()
        $c = 0
        while ($c -lt $str.Length -and $str[$c] -eq $starChar) { $c++ }
        if ($c -gt 0) { $starVals += $c }
    }
    if ($starVals.Count -eq 0) { return [char]0x2B50 }
    $minS = ($starVals | Measure-Object -Minimum).Minimum
    $maxS = ($starVals | Measure-Object -Maximum).Maximum
    $starEmoji = [char]0x2B50
    $waveDash = [char]0x301C
    if ($minS -eq $maxS) {
        $emojis = [string]::new($starEmoji, $minS)
        return "$emojis ($minS)"
    } else {
        $eMin = [string]::new($starEmoji, $minS)
        $eMax = [string]::new($starEmoji, $maxS)
        return "$eMin$waveDash$eMax"
    }
}

function Build-SingleSiteRow {
    param(
        [string]$Status,
        [string]$GenreNo,
        [string]$GenreNm,
        [string]$SiteNm,
        [string]$SiteUrl,
        $SiteDa,
        [string[]]$Keywords,
        [string]$DateFormatted
    )

    $row = @(
        $Status,
        $GenreNo,
        $GenreNm,
        $SiteNm,
        $SiteUrl,
        $SiteDa
    )
    $kwsToPut = @()
    if ($Keywords) {
        $kwsToPut = @($Keywords | Select-Object -First 16)
    }
    foreach ($k in $kwsToPut) { $row += $k }
    while ($row.Count -lt 22) { $row += "" }
    $row += (Get-CommitStarDisplayString -Keywords $kwsToPut)
    $row += $DateFormatted
    $row += ""
    return $row
}
