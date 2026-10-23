<#
.SYNOPSIS
    tools/store_save_api_data.ps1
    Responsibility: Standard CLI tool for agents to archive raw Ubersuggest API responses.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$Endpoint,

    [Parameter(Mandatory=$true)]
    [string]$TargetKey,

    [Parameter(Mandatory=$false, ValueFromPipeline=$true)]
    [string]$ResponseJson = "",

    [Parameter(Mandatory=$false)]
    [string]$JsonFilePath = "",

    [Parameter(Mandatory=$false)]
    [string]$DateString = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\store_api_archive.ps1"

$dataToSave = $null
if (-not [string]::IsNullOrWhiteSpace($JsonFilePath) -and (Test-Path $JsonFilePath)) {
    $dataToSave = [System.IO.File]::ReadAllText($JsonFilePath, [System.Text.Encoding]::UTF8)
} elseif (-not [string]::IsNullOrWhiteSpace($ResponseJson)) {
    $dataToSave = $ResponseJson
} else {
    throw "Either -ResponseJson or -JsonFilePath must be provided."
}

$res = Save-ApiArchive -Endpoint $Endpoint -TargetKey $TargetKey -ResponseData $dataToSave -DateString $DateString

$res | ConvertTo-Json -Compress
