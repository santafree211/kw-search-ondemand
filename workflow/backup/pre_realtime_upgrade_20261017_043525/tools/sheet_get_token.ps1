<#
.SYNOPSIS
    tools/sheet_get_token.ps1
    Responsibility: CLI tool to acquire a Google Sheets API access token.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$KeyPath = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_auth_provider.ps1"

$token = Get-GoogleAccessToken -JsonPath $KeyPath

[PSCustomObject]@{
    Status = "Success"
    AccessToken = $token
    ExpiresIn = 3600
} | ConvertTo-Json
