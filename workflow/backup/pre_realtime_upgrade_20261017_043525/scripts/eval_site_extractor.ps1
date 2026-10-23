<#
.SYNOPSIS
    eval_site_extractor.ps1
    Responsibility: Extract target weak site metadata and structure spreadsheet row objects.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function New-SiteRowObject {
    param(
        [Parameter(Mandatory=$true)]
        $SiteEntry,

        [Parameter(Mandatory=$true)]
        [string]$OriginKeyword,

        [Parameter(Mandatory=$true)]
        [string[]]$Keywords,

        [Parameter(Mandatory=$false)]
        [string]$SiteType = "Specialized Blog",

        [Parameter(Mandatory=$false)]
        [string]$Attribute = "General"
    )

    if ($Keywords.Count -eq 0) {
        throw "Cannot create site row with 0 winning keywords (Pre-Write Gate violation)."
    }

    $domain = [string]$SiteEntry.domain
    $da = [int]$SiteEntry.domainAuthority
    $url = [string]$SiteEntry.url
    $title = [string]$SiteEntry.title

    # Clean domain to extract site name candidate
    $siteName = if ($title) {
        $parts = $title -split "[\-\|\:・]"
        if ($parts.Count -gt 1) { $parts[-1].Trim() } else { $title.Trim() }
    } else {
        $domain
    }

    return [PSCustomObject]@{
        SiteName = $siteName
        Url = $url
        SiteKey = $domain
        Da = $da
        SiteType = $SiteType
        Attribute = $Attribute
        OriginKw = $OriginKeyword
        WinningKws = $Keywords
    }
}


