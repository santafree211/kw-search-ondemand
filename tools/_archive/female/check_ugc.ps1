<#
.SYNOPSIS
    tools/female/check_ugc.ps1
    Female Dedicated CLI Tool: Check whether a domain or URL is a female weak UGC competitor.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false, Position=0)]
    [string]$Domain = "",

    [Parameter(Mandatory=$false)]
    [string]$Url = ""
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
$ugcScript = Join-Path $toolsDir "eval_check_weak_competitor.ps1"

& $ugcScript -Domain $Domain -Url $Url
