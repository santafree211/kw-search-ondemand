<#
.SYNOPSIS
    tools/sheet_update_category_tab.ps1
    CLI Tool to organize Winning Keywords by Category and refresh the 'カテゴリ別集計' tab
    in both Male and Female Google Spreadsheets.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("all", "both", "male", "female")]
    [string]$Profile = "all"
)

$ErrorActionPreference = "Stop"
$projectRoot = "c:\Users\santa\OneDrive\prideall\projects\kw-serch"

Write-Output "=========================================================="
Write-Output "=== UPDATING CATEGORY ORGANIZATION TAB IN GOOGLE SHEETS ==="
Write-Output "=========================================================="

$scriptPath = Join-Path $projectRoot "workflow\scripts\update_category_tabs.py"
& python $scriptPath
Write-Output "`n[SUCCESS] 'カテゴリ別集計' tabs refreshed in Google Sheets."
