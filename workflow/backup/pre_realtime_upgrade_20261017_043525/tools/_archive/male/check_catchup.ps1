<#
.SYNOPSIS
    tools/male/check_catchup.ps1
    Male Dedicated CLI Tool: Verify whether today's male keyword discovery & commit is completed (Rule 1: Auto-Catchup).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
$catchupScript = Join-Path $toolsDir "guard_check_catchup.ps1"

& $catchupScript -ProfileName "male"
