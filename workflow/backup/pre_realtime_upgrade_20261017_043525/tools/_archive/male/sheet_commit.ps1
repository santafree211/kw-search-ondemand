<#
.SYNOPSIS
    tools/male/sheet_commit.ps1
    Male Dedicated CLI Tool: Safely commit a verified site and winning keywords to male spreadsheet.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

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

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$WinningKws = @(),

    [Parameter(Mandatory=$false)]
    [string]$SurveyDate = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreNumber = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreName = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$expandedKws = @()
foreach ($kw in $WinningKws) {
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
$WinningKws = $expandedKws

$toolsDir = Split-Path -Parent $PSScriptRoot
$commitScript = Join-Path $toolsDir "sheet_commit_site.ps1"

& $commitScript `
    -SiteJsonPath $SiteJsonPath `
    -SiteName $SiteName `
    -Url $Url `
    -SiteKey $SiteKey `
    -Da $Da `
    -OriginKw $OriginKw `
    -WinningKws $WinningKws `
    -Gender "male" `
    -SurveyDate $SurveyDate `
    -GenreNumber $GenreNumber `
    -GenreName $GenreName `
    -DryRun:$DryRun
