<#
.SYNOPSIS
    commit_row_formatter.ps1 - 単一サイト行フォーマット＆星表示生成モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       スプレッドシートの25列標準行データ（ステータス、ジャンル番号/名前、サイト名、代表URL、DA、KW1〜16、星表示、調査日、備考）
       の組み立て、およびキーワード群に応じた星表示範囲文字列（例: ⭐️⭐️⭐️ (3) や ⭐️〜⭐️⭐️⭐️）の生成を行う。
    2. 入力・出力仕様:
       - Get-CommitStarDisplayString:
           - Inputs : $Keywords (string[])
           - Outputs: string (星表示文字列)
       - Build-SingleSiteRow:
           - Inputs : $Status, $GenreNo, $GenreNm, $SiteNm, $SiteUrl, $SiteDa, $Keywords, $DateFormatted
           - Outputs: object[] (25列の配列)
    3. 修正時の注意点:
       - スプレッドシートの列インデックス配置（特にKW1〜16列と星表示列）を崩さないこと。
#>

$ErrorActionPreference = "Stop"

function Get-CommitStarDisplayString {
    param([string[]]$Keywords)

    $starVals = @()
    $starChar = [char]0x2606
    foreach ($k in $Keywords) {
        $str = ([string]$k).Trim()
        $c = 0
        while ($c -lt $str.Length -and $str[$c] -eq $starChar) { $c++ }
        if ($c -gt 0) { $starVals += $c }
    }
    if ($starVals.Count -eq 0) { return [char]0x2B50 }
    $minS = ($starVals | Measure-Object -Minimum).Minimum
    $maxS = ($starVals | Measure-Object -Maximum).Maximum
    $starEmoji = [char]0x2B50
    $waveDash = [char]0x301C
    if ($minS -eq $maxS) {
        $emojis = [string]::new($starEmoji, $minS)
        return "$emojis ($minS)"
    } else {
        $eMin = [string]::new($starEmoji, $minS)
        $eMax = [string]::new($starEmoji, $maxS)
        return "$eMin$waveDash$eMax"
    }
}

function Build-SingleSiteRow {
    param(
        [string]$Status,
        [string]$GenreNo,
        [string]$GenreNm,
        [string]$SiteNm,
        [string]$SiteUrl,
        $SiteDa,
        [string[]]$Keywords,
        [string]$DateFormatted
    )

    $row = @(
        $Status,
        $GenreNo,
        $GenreNm,
        $SiteNm,
        $SiteUrl,
        $SiteDa
    )
    $kwsToPut = @()
    if ($Keywords) {
        $kwsToPut = @($Keywords | Select-Object -First 16)
    }
    foreach ($k in $kwsToPut) { $row += $k }
    while ($row.Count -lt 22) { $row += "" }
    $row += (Get-CommitStarDisplayString -Keywords $kwsToPut)
    $row += $DateFormatted
    $row += ""
    return $row
}
