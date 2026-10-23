<#
.SYNOPSIS
    tools/guard_inspect_daily_quota.ps1
    Responsibility: Standard CLI tool to inspect real API calls consumed today (09:00 JST standard) and remaining quota.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$QuotaLimit = 100
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\guard_quota_archive.ps1"

$res = Get-DailyApiQuotaUsage -DailyQuotaLimit $QuotaLimit

$res | ConvertTo-Json -Depth 5
