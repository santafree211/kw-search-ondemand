<#
.SYNOPSIS
    pipeline_gender_balancer.ps1
    Single Responsibility: Inspect male & female sheet keyword counts to determine starting gender and manage rotation.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\sheet_profile_resolver.ps1"
. "$PSScriptRoot\sheet_data_reader.ps1"

function Get-StartingGenderRotation {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetGender = "both"
    )

    if ($TargetGender -ne "both") {
        return [PSCustomObject]@{
            StartingGender = $TargetGender
            FemaleKws      = 0
            MaleKws        = 0
        }
    }

    $femaleProfile = Resolve-SheetProfile -Gender "female"
    $maleProfile   = Resolve-SheetProfile -Gender "male"

    $femaleData = Read-SheetData -SheetId $femaleProfile.SpreadsheetId -TargetSheetName $femaleProfile.TargetSheetName
    $maleData   = Read-SheetData -SheetId $maleProfile.SpreadsheetId -TargetSheetName $maleProfile.TargetSheetName

    Write-Output "`n[Sheet State]"
    Write-Output "  Female Sheet: $($femaleData.SiteCount) Sites, $($femaleData.ValidKeywordCount) Keywords"
    Write-Output "  Male Sheet  : $($maleData.SiteCount) Sites, $($maleData.ValidKeywordCount) Keywords"

    $startGender = if ($maleData.ValidKeywordCount -le $femaleData.ValidKeywordCount) { "male" } else { "female" }
    Write-Output "Starting rotation with: $startGender (closing keyword gap first)"

    return [PSCustomObject]@{
        StartingGender = $startGender
        FemaleKws      = $femaleData.ValidKeywordCount
        MaleKws        = $maleData.ValidKeywordCount
    }
}

function Switch-PipelineGender {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CurrentGender,

        [Parameter(Mandatory=$false)]
        [string]$Mode = "both"
    )

    if ($Mode -ne "both") {
        return $CurrentGender
    }
    return if ($CurrentGender -eq "male") { "female" } else { "male" }
}
