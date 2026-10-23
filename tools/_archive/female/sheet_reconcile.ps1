<#
.SYNOPSIS
    tools/female/sheet_reconcile.ps1
    Female Dedicated 3-Way Reconciliation Audit CLI Tool.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$RowNumber = 0,

    [Parameter(Mandatory=$false)]
    [switch]$CheckAllRows = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$toolsDir = Split-Path -Parent $PSScriptRoot
& "$toolsDir\sheet_reconcile.ps1" -Profile "female" -RowNumber $RowNumber -CheckAllRows:$CheckAllRows -Json:$Json
