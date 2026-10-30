<#
.SYNOPSIS
    pipeline_gender_balancer.ps1 - 男女シート件数バランス判定＆ローテーションモジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       男女スプレッドシートの登録KW件数をリアルタイム集計し、件数の少ない側を優先して開始性別を決定。
       探索ループごとに交互にローテーションする順序を管理する。
    2. 準拠ルール:
       - GEMINI.md 第1条: 男女交互均等底上げ（特定性別への偏重防止）。
    3. 入力・出力仕様:
       - Get-StartingGenderRotation:
           - Inputs : $TargetGenderMode ("both" | "female" | "male")
           - Outputs: PSCustomObject @{ StartingGender, MaleCount, FemaleCount, Rotations }
       - Switch-Gender:
           - Inputs : $CurrentGender ("female" | "male")
           - Outputs: 交代後の性別文字列 ("male" | "female")
    4. 修正時の注意点:
       - 片方の性別のみ指定された場合（例: -Gender male）はローテーションを行わず単一性別を維持すること。
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
    if ($CurrentGender -eq "male") {
        return "female"
    } else {
        return "male"
    }
}
