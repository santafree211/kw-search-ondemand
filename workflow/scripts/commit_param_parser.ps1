<#
.SYNOPSIS
    commit_param_parser.ps1
    Single Responsibility: Normalize input parameters, expand comma-separated keywords and ExtraArgs, and parse JSON input files.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Parse-CommitParameters {
    param(
        [Parameter(Mandatory=$false)]
        [string]$SiteJsonPath = "",

        [Parameter(Mandatory=$false)]
        [string]$SiteName = "",

        [Parameter(Mandatory=$false)]
        [string]$Url = "",

        [Parameter(Mandatory=$false)]
        [string]$SiteKey = "",

        [Parameter(Mandatory=$false)]
        [int]$Da = 0,

        [Parameter(Mandatory=$false)]
        [string]$OriginKw = "",

        [Parameter(Mandatory=$false)]
        [string[]]$WinningKws = @(),

        [Parameter(Mandatory=$false)]
        [string]$GenreNumber = "",

        [Parameter(Mandatory=$false)]
        [string]$GenreName = "",

        [Parameter(Mandatory=$false)]
        [string[]]$ExtraArgs = @()
    )

    # 1. Parse JSON file if supplied
    if (-not [string]::IsNullOrWhiteSpace($SiteJsonPath) -and (Test-Path $SiteJsonPath)) {
        try {
            $text = [System.IO.File]::ReadAllText($SiteJsonPath, [System.Text.Encoding]::UTF8)
            $obj = $text | ConvertFrom-Json
            if ($obj.SiteName) { $SiteName = $obj.SiteName }
            if ($obj.Url) { $Url = $obj.Url }
            if ($obj.SiteKey) { $SiteKey = $obj.SiteKey }
            if ($obj.Da) { $Da = [int]$obj.Da }
            if ($obj.OriginKw) { $OriginKw = $obj.OriginKw }
            if ($obj.WinningKws) { $WinningKws = @($obj.WinningKws) }
            if ($obj.GenreNumber) { $GenreNumber = $obj.GenreNumber }
            if ($obj.GenreName) { $GenreName = $obj.GenreName }
        } catch {}
    }

    # 2. Flatten and normalize comma-separated keywords and ExtraArgs
    $expandedKws = @()
    $rawKwList = @($WinningKws) + @($ExtraArgs)
    foreach ($kw in $rawKwList) {
        if (-not [string]::IsNullOrWhiteSpace($kw)) {
            $parts = $kw -split ",\s*"
            foreach ($p in $parts) {
                $trimmed = $p.Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $expandedKws += $trimmed
                }
            }
        }
    }

    return [PSCustomObject]@{
        SiteName    = $SiteName
        Url         = $Url
        SiteKey     = $SiteKey
        Da          = $Da
        OriginKw    = $OriginKw
        WinningKws  = $expandedKws
        GenreNumber = $GenreNumber
        GenreName   = $GenreName
    }
}
